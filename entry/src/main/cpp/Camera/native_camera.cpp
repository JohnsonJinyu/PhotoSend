
// 主接口实现（调用其他模块）

// ###########################################################################
// 头文件引入：依赖库的核心接口定义
// ###########################################################################
// 基础内存/字符串操作库
#include <cstddef>
#include <cstdlib>
#include <cstring>
#include <string>
// NAPI头文件：ArkTS与C++交互的核心接口（定义数据类型、函数调用规则）
#include <napi/native_api.h>
#include "Camera/camera_device.h"
#include "napi/native_api.h"
// libgphoto2头文件：相机操作核心接口（相机对象、文件、配置、端口管理）
#include <gphoto2/gphoto2.h>
#include <gphoto2/gphoto2-camera.h>
#include <gphoto2/gphoto2-file.h>
#include <gphoto2/gphoto2-widget.h>
// ltdl头文件：动态库加载器（加载相机驱动、端口模块）
#include <ltdl.h>
// HarmonyOS日志头文件：打印调试信息
#include <hilog/log.h>

// 自定义的头文件部分
#include "native_common.h"
#include "camera_device.h"
#include "camera_config.h"
#include "camera_preview.h"

// ###########################################################################
//  宏定义：日志配置（固定格式，方便定位日志来源）
// ###########################################################################
#define LOG_DOMAIN 0x0001      // 日志域（自定义标识，区分不同模块日志）
#define LOG_TAG "NativeCamera" // 日志标签（日志中显示的模块名）











// ###########################################################################
// 核心函数：触发相机拍照（内部逻辑，不直接暴露给ArkTS）
// ###########################################################################
/**
 * @brief 内部函数：触发已连接的相机拍照，并返回照片在相机中的存储路径
 * @param outFolder 输出参数：存储照片的文件夹路径（如"/store_00010001/DCIM/100NIKON"）
 * @param outFilename 输出参数：照片文件名（如"DSC_0001.JPG"）
 * @return bool 拍照成功返回true，失败返回false
 */
static bool InternalCapture(char *outFolder, char *outFilename) {
    // 未连接相机，直接返回失败
    if (!g_connected)
        return false;

    // CameraFilePath：libgphoto2结构体，存储相机中文件的路径（文件夹+文件名）
    CameraFilePath path;

    // 调用libgphoto2拍照函数：gp_camera_capture
    // 参数1：已连接的相机对象
    // 参数2：拍摄类型（GP_CAPTURE_IMAGE = 静态照片，还有视频、音频等类型）
    // 参数3：输出参数，存储拍照后的文件路径
    // 参数4：上下文对象
    int ret = gp_camera_capture(g_camera, GP_CAPTURE_IMAGE, &path, g_context);
    
    

    // 拍照失败（如相机忙、无存储空间），返回false
    if (ret != GP_OK)
        return false;
    
    
    
    // 拍照成功后，同步路径到文件系统
    int fs_ret = gp_filesystem_append(g_camera->fs, path.folder, path.name, g_context);
    if (fs_ret != GP_OK) {
    // 记录警告日志，部分相机可能不需要此步骤，但建议兼容
    OH_LOG_Print(LOG_APP, LOG_WARN, LOG_DOMAIN, LOG_TAG, "Failed to append to filesystem: %{public}d", fs_ret);
    }

    // 将相机返回的路径拷贝到输出参数（供后续下载使用）
    strcpy(outFolder, path.folder); // 拷贝文件夹路径
    strcpy(outFilename, path.name); // 拷贝文件名
    return true;                    // 拍照成功
}


// ###########################################################################
// NAPI接口：触发拍照（暴露给ArkTS调用，封装InternalCapture）
// ###########################################################################
/**
 * @brief ArkTS层调用此函数，触发相机拍照，并返回照片路径信息
 * @param env NAPI环境
 * @param info NAPI回调信息
 * @return napi_value 返回ArkTS对象（包含success、folder、name三个属性）
 */
static napi_value TakePhoto(napi_env env, napi_callback_info info) {
    // 缓冲区：存储拍照后的文件夹路径和文件名
    char folder[128] = {0};
    char name[128] = {0};

    // 调用内部拍照函数
    bool success = InternalCapture(folder, name);

    // 创建ArkTS对象：用于返回多个结果（success、folder、name）
    napi_value result;
    napi_create_object(env, &result);

    // 给对象添加属性：success（拍照是否成功）
    napi_set_named_property(env, result, "success", CreateNapiString(env, success ? "true" : "false"));
    // 给对象添加属性：folder（照片在相机中的文件夹路径）
    napi_set_named_property(env, result, "folder", CreateNapiString(env, folder));
    // 给对象添加属性：name（照片在相机中的文件名）
    napi_set_named_property(env, result, "name", CreateNapiString(env, name));

    // 返回对象给ArkTS（ArkTS侧可通过result.folder获取路径）
    return result;
}






// ###########################################################################
// 核心函数：从相机下载照片（内部逻辑，不直接暴露给ArkTS）
// ###########################################################################
/**
 * @brief 内部函数：根据"相机中的文件路径"，下载照片到内存，并返回二进制数据
 * @param folder 照片在相机中的文件夹路径（如InternalCapture返回的outFolder）
 * @param filename 照片在相机中的文件名（如InternalCapture返回的outFilename）
 * @param data 输出参数：指向下载后的二进制数据（需调用者后续free释放）
 * @param length 输出参数：下载数据的长度（字节数，即照片大小）
 * @return bool 下载成功返回true，失败返回false
 */
static bool InternalDownloadFile(const char *folder, const char *filename, uint8_t **data, size_t *length) {
    // 未连接相机，直接返回失败
    if (!g_connected)
        return false;

    // CameraFile：libgphoto2结构体，存储从相机下载的文件数据（二进制+元信息）
    CameraFile *file = nullptr;

    // 创建空的CameraFile对象（用于存放下载的数据）
    gp_file_new(&file);

    // 调用libgphoto2文件下载函数：gp_camera_file_get
    // 参数1：已连接的相机对象
    // 参数2：文件夹路径（相机中）
    // 参数3：文件名（相机中）
    // 参数4：文件类型（GP_FILE_TYPE_NORMAL = 原始文件，还有缩略图、元数据等类型）
    // 参数5：存储下载数据的CameraFile对象
    // 参数6：上下文对象
    int ret = gp_camera_file_get(g_camera, folder, filename, GP_FILE_TYPE_NORMAL, file, g_context);

    // 下载失败，释放CameraFile并返回false
    if (ret != GP_OK) {
        gp_file_unref(file); // 减少引用计数，释放内存
        return false;
    }

    // 从CameraFile中提取二进制数据和大小
    const char *fileData = nullptr; // 临时存储文件数据（const，不可修改）
    unsigned long fileSize = 0;     // 临时存储文件大小（libgphoto2用unsigned long）
    // gp_file_get_data_and_size：获取文件的二进制数据指针和大小
    gp_file_get_data_and_size(file, &fileData, &fileSize);

    // 在堆上分配内存，存储下载的数据（供调用者使用）
    *data = (uint8_t *)malloc(fileSize);
    // 将CameraFile中的数据拷贝到分配的内存中
    memcpy(*data, fileData, fileSize);
    // 设置输出参数：数据长度（转换为size_t类型，符合C++标准）
    *length = fileSize;

    // 释放CameraFile对象（不再需要，避免内存泄漏）
    gp_file_unref(file);

    return true; // 下载成功
}




// ###########################################################################
// NAPI接口：下载照片（暴露给ArkTS调用，封装InternalDownloadFile）
// ###########################################################################
/**
 * @brief ArkTS层调用此函数，传入照片路径，下载照片并返回二进制数据
 * @param env NAPI环境
 * @param info NAPI回调信息（包含2个参数：folder、name）
 * @return napi_value 返回ArkTS的Buffer（存储照片二进制数据），失败返回nullptr
 */
static napi_value DownloadPhoto(napi_env env, napi_callback_info info) {
    size_t argc = 2;    // 期望接收2个参数（文件夹路径、文件名）
    napi_value args[2]; // 存储ArkTS传入的参数
    // 提取ArkTS传入的参数
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    // 缓冲区：存储转换后的C字符串路径
    char folder[128] = {0};
    char name[128] = {0};

    // 将ArkTS参数转换为C字符串
    napi_get_value_string_utf8(env, args[0], folder, sizeof(folder) - 1, nullptr);
    napi_get_value_string_utf8(env, args[1], name, sizeof(name) - 1, nullptr);

    // 指针：存储下载后的二进制数据（需手动free）
    uint8_t *data = nullptr;
    size_t length = 0; // 存储数据长度

    // 调用内部下载函数
    bool success = InternalDownloadFile(folder, name, &data, &length);

    // 下载失败或无数据，返回nullptr给ArkTS
    if (!success || data == nullptr || length == 0) {
        return nullptr;
    }

    // 创建ArkTS的Buffer：将C++的二进制数据转成ArkTS可操作的Buffer
    // napi_create_buffer_copy：拷贝数据到ArkTS管理的内存（后续无需C++手动释放）
    napi_value buffer;
    napi_create_buffer_copy(env, length, data, nullptr, &buffer);

    // 释放C++堆上的内存（数据已拷贝到ArkTS Buffer，此处需释放避免泄漏）
    free(data);

    // 返回Buffer给ArkTS（ArkTS侧可通过Buffer转成图片显示）
    return buffer;
}









// ###########################################################################
//  NAPI接口：断开相机连接（暴露给ArkTS调用）
// ###########################################################################
/**
 * @brief ArkTS层调用此函数，断开相机连接并释放所有资源
 * @param env NAPI环境
 * @param info NAPI回调信息
 * @return napi_value 返回true给ArkTS，标识已断开
 */
static napi_value Disconnect(napi_env env, napi_callback_info info) {
    // 若相机对象存在，先结束会话并释放
    if (g_camera) {
        // gp_camera_exit：通知相机结束连接（关闭端口、清理会话）
        gp_camera_exit(g_camera, g_context);
        // gp_camera_unref：释放相机对象（引用计数为0时自动销毁）
        gp_camera_unref(g_camera);
        g_camera = nullptr; // 指针置空，避免悬空
    }
    // 若上下文对象存在，释放上下文
    if (g_context) {
        gp_context_unref(g_context); // 释放上下文
        g_context = nullptr;         // 指针置空
    }
    // 更新连接状态为未连接
    g_connected = false;

    // 返回true给ArkTS
    napi_value result;
    napi_get_boolean(env, true, &result);
    return result;
}











// ###########################################################################
// NAPI模块注册：将C++函数映射为ArkTS可调用的接口（关键步骤）
// ###########################################################################
// EXTERN_C_START/EXTERN_C_END：确保函数按C语言规则编译（避免C++名称修饰）
// （NAPI框架依赖C语言函数名查找接口，C++会修改函数名，导致找不到）
EXTERN_C_START
/**
 * @brief 模块初始化函数：so库被加载时，NAPI框架自动调用此函数
 * @param env NAPI环境
 * @param exports ArkTS侧的"module.exports"对象（用于挂载接口）
 * @return napi_value 返回挂载好接口的exports对象
 */
static napi_value Init(napi_env env, napi_value exports) {
    // napi_property_descriptor：NAPI结构体，定义"ArkTS函数名→C++函数"的映射关系
    napi_property_descriptor api_list[] = {
        // 格式：{ArkTS侧函数名, 无, C++侧函数名, 无, 无, 无, 默认行为, 无}
        {"GetAvailableCameras", nullptr, GetAvailableCameras, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"SetGPhotoLibDirs", nullptr, SetGPhotoLibDirs, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"ConnectCamera", nullptr, ConnectCamera, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"Disconnect", nullptr, Disconnect, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"IsCameraConnected", nullptr, IsCameraConnectedNapi, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"TakePhoto", nullptr, TakePhoto, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"DownloadPhoto", nullptr, DownloadPhoto, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"SetCameraParameter", nullptr, SetCameraParameter, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"GetPreview", nullptr, GetPreviewNapi, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"GetCameraStatus", nullptr, GetCameraStatus, nullptr, nullptr, nullptr, napi_default, nullptr}, // 新增这行
        {"GetCameraConfig", nullptr, GetCameraConfig, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"GetParamOptions", nullptr, GetParamOptions, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"RegisterParamCallback", nullptr, RegisterParamCallback, nullptr, nullptr, nullptr, napi_default, nullptr},
        
    };

    // 将接口映射表挂载到exports对象（ArkTS侧通过import获取这些函数）
    napi_define_properties(env,                                    // NAPI环境
                           exports,                                // 目标对象（module.exports）
                           sizeof(api_list) / sizeof(api_list[0]), // 接口数量（自动计算，避免硬编码）
                           api_list                                // 接口映射表
    );

    // 打印日志：确认模块初始化成功
    OH_LOG_PrintMsg(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "InitModule: NativeCamera模块初始化成功");
    return exports; // 返回exports给NAPI框架
}
EXTERN_C_END


// ###########################################################################
// NAPI模块信息：定义模块的基本属性（ArkTS侧识别模块的关键）
// ###########################################################################
static napi_module cameraModule = {
    .nm_version = 1,          // NAPI模块版本（固定为1）
    .nm_flags = 0,            // 标志位（0=默认，无特殊配置）
    .nm_filename = nullptr,   // 模块文件名（可选，通常为nullptr）
    .nm_register_func = Init, // 模块初始化函数（指向上面的Init函数）
    .nm_modname = "entry",    // 模块名（必须与ArkTS工程的oh-package.json5中"name"一致）
    .nm_priv = ((void *)0),   // 私有数据（无特殊需求时为nullptr）
    .reserved = {0},          // 保留字段（必须为0）
};


// ###########################################################################
// 模块注册入口：so库加载时自动注册NAPI模块
// ###########################################################################
/**
 * @brief 构造函数属性（__attribute__((constructor))）：so库被加载时自动执行
 * 作用：将上面定义的cameraModule注册到NAPI框架，让ArkTS能找到模块
 */
extern "C" __attribute__((constructor)) void RegisterEntryModule(void) {
    // napi_module_register：NAPI框架函数，注册模块
    napi_module_register(&cameraModule);
}