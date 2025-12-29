// native_common.cpp
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




// ###########################################################################
// NAPI接口：从ArkTS获取动态库路径（驱动/端口模块存放位置）
// ###########################################################################
/**
 * @brief ArkTS层调用此函数，传入设备上"驱动/端口模块"的路径，存到全局变量g_camLibDir
 * @param env NAPI环境
 * @param info NAPI回调信息（包含ArkTS传入的参数）
 * @return napi_value 返回true给ArkTS，标识路径已接收
 */


/*
已经转移到NapiDeviceInterface中 毕竟是和设备相关的
napi_value SetGPhotoLibDirs(napi_env env, napi_callback_info info) {
    size_t argc = 1;    // 期望接收1个参数（动态库路径字符串）
    napi_value args[1]; // 存储ArkTS传入的参数
    // napi_get_cb_info：从回调信息中提取ArkTS传入的参数，存入args数组
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    char camDir[256]; // 缓冲区：存储转换后的C字符串（长度256足够存路径）
    // napi_get_value_string_utf8：将ArkTS字符串参数转C字符串，存入camDir
    napi_get_value_string_utf8(env, args[0], camDir, sizeof(camDir) - 1, nullptr);

    g_camLibDir = camDir; // 存入全局变量，供后续驱动加载使用
    // 打印日志：确认路径已正确接收（方便调试路径是否正确）
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "g_camLibDir的值为：%{public}s", g_camLibDir.c_str());

    napi_value result;                    // 返回结果给ArkTS
    napi_get_boolean(env, true, &result); // 生成ArkTS的布尔值true

    // 直接在这里把libgphoto2的环境变量设置好
    // CAMLIBS：相机驱动路径（如ptp2.so存放位置）
    setenv("CAMLIBS", g_camLibDir.c_str(), 1);
    // IOLIBS：端口模块路径（如ptpip.so存放位置，PTP/IP连接必需）
    setenv("IOLIBS", g_camLibDir.c_str(), 1);
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "CAMLIBS IOLIBS 环境变量设置OK");

    return result;
}
*/






// 实现：调用 NAPI 原生接口创建布尔值
napi_value CreateNapiBoolean(napi_env env, bool value) {
  napi_value result;
  // 调用 NAPI 的 napi_get_boolean 接口，根据 value 生成 true/false 的 napi_value
  napi_status status = napi_get_boolean(env, value, &result);
  if (status != napi_ok) {
    // 出错处理（例如返回空值或抛异常，根据业务需求调整）
    return nullptr;
  }
  return result;
}




