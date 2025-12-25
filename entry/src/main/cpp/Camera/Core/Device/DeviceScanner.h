//
// Created on 2025/12/25.
//
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".

#ifndef DEVICE_SCANNER_H
#define DEVICE_SCANNER_H

#include "Camera/Core/Types/CameraTypes.h"
#include <vector>
#include <string>

class DeviceScanner {
public:
    // 扫描可用相机
    std::vector<CameraDeviceInfo> scanAvailableCameras();
    
    // 设置驱动路径
    void setDriverPath(const std::string& path);
    
    // 检查驱动路径是否已设置
    bool isDriverPathSet() const { return !driverPath_.empty(); }
    
private:
    std::string driverPath_;
};

#endif // DEVICE_SCANNER_H