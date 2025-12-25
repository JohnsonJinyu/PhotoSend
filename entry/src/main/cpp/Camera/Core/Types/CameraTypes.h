// CameraTypes.h
// Created on 2025/12/25.
//
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".

#ifndef CAMERA_TYPES_H
#define CAMERA_TYPES_H

#include <string>
#include <vector>

// 相机连接信息
struct CameraDeviceInfo {
    std::string model;          // 相机型号
    std::string path;           // 连接路径：ptpip:192.168.1.1:55740
    std::string displayName;    // 显示名称
};

// 连接状态枚举
enum ConnectionStatus {
    DISCONNECTED,
    CONNECTING,
    CONNECTED,
    DISCONNECTING,
    ERROR
};

#endif // CAMERA_TYPES_H