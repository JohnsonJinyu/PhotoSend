#include <cstdlib>
#include <napi/native_api.h>
#include <gphoto2/gphoto2.h> // 包含 libgphoto2 核心定义
#include "gphoto2/gphoto2-list.h"
#include <gphoto2/gphoto2-camera.h>
#include <gphoto2/gphoto2-file.h>
#include <gphoto2/gphoto2-widget.h>
#include <cstring>


#define LOG_DOMAIN 0x0001
#define LOG_TAG "NativeCamera"
#include <hilog/log.h>


// ###########################################################################
// 全局变量：管理相机连接状态（跨函数共享，避免重复创建）
// ###########################################################################
// 相机对象指针：指向已连接的相机设备（nullptr表示未连接）
// 相机上下文指针：管理相机操作的环境（内存、线程等，nullptr表示未初始化）
static Camera* g_camera = nullptr;
static GPContext* g_context = nullptr;
static bool g_connected = false;

// napi_value 是 NAPI 定义的一种 通用类型，用于在 C/C++ 代码中表示 ArkTS/JS 中的任何值（包括数字、字符串、对象、数组、函数等


// 将 C 字符串转换为 ArkTS 可识别的 napi_value 字符串
static napi_value CreateNapiString(napi_env env, const char* str) {
    napi_value result;
    napi_create_string_utf8(env, str ? str : "", NAPI_AUTO_LENGTH, &result);
    return result;
}


// 用 libgphoto2 初始化相机连接（设置能力、端口、上下文）
static bool InternalConnectCamera(const char* model, const char* path) {
    if (g_camera || g_context) {
        if (g_camera) gp_camera_exit(g_camera, g_context);
        if (g_camera) gp_camera_unref(g_camera);
        if (g_context) gp_context_unref(g_context);
        g_camera = nullptr;
        g_context = nullptr;
    }

    g_context = gp_context_new();
    gp_camera_new(&g_camera);

    CameraAbilitiesList* abilities_list = nullptr;
    gp_abilities_list_new(&abilities_list);
    gp_abilities_list_load(abilities_list, g_context);
    int model_index = gp_abilities_list_lookup_model(abilities_list, model);
    CameraAbilities abilities;
    gp_abilities_list_get_abilities(abilities_list, model_index, &abilities);
    gp_camera_set_abilities(g_camera, abilities);
    gp_abilities_list_free(abilities_list);

    GPPortInfoList* port_list = nullptr;
    gp_port_info_list_new(&port_list);
    gp_port_info_list_load(port_list);
    int port_index = gp_port_info_list_lookup_path(port_list, path);
    GPPortInfo port_info;
    gp_port_info_list_get_info(port_list, port_index, &port_info);
    gp_camera_set_port_info(g_camera, port_info);
    gp_port_info_list_free(port_list);

    int ret = gp_camera_init(g_camera, g_context);
    g_connected = (ret == GP_OK);
    return g_connected;
}

// 触发拍照，返回照片路径（folder + name）
static bool InternalCapture(char* outFolder, char* outFilename) {
    if (!g_connected) return false;
    CameraFilePath path;
    int ret = gp_camera_capture(g_camera, GP_CAPTURE_IMAGE, &path, g_context);
    if (ret != GP_OK) return false;
    strcpy(outFolder, path.folder);
    strcpy(outFilename, path.name);
    return true;
}

// 下载指定照片文件，返回二进制数据
static bool InternalDownloadFile(const char* folder, const char* filename, uint8_t** data, size_t* length) {
    if (!g_connected) return false;
    CameraFile* file = nullptr;
    gp_file_new(&file);
    int ret = gp_camera_file_get(g_camera, folder, filename, GP_FILE_TYPE_NORMAL, file, g_context);
    if (ret != GP_OK) {
        gp_file_unref(file);
        return false;
    }
    const char* fileData = nullptr;
    unsigned long fileSize = 0;
    gp_file_get_data_and_size(file, &fileData, &fileSize);
    *data = (uint8_t*)malloc(fileSize);
    memcpy(*data, fileData, fileSize);
    *length = fileSize;
    gp_file_unref(file);
    return true;
}

/**
 * @brief 断开连接
 * */
static napi_value Disconnect(napi_env env, napi_callback_info info) {
    if (g_camera) {
        gp_camera_exit(g_camera, g_context);
        gp_camera_unref(g_camera);
        g_camera = nullptr;
    }
    if (g_context) {
        gp_context_unref(g_context);
        g_context = nullptr;
    }
    g_connected = false;
    napi_value result;
    napi_get_boolean(env, true, &result);
    return result;
}

/**
 * @brief  判断是否连接成功
 * */
static bool IsCameraConnected() {
    if (!g_camera || !g_context) return false;
    return (gp_camera_get_summary(g_camera, nullptr, g_context) == GP_OK);
}

// NAPI 封装的连接状态检查方法，返回 ArkTS 布尔值
static napi_value IsCameraConnectedNapi(napi_env env, napi_callback_info info) {
    bool connected = IsCameraConnected();
    napi_value result;
    napi_get_boolean(env, connected, &result);
    return result;
}

/**
 * @brief 连接相机（固定 IP）
 * */
static napi_value ConnectCamera(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    char model[128] = {0};
    char path[128] = {0};
    napi_get_value_string_utf8(env, args[0], model, sizeof(model) - 1, nullptr);
    napi_get_value_string_utf8(env, args[1], path, sizeof(path) - 1, nullptr);

    bool success = InternalConnectCamera(model, path); // 你之前写的核心逻辑
    napi_value result;
    napi_get_boolean(env, success, &result);
    return result;
}





/**
 * @brief 拍照
 * */
static napi_value TakePhoto(napi_env env, napi_callback_info info) {
    char folder[128] = {0};
    char name[128] = {0};
    bool success = InternalCapture(folder, name); // 你之前写的核心逻辑

    napi_value result;
    napi_create_object(env, &result);
    napi_set_named_property(env, result, "folder", CreateNapiString(env, folder));
    napi_set_named_property(env, result, "name", CreateNapiString(env, name));
    return result;
}


/**
 * @brief 下载照片
 * */

static napi_value DownloadPhoto(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    char folder[128] = {0};
    char name[128] = {0};
    napi_get_value_string_utf8(env, args[0], folder, sizeof(folder) - 1, nullptr);
    napi_get_value_string_utf8(env, args[1], name, sizeof(name) - 1, nullptr);

    uint8_t* data = nullptr;
    size_t length = 0;
    bool success = InternalDownloadFile(folder, name, &data, &length);
    if (!success || data == nullptr || length == 0) {
        return nullptr;
    }

    napi_value buffer;
    napi_create_buffer_copy(env, length, data, nullptr, &buffer);
    free(data);
    return buffer;
}

/**
 * @brief 设置参数
 * */
static bool SetConfig(const char* key, const char* value) {
    if (!g_connected) return false;
    CameraWidget* root = nullptr;
    gp_camera_get_config(g_camera, &root, g_context);
    CameraWidget* child = nullptr;
    if (gp_widget_get_child_by_name(root, key, &child) != GP_OK) {
        gp_widget_free(root);
        return false;
    }
    gp_widget_set_value(child, value);
    int ret = gp_camera_set_config(g_camera, root, g_context);
    gp_widget_free(root);
    return (ret == GP_OK);
}

static napi_value SetCameraParameter(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    char key[128] = {0};
    char value[128] = {0};
    napi_get_value_string_utf8(env, args[0], key, sizeof(key) - 1, nullptr);
    napi_get_value_string_utf8(env, args[1], value, sizeof(value) - 1, nullptr);

    bool success = SetConfig(key, value);
    napi_value result;
    napi_get_boolean(env, success, &result);
    return result;
}


/**
 * @brief 获取预览
 * */
static bool GetPreview(uint8_t** data, size_t* length) {
    if (!g_connected) return false;
    CameraFile* file = nullptr;
    gp_file_new(&file);
    int ret = gp_camera_capture_preview(g_camera, file, g_context);
    if (ret != GP_OK) {
        gp_file_unref(file);
        return false;
    }
    const char* previewData = nullptr;
    unsigned long previewSize = 0;
    gp_file_get_data_and_size(file, &previewData, &previewSize);
    *data = (uint8_t*)malloc(previewSize);
    memcpy(*data, previewData, previewSize);
    *length = previewSize;
    gp_file_unref(file);
    return true;
}
static napi_value GetPreviewNapi(napi_env env, napi_callback_info info) {
    uint8_t* data = nullptr;
    size_t length = 0;
    bool success = GetPreview(&data, &length);
    if (!success || data == nullptr || length == 0) return nullptr;

    napi_value buffer;
    napi_create_buffer_copy(env, length, data, nullptr, &buffer);
    free(data);
    return buffer;
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
static napi_value Init(napi_env env, napi_value exports) {
    // 定义接口映射表：每个元素对应一个ArkTS可调用的函数
    napi_property_descriptor api_list[] = {
        // 格式：{ArkTS侧函数名, 无, C++侧函数名, 无, 无, 无, 默认行为, 无}
         {"ConnectCamera", nullptr, ConnectCamera, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"Disconnect", nullptr, Disconnect, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"IsCameraConnected", nullptr, IsCameraConnectedNapi, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"TakePhoto", nullptr, TakePhoto, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"DownloadPhoto", nullptr, DownloadPhoto, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"SetCameraParameter", nullptr, SetCameraParameter, nullptr, nullptr, nullptr, napi_default, nullptr},
{"GetPreview", nullptr, GetPreviewNapi, nullptr, nullptr, nullptr, napi_default, nullptr},

        };

    // 将接口映射表挂载到导出对象（exports）上
    napi_define_properties(env,                                    // NAPI环境
                           exports,                                // 导出对象
                           sizeof(api_list) / sizeof(api_list[0]), // 接口数量（自动计算）
                           api_list                                // 接口映射表
    );

    /*if (status != napi_ok) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "InitModule: 注册接口失败，错误码：{public}%d", status);
        //return nullptr;   不能添加这句，不然就不会返回exports了
    }*/

    OH_LOG_PrintMsg(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "InitModule: NativeCamera模块初始化成功");
    return exports; // 返回导出对象给NAPI框架
}

EXTERN_C_END


// 这里定义了一个 napi_module 结构体，描述了这个原生模块的基本信息。
// 关键点是 .nm_modname = "entry"，它决定了 ArkTS 导入时的模块名。

static napi_module cameraModule = {
    .nm_version = 1,          // 模块版本
    .nm_flags = 0,            // 标志位（一般为 0）
    .nm_filename = nullptr,   // 文件名（可选）
    .nm_register_func = Init, // 模块初始化函数
    .nm_modname = "entry",    // 模块名，必须和 oh-package.json5 的 name 一致
    .nm_priv = ((void *)0),   // 私有数据（一般不用）
    .reserved = {0},          // 保留字段
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
extern "C" __attribute__((constructor)) void RegisterEntryModule(void) { napi_module_register(&cameraModule); }
