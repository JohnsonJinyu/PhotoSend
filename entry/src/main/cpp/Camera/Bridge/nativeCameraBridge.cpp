// nativeCameraBridge.cpp
// 主接口实现（调用其他模块）

// ###########################################################################
// 头文件引入：依赖库的核心接口定义
// ###########################################################################
#include <napi/native_api.h>
#include "../Core/Device/NapiDeviceInterface.h"
#include "Camera/CameraDownloadKit/camera_download.h"
#include "../Core/Media/ExifProcessor.h"
#include "Camera/Common/Constants.h"
#include "napi/native_api.h"
#include <hilog/log.h>
#include <Camera/Common/Constants.h>
#include "../Common/native_common.h"
#include "../Core/Device/NapiDeviceInterface.h"
#include "../Core/Config/camera_config.h"
#include "../Core/Capture/camera_preview.h"
#include "../Core/Capture/camera_capture.h"

// ###########################################################################
//  宏定义：日志配置（固定格式，方便定位日志来源）
// ###########################################################################
#define LOG_DOMAIN ModuleLogs::NativeCameraBridge.domain
#define LOG_TAG ModuleLogs::NativeCameraBridge.tag

// ###########################################################################
// NAPI模块注册：将C++函数映射为ArkTS可调用的接口（关键步骤）
// ###########################################################################
EXTERN_C_START
/**
 * @brief 模块初始化函数：so库被加载时，NAPI框架自动调用此函数
 */
static napi_value Init(napi_env env, napi_value exports) {
    // napi_property_descriptor：NAPI结构体，定义"ArkTS函数名→C++函数"的映射关系
    napi_property_descriptor api_list[] = {
        // 设备管理接口
        {"GetAvailableCameras", nullptr, GetAvailableCameras, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"SetGPhotoLibDirs", nullptr, SetGPhotoLibDirs, nullptr, nullptr, nullptr, napi_default, nullptr},
        
        // 连接接口（增强版）
        {"ConnectCamera", nullptr, ConnectCamera, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"ConnectCameraAPMode", nullptr, ConnectCameraAPMode, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"QuickConnectNikon", nullptr, QuickConnectNikon, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"DisconnectCamera", nullptr, DisconnectCamera, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"IsCameraConnected", nullptr, IsCameraConnectedNapi, nullptr, nullptr, nullptr, napi_default, nullptr},
        
        // 连接状态查询接口
        {"GetConnectionStatusInfo", nullptr, GetConnectionStatusInfo, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"QuickConnectionTest", nullptr, QuickConnectionTest, nullptr, nullptr, nullptr, napi_default, nullptr},
        
        // 原有其他接口（保持兼容）
        {"TakePhoto", nullptr, TakePhoto, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"DownloadPhoto", nullptr, DownloadPhoto, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"SetCameraParameter", nullptr, SetCameraParameter, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"GetPreview", nullptr, GetPreviewNapi, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"GetCameraStatus", nullptr, GetCameraStatus, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"GetCameraConfig", nullptr, GetCameraConfig, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"GetParamOptions", nullptr, GetParamOptions, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"RegisterParamCallback", nullptr, RegisterParamCallback, nullptr, nullptr, nullptr, napi_default, nullptr},

        {"GetPhotoTotalCount", nullptr, GetPhotoTotalCount, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"DownloadSingleThumbnail", nullptr, DownloadSingleThumbnail, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"GetPhotoMetaList", nullptr, GetPhotoMetaList, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"ClearPhotoCache", nullptr, ClearPhotoCacheNapi, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"GetImageOrientationNapi", nullptr, GetImageOrientationNapi, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"GetImageExifInfoNapi", nullptr, GetImageExifInfoNapi, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"GetRawImageOrientationNapi", nullptr, GetRawImageOrientationNapi, nullptr, nullptr, nullptr, napi_default,nullptr},
        {"GetRawImageExifInfoNapi", nullptr, GetRawImageExifInfoNapi, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"StartAsyncScan", nullptr, StartAsyncScan, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"IsScanComplete", nullptr, IsScanComplete, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"GetScanProgress", nullptr, GetScanProgress, nullptr, nullptr, nullptr, napi_default, nullptr},
    };

    // 将接口映射表挂载到exports对象（ArkTS侧通过import获取这些函数）
    napi_define_properties(env,
                           exports,
                           sizeof(api_list) / sizeof(api_list[0]),
                           api_list);

    // 打印日志：确认模块初始化成功
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                 "NativeCamera模块初始化成功，注册了 %d 个接口",
                 (int)(sizeof(api_list) / sizeof(api_list[0])));
    
    return exports;
}
EXTERN_C_END

// ###########################################################################
// NAPI模块信息：定义模块的基本属性（ArkTS侧识别模块的关键）
// ###########################################################################
static napi_module cameraModule = {
    .nm_version = 1,          // NAPI模块版本（固定为1）
    .nm_flags = 0,            // 标志位（0=默认，无特殊配置）
    .nm_filename = nullptr,   // 模块文件名（可选，通常为nullptr）
    .nm_register_func = Init, // 模块初始化函数（指向上面的Init函数）
    .nm_modname = "entry",    // 模块名（必须与ArkTS工程的oh-package.json5中"name"一致）
    .nm_priv = ((void *)0),   // 私有数据（无特殊需求时为nullptr）
    .reserved = {0},          // 保留字段（必须为0）
};

// ###########################################################################
// 模块注册入口：so库加载时自动注册NAPI模块
// ###########################################################################
/**
 * @brief 构造函数属性：so库被加载时自动执行，注册模块到NAPI框架
 */
extern "C" __attribute__((constructor)) void RegisterEntryModule(void) {
    // napi_module_register：NAPI框架函数，注册模块
    napi_module_register(&cameraModule);
    
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                 "NativeCamera模块注册成功，支持AP模式连接");
}