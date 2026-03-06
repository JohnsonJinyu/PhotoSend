// ThumbnailDownloader.cpp
// Created on 2025/12/25.
//
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".

#include "ThumbnailDownloader.h"
#include "Camera/CameraDownloadKit/camera_download.h"
#include "Camera/Common/native_common.h"
#include "gphoto2/gphoto2-port-result.h"
#include <hilog/log.h>
#include <chrono>
#include <thread>
#include <Camera/Common/Constants.h>


#define LOG_DOMAIN ModuleLogs::ThumbnailDownloader.domain
#define LOG_TAG ModuleLogs::ThumbnailDownloader.tag

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
    
    auto startTime = std::chrono::high_resolution_clock::now();
    
    // 参数验证
    if (folder.empty() || filename.empty()) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, 
                   "❌ 参数错误：folder 或 filename 为空");
        return {};
    }
    
    if (folder.length() > 500) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, 
                   "❌ 参数错误：folder 过长 (%{public}zu 字节)", folder.length());
        return {};
    }
    
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
                       "等待缩略图下载信号量超时：%{public}s/%{public}s", 
                       folder.c_str(), filename.c_str());
            return thumbnailData;
        }
    }
    
    CameraFile *thumbFile = nullptr;
    gp_file_new(&thumbFile);
    
    auto downloadStartTime = std::chrono::high_resolution_clock::now();
    
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                "开始下载缩略图：%{public}s/%{public}s", 
                folder.c_str(), filename.c_str());
    
    int ret = GP_OK;
    int retryCount = 0;
    const int MAX_RETRIES = 3;
    
    // 优化：添加重试机制，处理 I/O in progress 错误
    while (retryCount < MAX_RETRIES) {
        try {
            // 优化：直接使用 PREVIEW 类型获取缩略图
            // 注：libgphoto2 没有 THUMBNAIL 类型，PREVIEW 即为相机提供的缩略图/预览图
            ret = gp_camera_file_get(camera_, folder.c_str(), filename.c_str(), 
                                    GP_FILE_TYPE_PREVIEW, thumbFile, context_);
            
            // 如果成功，退出循环
            if (ret == GP_OK) {
                break;
            }
            
            // 如果是 I/O 错误，等待后重试
            if (ret == GP_ERROR_IO) {
                retryCount++;
                if (retryCount < MAX_RETRIES) {
                    OH_LOG_Print(LOG_APP, LOG_WARN, LOG_DOMAIN, LOG_TAG, 
                                "⚠️ 缩略图下载遇到 I/O 错误，%{public}d 秒后重试 (%{public}d/%{public}d): %{public}s",
                                retryCount, retryCount, MAX_RETRIES, gp_result_as_string(ret));
                                
                    // 等待 1 秒后重试
                    std::this_thread::sleep_for(std::chrono::seconds(1));
                    continue;
                }
            }
            
            // 其他错误直接退出
            break;
            
        } catch (...) {
            OH_LOG_PrintMsg(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, 
                           "下载缩略图异常");
            ret = GP_ERROR;
            break;
        }
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
        // 优化：如果图片过大，进行简单的尺寸检查和日志记录
        if (thumbSize > 500 * 1024) {  // 大于 500KB
            OH_LOG_Print(LOG_APP, LOG_WARN, LOG_DOMAIN, LOG_TAG, 
                        "⚠️ 缩略图尺寸过大：%{public}lu bytes，建议检查相机设置", thumbSize);
        }
            
        // 复制数据到 vector
        thumbnailData.assign(thumbData, thumbData + thumbSize);
            
        // 计算耗时
        auto endTime = std::chrono::high_resolution_clock::now();
        auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(endTime - startTime);
        auto downloadDuration = std::chrono::duration_cast<std::chrono::milliseconds>(
            endTime - downloadStartTime);
            
        OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                    "✅ 缩略图下载成功：%{public}s, 大小：%{public}lu bytes, 总耗时：%{public}lld ms, 下载耗时：%{public}lld ms", 
                    filename.c_str(), thumbSize, duration.count(), downloadDuration.count());
    } else {
        OH_LOG_PrintMsg(LOG_APP, LOG_WARN, LOG_DOMAIN, LOG_TAG, 
                       "❌ 缩略图数据为空");
    }
    
    gp_file_unref(thumbFile);
    return thumbnailData;
}