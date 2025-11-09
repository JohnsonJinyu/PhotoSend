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

// 声明全局相机变量（extern表示“在其他地方定义”）
extern Camera* g_camera;       // 相机对象指针
extern GPContext* g_context;   // 相机上下文指针

extern bool g_connected;

extern  napi_value CreateNapiString(napi_env env, const char *str);


#endif //PHOTOSEND_NATIVE_COMMON_H
