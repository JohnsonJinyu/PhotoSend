// camera_capture.cpp
// Created on 2025/11/10.
//
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".

#include "gphoto2/gphoto2-camera.h"
#include <napi/native_api.h>
#include <hilog/log.h>
#include <camera/native_common.h>


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
napi_value TakePhoto(napi_env env, napi_callback_info info) {
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
