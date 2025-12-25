//
// Created on 2025/12/25.
//
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".

#ifndef CONNECTION_MANAGER_H
#define CONNECTION_MANAGER_H

#include "Camera/Core/Types/CameraTypes.h"
#include <gphoto2/gphoto2.h>
#include <string>

class ConnectionManager {
public:
    // 单例访问
    static ConnectionManager& getInstance();
    
    // 禁止拷贝
    ConnectionManager(const ConnectionManager&) = delete;
    ConnectionManager& operator=(const ConnectionManager&) = delete;
    
    // 连接相关方法
    bool connect(const std::string& model, const std::string& path);
    bool disconnect();
    bool isConnected() const;
    
    // 获取相机和上下文（供其他模块使用）
    Camera* getCamera() const { return camera_; }
    GPContext* getContext() const { return context_; }
    
    // 驱动路径设置
    void setDriverPath(const std::string& path);
    
private:
    ConnectionManager();
    ~ConnectionManager();
    
    // 内部连接步骤
    bool initializeLtdl();
    bool loadCameraAbilities(const std::string& model);
    bool setupPort(const std::string& path);
    bool finalizeConnection();
    
    // 资源清理
    void cleanupResources();
    
    // 成员变量
    Camera* camera_;
    GPContext* context_;
    std::string driverPath_;
    bool isConnected_;
};

#endif // CONNECTION_MANAGER_H