// ConnectionManager.cpp
// Created on 2025/12/25.
//
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".

#include "ConnectionManager.h"
#include "Camera/Core/Types/CameraTypes.h"
#include <hilog/log.h>
#include <ltdl.h>
#include "Camera/CameraDownloadKit/camera_download.h"
#include <cstring>

// 本模块的日志配置
#define LOG_DOMAIN 0x0003   
#define LOG_TAG "ConnectionManager"

ConnectionManager::ConnectionManager() 
    : camera_(nullptr), context_(nullptr), isConnected_(false) {
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "ConnectionManager初始化");
}

ConnectionManager::~ConnectionManager() {
    disconnect();
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "ConnectionManager销毁");
}

ConnectionManager& ConnectionManager::getInstance() {
    static ConnectionManager instance;
    return instance;
}

void ConnectionManager::setDriverPath(const std::string& path) {
    driverPath_ = path;
    setenv("CAMLIBS", path.c_str(), 1);
    setenv("IOLIBS", path.c_str(), 1);
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "设置驱动路径: %{public}s", path.c_str());
}

bool ConnectionManager::connect(const std::string& model, const std::string& path) {
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                 "开始连接相机: model=%{public}s, path=%{public}s", 
                 model.c_str(), path.c_str());
    
    // 1. 清理现有连接
    disconnect();
    
    // 2. 创建上下文和相机对象
    context_ = gp_context_new();
    if (!context_) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "创建上下文失败");
        return false;
    }
    
    if (gp_camera_new(&camera_) != GP_OK) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "创建相机对象失败");
        gp_context_unref(context_);
        context_ = nullptr;
        return false;
    }
    
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "创建相机对象和上下文成功");
    
    // 3. 初始化ltdl
    if (!initializeLtdl()) {
        cleanupResources();
        return false;
    }
    
    // 4. 加载相机能力并设置型号
    if (!loadCameraAbilities(model)) {
        cleanupResources();
        return false;
    }
    
    // 5. 设置端口
    if (!setupPort(path)) {
        cleanupResources();
        return false;
    }
    
    // 6. 完成连接
    if (!finalizeConnection()) {
        cleanupResources();
        return false;
    }
    
    isConnected_ = true;
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                 "相机连接成功: %{public}s @ %{public}s", 
                 model.c_str(), path.c_str());
    
    // 关键：连接成功后，设置全局变量并初始化下载模块
    if (camera_ && context_) {
        // 设置全局相机对象（如果你的其他模块还需要使用全局变量）
        extern Camera* g_camera;  // 声明外部全局变量
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

bool ConnectionManager::disconnect() {
    if (!camera_ && !context_) {
        return true;
    }
    
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "断开相机连接");
    
    // 关键：先清理下载模块
    CleanupCameraDownloadModules();
    
    if (camera_) {
        gp_camera_exit(camera_, context_);
        gp_camera_unref(camera_);
        camera_ = nullptr;
    }
    
    if (context_) {
        gp_context_unref(context_);
        context_ = nullptr;
    }
    
    isConnected_ = false;
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "相机已断开连接");
    
    return true;
}

bool ConnectionManager::isConnected() const {
    return isConnected_ && camera_ && context_;
}

// 私有方法实现
bool ConnectionManager::initializeLtdl() {
    int ltdlResult = lt_dlinit();
    if (ltdlResult != 0) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, 
                     "ltdl初始化失败: %{public}s", lt_dlerror());
        return false;
    }
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "ltdl初始化成功");
    return true;
}

bool ConnectionManager::loadCameraAbilities(const std::string& model) {
    CameraAbilitiesList* abilitiesList = nullptr;
    gp_abilities_list_new(&abilitiesList);
    
    if (!abilitiesList) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "创建能力列表失败");
        return false;
    }
    
    // 加载能力列表
    int loadResult = gp_abilities_list_load(abilitiesList, context_);
    if (loadResult != GP_OK) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, 
                     "加载相机能力列表失败: %{public}s", gp_result_as_string(loadResult));
        gp_abilities_list_free(abilitiesList);
        return false;
    }
    
    // 查找型号
    int modelIndex = gp_abilities_list_lookup_model(abilitiesList, model.c_str());
    if (modelIndex < 0) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, 
                     "找不到相机型号: %{public}s", model.c_str());
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

bool ConnectionManager::setupPort(const std::string& path) {
    GPPortInfoList* portList = nullptr;
    gp_port_info_list_new(&portList);
    
    if (!portList) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "创建端口列表失败");
        return false;
    }
    
    // 加载端口列表
    gp_port_info_list_load(portList);
    
    // 查找IP类型端口
    int ipPortIndex = -1;
    int portCount = gp_port_info_list_count(portList);
    
    for (int i = 0; i < portCount; i++) {
        GPPortInfo portInfo;
        if (gp_port_info_list_get_info(portList, i, &portInfo) != GP_OK) {
            continue;
        }
        
        GPPortType portType;
        gp_port_info_get_type(portInfo, &portType);
        if (portType == GP_PORT_IP) {
            ipPortIndex = i;
            OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                         "找到IP类型端口，索引: %{public}d", i);
            break;
        }
    }
    
    if (ipPortIndex == -1) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, 
                     "端口列表中无GP_PORT_IP类型端口");
        gp_port_info_list_free(portList);
        return false;
    }
    
    // 查找指定路径的端口
    int portIndex = gp_port_info_list_lookup_path(portList, path.c_str());
    if (portIndex < 0) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, 
                     "找不到端口路径: %{public}s", path.c_str());
        gp_port_info_list_free(portList);
        return false;
    }
    
    // 设置端口信息
    GPPortInfo portInfo;
    gp_port_info_list_get_info(portList, portIndex, &portInfo);
    gp_camera_set_port_info(camera_, portInfo);
    
    gp_port_info_list_free(portList);
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                 "设置端口成功: %{public}s", path.c_str());
    
    return true;
}

bool ConnectionManager::finalizeConnection() {
    int result = gp_camera_init(camera_, context_);
    if (result != GP_OK) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, 
                     "相机连接初始化失败: %{public}d", result);
        return false;
    }
    
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "相机连接初始化成功");
    return true;
}

void ConnectionManager::cleanupResources() {
    if (camera_) {
        gp_camera_unref(camera_);
        camera_ = nullptr;
    }
    if (context_) {
        gp_context_unref(context_);
        context_ = nullptr;
    }
}