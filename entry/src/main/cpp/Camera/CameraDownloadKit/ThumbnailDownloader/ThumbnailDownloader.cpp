// ThumbnailDownloader.cpp
// Created on 2025/12/25.
//
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".

#include "ThumbnailDownloader.h"
#include "Camera/CameraDownloadKit/camera_download.h"
#include "Camera/native_common.h"
#include "gphoto2/gphoto2-port-result.h"
#include <hilog/log.h>
#include <chrono>
#include <thread>

#define LOG_DOMAIN 0x0008
#define LOG_TAG "ThumbnailDownloader"

ThumbnailDownloader::ThumbnailDownloader() 
    : camera_(nullptr)
    , context_(nullptr)
    , semaphoreInitialized_(false)
    , timeoutMs_(DEFAULT_TIMEOUT_MS) {
}

ThumbnailDownloader::~ThumbnailDownloader() {
    Cleanup();
}

void ThumbnailDownloader::Init(Camera* camera, GPContext* context) {
    camera_ = camera;
    context_ = context;
    
    // 初始化信号量
    if (!semaphoreInitialized_) {
        InitSemaphore();
    }
}

void ThumbnailDownloader::Cleanup() {
    if (semaphoreInitialized_) {
        CleanupSemaphore();
    }
    
    camera_ = nullptr;
    context_ = nullptr;
}

bool ThumbnailDownloader::InitSemaphore(int maxConcurrent) {
    if (semaphoreInitialized_) {
        return true;
    }
    
    int ret = sem_init(&thumbnailSemaphore_, 0, maxConcurrent);
    if (ret == 0) {
        semaphoreInitialized_ = true;
        OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                   "缩略图信号量初始化成功，最大并发数: %d", maxConcurrent);
        return true;
    } else {
        OH_LOG_PrintMsg(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, 
                       "缩略图信号量初始化失败");
        return false;
    }
}

void ThumbnailDownloader::CleanupSemaphore() {
    if (semaphoreInitialized_) {
        sem_destroy(&thumbnailSemaphore_);
        semaphoreInitialized_ = false;
        OH_LOG_PrintMsg(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                       "缩略图信号量已清理");
    }
}

std::vector<uint8_t> ThumbnailDownloader::DownloadSingleThumbnail(
    const std::string& folder, const std::string& filename) {
    
    if (!camera_ || !context_) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, 
                   "相机未连接，无法下载缩略图");
        return {};
    }
    
    return InternalDownloadThumbnail(folder, filename);
}

std::vector<uint8_t> ThumbnailDownloader::InternalDownloadThumbnail(
    const std::string& folder, const std::string& filename) {
    
    std::vector<uint8_t> thumbnailData;
    
    // 等待信号量（支持超时）
    if (semaphoreInitialized_) {
        struct timespec ts;
        clock_gettime(CLOCK_REALTIME, &ts);
        
        // 计算超时时间
        long addSeconds = timeoutMs_ / 1000;
        long addNanoseconds = (timeoutMs_ % 1000) * 1000000;
        ts.tv_sec += addSeconds;
        ts.tv_nsec += addNanoseconds;
        
        if (ts.tv_nsec >= 1000000000) {
            ts.tv_sec += 1;
            ts.tv_nsec -= 1000000000;
        }
        
        int semRet = sem_timedwait(&thumbnailSemaphore_, &ts);
        if (semRet != 0) {
            OH_LOG_Print(LOG_APP, LOG_WARN, LOG_DOMAIN, LOG_TAG, 
                       "等待缩略图下载信号量超时: %{public}s/%{public}s", 
                       folder.c_str(), filename.c_str());
            return thumbnailData;
        }
    }
    
    CameraFile *thumbFile = nullptr;
    gp_file_new(&thumbFile);
    
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                "开始下载缩略图: %{public}s/%{public}s", 
                folder.c_str(), filename.c_str());
    
    int ret = GP_OK;
    try {
        // 获取缩略图
        ret = gp_camera_file_get(camera_, folder.c_str(), filename.c_str(), 
                                GP_FILE_TYPE_PREVIEW, thumbFile, context_);
    } catch (...) {
        OH_LOG_PrintMsg(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, 
                       "下载缩略图异常");
        ret = GP_ERROR;
    }
    
    // 释放信号量
    if (semaphoreInitialized_) {
        sem_post(&thumbnailSemaphore_);
    }
    
    if (ret != GP_OK) {
        OH_LOG_Print(LOG_APP, LOG_WARN, LOG_DOMAIN, LOG_TAG, 
                    "下载缩略图失败: %{public}s", gp_result_as_string(ret));
        gp_file_unref(thumbFile);
        return thumbnailData;
    }
    
    // 提取数据
    const char *thumbData;
    unsigned long thumbSize;
    gp_file_get_data_and_size(thumbFile, &thumbData, &thumbSize);
    
    if (thumbData && thumbSize > 0) {
        // 复制数据到vector
        thumbnailData.assign(thumbData, thumbData + thumbSize);
        
        OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                    "缩略图下载成功: %{public}s, 大小: %{public}lu", 
                    filename.c_str(), thumbSize);
    } else {
        OH_LOG_PrintMsg(LOG_APP, LOG_WARN, LOG_DOMAIN, LOG_TAG, 
                       "缩略图数据为空");
    }
    
    gp_file_unref(thumbFile);
    return thumbnailData;
}