//
// Created on 2025/11/10.
//
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".

#ifndef PHOTOSEND_CAMERA_DOWNLOAD_H
#define PHOTOSEND_CAMERA_DOWNLOAD_H

#include <string>

// 照片元信息，不含缩略图数据
struct PhotoMeta{
    std::string folder; //文件夹路径
    std::string fileName; //文件名
    size_t fileSize;  //文件大小
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



#endif //PHOTOSEND_CAMERA_DOWNLOAD_H
