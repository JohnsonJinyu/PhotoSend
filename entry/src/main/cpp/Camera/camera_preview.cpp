//
// Created on 2025/11/5.
//
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".
#include <napi/native_api.h>
#include "native_common.h"
#include "hilog/log.h"

#define LOG_DOMAIN 0X0003
#define LOG_TAG "Camera_Preview"








// ###########################################################################
// 核心函数：获取相机实时预览（内部逻辑，如取景框画面）
// ###########################################################################
/**
 * @brief 内部函数：获取相机实时预览画面（二进制数据，通常为JPEG格式）
 * @param data 输出参数：指向预览数据（需调用者后续free释放）
 * @param length 输出参数：预览数据长度（字节数）
 * @return bool 获取成功返回true，失败返回false
 */
static bool GetPreview(uint8_t **data, size_t *length) {
    // 1. 基础校验：连接状态和相机句柄
    if (!g_connected || !g_camera || !data || !length) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "GetPreview: 无效的连接状态或参数");
        return false;
    }
    *data = nullptr;
    *length = 0;



    // 新增：校验上下文是否有效（若g_context为空，用默认上下文）
    GPContext *ctx = g_context ? g_context : gp_context_new();
    if (!ctx) {
        printf("GetPreview: 上下文无效，无法创建默认上下文\n");
        return false;
    }



    // 2. 创建文件对象并校验
    CameraFile *file = nullptr;
    int ret = gp_file_new(&file);
    if (ret != GP_OK || !file) {
        printf("GetPreview: 创建CameraFile失败\n");
        return false;
    }

    // 3. 拉取预览数据（核心步骤，打印错误码）
    ret = gp_camera_capture_preview(g_camera, file, g_context);
    if (ret != GP_OK) {
         OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, 
                    "GetPreview: 拉取预览失败，错误码: %{public}d, 原因: %{public}s", 
                    ret, gp_result_as_string(ret));
        gp_file_unref(file); // 错误码可查libgphoto2文档
        gp_file_unref(file);
        return false;
    }

    // 4. 提取数据和大小（严格校验）
    const char *previewData = nullptr;
    unsigned long previewSize = 0;
    gp_file_get_data_and_size(file, &previewData, &previewSize);

    // 校验数据有效性（关键：避免空指针或0长度）
    if (!previewData || previewSize == 0 || previewSize > 1024 * 1024) { // 限制最大1MB（防异常大文件）
        //printf("GetPreview: 无效的预览数据，size=%lu\n", previewSize);
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "GetPreview: 无效的预览数据，size=%lu", previewSize);
        gp_file_unref(file);
        return false;
    }

    // 5. 安全分配内存并拷贝（避免溢出）
    *data = (uint8_t *)malloc(previewSize);
    if (!*data) {
        //printf("GetPreview: 内存分配失败\n");
        OH_LOG_PrintMsg(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "GetPreview: 内存分配失败");
        gp_file_unref(file);
        return false;
    }
    memcpy(*data, previewData, previewSize);
    *length = previewSize;

    // 提取数据后添加
    printf("Preview header: 0x%02X%02X%02X%02X, size=%lu\n",
       (unsigned char)previewData[0],
       (unsigned char)previewData[1],
       (unsigned char)previewData[2],
       (unsigned char)previewData[3],
       previewSize);
    
    
    // 6. 释放资源（必须做）
    gp_file_unref(file);
    return true;
}


// ###########################################################################
// NAPI接口：获取相机预览（暴露给ArkTS调用，封装GetPreview）
// ###########################################################################
/**
 * @brief ArkTS层调用此函数，获取相机实时预览画面
 * @param env NAPI环境
 * @param info NAPI回调信息
 * @return napi_value 返回ArkTS的Buffer（预览数据），失败返回nullptr
 */
napi_value GetPreviewNapi(napi_env env, napi_callback_info info) {
    // 指针：存储预览数据
    uint8_t *data = nullptr;
    size_t length = 0; // 预览数据长度

    // 调用内部获取预览函数
    bool success = GetPreview(&data, &length);

    // 失败或无数据，返回nullptr
    if (!success || data == nullptr || length == 0)
        return nullptr;

    // 创建ArkTS Buffer，拷贝预览数据
    napi_value buffer;
    napi_create_buffer_copy(env, length, data, nullptr, &buffer);

    // 释放C++内存
    free(data);

    // 返回Buffer给ArkTS（ArkTS侧可渲染为预览画面）
    return buffer;
}