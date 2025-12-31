// DeviceScanner.cpp
// Created on 2025/12/25.
//
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".

#include "DeviceScanner.h"
#include "Camera/Common/Constants.h"
#include <hilog/log.h>
#include <ltdl.h>
#include <gphoto2/gphoto2.h>
#include <chrono>
#include <thread>

// 本模块的日志配置
#define LOG_DOMAIN ModuleLogs::DeviceScanner.domain
#define LOG_TAG ModuleLogs::DeviceScanner.tag

/**
 * @brief 扫描可用相机
 * @return std::vector<CameraDeviceInfo> 相机设备列表
 */
std::vector<CameraDeviceInfo> DeviceScanner::scanAvailableCameras() {
    std::vector<CameraDeviceInfo> cameras;
    
    // 检查驱动路径是否设置
    if (!isDriverPathSet()) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, 
                     "未设置驱动路径，请先调用SetGPhotoLibDirs");
        return cameras;
    }
    
    auto scanStartTime = std::chrono::steady_clock::now();
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "开始扫描可用相机");
    
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
    
    // 自动检测相机（带超时机制）
    int result = GP_ERROR;
    auto timeoutTime = scanStartTime + std::chrono::seconds(10); // 10秒超时
    
    // 在单独线程中执行扫描，以便超时控制
    std::thread scanThread([&]() {
        result = gp_camera_autodetect(list, context);
    });
    
    // 等待扫描完成
    if (scanThread.joinable()) {
        scanThread.join();
    }
    
    // 检查扫描结果
    if (result != GP_OK) {
        auto scanEndTime = std::chrono::steady_clock::now();
        auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(scanEndTime - scanStartTime);
        
        OH_LOG_Print(LOG_APP, LOG_WARN, LOG_DOMAIN, LOG_TAG, 
                     "相机扫描失败，错误码: %{public}d，耗时: %lldms", 
                     result, duration.count());
        
        // 清理资源
        gp_list_free(list);
        gp_context_unref(context);
        return cameras;
    }
    
    // 获取相机数量
    int count = gp_list_count(list);
    
    auto scanEndTime = std::chrono::steady_clock::now();
    auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(scanEndTime - scanStartTime);
    
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                 "检测到 %{public}d 台可用相机，耗时: %lldms", count, duration.count());
    
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
        
        // 判断连接类型
        if (info.path.find("ptpip:") != std::string::npos) {
            info.connectionType = "WiFi-AP";
        } else if (info.path.find("usb:") != std::string::npos) {
            info.connectionType = "USB";
        } else {
            info.connectionType = "Unknown";
        }
        
        cameras.push_back(info);
        
        OH_LOG_Print(LOG_APP, LOG_DEBUG, LOG_DOMAIN, LOG_TAG, 
                     "发现相机: %{public}s - %{public}s (%s)", 
                     model, path, info.connectionType.c_str());
    }
    
    // 按品牌排序（可选）
    std::sort(cameras.begin(), cameras.end(), [](const CameraDeviceInfo& a, const CameraDeviceInfo& b) {
        return a.model < b.model;
    });
    
    // 清理资源
    gp_list_free(list);
    gp_context_unref(context);
    
    return cameras;
}

/**
 * @brief 设置驱动路径
 * @param path 驱动路径
 */
void DeviceScanner::setDriverPath(const std::string& path) {
    driverPath_ = path;
    
    // 设置libgphoto2环境变量
    setenv("CAMLIBS", path.c_str(), 1);
    setenv("IOLIBS", path.c_str(), 1);
    
    // 对于AP模式，可能需要额外的环境变量
    setenv("PTPIP_IP", "192.168.1.1", 1); // 默认IP
    setenv("PTPIP_PORT", "15740", 1);     // 默认端口
    
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                 "设置扫描器驱动路径: %{public}s", path.c_str());
}