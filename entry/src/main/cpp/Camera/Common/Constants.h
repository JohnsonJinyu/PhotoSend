// Constants.h
// Created on 2025/12/29.
//
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".

#ifndef PHOTOSEND_CONSTANTS_H
#define PHOTOSEND_CONSTANTS_H

// 模块日志配置结构体
struct ModuleLogConfig {
    unsigned int domain;
    const char* tag;
};

// 定义各个模块的配置，日志域和日志标签
namespace ModuleLogs {
    // 使用inline变量确保单一定义   NapiDeviceInterface  ExifReader
    inline const ModuleLogConfig NativeCameraBridge = {0x0001,"NativeCameraBridge"};
    inline const ModuleLogConfig Camera_download = {0x0002,"Camera_download"};
    inline const ModuleLogConfig ThumbnailDownloader = {0x0003,"ThumbnailDownloader"};
    inline const ModuleLogConfig PhotoScanner = {0x0004,"PhotoScanner"};
    inline const ModuleLogConfig PhotoDownloader = {0x0005,"PhotoDownloader"};
    inline const ModuleLogConfig CameraPreview = {0x0006, "CameraPreview"};
    inline const ModuleLogConfig CameraConfig = {0x0007, "CameraConfig"};
    inline const ModuleLogConfig CameraDeviceManager = {0x0008, "CameraDeviceManager"};
    inline const ModuleLogConfig ConnectionManager = {0x0009, "ConnectionManager"};
    inline const ModuleLogConfig DeviceScanner = {0x0010, "DeviceScanner"};
    inline const ModuleLogConfig NapiDeviceInterface = {0x0011, "NapiDeviceInterface"};
    inline const ModuleLogConfig ExifReader = {0x0011, "ExifReader"};
    // 添加更多...
}

#endif //PHOTOSEND_CONSTANTS_H
