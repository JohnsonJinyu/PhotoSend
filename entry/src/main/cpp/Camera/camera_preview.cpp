#include <napi/native_api.h>
#include "hilog/log.h"
#include "native_common.h"
#include <pthread.h>
#include <gphoto2/gphoto2.h>
#include <gphoto2/gphoto2-port.h>
#include <unistd.h>

// 日志配置
#define LOG_DOMAIN 0X0003
#define LOG_TAG "Nikon_Camera_Preview"

// 全局状态与线程锁（复用原有设计，确保线程安全）
static pthread_mutex_t g_camera_mutex = PTHREAD_MUTEX_INITIALIZER;
static bool g_liveview_active = false; // 标记预览是否活跃


// 简化的预览启动逻辑：依赖libgphoto2自动处理厂商私有逻辑
static bool startLiveview(Camera *camera, GPContext *ctx) {
    if (g_liveview_active) {
        OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "预览已启动");
        return true;
    }

    // 部分相机需要显式开启预览配置（通过libgphoto2配置树）
    CameraWidget *root = nullptr;
    int ret = gp_camera_get_config(camera, &root, ctx);
    if (ret == GP_OK) {
        // 尝试查找并启用预览开关（不同相机配置项名称可能不同）
        CameraWidget *liveview_widget = nullptr;
        // 常见配置项名称："liveview", "live-view", "lv", "viewfinder"
        if (gp_widget_get_child_by_name(root, "liveview", &liveview_widget) == GP_OK) {
            int enable = 1;
            gp_widget_set_value(liveview_widget, &enable);
            gp_camera_set_config(camera, root, ctx);
            OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "已通过配置项启用预览模式");
        } else {
            OH_LOG_Print(LOG_APP, LOG_WARN, LOG_DOMAIN, LOG_TAG, "未找到预览配置项，尝试直接捕获");
        }
        gp_widget_unref(root);
    } else {
        OH_LOG_Print(LOG_APP, LOG_WARN, LOG_DOMAIN, LOG_TAG, "获取配置树失败（%{public}s），直接尝试预览",
                     gp_result_as_string(ret));
    }

    // 预捕获一帧验证预览是否可用
    CameraFile *test_file = nullptr;
    ret = gp_file_new(&test_file);
    if (ret != GP_OK) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "创建测试文件失败：%{public}s", gp_result_as_string(ret));
        return false;
    }

    ret = gp_camera_capture_preview(camera, test_file, ctx);
    gp_file_unref(test_file); // 仅验证，不保存

    if (ret != GP_OK) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "预览启动失败：%{public}s", gp_result_as_string(ret));
        return false;
    }

    g_liveview_active = true;
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "预览启动成功");
    return true;
}


// 停止预览（通过libgphoto2释放资源）
static void stopLiveview(Camera *camera, GPContext *ctx) {
    if (!g_liveview_active)
        return;

    // 部分相机需要显式关闭预览配置
    CameraWidget *root = nullptr;
    if (gp_camera_get_config(camera, &root, ctx) == GP_OK) {
        CameraWidget *liveview_widget = nullptr;
        if (gp_widget_get_child_by_name(root, "liveview", &liveview_widget) == GP_OK) {
            gp_widget_set_value(liveview_widget, 0); // 0=关闭
            gp_camera_set_config(camera, root, ctx);
        }
        gp_widget_unref(root);
    }

    g_liveview_active = false;
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "预览已停止");
}


// 核心：通过libgphoto2原生接口获取预览数据
static bool GetCameraPreview(uint8_t **data, size_t *length) {
    // 校验前置条件（依赖全局相机连接状态）
    if (!g_connected || !g_camera || !data || !length) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "相机未连接或参数无效");
        return false;
    }
    *data = nullptr;
    *length = 0;

    // 获取上下文（复用全局上下文或临时创建）
    GPContext *ctx = g_context ? g_context : gp_context_new();
    bool is_temp_ctx = !g_context;

    // 确保预览已启动
    if (!startLiveview(g_camera, ctx)) {
        if (is_temp_ctx)
            gp_context_unref(ctx);
        return false;
    }

    // 创建文件对象接收预览数据
    CameraFile *file = nullptr;
    int ret = gp_file_new(&file);
    if (ret != GP_OK || !file) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "创建文件对象失败：%{public}s", gp_result_as_string(ret));
        stopLiveview(g_camera, ctx);
        if (is_temp_ctx)
            gp_context_unref(ctx);
        return false;
    }

    // 核心：调用libgphoto2封装接口捕获预览（自动处理厂商私有协议）
    ret = gp_camera_capture_preview(g_camera, file, ctx);
    if (ret != GP_OK) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "捕获预览失败：%{public}s", gp_result_as_string(ret));
        gp_file_unref(file);
        stopLiveview(g_camera, ctx);
        if (is_temp_ctx)
            gp_context_unref(ctx);
        return false;
    }


    const char *mime_type;
    gp_file_get_mime_type(file, &mime_type); // file 是 gp_camera_capture_preview 输出的 CameraFile 对象
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "预览数据格式：%{public}s", mime_type);


    // 提取预览数据
    const char *preview_data;
    unsigned long preview_size;
    gp_file_get_data_and_size(file, &preview_data, &preview_size);


    // 在获取preview_data和preview_size之后
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "预览数据头部（前8字节）：");
    for (int i = 0; i < 8 && i < preview_size; i++) {
        OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "字节%{public}d: 0x%{public}02X", i,
                     (uint8_t)preview_data[i]);
    }

    // 新增：JPEG格式校验
    bool is_jpeg = false;
    if (preview_size >= 2) {
        uint8_t start_byte1 = static_cast<uint8_t>(preview_data[0]);
        uint8_t start_byte2 = static_cast<uint8_t>(preview_data[1]);
        is_jpeg = (start_byte1 == 0xFF && start_byte2 == 0xD8); // 检查JPEG文件头
    }


    // 验证数据有效性
    if (!preview_data || preview_size == 0 || preview_size > 5 * 1024 * 1024 || !is_jpeg) { // 限制最大5MB
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "预览数据无效（大小：%{public}lu，是否JPEG：%{public}s）",
                     preview_size, is_jpeg ? "是" : "否");
        gp_file_unref(file);
        stopLiveview(g_camera, ctx);
        if (is_temp_ctx)
            gp_context_unref(ctx);
        return false;
    }

    // 复制数据到输出缓冲区
    *data = (uint8_t *)malloc(preview_size);
    if (!*data) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "内存分配失败");
        gp_file_unref(file);
        stopLiveview(g_camera, ctx);
        if (is_temp_ctx)
            gp_context_unref(ctx);
        return false;
    }
    memcpy(*data, preview_data, preview_size);
    //*length = preview_size;
    // 显式转换为size_t，避免类型不兼容
    *length = static_cast<size_t>(preview_size);


    // 清理资源
    gp_file_unref(file);
    if (is_temp_ctx)
        gp_context_unref(ctx);
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "获取预览数据成功（大小：%{public}zu）", *length);
    return true;
}


// NAPI接口：获取预览数据（供JS调用）
napi_value GetPreviewNapi(napi_env env, napi_callback_info info) {
    // 加锁确保线程安全
    if (pthread_mutex_lock(&g_camera_mutex) != 0) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "获取线程锁失败");
        return nullptr;
    }

    uint8_t *data = nullptr;
    size_t length = 0;
    bool success = GetCameraPreview(&data, &length);

    // 失败时停止预览
    if (!success) {
        stopLiveview(g_camera, g_context);
    }

    // 解锁
    pthread_mutex_unlock(&g_camera_mutex);

    // 处理返回结果
    if (!success || !data || length == 0) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "预览数据获取失败");
        if (data)
            free(data);
        return nullptr;
    }

    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "准备创建NAPI Buffer，长度：%{public}zu，数据指针：%{public}p",
                 length, data);
    if (length == 0 || data == nullptr) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "无效的预览数据（长度：%{public}zu，指针：%{public}p）",
                     length, data);
        free(data);
        return nullptr;
    }


    // 转换为HarmonyOS NAPI Buffer
    napi_value buffer = nullptr;
    void *buffer_data = nullptr; // NAPI Buffer的内存指针
    napi_status status = napi_create_buffer(env, length, &buffer_data, &buffer);
    if (status == napi_ok && buffer_data != nullptr) {
        // 新增日志：验证源数据和目标缓冲区的基本信息
        OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG,
                     "准备复制数据到NAPI Buffer：源数据长度=%{public}zu，源指针=%{public}p，目标Buffer指针=%{public}p",
                     length, data, buffer_data);

        // 手动复制数据到NAPI Buffer
        memcpy(buffer_data, data, length);

        // 新增日志：打印NAPI Buffer的前8字节（与源数据对比）
        OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "NAPI Buffer数据头部（前8字节）：");
        for (int i = 0; i < 8 && i < length; i++) {
            OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "Buffer字节%{public}d: 0x%{public}02X", i,
                         (uint8_t) * ((uint8_t *)buffer_data + i)); // 强制转换为uint8_t指针访问
        }
        
        // 假设data是原始JPEG数据指针，length=60823
        OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "NAPI Buffer数据头部（后8字节）：");
        for (int i = length - 8; i < length; i++) {

            OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "数据尾字节%{public}d: 0x%{public}02X",i,
                         (uint8_t) * ((uint8_t *)buffer_data + i));
        }
    }
    free(data); // 释放源数据内存

    if (status != napi_ok) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "创建NAPI Buffer失败：%{public}d", status);
        return nullptr;
    }

    // 新增日志：确认返回给ArkTS层的Buffer信息
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG,
                 "成功返回NAPI Buffer给ArkTS层：长度=%{public}zu，Buffer指针=%{public}p", length, buffer);

    return buffer;
}


// NAPI接口：停止预览（供JS调用）
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