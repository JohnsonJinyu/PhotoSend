//
// Created on 2025/11/4.
// 专注于 WiFi（PTP/IP）相机的发现、连接、断开逻辑，维护设备连接状态。
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".
// git recover test 18:55
#ifndef PHOTOSEND_CAMERA_DEVICE_H
#define PHOTOSEND_CAMERA_DEVICE_H

#include <js_native_api_types.h>



// 日志域（自定义标识，区分不同模块日志）
#define LOG_DOMAIN 0x0001
// 日志标签（日志中显示的模块名）
#define LOG_TAG "NativeCamera"



// 向前声明libgphoto2核心类型（避免头文件冗余包含）
typedef struct _Camera Camera;
typedef struct _GPContext GPContext;



/**
 * @brief NAPI接口：连接WiFi（PTP/IP）相机
 * @param env NAPI环境变量
 * @param info NAPI回调信息（包含2个参数：相机型号字符串、PTP/IP路径字符串）
 * @return napi_value 返回布尔值给ArkTS层（true=连接成功，false=连接失败）
 */
static napi_value ConnectCamera(napi_env env, napi_callback_info info);



/**
 * @brief ArkTS层调用此函数，获取当前相机连接状态
 * @param env NAPI环境
 * @param info NAPI回调信息
 * @return napi_value 返回布尔值给ArkTS（true=已连接，false=未连接）
 */
static napi_value IsCameraConnectedNapi(napi_env env, napi_callback_info info);

#endif // PHOTOSEND_CAMERA_DEVICE_H