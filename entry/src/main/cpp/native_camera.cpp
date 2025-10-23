#include <cstdlib>
#include <napi/native_api.h>
#include <gphoto2/gphoto2.h> // 包含 libgphoto2 核心定义
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
static Camera *g_camera = nullptr;
static GPContext *g_context = nullptr;
static bool g_connected = false;

// napi_value 是 NAPI 定义的一种 通用类型，用于在 C/C++ 代码中表示 ArkTS/JS 中的任何值（包括数字、字符串、对象、数组、函数等


// 将 C 字符串转换为 ArkTS 可识别的 napi_value 字符串
static napi_value CreateNapiString(napi_env env, const char *str) {
    napi_value result;
    napi_create_string_utf8(env, str ? str : "", NAPI_AUTO_LENGTH, &result);
    return result;
}


/**
 * @brief 用 libgphoto2 初始化相机连接（设置能力、端口、上下文）
 * 
 * */
static bool InternalConnectCamera(const char *model, const char *path) {
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "开始连接相机: model=%{public}s, path=%{public}s", model, path);

    if (g_camera || g_context) {
        OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "释放已有连接资源");
        if (g_camera) gp_camera_exit(g_camera, g_context);
        if (g_camera) gp_camera_unref(g_camera);
        if (g_context) gp_context_unref(g_context);
        g_camera = nullptr;
        g_context = nullptr;
    }

    g_context = gp_context_new();
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "创建上下文成功");

    gp_camera_new(&g_camera);
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "创建相机对象成功");

    CameraAbilitiesList *abilities_list = nullptr;
    gp_abilities_list_new(&abilities_list);
    gp_abilities_list_load(abilities_list, g_context);
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "加载相机能力列表成功");

    int model_index = gp_abilities_list_lookup_model(abilities_list, model);
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "查找型号索引: %{public}d", model_index);
    if (model_index < 0) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "找不到相机型号: %{public}s", model);
        gp_abilities_list_free(abilities_list);
        return false;
    }

    CameraAbilities abilities;
    gp_abilities_list_get_abilities(abilities_list, model_index, &abilities);
    gp_camera_set_abilities(g_camera, abilities);
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "设置相机能力成功");
    gp_abilities_list_free(abilities_list);

    GPPortInfoList *port_list = nullptr;
    gp_port_info_list_new(&port_list);
    gp_port_info_list_load(port_list);
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "加载端口列表成功");

    int port_index = gp_port_info_list_lookup_path(port_list, path);
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "查找端口索引: %{public}d", port_index);
    if (port_index < 0) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "找不到端口路径: %{public}s", path);
        gp_port_info_list_free(port_list);
        return false;
    }

    GPPortInfo port_info;
    gp_port_info_list_get_info(port_list, port_index, &port_info);
    gp_camera_set_port_info(g_camera, port_info);
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "设置端口信息成功");
    gp_port_info_list_free(port_list);

    int ret = gp_camera_init(g_camera, g_context);
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "初始化相机返回值: %{public}d", ret);
    if (ret != GP_OK) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "相机初始化失败，错误码: %{public}d", ret);
        g_connected = false;
        return false;
    }

    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "相机连接成功");
    g_connected = true;
    return true;
}
// 触发拍照，返回照片路径（folder + name）
static bool InternalCapture(char *outFolder, char *outFilename) {
    // 如果当前没有简历相机连接（全局状态g_connected 为false），直接返回失败
    if (!g_connected)
        return false;
    
    // 定义一个 CameraFilePath 结构体，用于存储拍照后相机返回的文件路径信息
    // 定义包含两个字点：folder（文件夹路径）和name（文件名）
    CameraFilePath path;
    
    // 调用libgphoto2 的拍照函数
    // 参数说明：
    //   g_camera     : 已连接的相机对象
    //   GP_CAPTURE_IMAGE : 表示拍摄静态照片
    //   &path        : 输出参数，拍照成功后相机会返回照片存储的路径和文件名
    //   g_context    : 上下文对象
    int ret = gp_camera_capture(g_camera, GP_CAPTURE_IMAGE, &path, g_context);
    
    // 如果返回值不是 GP_OK，说明拍照失败，直接返回 false
    if (ret != GP_OK)
        return false;
    
    // 将相机返回的文件夹路径拷贝到 outFolder（调用者提供的缓冲区）
    strcpy(outFolder, path.folder);
    // 将相机返回的文件名拷贝到 outFilename（调用者提供的缓冲区）
    strcpy(outFilename, path.name);
    // 拍照成功，返回 true
    return true;
}

/**
 * @brief 下载指定照片，返回文件的二进制数据和长度
 * */
static bool InternalDownloadFile(const char *folder, const char *filename, uint8_t **data, size_t *length) {
    // 如果当前没有建立相机连接，直接返回失败
    if (!g_connected)
        return false;
    
    // 定义一个 CameraFile 指针，用于存储下载的文件数据
    CameraFile *file = nullptr;
    
    // 创建一个新的 CameraFile 对象（libgphoto2 用来存放文件内容的容器）
    gp_file_new(&file);
    
    // 调用 libgphoto2 的文件获取函数，从相机中读取指定路径和文件名的文件
    // 参数说明：
    //   g_camera     : 已连接的相机对象
    //   folder       : 照片所在的文件夹路径（例如 "/store_00010001/DCIM/100NIKON"）
    //   filename     : 照片文件名（例如 "DSC_0001.JPG"）
    //   GP_FILE_TYPE_NORMAL : 表示下载原始文件（非缩略图或元数据）
    //   file         : 输出参数，下载的数据会存放到这个 CameraFile 对象中
    //   g_context    : 上下文对象
    int ret = gp_camera_file_get(g_camera, folder, filename, GP_FILE_TYPE_NORMAL, file, g_context);

    // 如果下载失败（返回值不是 GP_OK），释放 file 对象并返回 false
    if (ret != GP_OK) {
        gp_file_unref(file);
        return false;
    }

    // 定义两个变量，用于接收文件数据指针和文件大小
    const char *fileData = nullptr;
    unsigned long fileSize = 0;

    // 从 CameraFile 对象中获取数据指针和文件大小
    gp_file_get_data_and_size(file, &fileData, &fileSize);

    // 在堆上分配一块内存，用于存放文件数据
    *data = (uint8_t *)malloc(fileSize);

    // 将相机返回的文件数据拷贝到我们分配的内存中
    memcpy(*data, fileData, fileSize);

    // 将文件大小写入调用者提供的 length 指针
    *length = fileSize;

    // 释放 CameraFile 对象，避免内存泄漏
    gp_file_unref(file);

    // 下载成功，返回 true
    return true;
}

/**
 * @brief 断开连接
 * */
static napi_value Disconnect(napi_env env, napi_callback_info info) {
    // 如果全局相机对象存在，索命之前已经连接过相机
    if (g_camera) {
        gp_camera_exit(g_camera, g_context);    // 通知相机退出当前会话，做善后处理
        gp_camera_unref(g_camera);              // 释放相机对象引用计数
        g_camera = nullptr;                     // 指针置空，避免悬挂指针
    }
    // 如果上下文对象存在，也需要释放
    if (g_context) {
        gp_context_unref(g_context);            // 释放上下文对象引用计数
        g_context = nullptr;                    // 指针置空
    }
    // 更新全局状态，标记为未连接
    g_connected = false;
    
    // 返回 ArkTS 层一个布尔值 true，表示断开操作执行完成
    napi_value result;
    napi_get_boolean(env, true, &result);
    return result;
}

/**
 * @brief  判断是否连接成功（内部逻辑函数）
 * */
static bool IsCameraConnected() {
    // 如果相机对象或上下文对象为空，说明没有连接
    if (!g_camera || !g_context)
        return false;
    // 调用 libgphoto2 的 gp_camera_get_summary 来测试相机是否还能正常响应
    // 如果返回 GP_OK，说明连接仍然有效
    return (gp_camera_get_summary(g_camera, nullptr, g_context) == GP_OK);
}

// NAPI 封装的连接状态检查方法，返回 ArkTS 布尔值
static napi_value IsCameraConnectedNapi(napi_env env, napi_callback_info info) {
    // 调用内部逻辑函数，获取布尔值（true=已连接，false=未连接）
    bool connected = IsCameraConnected();
    
    // 将布尔值转换为 ArkTS 可识别的 napi_value
    napi_value result;
    napi_get_boolean(env, connected, &result);
    
    // 返回给 ArkTS 层
    return result;
}

/**
 * @brief 连接相机（固定 IP）
 * */
static napi_value ConnectCamera(napi_env env, napi_callback_info info) {
    
    // 定义参数个数，这里期望接收 2 个参数（型号名 + 路径）
    size_t argc = 2;
    napi_value args[2];
    
    // 从 ArkTS 层获取传入的参数，存放到 args 数组中
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    // 定义两个缓冲区，用于存放解析后的字符串参数
    char model[128] = {0};
    char path[128] = {0};
    
    // 将 ArkTS 传入的第一个参数（型号名）转换为 C 字符串
    napi_get_value_string_utf8(env, args[0], model, sizeof(model) - 1, nullptr);
    // 将 ArkTS 传入的第二个参数（路径，如 "ptpip:192.168.1.1"）转换为 C 字符串
    napi_get_value_string_utf8(env, args[1], path, sizeof(path) - 1, nullptr);

    // 调用内部逻辑函数，尝试连接相机
    bool success = InternalConnectCamera(model, path); 
    
    // 将布尔结果转换为 ArkTS 可识别的 napi_value
    napi_value result;
    napi_get_boolean(env, success, &result);
    
    // 返回结果给 ArkTS 层
    return result;
}


/**
 * @brief 拍照
 * */
static napi_value TakePhoto(napi_env env, napi_callback_info info) {
    // 定义两个缓冲区，用于存放拍照后返回的文件夹路径和文件名
    char folder[128] = {0};
    char name[128] = {0};
    
    // 调用内部逻辑函数，触发拍照，并将结果写入 folder 和 name
    bool success = InternalCapture(folder, name); // 你之前写的核心逻辑

    // 创建一个 ArkTS 对象，用于返回照片信息
    napi_value result;
    napi_create_object(env, &result);
    
    napi_set_named_property(env, result, "success", CreateNapiString(env, success ? "true" : "false"));
    // 将文件夹路径作为属性 "folder" 添加到返回对象中
    napi_set_named_property(env, result, "folder", CreateNapiString(env, folder));
    // 将文件名作为属性 "name" 添加到返回对象中
    napi_set_named_property(env, result, "name", CreateNapiString(env, name));
    
    // 返回包含 folder 和 name 的对象给 ArkTS 层
    return result;
}


/**
 * @brief 下载照片
 * */

static napi_value DownloadPhoto(napi_env env, napi_callback_info info) {
    // 定义参数个数，这里期望接收 2 个参数（文件夹路径 + 文件名）
    size_t argc = 2;
    napi_value args[2];
    
    // 从 ArkTS 层获取传入的参数
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    // 定义缓冲区，用于存放解析后的文件夹路径和文件名
    char folder[128] = {0};
    char name[128] = {0};
    
    // 将 ArkTS 传入的第一个参数（文件夹路径）转换为 C 字符串
    napi_get_value_string_utf8(env, args[0], folder, sizeof(folder) - 1, nullptr);
    
    // 将 ArkTS 传入的第二个参数（文件名）转换为 C 字符串
    napi_get_value_string_utf8(env, args[1], name, sizeof(name) - 1, nullptr);

    // 定义指针和长度，用于接收下载的文件数据
    uint8_t *data = nullptr;
    size_t length = 0;
    
    // 调用内部逻辑函数，从相机下载指定文件
    bool success = InternalDownloadFile(folder, name, &data, &length);
    
    // 如果下载失败或数据为空，返回 null 给 ArkTS 层
    if (!success || data == nullptr || length == 0) {
        return nullptr;
    }

    // 创建一个 ArkTS Buffer，并将下载的数据拷贝进去
    napi_value buffer;
    napi_create_buffer_copy(env, length, data, nullptr, &buffer);
    
    // 释放在 C 层分配的内存，避免内存泄漏
    free(data);
    
    // 返回 Buffer 给 ArkTS 层，ArkTS 可以直接拿到二进制数据
    return buffer;
}

/**
 * @brief 设置参数
 * */
static bool SetConfig(const char *key, const char *value) {
    
    // 如果相机未连接，直接返回失败
    if (!g_connected)
        return false;
    
    // 定义一个根节点指针，用于存放相机的配置树
    CameraWidget *root = nullptr;
    
    // 获取相机的配置树（所有可配置参数都在这个树里）
    gp_camera_get_config(g_camera, &root, g_context);
    
    // 定义一个子节点指针，用于存放目标参数
    CameraWidget *child = nullptr;
    
    // 在配置树中查找指定 key 对应的参数节点
    if (gp_widget_get_child_by_name(root, key, &child) != GP_OK) {
        gp_widget_free(root); // 如果没找到，释放配置树内存
        return false;           // 返回失败
    }
    // 设置该参数节点的新值
    gp_widget_set_value(child, value);
    // 将修改后的配置树应用到相机
    int ret = gp_camera_set_config(g_camera, root, g_context);
    // 释放配置树内存
    gp_widget_free(root);
    // 返回是否设置成功
    return (ret == GP_OK);
}

// NAPI 封装：ArkTS 层调用时传入 key 和 value，内部调用 SetConfig
static napi_value SetCameraParameter(napi_env env, napi_callback_info info) {
    // 定义参数个数，这里期望接收 2 个参数（key 和 value）
    size_t argc = 2;
    napi_value args[2];

    // 从 ArkTS 层获取传入的参数
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    // 定义缓冲区，用于存放解析后的 key 和 value
    char key[128] = {0};
    char value[128] = {0};

    // 将 ArkTS 传入的第一个参数（key）转换为 C 字符串
    napi_get_value_string_utf8(env, args[0], key, sizeof(key) - 1, nullptr);

    // 将 ArkTS 传入的第二个参数（value）转换为 C 字符串
    napi_get_value_string_utf8(env, args[1], value, sizeof(value) - 1, nullptr);

    // 调用内部逻辑函数，设置相机参数
    bool success = SetConfig(key, value);

    // 将布尔结果转换为 ArkTS 可识别的 napi_value
    napi_value result;
    napi_get_boolean(env, success, &result);

    // 返回结果给 ArkTS 层
    return result;
}


/**
 * @brief 获取预览
 */
static bool GetPreview(uint8_t **data, size_t *length) {
    // 如果相机未连接，直接返回失败
    if (!g_connected)
        return false;

    // 定义一个 CameraFile 指针，用于存放预览图数据
    CameraFile *file = nullptr;

    // 创建一个新的 CameraFile 对象
    gp_file_new(&file);

    // 调用 libgphoto2 的预览函数，获取相机实时预览图
    int ret = gp_camera_capture_preview(g_camera, file, g_context);

    // 如果获取失败，释放 file 并返回 false
    if (ret != GP_OK) {
        gp_file_unref(file);
        return false;
    }

    // 定义两个变量，用于接收预览图数据指针和大小
    const char *previewData = nullptr;
    unsigned long previewSize = 0;

    // 从 CameraFile 对象中获取数据和大小
    gp_file_get_data_and_size(file, &previewData, &previewSize);

    // 在堆上分配一块内存，用于存放预览图数据
    *data = (uint8_t *)malloc(previewSize);

    // 将数据拷贝到我们分配的内存中
    memcpy(*data, previewData, previewSize);

    // 将数据大小写入调用者提供的 length 指针
    *length = previewSize;

    // 释放 CameraFile 对象，避免内存泄漏
    gp_file_unref(file);

    // 返回成功
    return true;
}


// NAPI 封装：ArkTS 层调用时获取预览图，返回 Buffer
static napi_value GetPreviewNapi(napi_env env, napi_callback_info info) {
    // 定义指针和长度，用于接收预览图数据
    uint8_t *data = nullptr;
    size_t length = 0;

    // 调用内部逻辑函数，获取预览图
    bool success = GetPreview(&data, &length);

    // 如果失败或数据为空，返回 null
    if (!success || data == nullptr || length == 0)
        return nullptr;

    // 创建一个 ArkTS Buffer，并将数据拷贝进去
    napi_value buffer;
    napi_create_buffer_copy(env, length, data, nullptr, &buffer);

    // 释放在 C 层分配的内存
    free(data);

    // 返回 Buffer 给 ArkTS 层
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
