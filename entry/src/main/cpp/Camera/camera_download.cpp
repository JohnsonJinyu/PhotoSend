//
// Created on 2025/11/10.
// 负责从机内下载照片
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".
// C++ 层需要实现的核心功能：获取缩略图列表和下载选中照片
#include "Camera/native_common.h"
#include "gphoto2/gphoto2-list.h"
#include "gphoto2/gphoto2-port-result.h"
#include <cstddef>
#include <cstdint>
#include <hilog/log.h>
#include <string>

#define LOG_DOMAIN 0x0005       // 日志域（自定义标识，区分不同模块日志）
#define LOG_TAG "Camera_Download" // 日志标签（日志中显示的模块名）

// 内部结构体：存储单张照片的缩略图信息
struct ThumbnailInfo {
    std::string folder;   // 相机中的文件夹路径
    std::string fileName; // 文件名
    uint8_t *thumbData;   // 缩略图二进制数据
    size_t thumbSize;     // 缩略图大小
};

// 存储异步任务所需数据（输入参数、结果、回调）
struct AsyncThumbnailData {
    napi_env env;               // NAPI环境
    napi_ref callback;          // ArkTS层传入的回调函数引用
    std::vector<ThumbnailInfo> result; // 异步操作结果
    int errorCode;              // 错误码（0表示成功）
    std::string errorMsg;       // 错误信息
};





// 主线程回调函数（处理结果并通知ArkTS）
static void CompleteAsyncWork(napi_env env, napi_status status, void* data) {
    AsyncThumbnailData* asyncData = static_cast<AsyncThumbnailData*>(data);
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
            ThumbnailInfo& info = asyncData->result[i];
            napi_value thumbObj;
            napi_create_object(env, &thumbObj);

            napi_set_named_property(env, thumbObj, "folder", CreateNapiString(env, info.folder.c_str()));
            napi_set_named_property(env, thumbObj, "filename", CreateNapiString(env, info.fileName.c_str()));
            
            napi_value thumbBuffer;
            napi_create_buffer_copy(env, info.thumbSize, info.thumbData, nullptr, &thumbBuffer);
            napi_set_named_property(env, thumbObj, "thumbnail", thumbBuffer);

            napi_set_element(env, resultArray, i, thumbObj);

            // 释放malloc的内存（避免泄漏）
            free(info.thumbData);
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
    napi_get_global(env, &global);
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
    CameraList *rootFolders  = nullptr;
    gp_list_new(&rootFolders );
    int ret = gp_camera_folder_list_folders(g_camera, "/", rootFolders , g_context);
    if (ret != GP_OK) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG,  "获取根目录下的文件夹失败: %{public}s", gp_result_as_string(ret));
        gp_list_free(rootFolders );
        return thumbList;
    }
    
    
    // 2、遍历根目录下的文件夹（如store_00010001），在其中寻找DCIM目录
    std::string dcimFolder; // 关键修改：用std::string存储，避免野指针 ，存储找到的DCIM目录完整路径
    int numRootFolders = gp_list_count(rootFolders);
    for (int i = 0; i < numRootFolders; i++) {
        const char* storageFolder; // 根目录下的存储文件夹（如store_00010001）
        gp_list_get_name(rootFolders, i, &storageFolder);
        OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "根目录下找到文件夹：%{public}s",storageFolder);
        
        // 将相对路径转化为据对路径（添加前缀“/”）
        std::string absoluteStoragePath = '/' + std::string(storageFolder);//转换为"/store_00010001"
        OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG,"转换为绝对路径：%{public}s", absoluteStoragePath.c_str());
        
        
        // 2.1 获取该存储文件夹下的子目录（检查是否有DCIM） 
        CameraList* storageSubFolders = nullptr;
        gp_list_new(&storageSubFolders);
        // 关键修改：传入绝对路径absoluteStoragePath.c_str()
        ret = gp_camera_folder_list_folders(g_camera, absoluteStoragePath.c_str(), storageSubFolders, g_context);
        if (ret != GP_OK) {
            OH_LOG_Print(LOG_APP, LOG_WARN, LOG_DOMAIN, LOG_TAG, "获取 %{public}s 下的子目录失败: %{public}s", absoluteStoragePath.c_str(), gp_result_as_string(ret));
            gp_list_free(storageSubFolders);
            continue;
        }
        
        // 2.2 在存储文件夹的子目录中寻找DCIM
        int numStorageSubFolders = gp_list_count(storageSubFolders);
        for (int j = 0 ;j < numStorageSubFolders  ;j++) {
            const char* subFolderName;
            gp_list_get_name(storageSubFolders, j, &subFolderName);
            OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "%{public}s下找到子目录：%{public}s", absoluteStoragePath.c_str(), subFolderName);
            
            
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
    //const char* photoFolder = nullptr;
    std::string photoFolder; // 关键修改：用std::string存储，避免野指针
    CameraList* dcimSubFolders = nullptr;
    gp_list_new(&dcimSubFolders);
    ret = gp_camera_folder_list_folders(g_camera, dcimFolder.c_str(), dcimSubFolders, g_context);
    if (ret == GP_OK && gp_list_count(dcimSubFolders) > 0) {
    // 取第一个子文件夹名称（相对路径，如100NCZ_F）
    const char* subFolderName;
    gp_list_get_name(dcimSubFolders, 0, &subFolderName);
    
    // 关键修改1：处理dcimFolder尾部可能的斜杠，避免拼接后出现双斜杠
    std::string dcimPathStr = dcimFolder;
    if (!dcimPathStr.empty() && dcimPathStr.back() == '/') {
        dcimPathStr.pop_back(); // 移除尾部斜杠
    }
    
    // 关键修改2：拼接绝对路径，确保无连续斜杠
    //std::string absolutePhotoPath = dcimPathStr + "/" + subFolderName;
        
        // 拼接绝对路径（用std::string存储，确保有效）
        photoFolder = dcimPathStr + "/" + subFolderName;
    
    // 关键修改3：再次验证路径格式（以/开头，无连续斜杠）
    if (photoFolder.empty() || photoFolder[0] != '/') {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "照片目录路径格式错误（不以/开头）：%{public}s", photoFolder.c_str());
        gp_list_free(dcimSubFolders);
        return thumbList;
    }
    if (photoFolder.find("//") != std::string::npos) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "照片目录路径包含连续斜杠：%{public}s", photoFolder.c_str());
        gp_list_free(dcimSubFolders);
        return thumbList;
    }
    
    //photoFolder = absolutePhotoPath.c_str();
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "找到照片存储目录（绝对路径，已校验）：%{public}s", photoFolder.c_str());
    } else {
        // 极端情况：DCIM下无子目录，直接用DCIM作为照片目录（确保无尾部斜杠）
        std::string dcimPathStr = dcimFolder;
        if (!dcimPathStr.empty() && dcimPathStr.back() == '/') {
            dcimPathStr.pop_back(); // 移除尾部斜杠
        }
        //photoFolder = dcimPathStr.c_str();
        photoFolder = dcimPathStr; // 直接用std::string赋值
        OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "DCIM下无子目录，使用DCIM作为照片目录：%{public}s", photoFolder.c_str());
    }
    gp_list_free(dcimSubFolders);
    
    
    // 4、获取照片目录下的所有文件
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "准备获取文件列表的路径：%{public}s", photoFolder.c_str());
    CameraList* files = nullptr;
    gp_list_new(&files);
    ret = gp_camera_folder_list_files(g_camera, photoFolder.c_str(), files, g_context);
    if (ret != GP_OK) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "获取照片目录下的文件列表失败:%{public}s",gp_result_as_string(ret));
        gp_list_free(files);
        return thumbList;
    }
    
    int numFiles = gp_list_count(files);
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "照片目录下找到%{public}d个文件",numFiles);
    
    // 5、遍历文件，提取每个文件的缩略图
    for (int i = 0; i< numFiles; i++) {
        const char* fileName;
        gp_list_get_name(files, i, &fileName);
        
        // 筛选照片文件(根据Nikon常见照片格式JPEG/NEF)
        if (strstr(fileName,".jpg")==nullptr && strstr(fileName, ".JPG") == nullptr
            && strstr(fileName, ".nef") == nullptr && strstr(fileName, ".NEF") == nullptr) {
            OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "跳过非照片文件：%{public}s",fileName);
            continue;
        }
        
        // 6、虎丘该文件的缩略图(GP_FILE_TYPE_THUMBNAIL)
        CameraFile* thumbFile = nullptr;
        gp_file_new(&thumbFile);
        // ibgphoto2 的类型定义规范：** 缩略图统一通过GP_FILE_TYPE_PREVIEW获取 **
        ret = gp_camera_file_get(g_camera, photoFolder.c_str(), fileName, GP_FILE_TYPE_PREVIEW, thumbFile, g_context);
        if (ret != GP_OK) {
            OH_LOG_Print(LOG_APP, LOG_WARN, LOG_DOMAIN, LOG_TAG,  "获取 %s 的缩略图失败: %{public}s", fileName, gp_result_as_string(ret));
            gp_file_unref(thumbFile);
            continue;
        }
        
        // 提取缩略图数据和大小（后续逻辑不变）
        const char* thumbData;
        unsigned long thumbSize;
        gp_file_get_data_and_size(thumbFile, &thumbData, &thumbSize);
        if (thumbSize == 0) {
            OH_LOG_Print(LOG_APP, LOG_WARN, LOG_DOMAIN, LOG_TAG, "%{public}s 的缩略图为空", fileName);
            gp_file_unref(thumbFile);
            continue;
        }
        
        
        // 保存到ThumbnailInfo结构体（后续逻辑不变）
        ThumbnailInfo info;
        info.folder = photoFolder;
        info.fileName = fileName;
        info.thumbSize = thumbSize;
        info.thumbData = (uint8_t*)malloc(thumbSize);  // 分配内存存储缩略图数据
        memcpy(info.thumbData, thumbData, thumbSize);
        
        thumbList.push_back(info);
        gp_file_unref(thumbFile);  // 释放缩略图文件对象
    }
    
    gp_list_free(files);  // 释放文件列表
    return thumbList;
    
}


// 后台线程执行的函数（耗时操作）
static void ExecuteAsyncWork(napi_env env, void* data) {
    AsyncThumbnailData* asyncData = static_cast<AsyncThumbnailData*>(data);
    try {
        // 执行耗时操作（获取缩略图列表）
        asyncData->result = InternalGetThumbnailList();
        asyncData->errorCode = 0;
    } catch (const std::exception& e) {
        // 捕获异常，记录错误信息
        asyncData->errorCode = -1;
        asyncData->errorMsg = e.what();
    }
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
    AsyncThumbnailData* asyncData = new AsyncThumbnailData();
    asyncData->env = env;
    // 保存回调函数引用（延长生命周期）
    napi_create_reference(env, args[0], 1, &asyncData->callback);

    // 4. 创建异步工作项
    napi_value workName;
    napi_create_string_utf8(env, "GetThumbnailListAsync", NAPI_AUTO_LENGTH, &workName);
    napi_async_work work;
    napi_create_async_work(
        env,
        nullptr,
        workName,
        ExecuteAsyncWork,    // 后台执行函数
        CompleteAsyncWork,   // 主线程完成回调
        asyncData,
        &work
    );

    // 5. 队列化异步工作（立即执行）
    napi_queue_async_work(env, work);

    // 6. 返回undefined（异步接口无需同步返回结果）
    napi_value result;
    napi_get_undefined(env, &result);
    return result;
}