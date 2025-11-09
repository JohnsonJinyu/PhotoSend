//
// Created on 2025/11/9.
//
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".



#include "native_common.h"
#include "gphoto2/gphoto2-camera.h"
#include <cstdarg>  // 用于可变参数（日志格式化）
#include <hilog//log.h>  // 以Android为例，其他平台可替换为对应日志接口


// ###########################################################################
// 全局变量：跨函数共享相机状态（避免重复创建/泄漏，需谨慎管理）
// ###########################################################################

// 相机对象指针：指向已初始化的相机实例（nullptr = 未连接）
// （libgphoto2中，Camera是所有相机操作的核心载体）
Camera *g_camera = nullptr;
// 相机上下文指针：管理相机操作的环境（内存、线程、错误回调等）
GPContext *g_context = nullptr;

// 连接状态标记：true = 已连接，false = 未连接（简化状态判断）
bool g_connected = false;

