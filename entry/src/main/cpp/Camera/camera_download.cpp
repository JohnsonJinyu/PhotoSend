// camera_download.cpp
// Created on 2025/11/10.
// 负责从机内下载照片
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".
// C++ 层需要实现的核心功能：获取缩略图列表和下载选中照片
#include "Camera/camera_download.h"
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

#define LOG_DOMAIN 0x0005         // 日志域（自定义标识，区分不同模块日志）
#define LOG_TAG "Camera_Download" // 日志标签（日志中显示的模块名）



// 全局变量：温存文件列表（提高性能）
static std::vector<PhotoMeta> g_cachedFileList;
static bool g_isFileListCached = false;
static std::mutex g_cacheMutex;



// 主线程回调函数（处理结果并通知ArkTS）
static void CompleteAsyncWork(napi_env env, napi_status status, void *data) {
    AsyncThumbnailData *asyncData = static_cast<AsyncThumbnailData *>(data);
    if (!asyncData || !asyncData->callback) {
        return;
    }

    // 1. 创建回调参数（[error, result]）
    napi_value args[2];
    // 错误信息（null表示无错误）
    napi_get_null(env, &args[0]);
    // 结果数组（默认空）
    napi_value resultArray;
    napi_create_array(env, &resultArray);

    if (asyncData->errorCode == 0) {
        // 2. 转换结果为NAPI数组（与原同步逻辑一致）
        for (size_t i = 0; i < asyncData->result.size(); i++) {
            ThumbnailInfo &info = asyncData->result[i];
            napi_value thumbObj;
            napi_create_object(env, &thumbObj);

            napi_set_named_property(env, thumbObj, "folder", CreateNapiString(env, info.folder.c_str()));
            napi_set_named_property(env, thumbObj, "filename", CreateNapiString(env, info.fileName.c_str()));

            napi_value thumbBuffer = nullptr; // 显式初始化为nullptr

            OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG,
                         "文件 %{public}s 的thumbData地址：%{public}p，准备包装为外部缓冲区", 
                         info.fileName.c_str(), info.thumbData);
            
            // 关键修改：使用napi_create_external_buffer包装已有内存
            // 定义finalize回调函数：当ArkTS层不再使用该缓冲区时释放内存
            auto finalize = [](napi_env env, void *data, void *hint) {
                OH_LOG_PrintMsg(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "自动释放缩略图内存");
                free(data); // 释放malloc分配的内存
            };
            
            // 创建外部缓冲区（不复制数据，直接包装info.thumbData）
            napi_status createStatus = napi_create_external_buffer(
                env,
                info.thumbSize,       // 数据长度
                info.thumbData,       // 已分配的内存指针（malloc的结果）
                finalize,             // 内存释放回调
                nullptr,              // 回调参数（无需求时为nullptr）
                &thumbBuffer          // 输出的Buffer对象
            );
            
            // 检查创建是否成功
            if (createStatus != napi_ok) {
                OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG,
                             "文件 %{public}s 的外部缓冲区创建失败，状态码：%{public}d", 
                             info.fileName.c_str(), createStatus);
                free(info.thumbData); // 若创建失败，手动释放内存
                continue;
            }
            
            // 设置缩略图属性
            napi_set_named_property(env, thumbObj, "thumbnail", thumbBuffer);
            napi_set_element(env, resultArray, i, thumbObj);


        }
        args[1] = resultArray;
    } else {
        // 3. 处理错误（将错误信息作为第一个参数）
        napi_create_string_utf8(env, asyncData->errorMsg.c_str(), NAPI_AUTO_LENGTH, &args[0]);
        napi_get_null(env, &args[1]); // 结果为null
    }

    // 4. 调用ArkTS层回调函数
    napi_value callback;
    napi_get_reference_value(env, asyncData->callback, &callback);
    napi_value global;
    // napi_get_global(env, &global);
    napi_status envStatus = napi_get_global(env, &global);
    if (envStatus != napi_ok) {
        OH_LOG_PrintMsg(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "env已失效！");
        return;
    }

    napi_make_callback(env, nullptr, global, callback, 2, args, nullptr);

    // 5. 释放资源
    napi_delete_reference(env, asyncData->callback);
    delete asyncData;
}


/**
 * 内部函数：遍历相机照片目录，获取所有照片的缩略图信息
 * */

static std::vector<ThumbnailInfo> InternalGetThumbnailList() {
    std::vector<ThumbnailInfo> thumbList;
    if (!g_connected || !g_context || !g_camera) {
        OH_LOG_PrintMsg(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "相机未连接，无法获取缩略图");
        return thumbList;
    }

    // 1、获取相机根目录下的所有文件夹（如store_00010001，对应存储卡根目录）
    CameraList *rootFolders = nullptr;
    gp_list_new(&rootFolders);
    int ret = gp_camera_folder_list_folders(g_camera, "/", rootFolders, g_context);
    if (ret != GP_OK) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "获取根目录下的文件夹失败: %{public}s",
                     gp_result_as_string(ret));
        gp_list_free(rootFolders);
        return thumbList;
    }


    // 2、遍历根目录下的文件夹（如store_00010001），在其中寻找DCIM目录
    std::string dcimFolder; // 关键修改：用std::string存储，避免野指针 ，存储找到的DCIM目录完整路径
    int numRootFolders = gp_list_count(rootFolders);
    for (int i = 0; i < numRootFolders; i++) {
        const char *storageFolder; // 根目录下的存储文件夹（如store_00010001）
        gp_list_get_name(rootFolders, i, &storageFolder);
        OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "根目录下找到文件夹：%{public}s", storageFolder);

        // 将相对路径转化为据对路径（添加前缀“/”）
        std::string absoluteStoragePath = '/' + std::string(storageFolder); // 转换为"/store_00010001"
        OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "转换为绝对路径：%{public}s", absoluteStoragePath.c_str());


        // 2.1 获取该存储文件夹下的子目录（检查是否有DCIM）
        CameraList *storageSubFolders = nullptr;
        gp_list_new(&storageSubFolders);
        // 关键修改：传入绝对路径absoluteStoragePath.c_str()
        ret = gp_camera_folder_list_folders(g_camera, absoluteStoragePath.c_str(), storageSubFolders, g_context);
        if (ret != GP_OK) {
            OH_LOG_Print(LOG_APP, LOG_WARN, LOG_DOMAIN, LOG_TAG, "获取 %{public}s 下的子目录失败: %{public}s",
                         absoluteStoragePath.c_str(), gp_result_as_string(ret));
            gp_list_free(storageSubFolders);
            continue;
        }

        // 2.2 在存储文件夹的子目录中寻找DCIM
        int numStorageSubFolders = gp_list_count(storageSubFolders);
        for (int j = 0; j < numStorageSubFolders; j++) {
            const char *subFolderName;
            gp_list_get_name(storageSubFolders, j, &subFolderName);
            OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "%{public}s下找到子目录：%{public}s",
                         absoluteStoragePath.c_str(), subFolderName);


            // 找到DCIM目录，拼接完整绝对路径（如"/store_00010001/DCIM"）
            if (strstr(subFolderName, "DCIM") != nullptr) {
                // 直接用std::string存储dcimFolder，避免依赖局部变量
                dcimFolder = absoluteStoragePath + "/" + subFolderName;
                OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "找到DCIM目录：%{public}s", dcimFolder.c_str());
                gp_list_free(storageSubFolders);
                goto found_dcim;
            }
        }


        gp_list_free(storageSubFolders);
    }
found_dcim:

    gp_list_free(rootFolders); // 释放根目录文件夹列表

    // 若未找到照片目录，直接返回空列表
    if (dcimFolder.empty()) { // 检查字符串是否为空，而非指针是否为null
        OH_LOG_PrintMsg(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "未找到DCIM或照片存储目录");
        return thumbList;
    }


    // 3、获取DCIM目录下的子文件夹（如100NCZ_F，用户自定义）
    // const char* photoFolder = nullptr;
    std::string photoFolder; // 关键修改：用std::string存储，避免野指针
    CameraList *dcimSubFolders = nullptr;
    gp_list_new(&dcimSubFolders);
    ret = gp_camera_folder_list_folders(g_camera, dcimFolder.c_str(), dcimSubFolders, g_context);
    if (ret == GP_OK && gp_list_count(dcimSubFolders) > 0) {
        // 取第一个子文件夹名称（相对路径，如100NCZ_F）
        const char *subFolderName;
        gp_list_get_name(dcimSubFolders, 0, &subFolderName);

        // 关键修改1：处理dcimFolder尾部可能的斜杠，避免拼接后出现双斜杠
        std::string dcimPathStr = dcimFolder;
        if (!dcimPathStr.empty() && dcimPathStr.back() == '/') {
            dcimPathStr.pop_back(); // 移除尾部斜杠
        }

        // 关键修改2：拼接绝对路径，确保无连续斜杠
        // std::string absolutePhotoPath = dcimPathStr + "/" + subFolderName;

        // 拼接绝对路径（用std::string存储，确保有效）
        photoFolder = dcimPathStr + "/" + subFolderName;

        // 关键修改3：再次验证路径格式（以/开头，无连续斜杠）
        if (photoFolder.empty() || photoFolder[0] != '/') {
            OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "照片目录路径格式错误（不以/开头）：%{public}s",
                         photoFolder.c_str());
            gp_list_free(dcimSubFolders);
            return thumbList;
        }
        if (photoFolder.find("//") != std::string::npos) {
            OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "照片目录路径包含连续斜杠：%{public}s",
                         photoFolder.c_str());
            gp_list_free(dcimSubFolders);
            return thumbList;
        }

        // photoFolder = absolutePhotoPath.c_str();
        OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "找到照片存储目录（绝对路径，已校验）：%{public}s",
                     photoFolder.c_str());
    } else {
        // 极端情况：DCIM下无子目录，直接用DCIM作为照片目录（确保无尾部斜杠）
        std::string dcimPathStr = dcimFolder;
        if (!dcimPathStr.empty() && dcimPathStr.back() == '/') {
            dcimPathStr.pop_back(); // 移除尾部斜杠
        }
        // photoFolder = dcimPathStr.c_str();
        photoFolder = dcimPathStr; // 直接用std::string赋值
        OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "DCIM下无子目录，使用DCIM作为照片目录：%{public}s",
                     photoFolder.c_str());
    }
    gp_list_free(dcimSubFolders);


    // 4、获取照片目录下的所有文件
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "准备获取文件列表的路径：%{public}s", photoFolder.c_str());
    CameraList *files = nullptr;
    gp_list_new(&files);
    ret = gp_camera_folder_list_files(g_camera, photoFolder.c_str(), files, g_context);
    if (ret != GP_OK) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "获取照片目录下的文件列表失败:%{public}s",
                     gp_result_as_string(ret));
        gp_list_free(files);
        return thumbList;
    }

    int numFiles = gp_list_count(files);
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "照片目录下找到%{public}d个文件", numFiles);

    // 5、遍历文件，提取每个文件的缩略图
    for (int i = 0; i < numFiles; i++) {
        const char *fileName;
        gp_list_get_name(files, i, &fileName);

        // 筛选照片文件(根据Nikon常见照片格式JPEG/NEF)
        if (strstr(fileName, ".jpg") == nullptr && strstr(fileName, ".JPG") == nullptr &&
            strstr(fileName, ".nef") == nullptr && strstr(fileName, ".NEF") == nullptr) {
            OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "跳过非照片文件：%{public}s", fileName);
            continue;
        }

        // 6、虎丘该文件的缩略图(GP_FILE_TYPE_THUMBNAIL)
        CameraFile *thumbFile = nullptr;
        gp_file_new(&thumbFile);
        // ibgphoto2 的类型定义规范：** 缩略图统一通过GP_FILE_TYPE_PREVIEW获取 **
        ret = gp_camera_file_get(g_camera, photoFolder.c_str(), fileName, GP_FILE_TYPE_PREVIEW, thumbFile, g_context);
        if (ret != GP_OK) {
            OH_LOG_Print(LOG_APP, LOG_WARN, LOG_DOMAIN, LOG_TAG, "获取 %{public}s 的缩略图失败: %{public}s", fileName,
                         gp_result_as_string(ret));
            gp_file_unref(thumbFile);
            continue;
        }

        // 提取缩略图数据和大小（后续逻辑不变）
        const char *thumbData;
        unsigned long thumbSize;
        gp_file_get_data_and_size(thumbFile, &thumbData, &thumbSize);
        if (thumbData == nullptr || thumbSize == 0) {
            OH_LOG_Print(LOG_APP, LOG_WARN, LOG_DOMAIN, LOG_TAG, "%{public}s 的缩略图数据无效（指针为空或大小为0）",
                         fileName);
            gp_file_unref(thumbFile);
            continue;
        }


        OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG,
                     "文件 %{public}s 的缩略图大小：%{public}lu 字节，数据指针：%{public}p", fileName, thumbSize,
                     thumbData);

        // 保存到ThumbnailInfo结构体（后续逻辑不变）
        ThumbnailInfo info;
        info.folder = photoFolder;
        info.fileName = fileName;
        info.thumbSize = thumbSize;
        info.thumbData = (uint8_t *)malloc(thumbSize); // 分配内存存储缩略图数据

        if (info.thumbData == nullptr) {
            OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG,
                         "文件 %{public}s 分配缩略图内存失败（大小：%{public}lu）", fileName, thumbSize);
            continue;
        }

        memcpy(info.thumbData, thumbData, thumbSize);

        if (thumbSize >= 2) {
            OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG,
                         "文件 %{public}s 复制后的数据头：0x%{public}02X%{public}02X", fileName, info.thumbData[0],
                         info.thumbData[1]);
        }

        // 验证JPEG格式（关键：避免无效数据传入ArkTS）
        if (thumbSize < 2 || info.thumbData[0] != 0xFF || info.thumbData[1] != 0xD8) {
            OH_LOG_Print(LOG_APP, LOG_WARN, LOG_DOMAIN, LOG_TAG, "%{public}s 不是有效的JPEG缩略图", fileName);
            free(info.thumbData); // 释放无效数据
            continue;
        }

        thumbList.push_back(info);
        gp_file_unref(thumbFile); // 释放缩略图文件对象
    }

    gp_list_free(files); // 释放文件列表
    return thumbList;
}


// 后台线程执行的函数（耗时操作）
static void ExecuteAsyncWork(napi_env env, void *data) {
    AsyncThumbnailData *asyncData = static_cast<AsyncThumbnailData *>(data);
    try {
        // 执行耗时操作（获取缩略图列表）
        asyncData->result = InternalGetThumbnailList();

        asyncData->errorCode = 0;
    } catch (const std::exception &e) {
        // 捕获异常，记录错误信息
        asyncData->errorCode = -1;
        asyncData->errorMsg = e.what();
    }
}






// ###########################################################################
// 优化部分:1、获取机内照片总数的实现
// ###########################################################################

/**
 * @brief 内部函数：获取照片总数（不加载缩略图）
 */
static int InternalGetPhotoTotalCount(){
    if (!g_connected || !g_context || !g_camera) {
        OH_LOG_PrintMsg(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "相机未连接，无法获取照片总数");
        return 0;;
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
    
    // 扫描相机获取文件列表（不获取缩略图）
    std::vector<PhotoMeta> fileList = InternalScanPhotoFilesOnly();
    
    {
        std::lock_guard<std::mutex> lock(g_cacheMutex);
        g_cachedFileList = fileList;
        g_isFileListCached = true;
        OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                    "扫描完成，照片总数: %{public}zu", g_cachedFileList.size());
    }
    
    return static_cast<int>(fileList.size());
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
// 优化部分，分也获取照片元信息
// ###########################################################################
/**
 * @brief NAPI接口：分页获取照片元信息
 */

napi_value GetPhotoMetaList(napi_env env, napi_callback_info info){
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
    
    // 3. 确保文件列表已缓存
    {
        std::lock_guard<std::mutex> lock(g_cacheMutex);
        if (!g_isFileListCached) {
            OH_LOG_PrintMsg(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                          "文件列表未缓存，开始扫描...");
            g_cachedFileList = InternalScanPhotoFilesOnly();
            g_isFileListCached = true;
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
        OH_LOG_PrintMsg(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, 
                       "相机未连接，无法下载缩略图");
        return thumbnailData;
    }
    
    CameraFile *thumbFile = nullptr;
    gp_file_new(&thumbFile);
    
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                "开始下载缩略图: %{public}s/%{public}s", folder, filename);
    
    // 获取缩略图
    int ret = gp_camera_file_get(g_camera, folder, filename, 
                                GP_FILE_TYPE_PREVIEW, thumbFile, g_context);
    
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
 * 异步NAPI接口：接收ArkTS层的回调函数，在后台获取缩略图列表后触发回调
 * 调用方式（ArkTS）：GetThumbnailList((err, list) => { ... })
 */
napi_value GetThumbnailList(napi_env env, napi_callback_info info) {
    // 1. 解析输入参数（获取ArkTS层传入的回调函数）
    size_t argc = 1;
    napi_value args[1];
    napi_value thisArg;
    napi_status status = napi_get_cb_info(env, info, &argc, args, &thisArg, nullptr);
    if (status != napi_ok || argc < 1) {
        OH_LOG_PrintMsg(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "参数错误：需要传入回调函数");
        return nullptr;
    }

    // 2. 验证回调函数类型
    napi_valuetype argType;
    napi_typeof(env, args[0], &argType);
    if (argType != napi_function) {
        OH_LOG_PrintMsg(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "参数错误：第一个参数必须是函数");
        return nullptr;
    }

    // 3. 创建异步任务数据
    AsyncThumbnailData *asyncData = new AsyncThumbnailData();
    asyncData->env = env;
    // 保存回调函数引用（延长生命周期）
    napi_create_reference(env, args[0], 1, &asyncData->callback);

    // 4. 创建异步工作项
    napi_value workName;
    napi_create_string_utf8(env, "GetThumbnailListAsync", NAPI_AUTO_LENGTH, &workName);
    napi_async_work work;
    napi_create_async_work(env, nullptr, workName,
                           ExecuteAsyncWork,  // 后台执行函数
                           CompleteAsyncWork, // 主线程完成回调
                           asyncData, &work);

    // 5. 队列化异步工作（立即执行）
    napi_queue_async_work(env, work);

    // 6. 返回undefined（异步接口无需同步返回结果）
    napi_value result;
    napi_get_undefined(env, &result);
    return result;
}



// ###########################################################################
// 优化部分，主要优化获取机内照片信息，实现按需加载
// ###########################################################################
/**
 * @brief 内部函数： 获取照片的总数
 * */





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

