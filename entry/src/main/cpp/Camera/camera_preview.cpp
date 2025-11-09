#include <napi/native_api.h>
#include "hilog/log.h"
#include "native_common.h"
#include <pthread.h>
#include <gphoto2/gphoto2.h>
#include <unistd.h>

// 日志配置
#define LOG_DOMAIN 0X0003
#define LOG_TAG "Nikon_Camera_Preview"

// 全局状态与线程锁
static pthread_mutex_t g_camera_mutex = PTHREAD_MUTEX_INITIALIZER;
static bool g_liveview_active = false;


// 启动预览
static bool startLiveview(Camera *camera, GPContext *ctx) {
    if (g_liveview_active) {
        // OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "预览已启动");
        return true;
    }

    // 尝试通过配置项启用预览
    CameraWidget *root = nullptr;
    int ret = gp_camera_get_config(camera, &root, ctx);
    if (ret == GP_OK) {
        CameraWidget *liveview_widget = nullptr;
        // 尝试匹配常见预览配置项
        if (gp_widget_get_child_by_name(root, "liveview", &liveview_widget) == GP_OK ||
            gp_widget_get_child_by_name(root, "live-view", &liveview_widget) == GP_OK ||
            gp_widget_get_child_by_name(root, "lv", &liveview_widget) == GP_OK) {
            int enable = 1;
            gp_widget_set_value(liveview_widget, &enable);
            gp_camera_set_config(camera, root, ctx);
            // OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "已启用预览模式");
        }
        gp_widget_unref(root);
    }

    // 验证预览可用性
    CameraFile *test_file = nullptr;
    ret = gp_file_new(&test_file);
    if (ret != GP_OK) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "创建测试文件失败: %s", gp_result_as_string(ret));
        return false;
    }

    ret = gp_camera_capture_preview(camera, test_file, ctx);
    gp_file_unref(test_file);
    if (ret != GP_OK) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "预览启动失败: %s", gp_result_as_string(ret));
        return false;
    }

    g_liveview_active = true;
    return true;
}


// 停止预览
static void stopLiveview(Camera *camera, GPContext *ctx) {
    if (!g_liveview_active) return;

    // 尝试关闭预览配置
    CameraWidget *root = nullptr;
    if (gp_camera_get_config(camera, &root, ctx) == GP_OK) {
        CameraWidget *liveview_widget = nullptr;
        if (gp_widget_get_child_by_name(root, "liveview", &liveview_widget) == GP_OK) {
            gp_widget_set_value(liveview_widget, 0);
            gp_camera_set_config(camera, root, ctx);
        }
        gp_widget_unref(root);
    }

    g_liveview_active = false;
    // OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "预览已停止");
}


// 获取预览数据核心逻辑
static bool GetCameraPreview(uint8_t **data, size_t *length) {
    if (!g_connected || !g_camera || !data || !length) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "相机未连接或参数无效");
        return false;
    }
    *data = nullptr;
    *length = 0;

    GPContext *ctx = g_context ? g_context : gp_context_new();
    bool is_temp_ctx = !g_context;

    if (!startLiveview(g_camera, ctx)) {
        if (is_temp_ctx) gp_context_unref(ctx);
        return false;
    }

    CameraFile *file = nullptr;
    int ret = gp_file_new(&file);
    if (ret != GP_OK || !file) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "创建文件对象失败: %s", gp_result_as_string(ret));
        stopLiveview(g_camera, ctx);
        if (is_temp_ctx) gp_context_unref(ctx);
        return false;
    }

    // 捕获预览帧
    ret = gp_camera_capture_preview(g_camera, file, ctx);
    if (ret != GP_OK) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "捕获预览失败: %s", gp_result_as_string(ret));
        gp_file_unref(file);
        stopLiveview(g_camera, ctx);
        if (is_temp_ctx) gp_context_unref(ctx);
        return false;
    }

    // 提取数据
    const char *preview_data;
    unsigned long preview_size;
    gp_file_get_data_and_size(file, &preview_data, &preview_size);

    // 验证JPEG格式
    bool is_jpeg = (preview_size >= 2) && 
                  ((uint8_t)preview_data[0] == 0xFF) && 
                  ((uint8_t)preview_data[1] == 0xD8);

    if (!preview_data || preview_size == 0 || preview_size > 5 * 1024 * 1024 || !is_jpeg) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "无效预览数据 (大小: %lu, JPEG: %s)",
                     preview_size, is_jpeg ? "是" : "否");
        gp_file_unref(file);
        stopLiveview(g_camera, ctx);
        if (is_temp_ctx) gp_context_unref(ctx);
        return false;
    }

    // 复制数据到输出缓冲区
    *data = (uint8_t *)malloc(preview_size);
    if (!*data) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "内存分配失败");
        gp_file_unref(file);
        stopLiveview(g_camera, ctx);
        if (is_temp_ctx) gp_context_unref(ctx);
        return false;
    }
    memcpy(*data, preview_data, preview_size);
    *length = static_cast<size_t>(preview_size);

    // 清理资源
    gp_file_unref(file);
    if (is_temp_ctx) gp_context_unref(ctx);
    return true;
}


// NAPI接口：获取预览数据
napi_value GetPreviewNapi(napi_env env, napi_callback_info info) {
    if (pthread_mutex_lock(&g_camera_mutex) != 0) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "获取线程锁失败");
        return nullptr;
    }

    uint8_t *data = nullptr;
    size_t length = 0;
    bool success = GetCameraPreview(&data, &length);

    if (!success) {
        stopLiveview(g_camera, g_context);
    }

    pthread_mutex_unlock(&g_camera_mutex);

    if (!success || !data || length == 0) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "预览数据获取失败");
        if (data) free(data);
        return nullptr;
    }

    // 创建NAPI Buffer
    napi_value buffer = nullptr;
    void *buffer_data = nullptr;
    napi_status status = napi_create_buffer(env, length, &buffer_data, &buffer);
    if (status == napi_ok && buffer_data != nullptr) {
        memcpy(buffer_data, data, length);
    }
    free(data);

    if (status != napi_ok) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "创建Buffer失败: %d", status);
        return nullptr;
    }

    return buffer;
}


// NAPI接口：停止预览
napi_value StopPreviewNapi(napi_env env, napi_callback_info info) {
    if (pthread_mutex_lock(&g_camera_mutex) != 0) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "获取线程锁失败");
        return nullptr;
    }

    if (g_connected && g_camera) {
        stopLiveview(g_camera, g_context);
    }

    pthread_mutex_unlock(&g_camera_mutex);
    return nullptr;
}