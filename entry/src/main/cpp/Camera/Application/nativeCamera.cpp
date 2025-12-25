// native_camera.cpp
// 主接口实现（调用其他模块）

// ###########################################################################
// 头文件引入：依赖库的核心接口定义
// ###########################################################################
// 基础内存/字符串操作库
#include <cstddef>
#include <cstdlib>
#include <cstring>
#include <string>
// NAPI头文件：ArkTS与C++交互的核心接口（定义数据类型、函数调用规则）
#include <napi/native_api.h>
#include "Camera/camera_device.h"
#include "Camera/CameraDownloadKit/camera_download.h"
#include "Camera/exif_reader.h"
#include "napi/native_api.h"
#include <gphoto2/gphoto2.h>
#include <gphoto2/gphoto2-camera.h>
#include <gphoto2/gphoto2-widget.h>
#include <hilog/log.h>
#include "Camera/native_common.h"
#include "Camera/camera_device.h"
#include "Camera/camera_config.h"
#include "Camera/camera_preview.h"
#include "Camera/camera_capture.h"

// ###########################################################################
//  宏定义：日志配置（固定格式，方便定位日志来源）
// ###########################################################################
#define LOG_DOMAIN 0x0001      // 日志域（自定义标识，区分不同模块日志）
#define LOG_TAG "NativeCamera" // 日志标签（日志中显示的模块名）




// ###########################################################################
//  NAPI接口：断开相机连接（暴露给ArkTS调用）
// ###########################################################################
/**
 * @brief ArkTS层调用此函数，断开相机连接并释放所有资源
 * @param env NAPI环境
 * @param info NAPI回调信息
 * @return napi_value 返回true给ArkTS，标识已断开
 */
static napi_value Disconnect(napi_env env, napi_callback_info info) {
    // 若相机对象存在，先结束会话并释放
    if (g_camera) {
        // gp_camera_exit：通知相机结束连接（关闭端口、清理会话）
        gp_camera_exit(g_camera, g_context);
        // gp_camera_unref：释放相机对象（引用计数为0时自动销毁）
        gp_camera_unref(g_camera);
        g_camera = nullptr; // 指针置空，避免悬空
    }
    // 若上下文对象存在，释放上下文
    if (g_context) {
        gp_context_unref(g_context); // 释放上下文
        g_context = nullptr;         // 指针置空
    }
    // 更新连接状态为未连接
    g_connected = false;

    // 返回true给ArkTS
    napi_value result;
    napi_get_boolean(env, true, &result);
    return result;
}




// ###########################################################################
// NAPI模块注册：将C++函数映射为ArkTS可调用的接口（关键步骤）
// ###########################################################################
// EXTERN_C_START/EXTERN_C_END：确保函数按C语言规则编译（避免C++名称修饰）
// （NAPI框架依赖C语言函数名查找接口，C++会修改函数名，导致找不到）
EXTERN_C_START
/**
 * @brief 模块初始化函数：so库被加载时，NAPI框架自动调用此函数
 * @param env NAPI环境
 * @param exports ArkTS侧的"module.exports"对象（用于挂载接口）
 * @return napi_value 返回挂载好接口的exports对象
 */
static napi_value Init(napi_env env, napi_value exports) {
    // napi_property_descriptor：NAPI结构体，定义"ArkTS函数名→C++函数"的映射关系
    napi_property_descriptor api_list[] = {
        // 格式：{ArkTS侧函数名, 无, C++侧函数名, 无, 无, 无, 默认行为, 无}
        {"GetAvailableCameras", nullptr, GetAvailableCameras, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"SetGPhotoLibDirs", nullptr, SetGPhotoLibDirs, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"ConnectCamera", nullptr, ConnectCamera, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"Disconnect", nullptr, Disconnect, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"IsCameraConnected", nullptr, IsCameraConnectedNapi, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"TakePhoto", nullptr, TakePhoto, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"DownloadPhoto", nullptr, DownloadPhoto, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"SetCameraParameter", nullptr, SetCameraParameter, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"GetPreview", nullptr, GetPreviewNapi, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"GetCameraStatus", nullptr, GetCameraStatus, nullptr, nullptr, nullptr, napi_default, nullptr}, // 新增这行
        {"GetCameraConfig", nullptr, GetCameraConfig, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"GetParamOptions", nullptr, GetParamOptions, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"RegisterParamCallback", nullptr, RegisterParamCallback, nullptr, nullptr, nullptr, napi_default, nullptr},

        {"GetPhotoTotalCount", nullptr, GetPhotoTotalCount, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"DownloadSingleThumbnail", nullptr, DownloadSingleThumbnail, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"GetPhotoMetaList", nullptr, GetPhotoMetaList, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"ClearPhotoCache", nullptr, ClearPhotoCacheNapi, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"GetImageOrientationNapi", nullptr, GetImageOrientationNapi, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"GetImageExifInfoNapi", nullptr, GetImageExifInfoNapi, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"GetRawImageOrientationNapi", nullptr, GetRawImageOrientationNapi, nullptr, nullptr, nullptr, napi_default,
         nullptr},
        {"GetRawImageExifInfoNapi", nullptr, GetRawImageExifInfoNapi, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"StartAsyncScan", nullptr, StartAsyncScan, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"IsScanComplete", nullptr, IsScanComplete, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"GetScanProgress", nullptr, GetScanProgress, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"DisconnectCamera", nullptr, DisconnectCamera, nullptr, nullptr, nullptr, napi_default, nullptr},


    };

    // 将接口映射表挂载到exports对象（ArkTS侧通过import获取这些函数）
    napi_define_properties(env,                                    // NAPI环境
                           exports,                                // 目标对象（module.exports）
                           sizeof(api_list) / sizeof(api_list[0]), // 接口数量（自动计算，避免硬编码）
                           api_list                                // 接口映射表
    );

    // 打印日志：确认模块初始化成功
    OH_LOG_PrintMsg(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "InitModule: NativeCamera模块初始化成功");
    return exports; // 返回exports给NAPI框架
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
 * @brief 构造函数属性（__attribute__((constructor))）：so库被加载时自动执行
 * 作用：将上面定义的cameraModule注册到NAPI框架，让ArkTS能找到模块
 */
extern "C" __attribute__((constructor)) void RegisterEntryModule(void) {
    // napi_module_register：NAPI框架函数，注册模块
    napi_module_register(&cameraModule);
}