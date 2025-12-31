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
    // 单例访问
    static CameraDeviceManager& getInstance();
    
    // 禁止拷贝和移动（确保单例唯一性）
    CameraDeviceManager(const CameraDeviceManager&) = delete;
    CameraDeviceManager& operator=(const CameraDeviceManager&) = delete;
    CameraDeviceManager(CameraDeviceManager&&) = delete;
    CameraDeviceManager& operator=(CameraDeviceManager&&) = delete;
    
    // ======================== 设备管理接口 ========================
    
    /**
     * @brief 通用连接相机方法
     * @param model 相机型号
     * @param path 连接路径
     * @return bool 连接结果
     */
    bool connectCamera(const std::string& model, const std::string& path);
    
    /**
     * @brief AP模式连接相机（通过WiFi热点）
     * @param model 相机型号
     * @param ip IP地址
     * @param port 端口号（默认15740）
     * @return bool 连接结果
     */
    bool connectCameraAPMode(const std::string& model, const std::string& ip, int port = 15740);
    
    /**
     * @brief 快速连接尼康相机（AP模式专用）
     * @param model 相机型号
     * @return bool 连接结果
     */
    bool quickConnectNikon(const std::string& model);
    
    /**
     * @brief 断开相机连接
     * @return bool 断开结果
     */
    bool disconnectCamera();
    
    /**
     * @brief 检查是否已连接相机
     * @return bool 连接状态
     */
    bool isCameraConnected();
    
    // ======================== 设备扫描接口 ========================
    
    /**
     * @brief 扫描可用相机
     * @return std::vector<CameraDeviceInfo> 相机设备列表
     */
    std::vector<CameraDeviceInfo> scanCameras();
    
    // ======================== 配置接口 ========================
    
    /**
     * @brief 设置驱动路径
     * @param path 驱动路径
     */
    void setDriverPath(const std::string& path);
    
    // ======================== 状态查询接口 ========================
    
    /**
     * @brief 获取相机对象指针
     * @return Camera* 相机对象指针
     */
    Camera* getCamera();
    
    /**
     * @brief 获取相机上下文指针
     * @return GPContext* 上下文指针
     */
    GPContext* getContext();
    
    /**
     * @brief 获取详细的连接状态信息
     * @return ConnectionStatusInfo 状态信息
     */
    ConnectionStatusInfo getConnectionStatusInfo();
    
    /**
     * @brief 获取最后的错误信息
     * @return std::string 错误描述
     */
    std::string getLastError();
    
    /**
     * @brief 快速连接测试
     * @param ip IP地址
     * @param port 端口号
     * @return bool 测试结果
     */
    bool quickConnectionTest(const std::string& ip, int port = 15740);
    
    /**
     * @brief 检查是否处于AP模式
     * @return bool AP模式状态
     */
    bool isApModeEnabled() const;
    
private:
    // 构造函数和析构函数（私有化，确保单例）
    CameraDeviceManager();
    ~CameraDeviceManager();
    
    // 引用ConnectionManager的单例
    ConnectionManager& connectionManager_;
    
    // 设备扫描器
    DeviceScanner deviceScanner_;
    
    // 连接互斥锁（保护连接状态）
    std::mutex connectionMutex_;
    
    // AP模式标志
    bool isApModeEnabled_;
};

#endif // CAMERA_DEVICE_MANAGER_H