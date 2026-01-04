// native_common.cpp
// Created on 2025/11/9.
//
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".


// native_common.cpp
#include "native_common.h"
#include "Camera/Core/Device/ConnectionManager.h"  // 包含ConnectionManager
#include <hilog/log.h>

// 私有静态变量（仅在当前文件可见）
static Camera* s_camera = nullptr;
static GPContext* s_context = nullptr;
static bool s_connected = false;
static std::string s_lastError;

// 全局变量定义（为兼容性保留）
std::string g_camLibDir;

// ======================= 全局相机访问接口实现 =======================
Camera* GetGlobalCamera() {
    // 双重检查：先检查本地静态变量，再检查ConnectionManager
    if (s_camera != nullptr) {
        return s_camera;
    }
    // 如果静态变量为空，尝试从ConnectionManager获取
    auto& manager = ConnectionManager::getInstance();
    return manager.getCamera();
}

GPContext* GetGlobalContext() {
    if (s_context != nullptr) {
        return s_context;
    }
    auto& manager = ConnectionManager::getInstance();
    return manager.getContext();
}

bool IsCameraConnected() {
    if (s_camera != nullptr && s_context != nullptr) {
        return s_connected;
    }
    auto& manager = ConnectionManager::getInstance();
    return manager.isConnected();
}

std::string GetLastCameraError() {
    if (!s_lastError.empty()) {
        return s_lastError;
    }
    auto& manager = ConnectionManager::getInstance();
    return manager.getLastError();
}

void SetCameraInstance(Camera* camera, GPContext* context, bool connected) {
    s_camera = camera;
    s_context = context;
    s_connected = connected;
    s_lastError.clear();
    
    // 也可以选择性地更新ConnectionManager（如果需要）
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                 "设置全局相机实例: camera=%p, context=%p, connected=%d", 
                 camera, context, connected);
}

void ClearCameraInstance() {
    s_camera = nullptr;
    s_context = nullptr;
    s_connected = false;
    s_lastError = "Disconnected";
    
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                 "清除全局相机实例");
}

// ======================= 原有的全局变量定义 =======================
// 移除原有的全局变量定义，或者保留但标记为废弃
// Camera* g_camera = nullptr;  // 移除
// GPContext* g_context = nullptr;  // 移除
// bool g_connected = false;  // 移除

// ======================= 原有的工具函数 =======================
napi_value CreateNapiString(napi_env env, const char* str) {
    napi_value result;
    napi_create_string_utf8(env, str ? str : "", NAPI_AUTO_LENGTH, &result);
    return result;
}

napi_value CreateNapiBoolean(napi_env env, bool value) {
    napi_value result;
    napi_get_boolean(env, value, &result);
    return result;
}