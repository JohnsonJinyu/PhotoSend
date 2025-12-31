// NapiDeviceInterface.cpp
// Created on 2025/11/5.
//
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".

#include "NapiDeviceInterface.h"
#include "Camera/Core/Device/CameraDeviceManager.h"
#include <hilog/log.h>
#include <Camera/Common/Constants.h>
#include <string>
#include <cstring>

// 本模块的日志配置
#define LOG_DOMAIN ModuleLogs::NapiDeviceInterface.domain
#define LOG_TAG ModuleLogs::NapiDeviceInterface.tag

// 辅助函数：创建NAPI字符串
static napi_value CreateNapiString(napi_env env, const char* str) {
    napi_value result;
    napi_create_string_utf8(env, str ? str : "", NAPI_AUTO_LENGTH, &result);
    return result;
}

/**
 * @brief 获取可用相机列表
 * @param env NAPI环境
 * @param info 回调信息
 * @return napi_value 相机列表数组
 */
napi_value GetAvailableCameras(napi_env env, napi_callback_info info) {
    auto& deviceManager = CameraDeviceManager::getInstance();
    auto cameras = deviceManager.scanCameras();
    
    napi_value resultArray;
    napi_create_array(env, &resultArray);
    
    for (size_t i = 0; i < cameras.size(); ++i) {
        const auto& camera = cameras[i];
        std::string combined = camera.model + "|" + camera.path;
        napi_value item = CreateNapiString(env, combined.c_str());
        napi_set_element(env, resultArray, i, item);
    }
    
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                 "返回可用相机列表，数量: %{public}d", (int)cameras.size());
    
    return resultArray;
}

/**
 * @brief 通用连接相机方法
 * @param env NAPI环境
 * @param info 回调信息
 * @return napi_value 连接结果（布尔值）
 */
napi_value ConnectCamera(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    // 参数检查
    if (argc < 2) {
        napi_throw_error(env, nullptr, "需要2个参数：相机型号和连接路径");
        return nullptr;
    }
    
    char model[128] = {0};
    char path[128] = {0};
    
    // 获取字符串参数
    size_t modelLen = 0;
    size_t pathLen = 0;
    napi_get_value_string_utf8(env, args[0], model, sizeof(model) - 1, &modelLen);
    napi_get_value_string_utf8(env, args[1], path, sizeof(path) - 1, &pathLen);
    
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                 "连接相机: model=%{public}s, path=%{public}s", model, path);
    
    auto& deviceManager = CameraDeviceManager::getInstance();
    bool success = deviceManager.connectCamera(model, path);
    
    napi_value result;
    napi_get_boolean(env, success, &result);
    
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                 "连接结果: %{public}s", success ? "成功" : "失败");
    
    return result;
}

/**
 * @brief AP模式连接相机（通过WiFi热点）
 * @param env NAPI环境
 * @param info 回调信息
 * @return napi_value 连接结果（布尔值）
 */
napi_value ConnectCameraAPMode(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value args[3];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    // 参数检查
    if (argc < 2) {
        napi_throw_error(env, nullptr, "至少需要2个参数：相机型号和IP地址");
        return nullptr;
    }
    
    char model[128] = {0};
    char ipAddress[64] = {0};
    int port = 15740; // 默认端口
    
    // 获取字符串参数
    size_t modelLen = 0;
    size_t ipLen = 0;
    napi_get_value_string_utf8(env, args[0], model, sizeof(model) - 1, &modelLen);
    napi_get_value_string_utf8(env, args[1], ipAddress, sizeof(ipAddress) - 1, &ipLen);
    
    // 第三个参数可选（端口号）
    if (argc > 2) {
        napi_get_value_int32(env, args[2], &port);
    }
    
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                 "AP模式连接相机: model=%{public}s, ip=%{public}s, port=%{public}d", 
                 model, ipAddress, port);
    
    auto& deviceManager = CameraDeviceManager::getInstance();
    bool success = deviceManager.connectCameraAPMode(model, ipAddress, port);
    
    napi_value result;
    napi_get_boolean(env, success, &result);
    
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                 "AP模式连接结果: %{public}s", success ? "成功" : "失败");
    
    return result;
}

/**
 * @brief 快速连接尼康相机（AP模式专用）
 * @param env NAPI环境
 * @param info 回调信息
 * @return napi_value 连接结果（布尔值）
 */
napi_value QuickConnectNikon(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    // 参数检查
    if (argc < 1) {
        napi_throw_error(env, nullptr, "需要1个参数：相机型号");
        return nullptr;
    }
    
    char model[128] = {0};
    size_t modelLen = 0;
    napi_get_value_string_utf8(env, args[0], model, sizeof(model) - 1, &modelLen);
    
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                 "快速连接尼康相机: model=%{public}s", model);
    
    auto& deviceManager = CameraDeviceManager::getInstance();
    bool success = deviceManager.quickConnectNikon(model);
    
    napi_value result;
    napi_get_boolean(env, success, &result);
    
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                 "快速连接结果: %{public}s", success ? "成功" : "失败");
    
    return result;
}

/**
 * @brief 断开相机连接
 * @param env NAPI环境
 * @param info 回调信息
 * @return napi_value 断开结果（布尔值）
 */
napi_value DisconnectCamera(napi_env env, napi_callback_info info) {
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "断开相机连接");
    
    auto& deviceManager = CameraDeviceManager::getInstance();
    bool success = deviceManager.disconnectCamera();
    
    napi_value result;
    napi_get_boolean(env, success, &result);
    
    return result;
}

/**
 * @brief 检查是否已连接相机
 * @param env NAPI环境
 * @param info 回调信息
 * @return napi_value 连接状态（布尔值）
 */
napi_value IsCameraConnectedNapi(napi_env env, napi_callback_info info) {
    auto& deviceManager = CameraDeviceManager::getInstance();
    bool connected = deviceManager.isCameraConnected();
    
    napi_value result;
    napi_get_boolean(env, connected, &result);
    
    return result;
}

/**
 * @brief 设置驱动路径
 * @param env NAPI环境
 * @param info 回调信息
 * @return napi_value 设置结果（布尔值）
 */
napi_value SetGPhotoLibDirs(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    // 参数检查
    if (argc < 1) {
        napi_throw_error(env, nullptr, "需要1个参数：驱动路径");
        return nullptr;
    }
    
    char camDir[256] = {0};
    size_t dirLen = 0;
    napi_get_value_string_utf8(env, args[0], camDir, sizeof(camDir) - 1, &dirLen);
    
    // 1. 更新全局变量（保持向后兼容）
    extern std::string g_camLibDir;
    g_camLibDir = camDir;
    
    // 2. 通过设备管理器设置驱动路径
    auto& deviceManager = CameraDeviceManager::getInstance();
    deviceManager.setDriverPath(camDir);
    
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                 "设置驱动路径: %{public}s", camDir);
    
    napi_value result;
    napi_get_boolean(env, true, &result);
    return result;
}

/**
 * @brief 获取连接状态详细信息
 * @param env NAPI环境
 * @param info 回调信息
 * @return napi_value 状态信息对象
 */
napi_value GetConnectionStatusInfo(napi_env env, napi_callback_info info) {
    auto& deviceManager = CameraDeviceManager::getInstance();
    auto status = deviceManager.getConnectionStatusInfo();
    
    // 创建返回对象
    napi_value resultObj;
    napi_create_object(env, &resultObj);
    
    // 添加isConnected属性
    napi_value isConnectedValue;
    napi_get_boolean(env, status.isConnected, &isConnectedValue);
    napi_set_named_property(env, resultObj, "isConnected", isConnectedValue);
    
    // 添加cameraModel属性
    napi_value modelValue = CreateNapiString(env, status.cameraModel.c_str());
    napi_set_named_property(env, resultObj, "cameraModel", modelValue);
    
    // 添加portPath属性
    napi_value pathValue = CreateNapiString(env, status.portPath.c_str());
    napi_set_named_property(env, resultObj, "portPath", pathValue);
    
    // 添加connectionType属性
    napi_value typeValue = CreateNapiString(env, status.connectionType.c_str());
    napi_set_named_property(env, resultObj, "connectionType", typeValue);
    
    // 添加connectionTimeMs属性
    napi_value timeValue;
    napi_create_int64(env, status.connectionTimeMs, &timeValue);
    napi_set_named_property(env, resultObj, "connectionTimeMs", timeValue);
    
    // 添加isReady属性
    napi_value isReadyValue;
    napi_get_boolean(env, status.isReady, &isReadyValue);
    napi_set_named_property(env, resultObj, "isReady", isReadyValue);
    
    return resultObj;
}

/**
 * @brief 快速连接测试
 * @param env NAPI环境
 * @param info 回调信息
 * @return napi_value 测试结果（布尔值）
 */
napi_value QuickConnectionTest(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    // 参数检查
    if (argc < 1) {
        napi_throw_error(env, nullptr, "至少需要1个参数：IP地址");
        return nullptr;
    }
    
    char ipAddress[64] = {0};
    int port = 15740; // 默认端口
    
    // 获取IP地址参数
    size_t ipLen = 0;
    napi_get_value_string_utf8(env, args[0], ipAddress, sizeof(ipAddress) - 1, &ipLen);
    
    // 第二个参数可选（端口号）
    if (argc > 1) {
        napi_get_value_int32(env, args[1], &port);
    }
    
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                 "快速连接测试: ip=%{public}s, port=%{public}d", ipAddress, port);
    
    auto& deviceManager = CameraDeviceManager::getInstance();
    bool success = deviceManager.quickConnectionTest(ipAddress, port);
    
    napi_value result;
    napi_get_boolean(env, success, &result);
    
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                 "快速连接测试结果: %{public}s", success ? "成功" : "失败");
    
    return result;
}