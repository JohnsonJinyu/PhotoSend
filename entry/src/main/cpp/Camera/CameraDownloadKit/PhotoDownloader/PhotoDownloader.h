//
// Created on 2025/12/25.
//
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".

#ifndef PHOTO_DOWNLOADER_H
#define PHOTO_DOWNLOADER_H

#include <string>
#include <vector>
#include <functional>

// libgphoto2头文件
#include <gphoto2/gphoto2.h>
#include <gphoto2/gphoto2-camera.h>

struct DownloadProgressData;

/**
 * @brief 照片下载器类，负责从相机下载原始照片
 */
class PhotoDownloader {
public:
    /**
     * @brief 进度回调函数类型
     */
    using ProgressCallback = std::function<void(const DownloadProgressData&)>;

    /**
     * @brief 构造函数
     */
    PhotoDownloader();

    /**
     * @brief 析构函数
     */
    ~PhotoDownloader();

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
     * @brief 下载照片到指定文件
     * @param folder 照片所在文件夹
     * @param filename 照片文件名
     * @param filePath 保存的文件路径
     * @return 是否下载成功
     */
    bool DownloadFile(const std::string& folder, const std::string& filename, 
                     const std::string& filePath);

    /**
     * @brief 设置进度回调
     * @param callback 进度回调函数
     */
    void SetProgressCallback(ProgressCallback callback);

    /**
     * @brief 清除进度回调
     */
    void ClearProgressCallback();

    /**
     * @brief 获取最后一次的错误信息
     * @return 错误信息
     */
    std::string GetLastError() const { return lastError_; }

private:
    /**
     * @brief 内部下载文件实现
     */
    bool InternalDownloadFile(const std::string& folder, const std::string& filename, 
                             const std::string& filePath);

    /**
     * @brief libgphoto2进度回调函数
     */
    friend unsigned int progress_start_cb(GPContext *context, float target, 
                                        const char *text, void *data);
    friend void progress_update_cb(GPContext *context, unsigned int id, 
                                 float current, void *data);
    friend void progress_stop_cb(GPContext *context, unsigned int id, void *data);

    /**
     * @brief 更新下载进度
     */
    void UpdateProgress(const DownloadProgressData& progress);

private:
    Camera* camera_;                       // libgphoto2相机对象
    GPContext* context_;                   // libgphoto2上下文对象
    ProgressCallback progressCallback_;    // 进度回调函数
    std::string lastError_;                // 最后一次的错误信息
    DownloadProgressData* currentProgressData_; // 当前下载进度数据
};

#endif // PHOTO_DOWNLOADER_H