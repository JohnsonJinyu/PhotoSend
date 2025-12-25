// CameraDeviceManager.cpp
// Created on 2025/12/25.
//
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".

#include "CameraDeviceManager.h"
#include <hilog/log.h>

// 本模块的日志配置
#define LOG_DOMAIN 0x0005
#define LOG_TAG "DeviceManager"

CameraDeviceManager::CameraDeviceManager() 
    : connectionManager_(ConnectionManager::getInstance()),  // 引用单例
      deviceScanner_() {
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "CameraDeviceManager初始化");
}

CameraDeviceManager::~CameraDeviceManager() {
    disconnectCamera();
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "CameraDeviceManager销毁");
}

CameraDeviceManager& CameraDeviceManager::getInstance() {
    static CameraDeviceManager instance;
    return instance;
}

bool CameraDeviceManager::connectCamera(const std::string& model, const std::string& path) {
    std::lock_guard<std::mutex> lock(connectionMutex_);
    return connectionManager_.connect(model, path);
}

bool CameraDeviceManager::disconnectCamera() {
    std::lock_guard<std::mutex> lock(connectionMutex_);
    return connectionManager_.disconnect();
}

bool CameraDeviceManager::isCameraConnected() {
    std::lock_guard<std::mutex> lock(connectionMutex_);
    return connectionManager_.isConnected();
}

std::vector<CameraDeviceInfo> CameraDeviceManager::scanCameras() {
    std::lock_guard<std::mutex> lock(connectionMutex_);
    return deviceScanner_.scanAvailableCameras();
}

void CameraDeviceManager::setDriverPath(const std::string& path) {
    std::lock_guard<std::mutex> lock(connectionMutex_);
    connectionManager_.setDriverPath(path);
    deviceScanner_.setDriverPath(path);
}

Camera* CameraDeviceManager::getCamera() {
    std::lock_guard<std::mutex> lock(connectionMutex_);
    return connectionManager_.getCamera();
}

GPContext* CameraDeviceManager::getContext() {
    std::lock_guard<std::mutex> lock(connectionMutex_);
    return connectionManager_.getContext();
}