// PhotoScanner.cpp
// Created on 2025/12/25.
//
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".

#include "PhotoScanner.h"
#include "Camera/CameraDownloadKit/camera_download.h"
#include "../../Common/native_common.h"
#include "gphoto2/gphoto2-list.h"
#include "gphoto2/gphoto2-port-result.h"
#include <hilog/log.h>
#include <algorithm>
#include <cstring>
#include <fstream>
#include <set>
#include <Camera/Common/Constants.h>


#define LOG_DOMAIN ModuleLogs::PhotoScanner.domain
#define LOG_TAG ModuleLogs::PhotoScanner.tag

// 支持的图片格式
static const std::set<std::string> PHOTO_EXTENSIONS = {
    "jpg", "jpeg", "nef", "cr2", "arw", "dng", "rw2", "orf"
};

PhotoScanner::PhotoScanner() 
    : camera_(nullptr)
    , context_(nullptr)
    , isFileListCached_(false)
    , isScanning_(false)
    , scanCancelled_(false)
    , scanProgressCurrent_(0)
    , scanProgressTotal_(0) {
}

PhotoScanner::~PhotoScanner() {
    Cleanup();
}

void PhotoScanner::Init(Camera* camera, GPContext* context) {
    camera_ = camera;
    context_ = context;
    ClearCache();
}

void PhotoScanner::Cleanup() {
    if (isScanning_) {
        CancelScan();
        if (scanThread_.joinable()) {
            scanThread_.join();
        }
    }
    
    ClearCache();
    
    camera_ = nullptr;
    context_ = nullptr;
}

int PhotoScanner::GetPhotoTotalCount() {
    if (!camera_ || !context_) {
        OH_LOG_PrintMsg(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "相机未连接，无法获取照片总数");
        return 0;
    }
    
    // 如果缓存已存在，直接返回缓存数量
    {
        std::lock_guard<std::mutex> lock(cacheMutex_);
        if (isFileListCached_) {
            OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                        "使用缓存的文件列表，照片总数: %{public}zu", cachedFileList_.size());
            return static_cast<int>(cachedFileList_.size());
        }
    }
    
    // 如果正在扫描中，返回0表示正在扫描
    if (isScanning_) {
        OH_LOG_PrintMsg(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "正在扫描中...");
        return 0;
    }
    
    // 启动异步扫描
    StartAsyncScan();
    
    return 0; // 返回0，表示扫描中
}

std::vector<PhotoMeta> PhotoScanner::GetPhotoMetaList(int pageIndex, int pageSize) {
    std::vector<PhotoMeta> result;
    
    // 检查缓存状态
    {
        std::lock_guard<std::mutex> lock(cacheMutex_);
        if (!isFileListCached_) {
            OH_LOG_PrintMsg(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "文件列表未缓存");
            return result;
        }
    }
    
    // 计算分页范围
    std::lock_guard<std::mutex> lock(cacheMutex_);
    size_t startIndex = pageIndex * pageSize;
    size_t endIndex = std::min(startIndex + pageSize, cachedFileList_.size());
    
    if (startIndex >= cachedFileList_.size()) {
        return result;
    }
    
    // 复制分页数据
    for (size_t i = startIndex; i < endIndex; i++) {
        result.push_back(cachedFileList_[i]);
    }
    
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                "获取照片元信息: pageIndex=%{public}d, pageSize=%{public}d, 返回%{public}zu条记录", 
                pageIndex, pageSize, result.size());
    
    return result;
}

bool PhotoScanner::StartAsyncScan() {
    if (!camera_ || !context_) {
        OH_LOG_PrintMsg(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "相机未连接");
        return false;
    }
    
    if (isScanning_) {
        OH_LOG_PrintMsg(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "扫描已经在进行中");
        return false;
    }
    
    isScanning_ = true;
    scanCancelled_ = false;
    scanProgressCurrent_ = 0;
    scanProgressTotal_ = 0;
    
    scanThread_ = std::thread(&PhotoScanner::AsyncScanInternal, this);
    scanThread_.detach();
    
    return true;
}

void PhotoScanner::AsyncScanInternal() {
    OH_LOG_PrintMsg(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "异步扫描开始");
    
    try {
        std::vector<PhotoMeta> fileList;
        
        // 1. 寻找DCIM目录
        std::string dcimFolder = FindDcimFolder();
        if (dcimFolder.empty()) {
            OH_LOG_PrintMsg(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "未找到DCIM目录");
            isScanning_ = false;
            return;
        }
        
        // 2. 获取照片目录
        std::string photoFolder = FindPhotoFolder(dcimFolder);
        if (photoFolder.empty()) {
            photoFolder = dcimFolder;
        }
        
        OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                    "扫描照片目录: %{public}s", photoFolder.c_str());
        
        // 3. 获取文件列表
        CameraList *files = nullptr;
        gp_list_new(&files);
        int ret = gp_camera_folder_list_files(camera_, photoFolder.c_str(), files, context_);
        
        if (ret != GP_OK) {
            OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, 
                        "获取文件列表失败: %{public}s", gp_result_as_string(ret));
            gp_list_free(files);
            isScanning_ = false;
            return;
        }
        
        // 4. 获取文件总数用于进度
        int numFiles = gp_list_count(files);
        scanProgressTotal_ = numFiles;
        
        // 5. 构建元信息列表
        for (int i = 0; i < numFiles; i++) {
            // 检查是否被取消
            if (scanCancelled_) {
                OH_LOG_PrintMsg(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "扫描被取消");
                break;
            }
            
            const char *fileName;
            gp_list_get_name(files, i, &fileName);
            
            if (IsPhotoFile(fileName)) {
                PhotoMeta meta;
                meta.folder = photoFolder;
                meta.fileName = fileName;
                meta.fileSize = 0; // 暂时不获取文件大小
                
                fileList.push_back(meta);
            }
            
            // 更新进度
            scanProgressCurrent_ = i + 1;
            
            // 每扫描100个文件记录一次
            if (i % 100 == 0 || i == numFiles - 1) {
                OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                            "扫描进度: %{public}d/%{public}d", i + 1, numFiles);
            }
        }
        
        gp_list_free(files);
        
        if (!scanCancelled_) {
            // 6. 更新缓存
            {
                std::lock_guard<std::mutex> lock(cacheMutex_);
                cachedFileList_ = fileList;
                isFileListCached_ = true;
            }
            
            OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                        "异步扫描完成，找到 %{public}zu 个照片文件", fileList.size());
        }
        
    } catch (const std::exception& e) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, 
                    "异步扫描异常: %{public}s", e.what());
    } catch (...) {
        OH_LOG_PrintMsg(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "异步扫描未知异常");
    }
    
    isScanning_ = false;
}

bool PhotoScanner::IsScanComplete() const {
    return !isScanning_ && isFileListCached_;
}

bool PhotoScanner::GetScanProgress(int& current, int& total, bool& cached) const {
    current = scanProgressCurrent_;
    total = scanProgressTotal_;
    cached = isFileListCached_;
    return isScanning_;
}

void PhotoScanner::CancelScan() {
    scanCancelled_ = true;
}

void PhotoScanner::ClearCache() {
    std::lock_guard<std::mutex> lock(cacheMutex_);
    cachedFileList_.clear();
    isFileListCached_ = false;
    OH_LOG_PrintMsg(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "已清理照片缓存");
}

bool PhotoScanner::IsPhotoFile(const char* fileName) {
    if (!fileName) return false;
    
    // 获取文件扩展名
    const char* dot = strrchr(fileName, '.');
    if (!dot) return false;
    
    std::string ext = dot + 1;
    std::transform(ext.begin(), ext.end(), ext.begin(), ::tolower);
    
    return PHOTO_EXTENSIONS.find(ext) != PHOTO_EXTENSIONS.end();
}

std::vector<PhotoMeta> PhotoScanner::ScanPhotoFilesOnly() {
    std::vector<PhotoMeta> fileList;
    
    if (!camera_ || !context_) {
        return fileList;
    }
    
    OH_LOG_PrintMsg(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "开始扫描照片文件...");
    
    // 1. 寻找DCIM目录
    std::string dcimFolder = FindDcimFolder();
    if (dcimFolder.empty()) {
        OH_LOG_PrintMsg(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "未找到DCIM目录");
        return fileList;
    }
    
    // 2. 获取照片目录
    std::string photoFolder = FindPhotoFolder(dcimFolder);
    if (photoFolder.empty()) {
        photoFolder = dcimFolder;
    }
    
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                "扫描照片目录: %{public}s", photoFolder.c_str());
    
    // 3. 获取文件列表
    CameraList *files = nullptr;
    gp_list_new(&files);
    int ret = gp_camera_folder_list_files(camera_, photoFolder.c_str(), files, context_);
    
    if (ret != GP_OK) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, 
                    "获取文件列表失败: %{public}s", gp_result_as_string(ret));
        gp_list_free(files);
        return fileList;
    }
    
    // 4. 构建元信息列表
    int numFiles = gp_list_count(files);
    for (int i = 0; i < numFiles; i++) {
        const char *fileName;
        gp_list_get_name(files, i, &fileName);

        // 筛选照片文件
        if (IsPhotoFile(fileName)) {
            PhotoMeta meta;
            meta.folder = photoFolder;
            meta.fileName = fileName;
            meta.fileSize = 0;
            
            fileList.push_back(meta);
        }
    }

    gp_list_free(files);
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                "扫描完成，找到 %{public}zu 个照片文件", fileList.size());
    
    return fileList;
}

std::string PhotoScanner::FindDcimFolder() {
    CameraList *rootFolders = nullptr;
    gp_list_new(&rootFolders);
    std::string dcimFolder;
    
    int ret = gp_camera_folder_list_folders(camera_, "/", rootFolders, context_);
    if (ret == GP_OK) {
        int numRootFolders = gp_list_count(rootFolders);
        for (int i = 0; i < numRootFolders; i++) {
            const char *storageFolder;
            gp_list_get_name(rootFolders, i, &storageFolder);
            std::string absoluteStoragePath = '/' + std::string(storageFolder);
            
            // 检查存储文件夹下的子目录
            CameraList *storageSubFolders = nullptr;
            gp_list_new(&storageSubFolders);
            
            if (gp_camera_folder_list_folders(camera_, absoluteStoragePath.c_str(), 
                                             storageSubFolders, context_) == GP_OK) {
                int numSubFolders = gp_list_count(storageSubFolders);
                for (int j = 0; j < numSubFolders; j++) {
                    const char *subFolderName;
                    gp_list_get_name(storageSubFolders, j, &subFolderName);
                    
                    if (strstr(subFolderName, "DCIM") != nullptr) {
                        dcimFolder = absoluteStoragePath + "/" + subFolderName;
                        gp_list_free(storageSubFolders);
                        goto found_dcim;
                    }
                }
            }
            gp_list_free(storageSubFolders);
        }
    }
    
found_dcim:
    gp_list_free(rootFolders);
    return dcimFolder;
}

std::string PhotoScanner::FindPhotoFolder(const std::string& dcimFolder) {
    CameraList *dcimSubFolders = nullptr;
    gp_list_new(&dcimSubFolders);
    std::string photoFolder;
    
    if (gp_camera_folder_list_folders(camera_, dcimFolder.c_str(), 
                                     dcimSubFolders, context_) == GP_OK) {
        if (gp_list_count(dcimSubFolders) > 0) {
            const char *subFolderName;
            gp_list_get_name(dcimSubFolders, 0, &subFolderName);
            
            std::string dcimPathStr = dcimFolder;
            if (!dcimPathStr.empty() && dcimPathStr.back() == '/') {
                dcimPathStr.pop_back();
            }
            photoFolder = dcimPathStr + "/" + subFolderName;
        }
    }
    
    gp_list_free(dcimSubFolders);
    return photoFolder;
}