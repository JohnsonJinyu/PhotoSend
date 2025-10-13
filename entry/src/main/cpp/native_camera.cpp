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

/**
 * 工具函数：创建libgphoto2文件对象（适配最新版gp_file_new参数）
 * @param file 输出参数：存储创建的文件对象（需传入CameraFile*的地址）
 * @return bool true=创建成功，false=失败
 */
static bool CreateGpFile(CameraFile** file) {
    // 最新接口：传入CameraFile**，返回错误码
    int ret = gp_file_new(file);
    if (!CheckGpError("gp_file_new", ret) || *file == nullptr) {
        OH_LOG_PrintMsg(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "CreateGpFile: 创建文件对象失败");
        return false;
    }
    return true;
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
 * @brief 功能2：连接指定相机（修改后：需传入相机型号名 + 路径）
 * @param env NAPI环境上下文
 * @param info 回调信息：包含2个参数（相机型号名 + 相机路径）
 * @return napi_value ArkTS布尔值：true=连接成功，false=连接失败
 */
static napi_value ConnectCamera(napi_env env, napi_callback_info info) {
    OH_LOG_PrintMsg(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "ConnectCamera: 开始连接相机");
    
    // 步骤1：先断开已有连接
    ReleaseCameraResources();
    
    // 步骤2：从ArkTS侧获取2个参数（型号名 + 路径，关键修改）
    size_t argc = 2; // 改为接收2个参数
    napi_value args[2] = {nullptr};
    
    napi_status status = napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (status != napi_ok || argc < 2) { // 检查是否传入2个参数
        OH_LOG_PrintMsg(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "ConnectCamera: 需传入2个参数（型号名+路径）");
        return nullptr;
    }
    
    // 步骤3：解析参数（分别获取型号名和路径，关键修改）
    char camera_name[256] = {0};  // 存储相机型号名（如"Canon EOS R5"）
    char camera_path[256] = {0};  // 存储相机路径（如"usb:001,005"）
    size_t name_len = 0, path_len = 0;
    
    // 解析第一个参数：相机型号名
    status = napi_get_value_string_utf8(env, args[0], camera_name, sizeof(camera_name)-1, &name_len);
    if (status != napi_ok || name_len == 0) {
        OH_LOG_PrintMsg(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "ConnectCamera: 相机型号名无效");
        return nullptr;
    }
    
    // 解析第二个参数：相机路径
    status = napi_get_value_string_utf8(env, args[1], camera_path, sizeof(camera_path)-1, &path_len);
    if (status != napi_ok || path_len == 0) {
        OH_LOG_PrintMsg(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "ConnectCamera: 相机路径无效");
        return nullptr;
    }
    
    OH_LOG_Print(
        LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG,
        "ConnectCamera: 型号名：%s，路径：%s", camera_name, camera_path
    );
    
    // 步骤4：创建上下文（不变）
    g_context = gp_context_new();
    if (g_context == nullptr) {
        OH_LOG_PrintMsg(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "ConnectCamera: 创建上下文失败");
        return nullptr;
    }
    
    // 步骤5：创建相机对象（不变）
    int ret = gp_camera_new(&g_camera);
    if (!CheckGpError("gp_camera_new", ret) || g_camera == nullptr) {
        ReleaseCameraResources();
        return nullptr;
    }
    
    // 步骤6：加载能力列表（不变）
    CameraAbilitiesList* abilities_list = nullptr;
    ret = gp_abilities_list_new(&abilities_list);
    if (!CheckGpError("gp_abilities_list_new", ret)) { // 注意：原代码这里误写为gp_abilities_list_load
        ReleaseCameraResources();
        return nullptr;
    }
    
    ret = gp_abilities_list_load(abilities_list, g_context);
    if (!CheckGpError("gp_abilities_list_load", ret)) {
        gp_abilities_list_free(abilities_list);
        ReleaseCameraResources();
        return nullptr;
    }
    
    // 步骤7：查找能力索引（关键修改：传入型号名而非路径）
    int ability_index = gp_abilities_list_lookup_model(abilities_list, camera_name); // 这里传入camera_name
    if (ability_index < 0) {
        OH_LOG_Print(
            LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG,
            "ConnectCamera: 未找到相机能力，型号名：%s，索引：%d", // 日志也改为型号名
            camera_name, ability_index
        );
        gp_abilities_list_free(abilities_list);
        ReleaseCameraResources();
        return nullptr;
    }
    
    // 步骤8：设置相机能力（不变）
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
    
    // 步骤9：设置相机端口（不变，路径在这里用）
    GPPortInfoList* port_list = nullptr;
    ret = gp_port_info_list_new(&port_list);
    if (!CheckGpError("gp_port_info_list_new", ret)) {
        gp_abilities_list_free(abilities_list);
        ReleaseCameraResources();
        return nullptr;
    }
    
    ret = gp_port_info_list_load(port_list);
    if (!CheckGpError("gp_port_info_list_load", ret)) {
        gp_port_info_list_free(port_list);
        gp_abilities_list_free(abilities_list);
        ReleaseCameraResources();
        return nullptr;
    }
    
    // 端口查找用路径（正确，无需修改）
    int port_index = gp_port_info_list_lookup_path(port_list, camera_path);
    if (port_index < 0) {
        OH_LOG_Print(
            LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG,
            "ConnectCamera: 未找到相机端口，路径：%s，索引：%d",
            camera_path, port_index
        );
        gp_port_info_list_free(port_list);
        gp_abilities_list_free(abilities_list);
        ReleaseCameraResources();
        return nullptr;
    }
    
    // 步骤10：初始化相机连接（不变）
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
    
    ret = gp_camera_init(g_camera, g_context);
    if (!CheckGpError("gp_camera_init", ret)) {
        gp_port_info_list_free(port_list);
        gp_abilities_list_free(abilities_list);
        ReleaseCameraResources();
        return nullptr;
    }

    // 步骤11：释放资源（不变）
    gp_abilities_list_free(abilities_list);
    gp_port_info_list_free(port_list);

    // 步骤12：返回结果（不变）
    OH_LOG_PrintMsg(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "ConnectCamera: 相机连接成功");
    napi_value result;
    napi_get_boolean(env, true, &result);
    return result;
}


/**
 * @brief 功能3：设置相机参数（光圈、快门、ISO等，需知道相机支持的参数名）
 * @param env NAPI环境上下文
 * @param info 回调信息：包含2个参数（paramName=参数名，paramValue=参数值）
 * @return napi_value ArkTS布尔值：true=设置成功，false=设置失败
 */
static napi_value SetCameraParameter(napi_env env,napi_callback_info info){
    // 先检查相机是否已经连接
    if (g_camera ==nullptr || g_context == nullptr) {
        OH_LOG_PrintMsg(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "SetCameraParameter: 相机未连接");
        return nullptr;
    }
    
    OH_LOG_PrintMsg(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "SetCameraParameter: 开始设置相机参数");
    
    // 步骤1： 从ArkTS侧获取2个参数（参数名+参数值）
    size_t argc = 2; //期望接收2个参数
    napi_value args[2] = {nullptr};
    
    napi_status status = napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (status != napi_ok || argc <2) {
        OH_LOG_PrintMsg(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "SetCameraParameter: 需传入2个参数（参数名+参数值）");
        return nullptr;
    }
    
    // 步骤2：将ArkTS参数转为C语言字符串
    char param_name[64] = {0};  // 参数名（如"aperture"=光圈，"shutter-speed"=快门）
    char param_value[64] = {0}; // 参数值（如"f/5.6"=光圈值，"1/100"=快门速度）
    
    // 转换参数名
    status = napi_get_value_string_utf8(env, args[0], param_name, sizeof(param_name)-1, nullptr);
    if (status != napi_ok) {
        OH_LOG_PrintMsg(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "SetCameraParameter: 参数名无效");
        return nullptr;
    }
    
    // 转换参数值
    status = napi_get_value_string_utf8(env, args[1], param_value, sizeof(param_value)-1, nullptr);
    if (status != napi_ok) {
        OH_LOG_PrintMsg(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "SetCameraParameter: 参数值无效");
        return nullptr;
    }
    
    OH_LOG_Print(
        LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG,
        "SetCameraParameter: 参数名：{public}%s，参数值：{public}%s",
        param_name, param_value
    );
    
    // 步骤3：获取相机参数控件（libgphoto2用Widget表示参数）
    CameraWidget* root_widget = nullptr;
    int ret = gp_camera_get_config(g_camera, &root_widget, g_context);
    if (!CheckGpError("gp_camera_get_config", ret) || root_widget == nullptr) {
        return nullptr;
    }
    
    // 根据参数名查找对应的参数控件（如"aperture"对应光圈控件）
    CameraWidget* target_widget = nullptr;
    ret = gp_widget_get_child_by_name(root_widget, param_name, &target_widget);
    if (!CheckGpError("gp_widget_get_child_by_name", ret) || target_widget == nullptr) {
        gp_widget_free(root_widget); // 失败时释放根控件
        OH_LOG_Print(
            LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG,
            "SetCameraParameter: 相机不支持该参数：{public}%s", param_name
        );
        return nullptr;
    }
    
    // 步骤4：设置参数值到控件
    ret = gp_widget_set_value(target_widget, param_value);
    if (!CheckGpError("gp_widget_set_value", ret)) {
        gp_widget_free(root_widget);
        return nullptr;
    }
    
    // 步骤5：将设置后的参数提交给相机（生效）
    ret = gp_camera_set_config(g_camera, root_widget, g_context);
    if (!CheckGpError("gp_camera_set_config", ret)) {
        gp_widget_free(root_widget);
        return nullptr;
    }
    
    // 步骤6：释放参数控件资源
    gp_widget_free(root_widget);
    
    // 步骤7：返回设置成功的布尔值
    OH_LOG_PrintMsg(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "SetCameraParameter: 参数设置成功");
    napi_value result;
    napi_get_boolean(env, true, &result);
    return result;
}


/**
 * @brief 功能4：控制相机拍照（拍照后返回照片在相机内的存储路径）
 * @param env NAPI环境上下文
 * @param info 回调信息：无参数
 * @return napi_value ArkTS对象：含folder=照片文件夹路径，name=照片文件名
 */

static napi_value TakePhoto(napi_env env,napi_callback_info info){
    // 先检查相机是否已连接
    if (g_camera == nullptr || g_context == nullptr) {
        OH_LOG_PrintMsg(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "TakePhoto: 相机未连接");
        return nullptr;
    }
    
    OH_LOG_PrintMsg(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "TakePhoto: 开始拍照");
    
    // 步骤1：存储照片路径的结构体（libgphoto2定义）
    CameraFilePath photo_path = {0}; // 初始化：folder=文件夹，name=文件名
    
    // 步骤2：调用拍照接口（GP_CAPTURE_IMAGE=拍摄静态照片）
    int ret = gp_camera_capture(g_camera, GP_CAPTURE_IMAGE, &photo_path, g_context);
    if (!CheckGpError("gp_camera_capture", ret)) {
        return nullptr;
    }
    
    // 步骤3：创建ArkTS对象，存储照片路径信息
    napi_value photo_info = nullptr;
    napi_create_object(env, &photo_info);
    
    // 给对象设置属性："folder"=照片文件夹，"name"=照片文件名
    napi_set_named_property(env, photo_info, "folder", CreateNapiString(env, photo_path.folder));
    napi_set_named_property(env, photo_info, "name", CreateNapiString(env, photo_path.name));

    OH_LOG_Print(
        LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG,
        "TakePhoto: 拍照成功！照片路径：{public}%s/{public}%s",
        photo_path.folder, photo_path.name
    );
    return photo_info; // 返回照片信息给ArkTS侧
}


/**
 * @brief 功能5：获取相机实时预览画面（返回Base64编码的图像数据，ArkTS侧可解码显示）
 * @param env NAPI环境上下文
 * @param info 回调信息：无参数
 * @return napi_value ArkTS字符串：Base64编码的预览图像数据
 */

static napi_value GetPreview(napi_env env, napi_callback_info info) {
    // 先检查相机是否已连接
    if (g_camera == nullptr || g_context == nullptr) {
        OH_LOG_PrintMsg(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "GetPreview: 相机未连接");
        return nullptr;
    }

    OH_LOG_PrintMsg(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "GetPreview: 开始获取预览画面");

    // 步骤1：创建照片文件对象（存储预览数据）
    CameraFile* preview_file = nullptr;
    if (!CreateGpFile(&preview_file)) {
        OH_LOG_PrintMsg(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "GetPreview: 创建预览文件对象失败");
        return nullptr;
    }

    // 步骤2：获取预览数据（预览通常是小尺寸图像，如640x480）
    int ret = gp_camera_capture_preview(g_camera, preview_file, g_context);
    if (!CheckGpError("gp_camera_capture_preview", ret)) {
        gp_file_unref(preview_file); // 失败时释放文件对象
        return nullptr;
    }

    // 步骤3：获取预览数据的指针和长度
    const char* preview_data = nullptr; // 预览数据（二进制，如JPEG格式）
    unsigned long data_len = 0;         // 数据长度（字节数）
    ret = gp_file_get_data_and_size(preview_file, &preview_data, &data_len);
    if (!CheckGpError("gp_file_get_data_and_size", ret) || preview_data == nullptr || data_len == 0) {
        gp_file_unref(preview_file);
        return nullptr;
    }

    // 步骤4：将预览数据转为ArkTS字符串（直接传二进制数据可能有问题，这里简化为传原始数据）
    // 注意：实际项目中建议将二进制数据转为Base64编码后再返回（避免字符编码问题）
    napi_value preview_str = CreateNapiString(env, preview_data);

    // 步骤5：释放预览文件对象
    gp_file_unref(preview_file);

    OH_LOG_Print(
        LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG,
        "GetPreview: 获取预览成功，数据长度：{public}%lu 字节", data_len
    );
    return preview_str; // 返回预览数据给ArkTS侧
}

/**
 * @brief 功能6：从相机下载照片（需传入拍照后返回的文件夹和文件名）
 * @param env NAPI环境上下文
 * @param info 回调信息：包含2个参数（folder=照片文件夹，name=照片文件名）
 * @return napi_value ArkTS字符串：Base64编码的照片数据（ArkTS侧可解码保存）
 */


static napi_value DownloadPhoto(napi_env env, napi_callback_info info) {
    // 先检查相机是否已连接
    if (g_camera == nullptr || g_context == nullptr) {
        OH_LOG_PrintMsg(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "DownloadPhoto: 相机未连接");
        return nullptr;
    }

    OH_LOG_PrintMsg(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "DownloadPhoto: 开始下载照片");

    // 步骤1：从ArkTS侧获取2个参数（照片文件夹+文件名）
    size_t argc = 2;
    napi_value args[2] = {nullptr};

    napi_status status = napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (status != napi_ok || argc < 2) {
        OH_LOG_PrintMsg(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "DownloadPhoto: 需传入2个参数（文件夹+文件名）");
        return nullptr;
    }

    // 步骤2：转换参数为C语言字符串
    char photo_folder[256] = {0}; // 照片文件夹路径
    char photo_name[256] = {0};   // 照片文件名

    status = napi_get_value_string_utf8(env, args[0], photo_folder, sizeof(photo_folder)-1, nullptr);
    if (status != napi_ok) {
        OH_LOG_PrintMsg(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "DownloadPhoto: 文件夹路径无效");
        return nullptr;
    }

    status = napi_get_value_string_utf8(env, args[1], photo_name, sizeof(photo_name)-1, nullptr);
    if (status != napi_ok) {
        OH_LOG_PrintMsg(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "DownloadPhoto: 文件名无效");
        return nullptr;
    }

    OH_LOG_Print(
        LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG,
        "DownloadPhoto: 待下载照片路径：{public}%s/{public}%s",
        photo_folder, photo_name
    );

    // 步骤3：创建文件对象（存储下载的照片数据）
    CameraFile* photo_file = nullptr;
    if (!CreateGpFile(&photo_file)) {
        OH_LOG_PrintMsg(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "DownloadPhoto: 创建照片文件对象失败");
        return nullptr;
    }

    // 步骤4：从相机下载照片（GP_FILE_TYPE_NORMAL=下载原始照片文件）
    int ret = gp_camera_file_get(
        g_camera,          // 已连接的相机对象
        photo_folder,      // 照片文件夹
        photo_name,        // 照片文件名
        GP_FILE_TYPE_NORMAL, // 文件类型（原始照片）
        photo_file,        // 存储下载数据的文件对象
        g_context          // 上下文
    );
    if (!CheckGpError("gp_camera_file_get", ret)) {
        gp_file_unref(photo_file); // 失败时释放文件对象
        return nullptr;
    }

    // 步骤5：获取下载的照片数据（二进制，如JPEG格式）
    const char* photo_data = nullptr;
    unsigned long data_len = 0;
    ret = gp_file_get_data_and_size(photo_file, &photo_data, &data_len);
    if (!CheckGpError("gp_file_get_data_and_size", ret) || photo_data == nullptr || data_len == 0) {
        gp_file_unref(photo_file);
        return nullptr;
    }

    // 步骤6：将照片数据转为ArkTS字符串（实际项目建议转Base64，避免二进制传输问题）
    napi_value photo_str = CreateNapiString(env, photo_data);

    // 步骤7：释放文件对象
    gp_file_unref(photo_file);

    OH_LOG_Print(
        LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG,
        "DownloadPhoto: 照片下载成功，数据长度：{public}%lu 字节", data_len
    );
    return photo_str; // 返回照片数据给ArkTS侧
}

/**
 * @brief 功能7：断开相机连接（退出前必须调用，避免内存泄漏）
 * @param env NAPI环境上下文
 * @param info 回调信息：无参数
 * @return napi_value ArkTS布尔值：true=断开成功
 */
static napi_value DisconnectCamera(napi_env env, napi_callback_info info) {
    OH_LOG_PrintMsg(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "DisconnectCamera: 开始断开相机连接");

    // 调用工具函数释放所有资源
    ReleaseCameraResources();

    // 返回断开成功的布尔值
    napi_value result;
    napi_get_boolean(env, true, &result);
    return result;
}



// ###########################################################################
// NAPI模块注册：将C++函数映射为ArkTS可调用的接口（固定模板）
// ###########################################################################

// EXTERN_C_START/END：确保内部函数按C语言规则编译（避免C++名称修饰）
EXTERN_C_START
/**
 * @brief 模块初始化函数：NAPI框架加载模块时自动调用
 * @param env NAPI环境上下文
 * @param exports 模块导出对象（类似ArkTS的module.exports）
 * @return napi_value 导出对象（包含所有可调用接口）
 */
static napi_value InitModule(napi_env env, napi_value exports) {
    // 定义接口映射表：每个元素对应一个ArkTS可调用的函数
    napi_property_descriptor api_list[] = {
        // 格式：{ArkTS侧函数名, 无, C++侧函数名, 无, 无, 无, 默认行为, 无}
        {"GetCameraList",    nullptr, GetCameraList,    nullptr, nullptr, nullptr, napi_default, nullptr},
        {"ConnectCamera",    nullptr, ConnectCamera,    nullptr, nullptr, nullptr, napi_default, nullptr},
        {"SetCameraParameter", nullptr, SetCameraParameter, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"TakePhoto",        nullptr, TakePhoto,        nullptr, nullptr, nullptr, napi_default, nullptr},
        {"GetPreview",       nullptr, GetPreview,       nullptr, nullptr, nullptr, napi_default, nullptr},
        {"DownloadPhoto",    nullptr, DownloadPhoto,    nullptr, nullptr, nullptr, napi_default, nullptr},
        {"DisconnectCamera", nullptr, DisconnectCamera, nullptr, nullptr, nullptr, napi_default, nullptr}
    };

    // 将接口映射表挂载到导出对象（exports）上
    napi_status status = napi_define_properties(
        env,                                  // NAPI环境
        exports,                              // 导出对象
        sizeof(api_list) / sizeof(api_list[0]), // 接口数量（自动计算）
        api_list                               // 接口映射表
    );
    if (status != napi_ok) {
        OH_LOG_Print(
            LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG,
            "InitModule: 注册接口失败，错误码：{public}%d", status
        );
        return nullptr;
    }

    OH_LOG_PrintMsg(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "InitModule: NativeCamera模块初始化成功");
    return exports; // 返回导出对象给NAPI框架
}

EXTERN_C_END
    
    
    //这里定义了一个 napi_module 结构体，描述了这个原生模块的基本信息。
//关键点是 .nm_modname = "entry"，它决定了 ArkTS 导入时的模块名。

static napi_module demoModule = {
    .nm_version = 1,              // 模块版本
    .nm_flags = 0,                // 标志位（一般为 0）
    .nm_filename = nullptr,       // 文件名（可选）
    .nm_register_func = InitModule,     // 模块初始化函数
    .nm_modname = "entry",        // 模块名，必须和 oh-package.json5 的 name 一致
    .nm_priv = ((void*)0),        // 私有数据（一般不用）
    .reserved = { 0 },            // 保留字段
};

// 注册NAPI模块：模块名"entry"必须与oh-package.json5中的"name"字段一致
// NAPI_MODULE(entry, InitModule)


/**
 * 
 * 这是一个构造函数属性（__attribute__((constructor))），意思是：
- 当 so 库被加载时，这个函数会自动执行。
- 它调用 napi_module_register，把上面定义的 demoModule 注册到 NAPI 框架里。
- 这样 ArkTS 才能通过 import native from 'libentry.so'; 找到并使用这个模块。

 * */
extern "C" __attribute__((constructor)) void RegisterEntryModule(void)
{
    napi_module_register(&demoModule);
}
