// NapiDeviceInterface.h
// Created on 2025/11/5.
//
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".

#ifndef NAPI_DEVICE_INTERFACE_H
#define NAPI_DEVICE_INTERFACE_H

#include <napi/native_api.h>
#include <string>

// 声明全局变量（extern表示"在其他文件中定义"，供外部引用）
extern std::string g_camLibDir;  // 注意：去掉static，否则无法跨文件共享

/**
 * @brief NAPI接口函数声明
 * @details 这些函数通过NAPI框架暴露给ArkTS层调用
 */

// 相机设备管理接口
napi_value GetAvailableCameras(napi_env env, napi_callback_info info);
napi_value ConnectCamera(napi_env env, napi_callback_info info);
napi_value ConnectCameraAPMode(napi_env env, napi_callback_info info);
napi_value QuickConnectNikon(napi_env env, napi_callback_info info);
napi_value DisconnectCamera(napi_env env, napi_callback_info info);
napi_value IsCameraConnectedNapi(napi_env env, napi_callback_info info);
napi_value SetGPhotoLibDirs(napi_env env, napi_callback_info info);

// 连接状态查询接口
napi_value GetConnectionStatusInfo(napi_env env, napi_callback_info info);
napi_value QuickConnectionTest(napi_env env, napi_callback_info info);

#endif // NAPI_DEVICE_INTERFACE_H