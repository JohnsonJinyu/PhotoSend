// ThumbnailDownloader.h
// Created on 2025/12/25.
//
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".

#ifndef THUMBNAIL_DOWNLOADER_H
#define THUMBNAIL_DOWNLOADER_H

#include <semaphore.h>
#include <vector>
#include <string>
#include <mutex>
#include <atomic>

// libgphoto2头文件
#include <gphoto2/gphoto2.h>
#include <gphoto2/gphoto2-camera.h>

/**
 * @brief 缩略图下载器类，负责下载相机中的照片缩略图
 */
class ThumbnailDownloader {
public:
    /**
     * @brief 构造函数
     */
    ThumbnailDownloader();

    /**
     * @brief 析构函数
     */
    ~ThumbnailDownloader();

    /**
     * @brief 初始化下载器
     * @param camera libgphoto2相机对象
     * @param context libgphoto2上下文对象
     */
    void Init(Camera* camera, GPContext* context);

    /**
     * @brief 清理资源
     */
    void Cleanup();

    /**
     * @brief 初始化信号量
     * @param maxConcurrent 最大并发数
     * @return 是否初始化成功
     */
    bool InitSemaphore(int maxConcurrent = 2);

    /**
     * @brief 清理信号量
     */
    void CleanupSemaphore();

    /**
     * @brief 下载单张缩略图
     * @param folder 照片所在文件夹
     * @param filename 照片文件名
     * @return 缩略图二进制数据
     */
    std::vector<uint8_t> DownloadSingleThumbnail(const std::string& folder, 
                                                const std::string& filename);

    /**
     * @brief 设置超时时间
     * @param timeoutMs 超时时间（毫秒）
     */
    void SetTimeout(int timeoutMs) { timeoutMs_ = timeoutMs; }

private:
    /**
     * @brief 内部下载缩略图实现
     */
    std::vector<uint8_t> InternalDownloadThumbnail(const std::string& folder, 
                                                  const std::string& filename);

private:
    Camera* camera_;               // libgphoto2相机对象
    GPContext* context_;           // libgphoto2上下文对象
    sem_t thumbnailSemaphore_;     // 缩略图下载信号量
    std::atomic<bool> semaphoreInitialized_; // 信号量是否已初始化
    std::atomic<int> timeoutMs_;   // 等待信号量的超时时间（毫秒）
    
    static const int DEFAULT_TIMEOUT_MS = 1000; // 默认超时1秒
};

#endif // THUMBNAIL_DOWNLOADER_H
