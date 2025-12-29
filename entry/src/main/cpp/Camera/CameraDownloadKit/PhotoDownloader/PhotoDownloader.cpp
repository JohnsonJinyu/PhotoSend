// PhotoDownloader.cpp
// Created on 2025/12/25.
//
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".

#include "PhotoDownloader.h"
#include "Camera/CameraDownloadKit/camera_download.h"
#include "../../Common/native_common.h"
#include "gphoto2/gphoto2-port-result.h"
#include <hilog/log.h>
#include <fstream>
#include <Camera/Common/Constants.h>
#include <memory>

#define LOG_DOMAIN ModuleLogs::PhotoDownloader.domain
#define LOG_TAG ModuleLogs::PhotoDownloader.tag

// 进度回调函数实现
static unsigned int ProgressStartCallback(GPContext *context, float target, const char *text, void *data) {
    DownloadProgressData *progress_data = static_cast<DownloadProgressData *>(data);
    if (progress_data) {
        progress_data->currentProgress = 0.0f;
        progress_data->totalSize = target;
        OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                   "文件 %{public}s 下载开始: %{public}s（总大小: %{public}f 字节）",
                   progress_data->fileName.c_str(), text, target);
    }
    return GP_OK;
}

static void ProgressUpdateCallback(GPContext *context, unsigned int id, float current, void *data) {
    DownloadProgressData *progress_data = static_cast<DownloadProgressData *>(data);
    if (progress_data && progress_data->totalSize > 0) {
        float percentage = current / progress_data->totalSize;
        int progress = static_cast<int>(percentage * 100);
        progress_data->currentProgress = percentage;
        
        OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG,
                   "文件 %{public}s 下载进度：%{public}d%%（已下载: %{public}f 字节 / 总大小: %{public}f 字节）",
                   progress_data->fileName.c_str(), progress, current, progress_data->totalSize);
    } else if (progress_data) {
        OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG,
                   "文件 %{public}s 下载中...（当前已下载: %{public}f 字节）",
                   progress_data->fileName.c_str(), current);
    }
}

static void ProgressStopCallback(GPContext *context, unsigned int id, void *data) {
    DownloadProgressData *progress_data = static_cast<DownloadProgressData *>(data);
    if (progress_data) {
        int finalProgress = static_cast<int>(progress_data->currentProgress * 100);
        OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG,
                   "文件 %{public}s 下载结束，最终进度：%{public}d%%",
                   progress_data->fileName.c_str(), finalProgress);
    }
}

PhotoDownloader::PhotoDownloader() 
    : camera_(nullptr)
    , context_(nullptr)
    , currentProgressData_(nullptr) {
}

PhotoDownloader::~PhotoDownloader() {
    Cleanup();
}

void PhotoDownloader::Init(Camera* camera, GPContext* context) {
    camera_ = camera;
    context_ = context;
    ClearProgressCallback();
}

void PhotoDownloader::Cleanup() {
    if (currentProgressData_) {
        delete currentProgressData_;
        currentProgressData_ = nullptr;
    }
    
    camera_ = nullptr;
    context_ = nullptr;
    ClearProgressCallback();
}

bool PhotoDownloader::DownloadFile(const std::string& folder, 
                                  const std::string& filename, 
                                  const std::string& filePath) {
    
    if (!camera_ || !context_) {
        lastError_ = "相机未连接";
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, 
                   "错误: 相机未连接，下载失败");
        return false;
    }

    if (filePath.empty()) {
        lastError_ = "目标文件路径为空";
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, 
                   "错误: 目标文件路径为空");
        return false;
    }

    return InternalDownloadFile(folder, filename, filePath);
}

bool PhotoDownloader::InternalDownloadFile(const std::string& folder, 
                                          const std::string& filename, 
                                          const std::string& filePath) {
    
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                "===== 开始执行 InternalDownloadFile =====");
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                "参数: folder='%{public}s', filename='%{public}s', filePath='%{public}s'", 
                folder.c_str(), filename.c_str(), filePath.c_str());

    CameraFile *file = nullptr;
    int ret = gp_file_new(&file);
    if (ret != GP_OK) {
        lastError_ = "创建 CameraFile 对象失败";
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, 
                   "错误: 创建 CameraFile 对象失败. ret=%{public}d", ret);
        return false;
    }
    
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                "成功: CameraFile 对象创建. file=%{public}p", file);

    // 创建进度数据结构
    currentProgressData_ = new DownloadProgressData();
    currentProgressData_->fileName = filename;
    currentProgressData_->currentProgress = 0.0f;
    currentProgressData_->totalSize = 0.0f;

    // 设置进度回调
    gp_context_set_progress_funcs(
        context_,
        ProgressStartCallback,   // 使用新定义的函数
        ProgressUpdateCallback,  // 使用新定义的函数
        ProgressStopCallback,    // 使用新定义的函数
        currentProgressData_
    );

    // 开始下载
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                "步骤: 调用 gp_camera_file_get 开始下载文件");
    ret = gp_camera_file_get(camera_, folder.c_str(), filename.c_str(), 
                            GP_FILE_TYPE_NORMAL, file, context_);
    
    // 清除进度回调
    gp_context_set_progress_funcs(context_, nullptr, nullptr, nullptr, nullptr);
    
    if (ret != GP_OK) {
        lastError_ = std::string("gp_camera_file_get 下载失败: ") + gp_result_as_string(ret);
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, 
                   "错误: gp_camera_file_get 下载失败. ret=%{public}d", ret);
        gp_file_unref(file);
        
        delete currentProgressData_;
        currentProgressData_ = nullptr;
        
        return false;
    }
    
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                "成功: gp_camera_file_get 下载文件成功");

    // 从 CameraFile 对象中提取数据
    const char *fileData = nullptr;
    unsigned long fileSize = 0;
    gp_file_get_data_and_size(file, &fileData, &fileSize);

    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                "提取结果: fileData=%{public}p, fileSize=%{public}lu bytes", 
                fileData, fileSize);

    if (fileData == nullptr || fileSize == 0) {
        lastError_ = "提取的数据为空或大小为0";
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, 
                   "错误: 提取的数据为空或大小为0");
        gp_file_unref(file);
        
        delete currentProgressData_;
        currentProgressData_ = nullptr;
        
        return false;
    }

    // 将数据写入文件
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                "步骤: 将数据写入沙箱文件: %{public}s", filePath.c_str());
    std::ofstream outFile(filePath, std::ios::binary);
    if (!outFile.is_open()) {
        lastError_ = "无法打开沙箱文件进行写入";
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, 
                   "错误: 无法打开沙箱文件进行写入");
        gp_file_unref(file);
        
        delete currentProgressData_;
        currentProgressData_ = nullptr;
        
        return false;
    }

    outFile.write(fileData, fileSize);
    outFile.close();
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                "成功: 数据已全部写入沙箱文件");

    // 释放资源
    gp_file_unref(file);
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                "成功: CameraFile 对象已释放");
    
    delete currentProgressData_;
    currentProgressData_ = nullptr;

    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
                "===== InternalDownloadFile 执行成功 =====");
    return true;
}

void PhotoDownloader::SetProgressCallback(ProgressCallback callback) {
    progressCallback_ = callback;
}

void PhotoDownloader::ClearProgressCallback() {
    progressCallback_ = nullptr;
}

void PhotoDownloader::UpdateProgress(const DownloadProgressData& progress) {
    if (progressCallback_) {
        progressCallback_(progress);
    }
}