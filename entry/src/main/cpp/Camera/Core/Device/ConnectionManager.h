// ConnectionManager.h
// Created on 2025/12/25.
//
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".

#ifndef CONNECTION_MANAGER_H
#define CONNECTION_MANAGER_H

#include "Camera/Core/Types/CameraTypes.h"
#include <gphoto2/gphoto2.h>
#include <hilog/log.h>
#include <string>
#include <chrono>

/**
 * @brief 相机连接状态信息结构体
 * @details 提供详细的连接状态信息，便于调试和UI展示
 */
struct ConnectionStatusInfo {
    bool isConnected;               // 是否已连接
    std::string cameraModel;        // 相机型号
    std::string portPath;           // 端口路径（如ptpip:192.168.1.1:15740）
    std::string connectionType;     // 连接类型（USB/WiFi-AP/WiFi-Infrastructure）
    std::string lastError;          // 最后一次错误信息
    long long connectionTimeMs;     // 连接耗时（毫秒）
    bool isReady;                   // 连接是否就绪（完成初始化）
};

/**
 * @brief 连接管理器类
 * @details 管理相机连接、断开连接、状态维护等核心功能
 *          使用单例模式确保全局只有一个连接管理器实例
 *          支持PTP/IP协议通过WiFi热点连接相机
 */
class ConnectionManager {
public:
    // 单例访问
    static ConnectionManager& getInstance();
    
    // 禁止拷贝和移动（确保单例唯一性）
    ConnectionManager(const ConnectionManager&) = delete;
    ConnectionManager& operator=(const ConnectionManager&) = delete;
    ConnectionManager(ConnectionManager&&) = delete;
    ConnectionManager& operator=(ConnectionManager&&) = delete;
    
    // ======================== 连接相关方法 ========================
    
    /**
     * @brief 连接相机
     * @param model 相机型号（如"Nikon Zf"）
     * @param path 连接路径（如"ptpip:192.168.1.1:15740"或"usb:"）
     * @return true 连接成功，false 连接失败
     */
    bool connect(const std::string& model, const std::string& path);
    
    /**
     * @brief 断开相机连接
     * @return true 断开成功，false 断开失败（通常总是成功）
     */
    bool disconnect();
    
    /**
     * @brief 检查是否已连接相机
     * @return true 已连接，false 未连接
     */
    bool isConnected() const;
    
    // ======================== 配置相关方法 ========================
    
    /**
     * @brief 设置驱动路径
     * @param path 驱动库文件路径，包含CAMLIBS和IOLIBS
     */
    void setDriverPath(const std::string& path);
    
    /**
     * @brief 设置连接超时时间
     * @param timeoutMs 超时时间（毫秒），默认5000ms
     * @details 对于WiFi连接，建议设置更长的超时时间（如10000ms）
     */
    void setConnectionTimeout(int timeoutMs);
    
    /**
     * @brief 设置PTP/IP连接参数
     * @param ip IP地址（如"192.168.1.1"）
     * @param port 端口号（默认15740）
     */
    void setPtpIpConfig(const std::string& ip, int port = 15740);
    
    // ======================== 状态查询方法 ========================
    
    /**
     * @brief 获取相机对象指针
     * @return Camera* 相机对象指针，未连接时返回nullptr
     */
    Camera* getCamera() const { return camera_; }
    
    /**
     * @brief 获取相机上下文指针
     * @return GPContext* 上下文指针，未连接时返回nullptr
     */
    GPContext* getContext() const { return context_; }
    
    /**
     * @brief 获取详细的连接状态信息
     * @return ConnectionStatusInfo 包含所有连接状态信息
     */
    ConnectionStatusInfo getConnectionStatus() const;
    
    /**
     * @brief 获取最后的错误信息
     * @return std::string 错误描述，无错误时返回空字符串
     */
    std::string getLastError() const;
    
    /**
     * @brief 快速连接测试
     * @param ip IP地址
     * @param port 端口号
     * @return true 网络可达，false 网络不可达或相机未响应
     * @details 不进行完整的相机初始化，只测试网络连通性
     */
    bool quickConnectionTest(const std::string& ip, int port = 15740);
    
private:
    // 构造函数和析构函数（私有化，确保单例）
    ConnectionManager();
    ~ConnectionManager();
    
    // ======================== 内部连接步骤 ========================
    
    /**
     * @brief 初始化ltdl动态链接库
     * @return true 初始化成功，false 初始化失败
     */
    bool initializeLtdl();
    
    /**
     * @brief 加载相机能力列表并设置型号
     * @param model 相机型号
     * @return true 成功，false 失败
     */
    bool loadCameraAbilities(const std::string& model);
    
    /**
     * @brief 设置连接端口
     * @param path 端口路径
     * @return true 成功，false 失败
     * @details 支持多种端口类型：PTP/IP、USB等
     */
    bool setupPort(const std::string& path);
    
    /**
     * @brief 最终完成连接初始化
     * @return true 成功，false 失败
     */
    bool finalizeConnection();
    
    /**
     * @brief 清理资源（内部使用）
     * @details 清理camera_和context_，但不影响连接状态标志
     */
    void cleanupResources();
    
    /**
     * @brief 初始化PTP/IP连接环境
     * @param ip IP地址
     * @param port 端口号
     * @return true 环境设置成功，false 设置失败
     */
    bool initializePtpIpEnvironment(const std::string& ip, int port);
    
    /**
     * @brief 验证相机型号支持
     * @param model 相机型号
     * @return true 型号受支持，false 型号不受支持
     */
    bool validateCameraModel(const std::string& model);
    
    /**
     * @brief 记录连接日志
     * @param message 日志消息
     * @param level 日志级别
     * @details 统一连接相关的日志记录格式
     */
    void logConnection(const std::string& message, int level = LOG_INFO);
    
    // ======================== 成员变量 ========================
    
    // 相机和上下文对象
    Camera* camera_;            // libgphoto2相机对象
    GPContext* context_;        // libgphoto2上下文对象
    
    // 配置参数
    std::string driverPath_;    // 驱动路径
    std::string lastError_;     // 最后错误信息
    int connectionTimeout_;     // 连接超时时间（毫秒）
    
    // 连接状态
    bool isConnected_;          // 连接状态标志
    bool isInitialized_;        // 初始化完成标志
    std::chrono::steady_clock::time_point connectionStartTime_; // 连接开始时间
    ConnectionStatusInfo statusInfo_; // 连接状态信息
    
    // PTP/IP配置
    std::string ptpIpAddress_;  // PTP/IP地址
    int ptpIpPort_;             // PTP/IP端口
};

#endif // CONNECTION_MANAGER_H