// camera_device.h
// Created on 2025/11/5.
//
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".

#ifndef NAPI_DEVICE_INTERFACE_H
#define NAPI_DEVICE_INTERFACE_H

#include <napi/native_api.h>

// NAPI接口函数声明
napi_value GetAvailableCameras(napi_env env, napi_callback_info info);
napi_value ConnectCamera(napi_env env, napi_callback_info info);
napi_value DisconnectCamera(napi_env env, napi_callback_info info);
napi_value IsCameraConnectedNapi(napi_env env, napi_callback_info info);
napi_value SetGPhotoLibDirs(napi_env env, napi_callback_info info);

#endif // NAPI_DEVICE_INTERFACE_H