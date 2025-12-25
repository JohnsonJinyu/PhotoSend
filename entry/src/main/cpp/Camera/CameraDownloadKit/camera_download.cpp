// camera_download.cpp
// Created on 2025/11/10.
// 负责从机内下载照片
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".
// C++ 层需要实现的核心功能：获取缩略图列表和下载选中照片
#include "camera_download.h"
#include <Camera/CameraDownloadKit/PhotoScanner/PhotoScanner.h>
#include "Camera/CameraDownloadKit/ThumbnailDownloader/ThumbnailDownloader.h"
#include "Camera/CameraDownloadKit/PhotoDownloader/PhotoDownloader.h"
#include "Camera/native_common.h"
#include <hilog/log.h>
#include <memory>
#include <thread>
#include <condition_variable>

#define LOG_DOMAIN 0x0005
#define LOG_TAG "Camera_Download"

// 全局模块实例
static std::unique_ptr<PhotoScanner> g_photoScanner;
static std::unique_ptr<ThumbnailDownloader> g_thumbnailDownloader;
static std::unique_ptr<PhotoDownloader> g_photoDownloader;

// 辅助函数：创建NAPI字符串
static napi_value CreateNapiStringHelper(napi_env env, const char* str) {
    napi_value result;
    napi_create_string_utf8(env, str, NAPI_AUTO_LENGTH, &result);
    return result;
}

// ========== 模块初始化函数 ==========
void InitCameraDownloadModules() {
    if (!g_photoScanner) {
        g_photoScanner = std::make_unique<PhotoScanner>();
    }
    
    if (!g_thumbnailDownloader) {
        g_thumbnailDownloader = std::make_unique<ThumbnailDownloader>();
    }
    
    if (!g_photoDownloader) {
        g_photoDownloader = std::make_unique<PhotoDownloader>();
    }
    
    // 初始化模块
    if (g_camera && g_context) {
        g_photoScanner->Init(g_camera, g_context);
        g_thumbnailDownloader->Init(g_camera, g_context);
        g_photoDownloader->Init(g_camera, g_context);
    }
}

// ========== 模块清理函数 ==========
void CleanupCameraDownloadModules() {
    if (g_photoScanner) {
        g_photoScanner->Cleanup();
    }
    
    if (g_thumbnailDownloader) {
        g_thumbnailDownloader->Cleanup();
    }
    
    if (g_photoDownloader) {
        g_photoDownloader->Cleanup();
    }
}

// ========== 缩略图信号量相关函数 ==========
void InitThumbnailSemaphore() {
    if (g_thumbnailDownloader) {
        g_thumbnailDownloader->InitSemaphore();
    }
}

void CleanupThumbnailSemaphore() {
    if (g_thumbnailDownloader) {
        g_thumbnailDownloader->CleanupSemaphore();
    }
}

// ========== NAPI接口实现 ==========

napi_value GetPhotoTotalCount(napi_env env, napi_callback_info info) {
    if (!g_photoScanner) {
        OH_LOG_PrintMsg(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, 
                       "照片扫描器未初始化");
        napi_value result;
        napi_create_int32(env, 0, &result);
        return result;
    }
    
    int totalCount = g_photoScanner->GetPhotoTotalCount();
    napi_value result;
    napi_create_int32(env, totalCount, &result);
    
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                "GetPhotoTotalCount 返回: %{public}d", totalCount);
    
    return result;
}

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
    
    // 3. 检查扫描器是否初始化
    if (!g_photoScanner) {
        OH_LOG_PrintMsg(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, 
                       "照片扫描器未初始化");
        napi_value emptyArray;
        napi_create_array(env, &emptyArray);
        return emptyArray;
    }
    
    // 4. 获取照片元信息
    auto photoList = g_photoScanner->GetPhotoMetaList(pageIndex, pageSize);
    
    // 5. 创建返回数组
    napi_value resultArray;
    napi_create_array(env, &resultArray);
    
    for (size_t i = 0; i < photoList.size(); i++) {
        const PhotoMeta& meta = photoList[i];
        
        napi_value metaObj;
        napi_create_object(env, &metaObj);
        
        // 设置属性
        napi_set_named_property(env, metaObj, "folder", 
                              CreateNapiStringHelper(env, meta.folder.c_str()));
        napi_set_named_property(env, metaObj, "filename", 
                              CreateNapiStringHelper(env, meta.fileName.c_str()));
        
        // 如果有文件大小，也返回
        if (meta.fileSize > 0) {
            napi_value sizeValue;
            napi_create_int64(env, meta.fileSize, &sizeValue);
            napi_set_named_property(env, metaObj, "size", sizeValue);
        }
        
        // 添加到数组
        napi_set_element(env, resultArray, i, metaObj);
    }
    
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                "GetPhotoMetaList 返回 %{public}zu 条记录", photoList.size());
    
    return resultArray;
}

napi_value DownloadSingleThumbnail(napi_env env, napi_callback_info info) {
    // 1. 解析参数
    size_t argc = 3;
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
    taskData->errorMsg = "";
    
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
            if (!g_thumbnailDownloader) {
                taskData->errorMsg = "缩略图下载器未初始化";
                taskData->success = false;
                return;
            }
            
            taskData->thumbnailData = g_thumbnailDownloader->DownloadSingleThumbnail(
                taskData->folder, taskData->filename);
            taskData->success = !taskData->thumbnailData.empty();
            
            if (!taskData->success) {
                taskData->errorMsg = "下载缩略图失败";
            }
        } catch (const std::exception& e) {
            taskData->errorMsg = e.what();
            taskData->success = false;
        } catch (...) {
            taskData->errorMsg = "未知异常";
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

napi_value DownloadPhoto(napi_env env, napi_callback_info info) {
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                "!!!!!!!!!! 开始执行 NAPI 接口 DownloadPhoto !!!!!!!!!!");
    
    // 1. 准备提取3个参数
    size_t argc = 3;
    napi_value args[3];
    napi_status status = napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (status != napi_ok || argc < 3) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, 
                   "错误: 提取参数失败或参数数量不足（需要3个）");
        napi_value result;
        napi_get_boolean(env, false, &result);
        return result;
    }
    
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "成功: 提取参数成功");
    
    // 2. 定义缓冲区并转换字符串参数
    char folder[256] = {0};
    char name[256] = {0};
    char tempFilePath[1024] = {0};
    
    status = napi_get_value_string_utf8(env, args[0], folder, sizeof(folder), nullptr);
    if (status != napi_ok) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, 
                   "错误: 转换 folder 参数失败");
        napi_value result;
        napi_get_boolean(env, false, &result);
        return result;
    }
    
    status = napi_get_value_string_utf8(env, args[1], name, sizeof(name), nullptr);
    if (status != napi_ok) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, 
                   "错误: 转换 name 参数失败");
        napi_value result;
        napi_get_boolean(env, false, &result);
        return result;
    }
    
    status = napi_get_value_string_utf8(env, args[2], tempFilePath, sizeof(tempFilePath), nullptr);
    if (status != napi_ok) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, 
                   "错误: 转换 tempFilePath 参数失败");
        napi_value result;
        napi_get_boolean(env, false, &result);
        return result;
    }
    
    // 打印接收到的完整参数
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                "从 ArkTS 接收的参数:");
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                "  folder:     '%{public}s'", folder);
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                "  name:       '%{public}s'", name);
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                "  tempFilePath: '%{public}s'", tempFilePath);
    
    // 3. 调用照片下载器
    if (!g_photoDownloader) {
        OH_LOG_PrintMsg(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, 
                       "照片下载器未初始化");
        napi_value result;
        napi_get_boolean(env, false, &result);
        return result;
    }
    
    bool success = g_photoDownloader->DownloadFile(folder, name, tempFilePath);
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                "DownloadFile 执行结果: %{public}s", success ? "成功" : "失败");
    
    if (!success) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, 
                   "错误: %{public}s", g_photoDownloader->GetLastError().c_str());
    }
    
    // 4. 向 ArkTS 返回布尔结果
    napi_value result;
    napi_get_boolean(env, success, &result);
    
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                "!!!!!!!!!! DownloadPhoto 执行完毕，返回结果 !!!!!!!!!!");
    return result;
}

napi_value ClearPhotoCacheNapi(napi_env env, napi_callback_info info) {
    OH_LOG_PrintMsg(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "调用 ClearPhotoCacheNapi");
    
    if (g_photoScanner) {
        g_photoScanner->ClearCache();
    }
    
    // 返回 undefined
    napi_value result;
    napi_get_undefined(env, &result);
    return result;
}

napi_value StartAsyncScan(napi_env env, napi_callback_info info) {
    if (!g_photoScanner) {
        OH_LOG_PrintMsg(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "照片扫描器未初始化");
        napi_value result;
        napi_get_boolean(env, false, &result);
        return result;
    }
    
    bool success = g_photoScanner->StartAsyncScan();
    
    napi_value result;
    napi_get_boolean(env, success, &result);
    return result;
}

napi_value IsScanComplete(napi_env env, napi_callback_info info) {
    if (!g_photoScanner) {
        OH_LOG_PrintMsg(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "照片扫描器未初始化");
        napi_value result;
        napi_get_boolean(env, false, &result);
        return result;
    }
    
    bool isComplete = g_photoScanner->IsScanComplete();
    
    napi_value result;
    napi_get_boolean(env, isComplete, &result);
    return result;
}

napi_value GetScanProgress(napi_env env, napi_callback_info info) {
    napi_value result;
    napi_create_object(env, &result);
    
    if (!g_photoScanner) {
        // 如果扫描器未初始化，返回默认值
        napi_value scanningValue;
        napi_get_boolean(env, false, &scanningValue);
        napi_set_named_property(env, result, "scanning", scanningValue);
        
        napi_value currentValue;
        napi_create_int32(env, 0, &currentValue);
        napi_set_named_property(env, result, "current", currentValue);
        
        napi_value totalValue;
        napi_create_int32(env, 0, &totalValue);
        napi_set_named_property(env, result, "total", totalValue);
        
        napi_value cachedValue;
        napi_get_boolean(env, false, &cachedValue);
        napi_set_named_property(env, result, "cached", cachedValue);
        
        return result;
    }
    
    // 获取扫描进度
    int current = 0, total = 0;
    bool cached = false;
    bool scanning = g_photoScanner->GetScanProgress(current, total, cached);
    
    // 添加扫描中状态
    napi_value scanningValue;
    napi_get_boolean(env, scanning, &scanningValue);
    napi_set_named_property(env, result, "scanning", scanningValue);
    
    // 添加当前进度
    napi_value currentValue;
    napi_create_int32(env, current, &currentValue);
    napi_set_named_property(env, result, "current", currentValue);
    
    // 添加总进度
    napi_value totalValue;
    napi_create_int32(env, total, &totalValue);
    napi_set_named_property(env, result, "total", totalValue);
    
    // 添加缓存状态
    napi_value cachedValue;
    napi_get_boolean(env, cached, &cachedValue);
    napi_set_named_property(env, result, "cached", cachedValue);
    
    // 添加照片总数（如果缓存存在）
    if (cached) {
        // 注意：这里需要从扫描器获取总数，但GetScanProgress没有返回这个信息
        // 我们可以在扫描器添加一个GetCachedCount方法，或者在这里直接调用GetPhotoTotalCount
        // 这里暂时不添加count字段，因为需要额外的方法
    }
    
    return result;
}

/*
napi_value DisconnectCamera(napi_env env, napi_callback_info info) {
    OH_LOG_PrintMsg(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "断开相机连接，清理下载模块");
    
    // 清理模块
    CleanupCameraDownloadModules();
    
    // 返回 true
    napi_value result;
    napi_get_boolean(env, true, &result);
    return result;
}*/
