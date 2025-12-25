// DeviceScanner.cpp
// Created on 2025/12/25.
//
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".

#include "DeviceScanner.h"
#include <hilog/log.h>
#include <ltdl.h>
#include <gphoto2/gphoto2.h>

// 本模块的日志配置
#define LOG_DOMAIN 0x0004
#define LOG_TAG "DeviceScanner"

std::vector<CameraDeviceInfo> DeviceScanner::scanAvailableCameras() {
    std::vector<CameraDeviceInfo> cameras;
    
    if (!isDriverPathSet()) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, 
                     "未设置驱动路径，请先调用SetGPhotoLibDirs");
        return cameras;
    }
    
    // 初始化ltdl
    int ltdlResult = lt_dlinit();
    if (ltdlResult != 0) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, 
                     "ltdl初始化失败: %{public}s", lt_dlerror());
        return cameras;
    }
    
    // 创建上下文
    GPContext* context = gp_context_new();
    if (!context) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "创建上下文失败");
        return cameras;
    }
    
    // 创建相机列表
    CameraList* list = nullptr;
    gp_list_new(&list);
    
    if (!list) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "创建相机列表失败");
        gp_context_unref(context);
        return cameras;
    }
    
    // 自动检测相机
    int result = gp_camera_autodetect(list, context);
    if (result != GP_OK) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, 
                     "相机枚举失败，错误码: %{public}d", result);
        gp_list_free(list);
        gp_context_unref(context);
        return cameras;
    }
    
    // 获取相机数量
    int count = gp_list_count(list);
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                 "检测到 %{public}d 台可用相机", count);
    
    // 遍历所有相机
    for (int i = 0; i < count; i++) {
        const char* model = nullptr;
        const char* path = nullptr;
        
        gp_list_get_name(list, i, &model);
        gp_list_get_value(list, i, &path);
        
        CameraDeviceInfo info;
        info.model = model ? model : "Unknown";
        info.path = path ? path : "";
        info.displayName = info.model + " @ " + info.path;
        
        cameras.push_back(info);
        
        OH_LOG_Print(LOG_APP, LOG_DEBUG, LOG_DOMAIN, LOG_TAG, 
                     "发现相机: %{public}s - %{public}s", model, path);
    }
    
    // 清理资源
    gp_list_free(list);
    gp_context_unref(context);
    
    return cameras;
}

void DeviceScanner::setDriverPath(const std::string& path) {
    driverPath_ = path;
    setenv("CAMLIBS", path.c_str(), 1);
    setenv("IOLIBS", path.c_str(), 1);
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                 "设置扫描器驱动路径: %{public}s", path.c_str());
}