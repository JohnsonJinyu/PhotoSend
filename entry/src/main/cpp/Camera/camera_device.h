//
// Created on 2025/11/5.
//
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".

#ifndef PHOTOSEND_CAMERA_DEVICE_H
#define PHOTOSEND_CAMERA_DEVICE_H


// 手动连接相机的定义
bool InternalConnectCamera(const char *model, const char *path);

// 工具函数，检查连接状态的定义
bool IsCameraConnected();

#endif //PHOTOSEND_CAMERA_DEVICE_H
