//
// Created on 2025/11/9.
//
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".



#include "native_common.h"
#include "gphoto2/gphoto2-camera.h"
#include <cstdarg>  // 用于可变参数（日志格式化）
#include <hilog//log.h>  // 以Android为例，其他平台可替换为对应日志接口
#include <napi/native_api.h>


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

// 定义全局变量（这里是实际内存分配的地方）
std::string g_camLibDir;  // 无需static，默认初始化为空字符串






// ###########################################################################
// 工具函数：NAPI数据类型转换（C++ → ArkTS）
// ###########################################################################
/**
 * @brief 将C语言字符串（const char*）转换为ArkTS可识别的napi_value字符串
 * @param env NAPI环境（每个NAPI函数都需要，关联ArkTS上下文）
 * @param str 待转换的C字符串（nullptr时返回空字符串）
 * @return napi_value ArkTS侧的字符串对象
 */
napi_value CreateNapiString(napi_env env, const char *str) {
    napi_value result; // 存储转换后的ArkTS字符串
    // napi_create_string_utf8：NAPI内置函数，将UTF-8格式C字符串转ArkTS字符串
    // NAPI_AUTO_LENGTH：自动计算字符串长度（无需手动传strlen）
    napi_create_string_utf8(env, str ? str : "", NAPI_AUTO_LENGTH, &result);
    return result; // 返回给ArkTS层
}