// CameraDeviceManager.h
// Created on 2025/12/25.
//
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".

#ifndef CAMERA_DEVICE_MANAGER_H
#define CAMERA_DEVICE_MANAGER_H

#include "ConnectionManager.h"
#include "DeviceScanner.h"
#include <mutex>
#include <vector>

class CameraDeviceManager {
public:
    static CameraDeviceManager& getInstance();
    
    // 禁止拷贝和移动
    CameraDeviceManager(const CameraDeviceManager&) = delete;
    CameraDeviceManager& operator=(const CameraDeviceManager&) = delete;
    CameraDeviceManager(CameraDeviceManager&&) = delete;
    CameraDeviceManager& operator=(CameraDeviceManager&&) = delete;
    
    // 设备管理接口
    bool connectCamera(const std::string& model, const std::string& path);
    bool disconnectCamera();
    bool isCameraConnected();
    
    // 设备扫描接口
    std::vector<CameraDeviceInfo> scanCameras();
    
    // 驱动路径设置
    void setDriverPath(const std::string& path);
    
    // 获取相机对象（供其他模块使用）
    Camera* getCamera();
    GPContext* getContext();
    
private:
    CameraDeviceManager();
    ~CameraDeviceManager();
    
    // 引用ConnectionManager的单例
    ConnectionManager& connectionManager_;
    DeviceScanner deviceScanner_;
    std::mutex connectionMutex_;
};

#endif // CAMERA_DEVICE_MANAGER_H