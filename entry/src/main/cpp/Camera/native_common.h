//
// Created on 2025/11/9.
//
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".

#ifndef PHOTOSEND_NATIVE_COMMON_H
#define PHOTOSEND_NATIVE_COMMON_H


#include "gphoto2/gphoto2-camera.h"
#include "gphoto2/gphoto2-context.h"
#include <cstdarg>  // 暴露可变参数声明（供日志宏使用）
#include <napi/native_api.h>
#include <string>

// 声明全局相机变量（extern表示“在其他地方定义”）
extern Camera* g_camera;       // 相机对象指针
extern GPContext* g_context;   // 相机上下文指针

extern bool g_connected;


// 声明结构体类型（供其他文件使用该类型）
struct ConfigItem {
    std::string name;                 // 参数名（如"aperture"）
    std::string label;                // 显示名称（如"Aperture"）
    std::string type;                 // 参数类型（"choice"|"text"|"range"等）
    std::string current;              // 当前值
    std::vector<std::string> choices; // 可选值列表（仅选项类型）
};

// 声明全局变量（extern表示"在其他文件中定义"，供外部引用）
extern std::string g_camLibDir;  // 注意：去掉static，否则无法跨文件共享





// 工具函数 数据类型转换
extern  napi_value CreateNapiString(napi_env env, const char *str);



// 设置动态变量库
extern napi_value SetGPhotoLibDirs(napi_env env, napi_callback_info info);


// 声明：将 C++ bool 转换为 NAPI 布尔值
napi_value CreateNapiBoolean(napi_env env, bool value);

#endif //PHOTOSEND_NATIVE_COMMON_H
