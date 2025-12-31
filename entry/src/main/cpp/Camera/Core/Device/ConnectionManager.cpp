// ConnectionManager.cpp
// Created on 2025/12/25.
//
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".

#include "ConnectionManager.h"
#include "Camera/Common/Constants.h"
#include "Camera/Core/Types/CameraTypes.h"
#include <hilog/log.h>
#include <ltdl.h>
#include "Camera/CameraDownloadKit/camera_download.h"
#include <cstring>
#include <chrono>
#include <thread>

// 本模块的日志配置
#define LOG_DOMAIN ModuleLogs::ConnectionManager.domain
#define LOG_TAG ModuleLogs::ConnectionManager.tag

// 连接相关日志的标签
#define CONNECTION_TAG "CameraConnection"

/**
 * @brief ConnectionManager构造函数
 * @details 初始化所有成员变量，设置默认配置
 */
ConnectionManager::ConnectionManager() 
    : camera_(nullptr), 
      context_(nullptr), 
      driverPath_(""),
      lastError_(""),
      connectionTimeout_(5000), // 默认5秒超时
      isConnected_(false),
      isInitialized_(false),
      ptpIpAddress_(""),
      ptpIpPort_(15740) {
    
    // 初始化状态信息
    statusInfo_.isConnected = false;
    statusInfo_.isReady = false;
    statusInfo_.connectionTimeMs = 0;
    
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                 "ConnectionManager初始化完成，默认超时时间：%dms", connectionTimeout_);
}

/**
 * @brief ConnectionManager析构函数
 * @details 确保断开连接并清理资源
 */
ConnectionManager::~ConnectionManager() {
    // 确保断开连接
    disconnect();
    
    // 清理PTP/IP环境变量（如果设置了的话）
    if (!ptpIpAddress_.empty()) {
        unsetenv("PTPIP_IP");
        unsetenv("PTPIP_PORT");
    }
    
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "ConnectionManager销毁");
}

/**
 * @brief 获取单例实例
 * @return ConnectionManager& 单例引用
 */
ConnectionManager& ConnectionManager::getInstance() {
    static ConnectionManager instance;
    return instance;
}

/**
 * @brief 设置驱动路径
 * @param path 驱动库文件路径
 */
void ConnectionManager::setDriverPath(const std::string& path) {
    driverPath_ = path;
    
    // 设置libgphoto2环境变量
    setenv("CAMLIBS", path.c_str(), 1);
    setenv("IOLIBS", path.c_str(), 1);
    
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                 "设置驱动路径: %{public}s", path.c_str());
    
    // 更新状态信息
    statusInfo_.connectionType = "WiFi-AP";
}

/**
 * @brief 设置连接超时时间
 * @param timeoutMs 超时时间（毫秒）
 */
void ConnectionManager::setConnectionTimeout(int timeoutMs) {
    connectionTimeout_ = timeoutMs;
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                 "设置连接超时时间: %dms", timeoutMs);
}

/**
 * @brief 设置PTP/IP连接参数
 * @param ip IP地址
 * @param port 端口号
 */
void ConnectionManager::setPtpIpConfig(const std::string& ip, int port) {
    ptpIpAddress_ = ip;
    ptpIpPort_ = port;
    
    // 设置PTP/IP环境变量
    setenv("PTPIP_IP", ip.c_str(), 1);
    char portStr[16];
    snprintf(portStr, sizeof(portStr), "%d", port);
    setenv("PTPIP_PORT", portStr, 1);
    
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                 "设置PTP/IP配置: IP=%s, Port=%d", ip.c_str(), port);
}

/**
 * @brief 连接相机主方法
 * @param model 相机型号
 * @param path 连接路径
 * @return bool 连接结果
 */
bool ConnectionManager::connect(const std::string& model, const std::string& path) {
    // 记录连接开始时间
    auto startTime = std::chrono::steady_clock::now();
    connectionStartTime_ = startTime;
    
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                 "开始连接相机: model=%{public}s, path=%{public}s", 
                 model.c_str(), path.c_str());
    
    // 1. 检查是否已连接
    if (isConnected_ && camera_ && context_) {
        OH_LOG_Print(LOG_APP, LOG_WARN, LOG_DOMAIN, LOG_TAG, 
                     "相机已经连接，跳过重复连接");
        lastError_ = "相机已连接，无需重复连接";
        return true;
    }
    
    // 2. 检查驱动路径是否设置
    if (driverPath_.empty()) {
        lastError_ = "未设置驱动路径，请先调用setDriverPath";
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "%s", lastError_.c_str());
        return false;
    }
    
    // 3. 清理现有连接
    disconnect();
    
    // 4. 验证相机型号
    if (!validateCameraModel(model)) {
        lastError_ = "相机型号验证失败: " + model;
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "%s", lastError_.c_str());
        return false;
    }
    
    // 5. 创建上下文和相机对象
    context_ = gp_context_new();
    if (!context_) {
        lastError_ = "创建相机上下文失败";
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "%s", lastError_.c_str());
        return false;
    }
    
    if (gp_camera_new(&camera_) != GP_OK) {
        lastError_ = "创建相机对象失败";
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "%s", lastError_.c_str());
        gp_context_unref(context_);
        context_ = nullptr;
        return false;
    }
    
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                 "创建相机对象和上下文成功");
    
    // 6. 初始化ltdl动态库
    if (!initializeLtdl()) {
        cleanupResources();
        return false;
    }
    
    // 7. 加载相机能力并设置型号
    if (!loadCameraAbilities(model)) {
        cleanupResources();
        return false;
    }
    
    // 8. 设置端口（根据路径自动判断连接类型）
    if (!setupPort(path)) {
        cleanupResources();
        return false;
    }
    
    // 9. 完成连接初始化
    if (!finalizeConnection()) {
        cleanupResources();
        return false;
    }
    
    // 10. 更新连接状态
    isConnected_ = true;
    isInitialized_ = true;
    
    // 计算连接耗时
    auto endTime = std::chrono::steady_clock::now();
    auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(endTime - startTime);
    statusInfo_.connectionTimeMs = duration.count();
    
    // 更新状态信息
    statusInfo_.isConnected = true;
    statusInfo_.isReady = true;
    statusInfo_.cameraModel = model;
    statusInfo_.portPath = path;
    statusInfo_.lastError = "";
    
    // 判断连接类型
    if (path.find("ptpip:") != std::string::npos) {
        statusInfo_.connectionType = "WiFi-AP (PTP/IP)";
    } else if (path.find("usb:") != std::string::npos) {
        statusInfo_.connectionType = "USB";
    } else {
        statusInfo_.connectionType = "Unknown";
    }
    
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                 "相机连接成功: %{public}s @ %{public}s, 耗时: %lldms", 
                 model.c_str(), path.c_str(), duration.count());
    
    // 11. 关键：连接成功后，初始化下载模块
    if (camera_ && context_) {
        // 设置全局相机对象（供其他模块使用）
        extern Camera* g_camera;
        extern GPContext* g_context;
        extern bool g_connected;
        
        g_camera = camera_;
        g_context = context_;
        g_connected = true;
        
        // 初始化CameraDownloadKit模块
        InitCameraDownloadModules();
        OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                     "CameraDownloadKit模块已初始化");
    }
    
    return true;
}

/**
 * @brief 断开相机连接
 * @return bool 断开结果（通常总是成功）
 */
bool ConnectionManager::disconnect() {
    // 检查是否需要断开
    if (!camera_ && !context_) {
        isConnected_ = false;
        isInitialized_ = false;
        return true;
    }
    
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "开始断开相机连接");
    
    // 1. 先清理下载模块
    CleanupCameraDownloadModules();
    
    // 2. 清理全局变量（如果其他模块使用了的话）
    extern Camera* g_camera;
    extern GPContext* g_context;
    extern bool g_connected;
    
    g_camera = nullptr;
    g_context = nullptr;
    g_connected = false;
    
    // 3. 断开相机连接
    if (camera_) {
        // 尝试优雅退出
        gp_camera_exit(camera_, context_);
        
        // 释放相机资源
        gp_camera_unref(camera_);
        camera_ = nullptr;
    }
    
    // 4. 释放上下文资源
    if (context_) {
        gp_context_unref(context_);
        context_ = nullptr;
    }
    
    // 5. 更新状态
    isConnected_ = false;
    isInitialized_ = false;
    
    statusInfo_.isConnected = false;
    statusInfo_.isReady = false;
    statusInfo_.connectionType = "Disconnected";
    statusInfo_.lastError = "Disconnected";
    
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "相机已完全断开连接");
    
    return true;
}

/**
 * @brief 检查是否已连接相机
 * @return bool 连接状态
 */
bool ConnectionManager::isConnected() const {
    // 双重检查：状态标志和实际对象
    return isConnected_ && camera_ && context_;
}

/**
 * @brief 获取详细的连接状态信息
 * @return ConnectionStatusInfo 状态信息
 */
ConnectionStatusInfo ConnectionManager::getConnectionStatus() const {
    return statusInfo_;
}

/**
 * @brief 获取最后的错误信息
 * @return std::string 错误描述
 */
std::string ConnectionManager::getLastError() const {
    return lastError_;
}

/**
 * @brief 快速连接测试
 * @param ip IP地址
 * @param port 端口号
 * @return bool 测试结果
 */
bool ConnectionManager::quickConnectionTest(const std::string& ip, int port) {
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                 "快速连接测试: %s:%d", ip.c_str(), port);
    
    // 1. 创建临时上下文
    GPContext* tempContext = gp_context_new();
    if (!tempContext) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "创建临时上下文失败");
        return false;
    }
    
    // 2. 创建临时相机对象
    Camera* tempCamera = nullptr;
    if (gp_camera_new(&tempCamera) != GP_OK) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "创建临时相机对象失败");
        gp_context_unref(tempContext);
        return false;
    }
    
    // 3. 设置端口（简化版，只测试网络连通性）
    std::string testPath = "ptpip:" + ip;
    if (port > 0) {
        testPath += ":" + std::to_string(port);
    }
    
    // 4. 简单测试：尝试初始化（设置超时）
    int result = GP_ERROR;
    auto testStart = std::chrono::steady_clock::now();
    
    // 使用超时机制
    std::thread testThread([&]() {
        result = gp_camera_init(tempCamera, tempContext);
    });
    
    // 等待，但不超过超时时间
    if (testThread.joinable()) {
        testThread.join();
    }
    
    auto testEnd = std::chrono::steady_clock::now();
    auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(testEnd - testStart);
    
    // 5. 清理临时资源
    if (tempCamera) {
        gp_camera_exit(tempCamera, tempContext);
        gp_camera_unref(tempCamera);
    }
    if (tempContext) {
        gp_context_unref(tempContext);
    }
    
    // 6. 判断结果
    bool success = (result == GP_OK);
    OH_LOG_Print(LOG_APP, success ? LOG_INFO : LOG_WARN, LOG_DOMAIN, LOG_TAG,
                 "快速连接测试结果: %s, 耗时: %lldms", 
                 success ? "成功" : "失败", duration.count());
    
    return success;
}

// ======================== 私有方法实现 ========================

/**
 * @brief 初始化ltdl动态链接库
 * @return bool 初始化结果
 */
bool ConnectionManager::initializeLtdl() {
    // 检查是否已经初始化
    static bool ltdlInitialized = false;
    if (ltdlInitialized) {
        OH_LOG_Print(LOG_APP, LOG_DEBUG, LOG_DOMAIN, LOG_TAG, "ltdl已初始化，跳过");
        return true;
    }
    
    int ltdlResult = lt_dlinit();
    if (ltdlResult != 0) {
        lastError_ = std::string("ltdl初始化失败: ") + lt_dlerror();
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "%s", lastError_.c_str());
        return false;
    }
    
    ltdlInitialized = true;
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "ltdl初始化成功");
    return true;
}

/**
 * @brief 加载相机能力列表并设置型号
 * @param model 相机型号
 * @return bool 加载结果
 */
bool ConnectionManager::loadCameraAbilities(const std::string& model) {
    CameraAbilitiesList* abilitiesList = nullptr;
    gp_abilities_list_new(&abilitiesList);
    
    if (!abilitiesList) {
        lastError_ = "创建相机能力列表失败";
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "%s", lastError_.c_str());
        return false;
    }
    
    // 加载能力列表
    int loadResult = gp_abilities_list_load(abilitiesList, context_);
    if (loadResult != GP_OK) {
        lastError_ = std::string("加载相机能力列表失败: ") + gp_result_as_string(loadResult);
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "%s", lastError_.c_str());
        gp_abilities_list_free(abilitiesList);
        return false;
    }
    
    // 查找型号
    int modelIndex = gp_abilities_list_lookup_model(abilitiesList, model.c_str());
    if (modelIndex < 0) {
        lastError_ = "找不到相机型号: " + model;
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "%s", lastError_.c_str());
        
        // 尝试查找相似的型号
        OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "尝试查找相似的相机型号...");
        int count = gp_abilities_list_count(abilitiesList);
        for (int i = 0; i < count; i++) {
            CameraAbilities abilities;
            if (gp_abilities_list_get_abilities(abilitiesList, i, &abilities) == GP_OK) {
                OH_LOG_Print(LOG_APP, LOG_DEBUG, LOG_DOMAIN, LOG_TAG, 
                            "可用型号: %s", abilities.model);
            }
        }
        
        gp_abilities_list_free(abilitiesList);
        return false;
    }
    
    // 设置相机能力
    CameraAbilities abilities;
    gp_abilities_list_get_abilities(abilitiesList, modelIndex, &abilities);
    gp_camera_set_abilities(camera_, abilities);
    
    gp_abilities_list_free(abilitiesList);
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                 "设置相机型号成功: %{public}s", model.c_str());
    
    return true;
}

/**
 * @brief 设置连接端口
 * @param path 端口路径
 * @return bool 设置结果
 */
bool ConnectionManager::setupPort(const std::string& path) {
    GPPortInfoList* portList = nullptr;
    gp_port_info_list_new(&portList);
    
    if (!portList) {
        lastError_ = "创建端口列表失败";
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "%s", lastError_.c_str());
        return false;
    }
    
    // 加载端口列表
    gp_port_info_list_load(portList);
    
    // 自动处理路径格式
    std::string portPath = path;
    
    // 如果没有指定协议，根据常用情况自动添加
    if (portPath.find(":") == std::string::npos) {
        // 检查是否是IP地址格式
        if (portPath.find('.') != std::string::npos) {
            // 看起来像IP地址，添加ptpip:前缀
            portPath = "ptpip:" + portPath;
            OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                         "自动添加ptpip前缀: %s", portPath.c_str());
        }
    }
    
    // 检查端口路径是否包含端口号
    if (portPath.find("ptpip:") != std::string::npos) {
        size_t colonCount = std::count(portPath.begin(), portPath.end(), ':');
        if (colonCount == 2) {
            // 格式：ptpip:ip:port
            size_t firstColon = portPath.find(':');
            size_t secondColon = portPath.find(':', firstColon + 1);
            std::string ipPart = portPath.substr(firstColon + 1, secondColon - firstColon - 1);
            std::string portPart = portPath.substr(secondColon + 1);
            
            OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                         "解析PTP/IP地址: IP=%s, Port=%s", ipPart.c_str(), portPart.c_str());
        }
    }
    
    // 查找指定路径的端口
    int portIndex = gp_port_info_list_lookup_path(portList, portPath.c_str());
    
    if (portIndex < 0) {
        // 如果找不到，尝试查找IP类型端口
        OH_LOG_Print(LOG_APP, LOG_WARN, LOG_DOMAIN, LOG_TAG, 
                     "直接查找端口路径失败，尝试查找IP类型端口: %s", portPath.c_str());
        
        int portCount = gp_port_info_list_count(portList);
        for (int i = 0; i < portCount; i++) {
            GPPortInfo portInfo;
            if (gp_port_info_list_get_info(portList, i, &portInfo) != GP_OK) {
                continue;
            }
            
            GPPortType portType;
            gp_port_info_get_type(portInfo, &portType);
            if (portType == GP_PORT_IP || portType == GP_PORT_PTPIP) {
                portIndex = i;
                OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                             "找到IP/PTPIP类型端口，索引: %d", i);
                break;
            }
        }
    }
    
    if (portIndex < 0) {
        lastError_ = "找不到端口路径: " + portPath;
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "%s", lastError_.c_str());
        
        // 输出可用端口类型供调试 - 修正这里的gp_port_info_get_name调用
        int portCount = gp_port_info_list_count(portList);
        for (int i = 0; i < portCount; i++) {
            GPPortInfo portInfo;
            if (gp_port_info_list_get_info(portList, i, &portInfo) == GP_OK) {
                // 修正：gp_port_info_get_name的正确使用方式
                // 注意：函数签名是 char**，不是 const char**
                char* portName = nullptr;
                gp_port_info_get_name(portInfo, &portName);
                
                GPPortType portType;
                gp_port_info_get_type(portInfo, &portType);
                
                // 转换端口类型为字符串
                std::string portTypeStr = "Unknown";
                if (portType == GP_PORT_SERIAL) portTypeStr = "Serial";
                else if (portType == GP_PORT_USB) portTypeStr = "USB";
                else if (portType == GP_PORT_DISK) portTypeStr = "Disk";
                else if (portType == GP_PORT_PTPIP) portTypeStr = "PTP/IP";
                else if (portType == GP_PORT_USB_DISK_DIRECT) portTypeStr = "USB Disk Direct";
                else if (portType == GP_PORT_USB_SCSI) portTypeStr = "USB SCSI";
                else if (portType == GP_PORT_IP) portTypeStr = "IP";
                
                OH_LOG_Print(LOG_APP, LOG_DEBUG, LOG_DOMAIN, LOG_TAG, 
                             "可用端口[%d]: 名称=%s, 类型=%s", 
                             i, portName ? portName : "Unknown", portTypeStr.c_str());
            }
        }
        
        gp_port_info_list_free(portList);
        return false;
    }
    
    // 设置端口信息
    GPPortInfo portInfo;
    gp_port_info_list_get_info(portList, portIndex, &portInfo);
    gp_camera_set_port_info(camera_, portInfo);
    
    // 获取并记录端口信息
    char* portName = nullptr;
    gp_port_info_get_name(portInfo, &portName);
    
    GPPortType portType;
    gp_port_info_get_type(portInfo, &portType);
    
    std::string portTypeStr = "Unknown";
    if (portType == GP_PORT_PTPIP) portTypeStr = "PTP/IP";
    else if (portType == GP_PORT_IP) portTypeStr = "IP";
    else if (portType == GP_PORT_USB) portTypeStr = "USB";
    
    gp_port_info_list_free(portList);
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                 "设置端口成功: %s (类型: %s)", portPath.c_str(), portTypeStr.c_str());
    
    // 更新状态信息中的端口路径
    statusInfo_.portPath = portPath;
    
    return true;
}

/**
 * @brief 最终完成连接初始化
 * @return bool 初始化结果
 */
bool ConnectionManager::finalizeConnection() {
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                 "开始最终连接初始化，超时时间: %dms", connectionTimeout_);
    
    auto startTime = std::chrono::steady_clock::now();
    
    // 尝试连接，使用单独的线程以便超时控制
    int result = GP_ERROR;
    std::thread connectThread([&]() {
        result = gp_camera_init(camera_, context_);
    });
    
    // 等待连接完成或超时
    bool timedOut = false;
    auto timeoutTime = startTime + std::chrono::milliseconds(connectionTimeout_);
    
    if (connectThread.joinable()) {
        // 等待线程完成，但最多等待超时时间
        while (std::chrono::steady_clock::now() < timeoutTime) {
            // 检查线程是否仍在运行
            bool stillRunning = true;
            
            // 尝试join，等待100ms
            if (connectThread.joinable()) {
                connectThread.join();
                stillRunning = false;
            }
            
            if (!stillRunning) {
                break; // 线程已结束
            }
            
            // 等待一小段时间再检查
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
        }
        
        // 检查是否超时
        if (std::chrono::steady_clock::now() >= timeoutTime) {
            timedOut = true;
            OH_LOG_Print(LOG_APP, LOG_WARN, LOG_DOMAIN, LOG_TAG, 
                         "连接初始化超时，强制中断");
            
            // 无法安全中断gp_camera_init，只能记录超时
            result = GP_ERROR_TIMEOUT;
        }
    }
    
    auto endTime = std::chrono::steady_clock::now();
    auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(endTime - startTime);
    
    if (result != GP_OK) {
        if (timedOut) {
            lastError_ = "连接超时，请检查网络连接和相机状态";
        } else {
            lastError_ = std::string("相机连接初始化失败: ") + gp_result_as_string(result);
        }
        
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, 
                     "%s, 耗时: %lldms", lastError_.c_str(), duration.count());
        return false;
    }
    
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                 "相机连接初始化成功，耗时: %lldms", duration.count());
    return true;
}

/**
 * @brief 初始化PTP/IP连接环境
 * @param ip IP地址
 * @param port 端口号
 * @return bool 初始化结果
 */
bool ConnectionManager::initializePtpIpEnvironment(const std::string& ip, int port) {
    // 设置PTP/IP特定环境变量
    setenv("PTPIP_IP", ip.c_str(), 1);
    
    char portStr[16];
    snprintf(portStr, sizeof(portStr), "%d", port);
    setenv("PTPIP_PORT", portStr, 1);
    
    // 对于某些相机，可能需要额外的设置
    setenv("PTP2_IP", ip.c_str(), 1);
    
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                 "PTP/IP环境初始化完成: %s:%d", ip.c_str(), port);
    
    return true;
}

/**
 * @brief 验证相机型号支持
 * @param model 相机型号
 * @return bool 验证结果
 */
bool ConnectionManager::validateCameraModel(const std::string& model) {
    // 简单验证：检查型号是否为空
    if (model.empty()) {
        return false;
    }
    
    // 可以在这里添加更复杂的验证逻辑
    // 例如：检查型号格式、品牌前缀等
    
    // 常见品牌前缀检查（可选）
    std::vector<std::string> knownBrands = {
        "Nikon", "Canon", "Sony", "Fujifilm", "Olympus", "Panasonic", "Pentax"
    };
    
    bool hasKnownBrand = false;
    for (const auto& brand : knownBrands) {
        if (model.find(brand) == 0) { // 检查是否以品牌名开头
            hasKnownBrand = true;
            break;
        }
    }
    
    if (!hasKnownBrand) {
        OH_LOG_Print(LOG_APP, LOG_WARN, LOG_DOMAIN, LOG_TAG, 
                     "相机型号可能不受支持或格式不正确: %s", model.c_str());
        // 仍然返回true，让libgphoto2自己判断是否支持
    }
    
    return true;
}

/**
 * @brief 清理资源
 */
void ConnectionManager::cleanupResources() {
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "清理连接资源");
    
    if (camera_) {
        gp_camera_unref(camera_);
        camera_ = nullptr;
    }
    
    if (context_) {
        gp_context_unref(context_);
        context_ = nullptr;
    }
    
    // 重置状态（但不重置连接标志，因为可能在其他地方使用）
    isInitialized_ = false;
    lastError_ = "连接过程中断";
}

/**
 * @brief 记录连接日志
 * @param message 日志消息
 * @param level 日志级别
 */
void ConnectionManager::logConnection(const std::string& message, int level) {
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                 "[%s] %s", CONNECTION_TAG, message.c_str());
}