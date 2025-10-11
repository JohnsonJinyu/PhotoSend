#include <napi/native_api.h>
#include <gphoto2/gphoto2.h> // 包含 libgphoto2 核心定义
#include "gphoto2/gphoto2-list.h"
#include <gphoto2/gphoto2-camera.h>
#include <gphoto2/gphoto2-file.h>
#include <gphoto2/gphoto2-widget.h>
#include <cstring>
#include <vector>
#include <string>


#define LOG_DOMAIN 0x0001
#define LOG_TAG "NativeCamera"
#include <hilog/log.h>


// ###########################################################################
// 全局变量：管理相机连接状态（跨函数共享，避免重复创建）
// ###########################################################################
// 相机对象指针：指向已连接的相机设备（nullptr表示未连接）
static Camera* g_camera = nullptr;
// 相机上下文指针：管理相机操作的环境（内存、线程等，nullptr表示未初始化）
static GPContext* g_context = nullptr;

// napi_value 是 NAPI 定义的一种 通用类型，用于在 C/C++ 代码中表示 ArkTS/JS 中的任何值（包括数字、字符串、对象、数组、函数等



// ###########################################################################
// 工具函数：封装重复逻辑，减少代码冗余（新手可先理解用途，不用深究实现）
// ###########################################################################

/**
 * @brief 工具函数：创建NAPI字符串（将C语言字符串转为ArkTS可识别的字符串类型）
 * @param env NAPI环境上下文（必须传，所有NAPI操作都需要）
 * @param c_str 要转换的C语言字符串（如"camera_001"）
 * @return napi_value 转换后的ArkTS字符串对象（给ArkTS侧使用）
 */
static napi_value CreateNapiString(napi_env env, const char* c_str) {
    // 防御：如果传入的C字符串为空，返回空字符串
    if(c_str == nullptr){
        c_str = "";
    }
    
    napi_value napi_str = nullptr;
    // NAPI接口，将C字符串转为arkTS字符串
    napi_status status = napi_create_string_utf8(env, c_str, NAPI_AUTO_LENGTH, &napi_str);
    
    //若转换失败，返回空(arkTS侧会收到undefined)
    if (status != napi_ok) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "CreateNapiString: 转换字符串失败，错误码：{public}%d", status);
        return nullptr;
    }
    
    return napi_str;
}



/**
 * @brief 工具函数：检查libgphoto2函数的返回值（统一错误处理）
 * @param func_name 调用的libgphoto2函数名（如"gp_camera_new"，用于日志）
 * @param ret libgphoto2函数的返回值（0=成功，非0=失败）
 * @return bool true=成功，false=失败
 */
static bool CheckGpError(const char* func_name,int ret){
    // libgphoto2规定，返回值为GP_OK(即为0）表示成功
    if(ret == GP_OK){
        return true;
    }
    
    // 失败时打印日志：包含函数名和错误码（方便定位问题）
    OH_LOG_Print(
        LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG,
        "CheckGpError: libgphoto2函数调用失败！函数名：{public}%s，错误码：{public}%d",
        func_name, ret
    );
    return false;
}


/**
 * @brief 工具函数：释放相机相关资源（避免内存泄漏）
 * @note 断开相机连接、程序退出前必须调用
 */
static  void ReleaseCameraResources(){
    // 1、先断开相机连接（如果已经链接）
    if(g_camera != nullptr){
        // 退出相机：通知相机结束当前操作（如停止预览）
        gp_camera_exit(g_camera, g_context);
        gp_camera_unref(g_camera);
        g_camera = nullptr; // 置空，避免后续误用
        OH_LOG_PrintMsg(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "ReleaseCameraResources: 相机对象已释放");
    }
    
    // 2、在释放上下文（如果已经创建）
    if (g_context != nullptr) {
        gp_context_unref(g_context); // 释放上下文引用
        g_context = nullptr; // 置空
        OH_LOG_PrintMsg(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "ReleaseCameraResources: 上下文已释放");
    }
}



// ###########################################################################
// 核心功能函数：对应ArkTS侧可调用的接口（按功能分类）
// ###########################################################################

/**
 * @brief 功能1：获取已连接的相机列表（ArkTS侧调用此函数获取可控制的相机）
 * @param env NAPI环境上下文（自动传入，无需手动处理）
 * @param info 回调信息（包含ArkTS侧传入的参数，此函数无参数）
 * @return napi_value ArkTS数组：每个元素是相机对象（含name=相机名，path=相机路径）
 */
static napi_value GetCameraList(napi_env env,napi_callback_info info){
    OH_LOG_PrintMsg(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "GetCameraList: 开始获取相机列表");
    
    // 步骤1：创建临时上下文（仅用于检测相机，不予后续连接共享）
    GPContext* temp_context = gp_context_new();
    if (temp_context == nullptr) {
        OH_LOG_PrintMsg(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "GetCameraList: 创建临时上下文失败");
        return nullptr; // 返回空给ArkTS侧
    }
    
    // 步骤2：初始化相机列表对象（存储检测到的相机）
    CameraList* camera_list = nullptr;
    int ret = gp_list_new(&camera_list); // 新版本libgphoto2：传入&camera_list（指针的指针）
    if (!CheckGpError("gp_list_new", ret) || camera_list == nullptr) {
        gp_context_unref(temp_context); // 失败时释放临时上下文
        return nullptr;
    }
    
    // 步骤3：自动检测已经连接的相机（如USB/WiFi连接的Nikon相机）
    ret = gp_camera_autodetect(camera_list, temp_context);
    if (!CheckGpError("gp_camera_autodetect", ret)) {
        gp_list_free(camera_list); //失败时释放相机列表
        gp_context_unref(temp_context); // 释放临时放下问
        return nullptr;
    }
    
    // 步骤4：获取相机数量（用于遍历）
    int camera_count = gp_list_count(camera_list);
    OH_LOG_Print(
        LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG,
        "GetCameraList: 检测到相机数量：{public}%d", camera_count
    );
    
    // 步骤5：创建ArkTS数组（用于存储相机信息，返回给ArkTS侧）
    napi_value result_array = nullptr;
    napi_status status = napi_create_array(env, &result_array);
    if (status != napi_ok) {
        OH_LOG_Print(
            LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG,
            "GetCameraList: 创建ArkTS数组失败，错误码：{public}%d", status
        );
        gp_list_free(camera_list);
        gp_context_unref(temp_context);
        return nullptr;
    }
    
    // 步骤6：遍历相机里表，填充相机信息到ArkTS数组
    for (int i = 0 ;i<camera_count;i++){
        //获取相机名（如“Nikon D850”），和相机路径（如“usb:001,005”，连接相机需要此路径）
        const char* camera_name = nullptr;
        const char* camera_path = nullptr;
        gp_list_get_name(camera_list, i, &camera_name); // 获取相机名称
        gp_list_get_value(camera_list, i, &camera_path); // 获取相机路径
        
        // 创建ArkTS对象：存储单个相机的name和path
        napi_value camera_obj = nullptr;
        napi_create_object(env, &camera_obj);
        
        // 给ArkTS对象设置属性：“name”=相机名."path"=相机路径
        napi_set_named_property(env, camera_obj, "name", CreateNapiString(env, camera_name));
        napi_set_named_property(env, camera_obj, "path", CreateNapiString(env, camera_path));
        
        // 将相机对象添加到ArkTS数组的第1个位置
        napi_set_element(env, result_array, i, camera_obj);
                
    }
    
    // 步骤7：释放临时资源（检测完成，不再需要）
    gp_list_free(camera_list);  //释放相机列表
    gp_context_unref(temp_context); // 释放临时上下文
    
    OH_LOG_PrintMsg(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "GetCameraList: 获取相机列表完成");
    return result_array; // 返回ArkTS数组给ArkTS侧
}


/**
 * @brief 功能2：连接指定相机（ArkTS侧需传入相机路径，路径来自GetCameraList的返回值）
 * @param env NAPI环境上下文
 * @param info 回调信息：包含1个参数（相机路径，如"usb:001,005"）
 * @return napi_value ArkTS布尔值：true=连接成功，false=连接失败
 */
static napi_value ConnectCamera(napi_env env,napi_callback_info info){
    OH_LOG_PrintMsg(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "ConnectCamera: 开始连接相机");
    
    // 步骤1：先断开已有链接（避免重复连接导致内存泄漏）
    ReleaseCameraResources();
    
    // 步骤2：从ArkTS侧获取传入的参数（必须传入一个相机路径）
    size_t argc = 1; //期望接收到1个参数
    napi_value args[1] = {nullptr}; // 存储传入的参数
    
    // NAPI接口：获取ArkTS侧传入的参数列表
    napi_status status = napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (status != napi_ok || argc <1) {
        OH_LOG_PrintMsg(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "ConnectCamera: 未传入相机路径参数");
        return nullptr;
    }
    
    // 步骤3：将ArkTS子串串参数（相机路径）转为C语言字符串
    char camera_path[256] = {0}; // 存储相机路径
    size_t path_len = 0; // 存储路径长度
    
    status = napi_get_value_string_utf8(
        env,            // NAPI环境
        args[0],        // ArkTS侧传入的参数（相机路径）
        camera_path,    // 输出：C语言字符串
        sizeof(camera_path) - 1, // 最大长度（留1位存字符串结束符'\0'）
        &path_len       // 输出：实际路径长度
    );
    if (status != napi_ok || path_len == 0) {
        OH_LOG_PrintMsg(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "ConnectCamera: 相机路径参数无效");
        return nullptr;
    }
    OH_LOG_Print(
        LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG,
        "ConnectCamera: 待连接的相机路径：{public}%s", camera_path
    );
    
    // 步骤4：创建相机上下文（全局变量g_context）
    g_context = gp_context_new();
    if (g_context == nullptr) {
        OH_LOG_PrintMsg(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "ConnectCamera: 创建相机上下文失败");
        return nullptr;
    }
    
    // 步骤5：创建相机对象（全局变量g_camera,适配新版本libgphoto2）
    int ret = gp_camera_new(&g_camera); // 关键：传入&g_camera（指针的指针），返回错误码
    if (!CheckGpError("gp_camera_new", ret) || g_camera == nullptr) {
        ReleaseCameraResources(); // 失败时释放已创建的上下文
        return nullptr;
    }
    
    // 步骤6：加载相机能力列表（识别相机信号、支持的功能）
    CameraAbilitiesList* abilities_list = nullptr;
    ret = gp_abilities_list_new(&abilities_list);
    if (!CheckGpError("gp_abilities_list_load", ret)) {
        ReleaseCameraResources();
        return nullptr;
    }
    
    // 加载系统中支持的相机能力（如Nikon D850的参数范围）
    ret = gp_abilities_list_load(abilities_list, g_context);
     if (!CheckGpError("gp_abilities_list_load", ret)) {
        gp_abilities_list_free(abilities_list); // 释放能力列表
        ReleaseCameraResources();
        return nullptr;
    }
    
    // 步骤7：根据相机路径查找对应的能力索引（匹配具体相机型号）
    // gp_abilities_list_lookup_model这个方法要确认下对不对
    int ability_index = gp_abilities_list_lookup_model(abilities_list, camera_path);
    if (ability_index < 0) {
        OH_LOG_Print(
            LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG,
            "ConnectCamera: 未找到相机能力，路径：{public}%s，索引：{public}%d",
            camera_path, ability_index
        );
        gp_abilities_list_free(abilities_list);
        ReleaseCameraResources();
        return nullptr;
    }
    
    // 步骤8：设置相机能力（告诉相机对象当前连接的相机型号）
    CameraAbilities camera_abilities;
    ret = gp_abilities_list_get_abilities(abilities_list, ability_index, &camera_abilities);
    if (!CheckGpError("gp_abilities_list_get_abilities", ret)) {
        gp_abilities_list_free(abilities_list);
        ReleaseCameraResources();
        return nullptr;
    }
    ret = gp_camera_set_abilities(g_camera, camera_abilities);
    if (!CheckGpError("gp_camera_set_abilities", ret)) {
        gp_abilities_list_free(abilities_list);
        ReleaseCameraResources();
        return nullptr;
    }
    
    
     // 步骤9：设置相机端口（USB/WiFi等连接方式）
    GPPortInfoList* port_list = nullptr;
    ret = gp_port_info_list_new(&port_list);
    if (!CheckGpError("gp_port_info_list_new", ret)) {
        gp_abilities_list_free(abilities_list);
        ReleaseCameraResources();
        return nullptr;
    }
    
     // 加载系统中支持的端口（如USB端口、网络端口）
    ret = gp_port_info_list_load(port_list);
    if (!CheckGpError("gp_port_info_list_load", ret)) {
        gp_port_info_list_free(port_list);
        gp_abilities_list_free(abilities_list);
        ReleaseCameraResources();
        return nullptr;
    }
    
    
    // 根据相机路径查找对应的端口索引
    int port_index = gp_port_info_list_lookup_path(port_list, camera_path);
    if (port_index < 0) {
        OH_LOG_Print(
            LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG,
            "ConnectCamera: 未找到相机端口，路径：{public}%s，索引：{public}%d",
            camera_path, port_index
        );
        gp_port_info_list_free(port_list);
        gp_abilities_list_free(abilities_list);
        ReleaseCameraResources();
        return nullptr;
    }
    
    // 设置相机端口信息（告诉相机对象用哪种方式连接）
    GPPortInfo port_info;
    ret = gp_port_info_list_get_info(port_list, port_index, &port_info);
    if (!CheckGpError("gp_port_info_list_get_info", ret)) {
        gp_port_info_list_free(port_list);
        gp_abilities_list_free(abilities_list);
        ReleaseCameraResources();
        return nullptr;
    }
    ret = gp_camera_set_port_info(g_camera, port_info);
    if (!CheckGpError("gp_camera_set_port_info", ret)) {
        gp_port_info_list_free(port_list);
        gp_abilities_list_free(abilities_list);
        ReleaseCameraResources();
        return nullptr;
    }
    
    // 步骤10：最终初始化相机连接（建立与相机的实际通信）
    ret = gp_camera_init(g_camera, g_context);
    if (!CheckGpError("gp_camera_init", ret)) {
        gp_port_info_list_free(port_list);
        gp_abilities_list_free(abilities_list);
        ReleaseCameraResources();
        return nullptr;
    }

    // 步骤11：释放临时资源（能力列表、端口列表不再需要）
    gp_abilities_list_free(abilities_list);
    gp_port_info_list_free(port_list);

    // 步骤12：返回连接成功的布尔值给ArkTS侧
    OH_LOG_PrintMsg(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "ConnectCamera: 相机连接成功");
    napi_value result;
    napi_create_bool(env, true, &result); // 创建ArkTS布尔值true
    return result;
    
    
}











// 注册NAPI接口(类似官方模板)
EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        {"GetCameraList", nullptr, GetCameraList, nullptr, nullptr, nullptr, napi_default, nullptr}};
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}

EXTERN_C_END


NAPI_MODULE(entry, Init)