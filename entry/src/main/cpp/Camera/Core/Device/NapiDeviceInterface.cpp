// camera_device.cpp
// Created on 2025/11/5.
//
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".

#include "NapiDeviceInterface.h"
#include "Camera/Core/Device/CameraDeviceManager.h"
#include <hilog/log.h>

// 本模块的日志配置
#define LOG_DOMAIN 0x0006
#define LOG_TAG "NapiDeviceInterface"

// 辅助函数：创建NAPI字符串
static napi_value CreateNapiString(napi_env env, const char* str) {
    napi_value result;
    napi_create_string_utf8(env, str ? str : "", NAPI_AUTO_LENGTH, &result);
    return result;
}

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

napi_value ConnectCamera(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    char model[128] = {0};
    char path[128] = {0};
    
    napi_get_value_string_utf8(env, args[0], model, sizeof(model) - 1, nullptr);
    napi_get_value_string_utf8(env, args[1], path, sizeof(path) - 1, nullptr);
    
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

napi_value DisconnectCamera(napi_env env, napi_callback_info info) {
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "断开相机连接");
    
    auto& deviceManager = CameraDeviceManager::getInstance();
    bool success = deviceManager.disconnectCamera();
    
    napi_value result;
    napi_get_boolean(env, success, &result);
    
    return result;
}

napi_value IsCameraConnectedNapi(napi_env env, napi_callback_info info) {
    auto& deviceManager = CameraDeviceManager::getInstance();
    bool connected = deviceManager.isCameraConnected();
    
    napi_value result;
    napi_get_boolean(env, connected, &result);
    
    return result;
}

napi_value SetGPhotoLibDirs(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    char camDir[256] = {0};
    napi_get_value_string_utf8(env, args[0], camDir, sizeof(camDir) - 1, nullptr);
    
    // 1. 更新全局变量（保持向后兼容）
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
