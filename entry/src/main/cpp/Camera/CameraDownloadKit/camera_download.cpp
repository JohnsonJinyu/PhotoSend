// camera_download.cpp
// Created on 2025/11/10.
// 负责从机内下载照片
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".
// C++ 层需要实现的核心功能：获取缩略图列表和下载选中照片
#include "camera_download.h"
#include "Camera/native_common.h"
#include "gphoto2/gphoto2-list.h"
#include "gphoto2/gphoto2-port-result.h"
#include <cstddef>
#include <cstdint>
#include <hilog/log.h>
#include <set>
#include <string>
#include <fstream> 
#include <stdarg.h>
#include <atomic>
#include <thread>
#include <condition_variable>

#include <semaphore.h>

#define LOG_DOMAIN 0x0005         // 日志域（自定义标识，区分不同模块日志）
#define LOG_TAG "Camera_Download" // 日志标签（日志中显示的模块名）














// ========== 添加初始化函数（在相机连接成功时调用） ==========
void InitThumbnailSemaphore() {
    if (!g_semaphoreInitialized) {
        int ret = sem_init(&g_thumbnailSemaphore, 0, MAX_CONCURRENT_THUMBNAILS);
        if (ret == 0) {
            g_semaphoreInitialized = true;
            OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                           "缩略图信号量初始化成功，最大并发数: %d", MAX_CONCURRENT_THUMBNAILS);
        } else {
            OH_LOG_PrintMsg(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, 
                           "缩略图信号量初始化失败");
        }
    }
}


// ========== 添加清理函数（在相机断开时调用） ==========
void CleanupThumbnailSemaphore() {
    if (g_semaphoreInitialized) {
        sem_destroy(&g_thumbnailSemaphore);
        g_semaphoreInitialized = false;
        OH_LOG_PrintMsg(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "缩略图信号量已清理");
    }
}



// ###########################################################################
// 优化部分:1、获取机内照片总数的实现
// ###########################################################################

/**
 * @brief 内部函数：获取照片总数（不加载缩略图）
 */
static int InternalGetPhotoTotalCount() {
    if (!g_connected || !g_context || !g_camera) {
        OH_LOG_PrintMsg(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "相机未连接，无法获取照片总数");
        return 0;
    }
    
    // 如果缓存已存在，直接返回缓存数量
    {
        std::lock_guard<std::mutex> lock(g_cacheMutex);
        if (g_isFileListCached) {
            OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                        "使用缓存的文件列表，照片总数: %{public}zu", g_cachedFileList.size());
            return static_cast<int>(g_cachedFileList.size());
        }
    }
    
    // 如果正在扫描中，返回0表示正在扫描
    if (g_isScanning) {
        OH_LOG_PrintMsg(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "正在扫描中...");
        return 0;
    }
    
    // 启动异步扫描
    StartAsyncScanInternal();
    
    return 0; // 返回0，表示扫描中
}



// ========== 添加异步扫描内部函数 ==========
static void StartAsyncScanInternal() {
    if (g_isScanning) {
        return;
    }
    
    g_isScanning = true;
    g_scanCancelled = false;
    g_scanProgressCurrent = 0;
    g_scanProgressTotal = 0;
    
    g_scanThread = std::thread([]() {
        OH_LOG_PrintMsg(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "异步扫描开始");
        
        try {
            std::vector<PhotoMeta> fileList;
            
            // 1. 寻找DCIM目录
            std::string dcimFolder = FindDcimFolder();
            if (dcimFolder.empty()) {
                OH_LOG_PrintMsg(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "未找到DCIM目录");
                g_isScanning = false;
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
            int ret = gp_camera_folder_list_files(g_camera, photoFolder.c_str(), files, g_context);
            
            if (ret != GP_OK) {
                OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, 
                            "获取文件列表失败: %{public}s", gp_result_as_string(ret));
                gp_list_free(files);
                g_isScanning = false;
                return;
            }
            
            // 4. 获取文件总数用于进度
            int numFiles = gp_list_count(files);
            g_scanProgressTotal = numFiles;
            
            // 5. 构建元信息列表
            for (int i = 0; i < numFiles; i++) {
                // 检查是否被取消
                if (g_scanCancelled) {
                    OH_LOG_PrintMsg(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "扫描被取消");
                    break;
                }
                
                const char *fileName;
                gp_list_get_name(files, i, &fileName);
                
                if (IsPhotoFile(fileName)) {
                    PhotoMeta meta;
                    meta.folder = photoFolder;
                    meta.fileName = fileName;
                    meta.fileSize = 0;
                    
                    fileList.push_back(meta);
                }
                
                // 更新进度
                g_scanProgressCurrent = i + 1;
                
                // 每扫描100个文件记录一次
                if (i % 100 == 0 || i == numFiles - 1) {
                    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                                "扫描进度: %{public}d/%{public}d", i + 1, numFiles);
                }
            }
            
            gp_list_free(files);
            
            if (!g_scanCancelled) {
                // 6. 更新缓存
                {
                    std::lock_guard<std::mutex> lock(g_cacheMutex);
                    g_cachedFileList = fileList;
                    g_isFileListCached = true;
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
        
        g_isScanning = false;
    });
    
    g_scanThread.detach(); // 分离线程
}


// ========== 添加新的NAPI函数 ==========

/**
 * @brief 启动异步扫描
 */
napi_value StartAsyncScan(napi_env env, napi_callback_info info) {
    if (!g_connected || !g_context || !g_camera) {
        OH_LOG_PrintMsg(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "相机未连接");
        napi_value result;
        napi_get_boolean(env, false, &result);
        return result;
    }
    
    if (g_isScanning) {
        OH_LOG_PrintMsg(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "扫描已经在进行中");
        napi_value result;
        napi_get_boolean(env, false, &result);
        return result;
    }
    
    StartAsyncScanInternal();
    
    napi_value result;
    napi_get_boolean(env, true, &result);
    return result;
}



/**
 * @brief 检查扫描是否完成
 */
napi_value IsScanComplete(napi_env env, napi_callback_info info) {
    bool isComplete = !g_isScanning && g_isFileListCached;
    
    napi_value result;
    napi_get_boolean(env, isComplete, &result);
    return result;
}


/**
 * @brief 获取扫描进度
 */
napi_value GetScanProgress(napi_env env, napi_callback_info info) {
    napi_value result;
    napi_create_object(env, &result);
    
    // 添加扫描中状态
    napi_value scanningValue;
    napi_get_boolean(env, g_isScanning, &scanningValue);
    napi_set_named_property(env, result, "scanning", scanningValue);
    
    // 添加当前进度
    napi_value currentValue;
    napi_create_int32(env, g_scanProgressCurrent, &currentValue);
    napi_set_named_property(env, result, "current", currentValue);
    
    // 添加总进度
    napi_value totalValue;
    napi_create_int32(env, g_scanProgressTotal, &totalValue);
    napi_set_named_property(env, result, "total", totalValue);
    
    // 添加缓存状态
    napi_value cachedValue;
    napi_get_boolean(env, g_isFileListCached, &cachedValue);
    napi_set_named_property(env, result, "cached", cachedValue);
    
    // 添加照片总数（如果缓存存在）
    if (g_isFileListCached) {
        std::lock_guard<std::mutex> lock(g_cacheMutex);
        napi_value countValue;
        napi_create_int32(env, static_cast<int>(g_cachedFileList.size()), &countValue);
        napi_set_named_property(env, result, "count", countValue);
    }
    
    return result;
}

/**
 * @brief 内部函数：仅扫描照片文件，不下载缩略图
 */

static std::vector<PhotoMeta> InternalScanPhotoFilesOnly(){
    std::vector<PhotoMeta> fileList;
    
    if (!g_connected || !g_context || !g_camera) {
        return fileList;
    }
    
     OH_LOG_PrintMsg(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "开始扫描照片文件...");
    
    // 1. 寻找DCIM目录（复用原有逻辑）
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
    int ret = gp_camera_folder_list_files(g_camera, photoFolder.c_str(), files, g_context);
    
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
            
            // 可选：获取文件大小（如果性能允许）
            // 注意：获取文件大小可能需要额外调用，影响性能
            meta.fileSize = 0; // 暂时不获取，需要时再获取
            
            fileList.push_back(meta);
        }
    }

    gp_list_free(files);
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                "扫描完成，找到 %{public}zu 个照片文件", fileList.size());
    
    return fileList;
    
}



/**
 * @brief 内部辅助函数：查找DCIM目录
 */
static std::string FindDcimFolder(){
    CameraList *rootFolders = nullptr;
    gp_list_new(&rootFolders);
    std::string dcimFolder;
    
    int ret = gp_camera_folder_list_folders(g_camera, "/", rootFolders, g_context);
    if (ret == GP_OK) {
        int numRootFolders = gp_list_count(rootFolders);
        for (int i = 0; i < numRootFolders; i++) {
            const char *storageFolder;
            gp_list_get_name(rootFolders, i, &storageFolder);
            std::string absoluteStoragePath = '/' + std::string(storageFolder);
            
            // 检查存储文件夹下的子目录
            CameraList *storageSubFolders = nullptr;
            gp_list_new(&storageSubFolders);
            
            if (gp_camera_folder_list_folders(g_camera, absoluteStoragePath.c_str(), 
                                             storageSubFolders, g_context) == GP_OK) {
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

/**
 * @brief 内部辅助函数：查找照片目录
 */
static std::string FindPhotoFolder(const std::string& dcimFolder){
     CameraList *dcimSubFolders = nullptr;
    gp_list_new(&dcimSubFolders);
    std::string photoFolder;
    
    if (gp_camera_folder_list_folders(g_camera, dcimFolder.c_str(), 
                                     dcimSubFolders, g_context) == GP_OK) {
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

/**
 * @brief 内部辅助函数：判断是否为照片文件
 */
static bool IsPhotoFile(const char* fileName){
    if (!fileName) return false;
    
    // 获取文件扩展名
    const char* dot = strrchr(fileName, '.');
    if (!dot) return false;
    
    std::string ext = dot + 1;
    std::transform(ext.begin(), ext.end(), ext.begin(), ::tolower);
    
    // 支持的图片格式
    static const std::set<std::string> photoExtensions = {
        "jpg", "jpeg", "nef", "cr2", "arw", "dng", "rw2", "orf"
    };
    
    return photoExtensions.find(ext) != photoExtensions.end();
}

/**
 * @brief NAPI接口：获取照片总数
 */
napi_value GetPhotoTotalCount(napi_env env, napi_callback_info info) {
    napi_value result;
    
    // 调用内部函数获取照片总数
    int totalCount = InternalGetPhotoTotalCount();
    
    // 创建NAPI整数值
    napi_create_int32(env, totalCount, &result);
    
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                "GetPhotoTotalCount 返回: %{public}d", totalCount);
    
    return result;
}

// ###########################################################################
// 优化部分，获取机内照片总数的实现截止到此
// ###########################################################################





// ###########################################################################
// 优化部分，分页获取照片元信息
// ###########################################################################
/**
 * @brief NAPI接口：分页获取照片元信息
 */

napi_value GetPhotoMetaList(napi_env env, napi_callback_info info) {
    // 1. 解析参数
    size_t argc = 2;
    napi_value args[2];
    napi_value thisArg;
    
    napi_status status = napi_get_cb_info(env, info, &argc, args, &thisArg, nullptr);
    if (status != napi_ok || argc < 2) {
        OH_LOG_PrintMsg(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, 
                       "GetPhotoMetaList 参数错误：需要pageIndex和pageSize");
        napi_value emptyArray;
        napi_create_array(env, &emptyArray);
        return emptyArray;
    }
    
    // 2. 获取分页参数
    int32_t pageIndex, pageSize;
    napi_get_value_int32(env, args[0], &pageIndex);
    napi_get_value_int32(env, args[1], &pageSize);
    
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                "GetPhotoMetaList 参数: pageIndex=%{public}d, pageSize=%{public}d", 
                pageIndex, pageSize);
    
    // 3. 检查缓存状态 - 如果正在扫描，返回空数组
    {
        std::lock_guard<std::mutex> lock(g_cacheMutex);
        if (!g_isFileListCached) {
            OH_LOG_PrintMsg(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                          "文件列表未缓存，返回空数组");
            napi_value emptyArray;
            napi_create_array(env, &emptyArray);
            return emptyArray;
        }
    }
    
    // 4. 计算分页范围
    std::lock_guard<std::mutex> lock(g_cacheMutex);
    size_t startIndex = pageIndex * pageSize;
    size_t endIndex = std::min(startIndex + pageSize, g_cachedFileList.size());
    
    if (startIndex >= g_cachedFileList.size()) {
        napi_value emptyArray;
        napi_create_array(env, &emptyArray);
        return emptyArray;
    }
    
    // 5. 创建返回数组
    napi_value resultArray;
    napi_create_array(env, &resultArray);
    
    for (size_t i = startIndex; i < endIndex; i++) {
        const PhotoMeta& meta = g_cachedFileList[i];
        
        napi_value metaObj;
        napi_create_object(env, &metaObj);
        
        // 设置属性
        napi_set_named_property(env, metaObj, "folder", 
                              CreateNapiString(env, meta.folder.c_str()));
        napi_set_named_property(env, metaObj, "filename", 
                              CreateNapiString(env, meta.fileName.c_str()));
        
        // 如果有文件大小，也返回
        if (meta.fileSize > 0) {
            napi_value sizeValue;
            napi_create_int64(env, meta.fileSize, &sizeValue);
            napi_set_named_property(env, metaObj, "size", sizeValue);
        }
        
        // 添加到数组
        napi_set_element(env, resultArray, i - startIndex, metaObj);
    }
    
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                "GetPhotoMetaList 返回 %{public}zu 条记录", endIndex - startIndex);
    
    return resultArray;
}



// ###########################################################################
// 优化部分，下载单张缩略图
// ###########################################################################
/**
 * @brief 内部函数：下载单张缩略图
 */
static std::vector<uint8_t> InternalDownloadSingleThumbnail(const char* folder, const char* filename) {
    std::vector<uint8_t> thumbnailData;
    
    if (!g_connected || !g_context || !g_camera) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, 
                   "相机未连接，无法下载缩略图");
        return thumbnailData;
    }
    
    // 等待信号量（最多等待1秒）
    if (g_semaphoreInitialized) {
        struct timespec ts;
        clock_gettime(CLOCK_REALTIME, &ts);
        ts.tv_sec += 1; // 等待1秒
        
        int semRet = sem_timedwait(&g_thumbnailSemaphore, &ts);
        if (semRet != 0) {
            OH_LOG_Print(LOG_APP, LOG_WARN, LOG_DOMAIN, LOG_TAG, 
                       "等待缩略图下载信号量超时: %{public}s/%{public}s", folder, filename);
            return thumbnailData;
        }
    }
    
    CameraFile *thumbFile = nullptr;
    gp_file_new(&thumbFile);
    
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                "开始下载缩略图: %{public}s/%{public}s", folder, filename);
    
    int ret = GP_OK;
    try {
        // 获取缩略图
        ret = gp_camera_file_get(g_camera, folder, filename, 
                                GP_FILE_TYPE_PREVIEW, thumbFile, g_context);
    } catch (...) {
        OH_LOG_PrintMsg(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "下载缩略图异常");
        ret = GP_ERROR;
    }
    
    // 释放信号量
    if (g_semaphoreInitialized) {
        sem_post(&g_thumbnailSemaphore);
    }
    
    if (ret != GP_OK) {
        OH_LOG_Print(LOG_APP, LOG_WARN, LOG_DOMAIN, LOG_TAG, 
                    "下载缩略图失败: %{public}s", gp_result_as_string(ret));
        gp_file_unref(thumbFile);
        return thumbnailData;
    }
    
    // 提取数据
    const char *thumbData;
    unsigned long thumbSize;
    gp_file_get_data_and_size(thumbFile, &thumbData, &thumbSize);
    
    if (thumbData && thumbSize > 0) {
        // 复制数据到vector
        thumbnailData.assign(thumbData, thumbData + thumbSize);
        
        OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                    "缩略图下载成功: %{public}s, 大小: %{public}lu", 
                    filename, thumbSize);
    } else {
        OH_LOG_PrintMsg(LOG_APP, LOG_WARN, LOG_DOMAIN, LOG_TAG, "缩略图数据为空");
    }
    
    gp_file_unref(thumbFile);
    return thumbnailData;
}

/**
 * @brief NAPI接口：异步下载单张缩略图
 */
napi_value DownloadSingleThumbnail(napi_env env, napi_callback_info info) {
    // 1. 解析参数
    size_t argc = 3; // folder, filename, callback
    napi_value args[3];
    napi_value thisArg;
    
    napi_status status = napi_get_cb_info(env, info, &argc, args, &thisArg, nullptr);
    if (status != napi_ok || argc < 3) {
        OH_LOG_PrintMsg(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, 
                       "DownloadSingleThumbnail 参数错误");
        return nullptr;
    }
    
    // 2. 验证回调函数
    napi_valuetype argType;
    napi_typeof(env, args[2], &argType);
    if (argType != napi_function) {
        OH_LOG_PrintMsg(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, 
                       "第三个参数必须是回调函数");
        return nullptr;
    }
    
    // 3. 获取参数
    char folder[256] = {0};
    char filename[256] = {0};
    napi_get_value_string_utf8(env, args[0], folder, sizeof(folder), nullptr);
    napi_get_value_string_utf8(env, args[1], filename, sizeof(filename), nullptr);
    
    // 4. 创建异步任务数据
    struct AsyncThumbnailTaskData {
        napi_env env;
        napi_ref callback;
        std::string folder;
        std::string filename;
        std::vector<uint8_t> thumbnailData;
        bool success;
        std::string errorMsg;
    };
    
    AsyncThumbnailTaskData* taskData = new AsyncThumbnailTaskData();
    taskData->env = env;
    taskData->folder = folder;
    taskData->filename = filename;
    taskData->success = false;
    
    // 保存回调函数
    napi_create_reference(env, args[2], 1, &taskData->callback);
    
    // 5. 创建异步工作
    napi_value workName;
    napi_create_string_utf8(env, "DownloadSingleThumbnail", NAPI_AUTO_LENGTH, &workName);
    napi_async_work work;
    
    // 工作函数（在后台线程执行）
    auto executeWork = [](napi_env env, void* data) {
        AsyncThumbnailTaskData* taskData = static_cast<AsyncThumbnailTaskData*>(data);
        
        try {
            taskData->thumbnailData = InternalDownloadSingleThumbnail(
                taskData->folder.c_str(), taskData->filename.c_str());
            taskData->success = !taskData->thumbnailData.empty();
        } catch (const std::exception& e) {
            taskData->errorMsg = e.what();
            taskData->success = false;
        }
    };
    
    // 完成函数（在主线程执行）
    auto completeWork = [](napi_env env, napi_status status, void* data) {
        AsyncThumbnailTaskData* taskData = static_cast<AsyncThumbnailTaskData*>(data);
        
        napi_value callback;
        napi_get_reference_value(env, taskData->callback, &callback);
        
        napi_value args[2];
        if (taskData->success) {
            // 创建Buffer返回缩略图数据
            void* bufferData = nullptr;
            napi_value buffer;
            
            napi_create_buffer_copy(env, taskData->thumbnailData.size(),
                                   taskData->thumbnailData.data(),
                                   &bufferData, &buffer);
            
            napi_get_null(env, &args[0]); // 错误为null
            args[1] = buffer;
        } else {
            // 返回错误
            napi_create_string_utf8(env, taskData->errorMsg.c_str(), 
                                   NAPI_AUTO_LENGTH, &args[0]);
            napi_get_null(env, &args[1]);
        }
        
        // 调用回调函数
        napi_value global;
        napi_get_global(env, &global);
        napi_make_callback(env, nullptr, global, callback, 2, args, nullptr);
        
        // 清理资源
        napi_delete_reference(env, taskData->callback);
        delete taskData;
    };
    
    // 创建并排队异步工作
    napi_create_async_work(env, nullptr, workName, executeWork, completeWork, 
                          taskData, &work);
    napi_queue_async_work(env, work);
    
    // 返回undefined（异步操作）
    napi_value result;
    napi_get_undefined(env, &result);
    return result;
}

// 清理缓存函数（可选，在断开相机连接时调用）
void ClearPhotoCache() {
    std::lock_guard<std::mutex> lock(g_cacheMutex);
    g_cachedFileList.clear();
    g_isFileListCached = false;
    OH_LOG_PrintMsg(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                   "已清理照片缓存");
}




/**
 * @brief NAPI接口：清理照片缓存
 * 注意：必须是napi_value返回类型，接受env和info参数
 */
napi_value ClearPhotoCacheNapi(napi_env env, napi_callback_info info) {
    OH_LOG_PrintMsg(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "调用 ClearPhotoCacheNapi");
    
    // 清理缓存
    ClearPhotoCache();
    
    // 返回 undefined（因为ArkTS层声明为 void 返回值）
    napi_value result;
    napi_get_undefined(env, &result);
    return result;
}


// ###########################################################################
// 优化部分，下载单张缩略图，到此截止
// ###########################################################################

 





// ###########################################################################
// 核心函数：下载进度回调函数
// ###########################################################################

// 1. 下载开始时调用
//    - target: 目标值（例如，文件总大小）
//    - text:   描述性文本（例如，"Downloading image.jpg"）
//    - 返回:    通常返回 GP_OK (0)
unsigned int progress_start_cb(GPContext *context, float target, const char *text, void *data) {
    DownloadProgressData *progress_data = static_cast<DownloadProgressData *>(data);
   if (progress_data) {
        progress_data->currentProgress = 0.0f;
        progress_data->totalSize = target; // 保存文件总大小
        // 打印开始日志（包含文件名和总大小）
        OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                     "文件 %{public}s 下载开始: %{public}s（总大小: %{public}f 字节）",
                     progress_data->fileName.c_str(), text, target);
    }
    return GP_OK;
}


// 2. 下载进度更新时调用 (核心回调)
//    - id:      进度任务ID（由 start 函数返回）
//    - current: 当前进度值（例如，已下载的字节数）
//    - 返回:    void
void progress_update_cb(GPContext *context, unsigned int id, float current, void *data) {
    DownloadProgressData *progress_data = static_cast<DownloadProgressData *>(data);
    if (progress_data && progress_data->totalSize > 0) {
        // 计算百分比（current是已下载字节数，totalSize是总字节数）
        float percentage = current / progress_data->totalSize;
        int progress = static_cast<int>(percentage * 100);
        // 打印百分比进度日志（与预期格式一致）
        OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG,
                     "文件 %{public}s 下载进度：%{public}d%%（已下载: %{public}f 字节 / 总大小: %{public}f 字节）",
                     progress_data->fileName.c_str(), progress, current, progress_data->totalSize);
        progress_data->currentProgress = percentage;
    } else if (progress_data) {
        // 若总大小未知，打印原始进度值
        OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG,
                     "文件 %{public}s 下载中...（当前已下载: %{public}f 字节）",
                     progress_data->fileName.c_str(), current);
    }
}

// 3. 下载结束时调用
//    - id:      进度任务ID
//    - 返回:    void
void progress_stop_cb(GPContext *context, unsigned int id, void *data) {
    DownloadProgressData *progress_data = static_cast<DownloadProgressData *>(data);
    if (progress_data) {
        int finalProgress = static_cast<int>(progress_data->currentProgress * 100);
        OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG,
                     "文件 %{public}s 下载结束，最终进度：%{public}d%%",
                     progress_data->fileName.c_str(), finalProgress);
    }
}







// ###########################################################################
// 核心函数：从相机下载照片到指定的沙箱文件路径
// ###########################################################################
/**
 * @brief 内部函数：根据"相机中的文件路径"，下载照片并直接写入到指定的沙箱文件中。
 * @param folder 照片在相机中的文件夹路径（如："/DCIM/100NIKON"）
 * @param filename 照片在相机中的文件名（如："DSC_0001.JPG"）
 * @param filePath 照片下载后在设备沙箱中的保存路径（如："/data/storage/el2/base/.../cache/temp_photo.jpg"）
 * @return bool 下载并成功写入文件返回true，失败返回false。
 */
bool InternalDownloadFile(const char* folder, const char* filename, const char* filePath) {
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "===== 开始执行 InternalDownloadFile =====");
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "参数: folder='%{public}s', filename='%{public}s', filePath='%{public}s'", folder, filename, filePath);

    // 1. 检查相机连接状态
    if (!g_connected) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "错误: 相机未连接，下载失败.");
        return false;
    }

    // 2. 检查目标文件路径是否有效
    if (filePath == nullptr || strlen(filePath) == 0) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "错误: 目标文件路径(filePath)为空.");
        return false;
    }

    CameraFile *file = nullptr;
    int ret = GP_OK;

    // 3. 创建 CameraFile 对象
    ret = gp_file_new(&file);
    if (ret != GP_OK) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "错误: 创建 CameraFile 对象失败. ret=%{public}d", ret);
        return false;
    }
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "成功: CameraFile 对象创建. file=%{public}p", file);
    
    
    // =====================================================================
    // 核心改动：设置进度回调
    // =====================================================================
    // 1. 创建并初始化进度数据结构体
    DownloadProgressData progress_data;
    progress_data.fileName = filename; // 将当前要下载的文件名传入
    progress_data.currentProgress = 0.0f;

    // 2. 向 g_context 注册你的回调函数和数据
    //    这告诉 libgphoto2：当下载开始、进度更新、结束时，
    //    请调用我的 progress_start_cb, progress_update_cb, progress_stop_cb 函数，
    //    并把 &progress_data 这个结构体指针作为参数传过去。
    gp_context_set_progress_funcs(
        g_context,
        progress_start_cb,   // 开始回调
        progress_update_cb,  // 进度更新回调
        progress_stop_cb,    // 结束回调
        &progress_data       // 要传递给回调函数的数据
    );

    // =====================================================================
    
    
    
    

    // 4. 调用 libgphoto2 核心下载接口
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "步骤 4: 调用 gp_camera_file_get 开始下载文件.");
    ret = gp_camera_file_get(g_camera, folder, filename, GP_FILE_TYPE_NORMAL, file, g_context);
    if (ret != GP_OK) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "错误: gp_camera_file_get 下载失败. ret=%{public}d", ret);
        gp_file_unref(file); // 释放已创建的对象
        return false;
    }
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "成功: gp_camera_file_get 下载文件成功.");


    // =====================================================================
    // 重要：下载完成后，移除回调函数
    // 这是一个好习惯，可以防止回调函数在后续操作中被意外调用，
    // 也可以避免悬挂指针的问题。
    // =====================================================================
    gp_context_set_progress_funcs(g_context, nullptr, nullptr, nullptr, nullptr);
    
    // =====================================================================

    // 5. 从 CameraFile 对象中提取数据和大小
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "步骤 5: 从 CameraFile 中提取数据和大小.");
    const char *fileData = nullptr;
    unsigned long fileSize = 0;
    gp_file_get_data_and_size(file, &fileData, &fileSize);

    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "提取结果: fileData=%{public}p, fileSize=%{public}lu bytes", fileData, fileSize);

    // 6. 检查提取的数据是否有效
    if (fileData == nullptr || fileSize == 0) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "错误: 提取的数据为空或大小为0.");
        gp_file_unref(file); // 释放资源
        return false;
    }

    // 7. 将数据写入到沙箱文件
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "步骤 7: 将数据写入沙箱文件: %{public}s", filePath);
    std::ofstream outFile(filePath, std::ios::binary);
    if (!outFile.is_open()) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "错误: 无法打开沙箱文件进行写入.");
        gp_file_unref(file); // 释放资源
        return false;
    }

    outFile.write(fileData, fileSize);
    outFile.close();
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "成功: 数据已全部写入沙箱文件.");

    // 8. 释放 CameraFile 对象
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "步骤 8: 释放 CameraFile 对象.");
    gp_file_unref(file);
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "成功: CameraFile 对象已释放.");

    // 9. 下载和写入全部成功
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "===== InternalDownloadFile 执行成功 =====");
    return true;
}


// ###########################################################################
// NAPI接口：下载照片到沙箱（暴露给ArkTS调用）
// ###########################################################################
/**
 * @brief ArkTS层调用此函数，传入相机文件路径和沙箱临时路径，触发下载。
 * @param env NAPI环境对象。
 * @param info NAPI回调信息对象。
 * @return napi_value 返回一个布尔值给ArkTS。true表示成功，false表示失败。
 */
napi_value DownloadPhoto(napi_env env, napi_callback_info info) {
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!");
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "!!!!!!!!!! 开始执行 NAPI 接口 DownloadPhoto !!!!!!!!!!");
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!");

    // 1. 准备提取3个参数
    size_t argc = 3;
    napi_value args[3];
    napi_status status = napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (status != napi_ok || argc < 3) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "错误: 提取参数失败或参数数量不足（需要3个）. status=%{public}d, argc=%{public}zu", status, argc);
        // 返回 false
        napi_value result;
        napi_get_boolean(env, false, &result);
        return result;
    }
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "成功: 提取参数成功.");

    // 2. 定义缓冲区并转换字符串参数
    char folder[256] = {0};
    char name[256] = {0};
    char tempFilePath[1024] = {0}; // 沙箱路径可能较长

    status = napi_get_value_string_utf8(env, args[0], folder, sizeof(folder), nullptr);
    if (status != napi_ok) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "错误: 转换 folder 参数失败. status=%{public}d", status);
        napi_value result;
        napi_get_boolean(env, false, &result);
        return result;
    }

    status = napi_get_value_string_utf8(env, args[1], name, sizeof(name), nullptr);
    if (status != napi_ok) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "错误: 转换 name 参数失败. status=%{public}d", status);
        napi_value result;
        napi_get_boolean(env, false, &result);
        return result;
    }

    status = napi_get_value_string_utf8(env, args[2], tempFilePath, sizeof(tempFilePath), nullptr);
    if (status != napi_ok) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "错误: 转换 tempFilePath 参数失败. status=%{public}d", status);
        napi_value result;
        napi_get_boolean(env, false, &result);
        return result;
    }
    
    // 打印接收到的完整参数
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "从 ArkTS 接收的参数:");
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "  folder:     '%{public}s'", folder);
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "  name:       '%{public}s'", name);
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "  tempFilePath: '%{public}s'", tempFilePath);

    // 3. 调用内部下载函数
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "准备调用 InternalDownloadFile...");
    bool success = InternalDownloadFile(folder, name, tempFilePath);
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "InternalDownloadFile 执行结果: %{public}s", success ? "成功" : "失败");

    // 4. 向 ArkTS 返回布尔结果
    napi_value result;
    napi_get_boolean(env, success, &result);

    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "!!!!!!!!!! DownloadPhoto 执行完毕，返回结果 !!!!!!!!!!");
    return result;
}

