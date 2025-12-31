// CameraDeviceManager.cpp
// Created on 2025/12/25.
//
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".

#include "CameraDeviceManager.h"
#include "Camera/Common/Constants.h"
#include <hilog/log.h>
#include <algorithm>

// 本模块的日志配置
#define LOG_DOMAIN ModuleLogs::CameraDeviceManager.domain
#define LOG_TAG ModuleLogs::CameraDeviceManager.tag

// AP模式连接相关标签
#define AP_MODE_TAG "APMode"

/**
 * @brief CameraDeviceManager构造函数
 * @details 初始化连接管理器和设备扫描器
 */
CameraDeviceManager::CameraDeviceManager() 
    : connectionManager_(ConnectionManager::getInstance()),  // 引用单例
      deviceScanner_(),
      isApModeEnabled_(false) {
    
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                 "CameraDeviceManager初始化完成");
}

/**
 * @brief CameraDeviceManager析构函数
 * @details 确保断开连接并清理资源
 */
CameraDeviceManager::~CameraDeviceManager() {
    disconnectCamera();
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "CameraDeviceManager销毁");
}

/**
 * @brief 获取单例实例
 * @return CameraDeviceManager& 单例引用
 */
CameraDeviceManager& CameraDeviceManager::getInstance() {
    static CameraDeviceManager instance;
    return instance;
}

/**
 * @brief 连接相机（通用方法）
 * @param model 相机型号
 * @param path 连接路径
 * @return bool 连接结果
 */
bool CameraDeviceManager::connectCamera(const std::string& model, const std::string& path) {
    std::lock_guard<std::mutex> lock(connectionMutex_);
    
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                 "通用连接相机: model=%s, path=%s", model.c_str(), path.c_str());
    
    return connectionManager_.connect(model, path);
}

/**
 * @brief AP模式连接相机（通过WiFi热点）
 * @param model 相机型号
 * @param ip IP地址
 * @param port 端口号（默认15740）
 * @return bool 连接结果
 */
bool CameraDeviceManager::connectCameraAPMode(const std::string& model, 
                                             const std::string& ip, 
                                             int port) {
    std::lock_guard<std::mutex> lock(connectionMutex_);
    
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                 "AP模式连接相机: model=%s, ip=%s, port=%d", 
                 model.c_str(), ip.c_str(), port);
    
    // 设置PTP/IP配置
    connectionManager_.setPtpIpConfig(ip, port);
    
    // 构建PTP/IP路径
    std::string path;
    if (port > 0) {
        path = "ptpip:" + ip + ":" + std::to_string(port);
    } else {
        path = "ptpip:" + ip;
    }
    
    // 设置更长的超时时间（WiFi连接可能较慢）
    connectionManager_.setConnectionTimeout(10000); // 10秒
    
    // 标记为AP模式
    isApModeEnabled_ = true;
    
    // 执行连接
    bool result = connectionManager_.connect(model, path);
    
    if (result) {
        OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                     "AP模式连接成功: %s @ %s:%d", 
                     model.c_str(), ip.c_str(), port);
    } else {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, 
                     "AP模式连接失败: %s", connectionManager_.getLastError().c_str());
    }
    
    return result;
}

/**
 * @brief 快速连接尼康相机（AP模式专用）
 * @param model 相机型号
 * @return bool 连接结果
 * @details 使用尼康相机的默认PTP/IP设置
 */
bool CameraDeviceManager::quickConnectNikon(const std::string& model) {
    std::lock_guard<std::mutex> lock(connectionMutex_);
    
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                 "快速连接尼康相机: model=%s", model.c_str());
    
    // 尼康相机在AP模式下的默认设置
    const std::string defaultIp = "192.168.1.1";
    const int defaultPort = 15740;
    
    return connectCameraAPMode(model, defaultIp, defaultPort);
}

/**
 * @brief 断开相机连接
 * @return bool 断开结果
 */
bool CameraDeviceManager::disconnectCamera() {
    std::lock_guard<std::mutex> lock(connectionMutex_);
    
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "断开相机连接");
    
    // 重置AP模式标志
    isApModeEnabled_ = false;
    
    return connectionManager_.disconnect();
}

/**
 * @brief 检查是否已连接相机
 * @return bool 连接状态
 */
bool CameraDeviceManager::isCameraConnected() {
    std::lock_guard<std::mutex> lock(connectionMutex_);
    return connectionManager_.isConnected();
}

/**
 * @brief 扫描可用相机
 * @return std::vector<CameraDeviceInfo> 相机设备列表
 */
std::vector<CameraDeviceInfo> CameraDeviceManager::scanCameras() {
    std::lock_guard<std::mutex> lock(connectionMutex_);
    
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "开始扫描可用相机");
    
    auto cameras = deviceScanner_.scanAvailableCameras();
    
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                 "扫描完成，找到 %d 台相机", (int)cameras.size());
    
    return cameras;
}

/**
 * @brief 设置驱动路径
 * @param path 驱动路径
 */
void CameraDeviceManager::setDriverPath(const std::string& path) {
    std::lock_guard<std::mutex> lock(connectionMutex_);
    
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                 "设置驱动路径: %s", path.c_str());
    
    connectionManager_.setDriverPath(path);
    deviceScanner_.setDriverPath(path);
}

/**
 * @brief 获取相机对象
 * @return Camera* 相机对象指针
 */
Camera* CameraDeviceManager::getCamera() {
    std::lock_guard<std::mutex> lock(connectionMutex_);
    return connectionManager_.getCamera();
}

/**
 * @brief 获取相机上下文
 * @return GPContext* 上下文指针
 */
GPContext* CameraDeviceManager::getContext() {
    std::lock_guard<std::mutex> lock(connectionMutex_);
    return connectionManager_.getContext();
}

/**
 * @brief 获取连接状态详细信息
 * @return ConnectionStatusInfo 状态信息
 */
ConnectionStatusInfo CameraDeviceManager::getConnectionStatusInfo() {
    std::lock_guard<std::mutex> lock(connectionMutex_);
    return connectionManager_.getConnectionStatus();
}

/**
 * @brief 获取最后的错误信息
 * @return std::string 错误描述
 */
std::string CameraDeviceManager::getLastError() {
    std::lock_guard<std::mutex> lock(connectionMutex_);
    return connectionManager_.getLastError();
}

/**
 * @brief 快速连接测试
 * @param ip IP地址
 * @param port 端口号
 * @return bool 测试结果
 */
bool CameraDeviceManager::quickConnectionTest(const std::string& ip, int port) {
    std::lock_guard<std::mutex> lock(connectionMutex_);
    return connectionManager_.quickConnectionTest(ip, port);
}

/**
 * @brief 检查是否处于AP模式
 * @return bool AP模式状态
 */
bool CameraDeviceManager::isApModeEnabled() const {
    return isApModeEnabled_;
}