// camera_device.h
// Created on 2025/11/5.
//
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".

#ifndef PHOTOSEND_CAMERA_DEVICE_H
#define PHOTOSEND_CAMERA_DEVICE_H
#include <napi/native_api.h>

// 手动连接相机的定义
bool InternalConnectCamera(const char *model, const char *path);

// 工具函数，检查连接状态的定义
bool IsCameraConnected();


/**
 * @brief NAPI接口：获取所有可用相机的型号和路径列表
 * @param env NAPI环境
 * @param info 回调信息
 * @return napi_value 返回ArkTS数组（每个元素为"型号|路径"字符串）
 */
extern  napi_value GetAvailableCameras(napi_env env, napi_callback_info info);


/**
 * @brief ArkTS层调用此函数，获取当前相机连接状态
 * @param env NAPI环境
 * @param info NAPI回调信息
 * @return napi_value 返回布尔值给ArkTS（true=已连接，false=未连接）
 */
extern napi_value IsCameraConnectedNapi(napi_env env, napi_callback_info info);


/**
 * @brief ArkTS层调用此函数，传入相机型号和PTP/IP路径，触发连接
 * @param env NAPI环境
 * @param info NAPI回调信息（包含2个参数：型号、路径）
 * @return napi_value 返回布尔值给ArkTS（true=连接成功，false=失败）
 */
extern napi_value ConnectCamera(napi_env env, napi_callback_info info);


#endif //PHOTOSEND_CAMERA_DEVICE_H
