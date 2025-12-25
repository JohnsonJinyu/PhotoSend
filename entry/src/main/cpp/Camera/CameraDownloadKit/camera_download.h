// camera_download.h
// Created on 2025/11/10.
//
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".

#ifndef PHOTOSEND_CAMERA_DOWNLOAD_H
#define PHOTOSEND_CAMERA_DOWNLOAD_H

#include <semaphore.h>
#include <string>
#include <napi/native_api.h>
#include <atomic>
#include <thread>
#include <functional>






// 照片元信息，不含缩略图数据
struct PhotoMeta{
    std::string folder; //文件夹路径
    std::string fileName; //文件名
    size_t fileSize;  //文件大小
};

// 用于在回调函数之间传递的进度信息结构体
struct DownloadProgressData {
    std::string fileName;  // 正在下载的文件名
    float currentProgress; // 当前下载进度 (0.0 ~ 1.0)
    float totalSize;       // 新增：文件总大小（从progress_start_cb的target获取）
};



// 全局变量：温存文件列表（提高性能）
static std::vector<PhotoMeta> g_cachedFileList;
static bool g_isFileListCached = false;
static std::mutex g_cacheMutex;
static std::atomic<bool> g_isScanning(false);
static std::thread g_scanThread;
static std::mutex g_scanMutex;
static std::condition_variable g_scanCV;
static int g_scanProgressCurrent = 0;
static int g_scanProgressTotal = 0;
static bool g_scanCancelled = false;

static sem_t g_thumbnailSemaphore;
static bool g_semaphoreInitialized = false;
static const int MAX_CONCURRENT_THUMBNAILS = 2; // 最多同时下载2个缩略图

// 异步扫描回调函数类型
using ScanCompleteCallback = std::function<void(int totalCount)>;

/**
 * @brief ArkTS层调用此函数，传入照片路径，下载照片并返回二进制数据
 * @param env NAPI环境
 * @param info NAPI回调信息（包含2个参数：folder、name）
 * @return napi_value 返回ArkTS的Buffer（存储照片二进制数据），失败返回nullptr
 */
extern napi_value DownloadPhoto(napi_env env, napi_callback_info info);

/**
 * @brief 获取照片总数
 */
extern napi_value GetPhotoTotalCount(napi_env env,napi_callback_info info);

/**
 * @brief 分页获取照片元信息，不包含缩略图
 */
extern napi_value GetPhotoMetaList(napi_env env,napi_callback_info info);

/**
 * @brief 单独下载单张照片的缩略图
 */
extern napi_value DownloadSingleThumbnail(napi_env env,napi_callback_info info);

/**
 * @brief NAPI接口：清理照片缓存
 * @param env NAPI环境
 * @param info NAPI回调信息
 * @return napi_value 返回undefined
 */
extern napi_value ClearPhotoCacheNapi(napi_env env, napi_callback_info info);

/**
 * @brief 内部函数：清理照片缓存（C++内部使用）
 */
extern void ClearPhotoCache();

/**
 * @brief 启动异步扫描照片文件
 */
extern napi_value StartAsyncScan(napi_env env, napi_callback_info info);

/**
 * @brief 启动异步扫描内部函数
 */
static void StartAsyncScanInternal();


/**
 * @brief 检查扫描是否完成
 */
extern napi_value IsScanComplete(napi_env env, napi_callback_info info);

/**
 * @brief 获取扫描进度
 */
extern napi_value GetScanProgress(napi_env env, napi_callback_info info);

/**
 * @brief 内部函数：获取照片总数（不加载缩略图）
 */
static int InternalGetPhotoTotalCount();

/**
 * @brief 内部函数：仅扫描照片文件，不下载缩略图
 */
static std::vector<PhotoMeta> InternalScanPhotoFilesOnly();

/**
 * @brief 内部辅助函数：查找DCIM目录
 */
static std::string FindDcimFolder();

/**
 * @brief 内部辅助函数：查找照片目录
 */
static std::string FindPhotoFolder(const std::string& dcimFolder);

/**
 * @brief 内部辅助函数：判断是否为照片文件
 */
static bool IsPhotoFile(const char* fileName);


/**
 * @brief 初始化缩略图下载信号量（在相机连接成功时调用）
 */
extern void InitThumbnailSemaphore();

/**
 * @brief 清理缩略图下载信号量（在相机断开连接时调用）
 */
extern void CleanupThumbnailSemaphore();

/**
 * @brief 相机断开连接
 */
extern napi_value DisconnectCamera(napi_env env, napi_callback_info info);

#endif //PHOTOSEND_CAMERA_DOWNLOAD_H