// camera_download.h
// Created on 2025/11/10.
//
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".

#ifndef PHOTOSEND_CAMERA_DOWNLOAD_H
#define PHOTOSEND_CAMERA_DOWNLOAD_H

#include <string>
#include <napi/native_api.h>

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

// 内部结构体：存储单张照片的缩略图信息
struct ThumbnailInfo {
    std::string folder;   // 相机中的文件夹路径
    std::string fileName; // 文件名
    uint8_t *thumbData;   // 缩略图二进制数据
    size_t thumbSize;     // 缩略图大小
};

// 存储异步任务所需数据（输入参数、结果、回调）
struct AsyncThumbnailData {
    napi_env env;                      // NAPI环境
    napi_ref callback;                 // ArkTS层传入的回调函数引用
    std::vector<ThumbnailInfo> result; // 异步操作结果
    int errorCode;                     // 错误码（0表示成功）
    std::string errorMsg;              // 错误信息
};


/**
 * NAPI接口声明：获取相机内照片的缩略图列表
 * @param env NAPI环境
 * @param info NAPI回调信息（包含ArkTS传入的参数）
 * @return napi_value 返回缩略图列表的NAPI数组对象
 */
#include <js_native_api_types.h>
extern napi_value GetThumbnailList(napi_env env, napi_callback_info info);


/**
 * @brief ArkTS层调用此函数，传入照片路径，下载照片并返回二进制数据
 * @param env NAPI环境
 * @param info NAPI回调信息（包含2个参数：folder、name）
 * @return napi_value 返回ArkTS的Buffer（存储照片二进制数据），失败返回nullptr
 */
extern napi_value DownloadPhoto(napi_env env, napi_callback_info info);


// 新增异步下载接口声明
extern napi_value DownloadPhotoAsync(napi_env env, napi_callback_info info);


/**
 * @brief 获取照片总数
 * */
extern napi_value GetPhotoTotalCount(napi_env env,napi_callback_info info);

/**
 * @brief 分页获取照片元信息，不包含缩略图
 * */
extern napi_value GetPhotoMetaList(napi_env env,napi_callback_info info);

/**
 * @brief 单独下载单张照片的缩略图
 * */
extern napi_value DownloadSingleThumbnail(napi_env env,napi_callback_info info);

/**
 * @brief 清理缓存函数（可选，在断开相机连接时调用）
 * */

extern void ClearPhotoCache();





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

#endif //PHOTOSEND_CAMERA_DOWNLOAD_H
