// native_common.h
// Created on 2025/11/9.
//
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".


#ifndef PHOTOSEND_NATIVE_COMMON_H
#define PHOTOSEND_NATIVE_COMMON_H

#include "gphoto2/gphoto2-camera.h"
#include "gphoto2/gphoto2-context.h"
#include <cstdarg>
#include <napi/native_api.h>
#include <string>

// 先声明前置类（解决循环依赖）
class ConnectionManager;

// ======================= 全局相机访问接口 =======================
// 统一的全局访问接口，避免其他模块直接访问ConnectionManager

/**
 * @brief 获取当前相机对象
 * @return Camera* 相机对象指针（可能为nullptr）
 */
Camera* GetGlobalCamera();

/**
 * @brief 获取当前相机上下文
 * @return GPContext* 上下文指针（可能为nullptr）
 */
GPContext* GetGlobalContext();

/**
 * @brief 检查相机是否已连接
 * @return bool 连接状态
 */
bool IsCameraConnected();

/**
 * @brief 获取最后的错误信息
 * @return std::string 错误描述
 */
std::string GetLastCameraError();

/**
 * @brief 设置相机对象（由ConnectionManager调用）
 * @param camera 相机对象
 * @param context 上下文
 * @param connected 连接状态
 */
void SetCameraInstance(Camera* camera, GPContext* context, bool connected);

/**
 * @brief 清除相机对象（由ConnectionManager调用）
 */
void ClearCameraInstance();

// ======================= 向后兼容的宏定义 =======================
// 为了兼容现有代码，提供宏定义（逐渐淘汰直接使用全局变量）

#define g_camera GetGlobalCamera()
#define g_context GetGlobalContext()
#define g_connected IsCameraConnected()

// ======================= 原有的结构体和函数 =======================
struct ConfigItem {
    std::string name;
    std::string label;
    std::string type;
    std::string current;
    std::vector<std::string> choices;
    float floatValue;
    float bottomFloat;
    float topFloat;
    float stepFloat;
    int intValue;
};

// 工具函数
extern napi_value CreateNapiString(napi_env env, const char* str);
extern napi_value CreateNapiBoolean(napi_env env, bool value);

#endif // PHOTOSEND_NATIVE_COMMON_H