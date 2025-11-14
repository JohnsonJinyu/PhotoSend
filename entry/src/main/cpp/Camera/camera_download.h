//
// Created on 2025/11/10.
//
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".

#ifndef PHOTOSEND_CAMERA_DOWNLOAD_H
#define PHOTOSEND_CAMERA_DOWNLOAD_H



/**
 * NAPI接口声明：获取相机内照片的缩略图列表
 * @param env NAPI环境
 * @param info NAPI回调信息（包含ArkTS传入的参数）
 * @return napi_value 返回缩略图列表的NAPI数组对象
 */
#include <js_native_api_types.h>
napi_value GetThumbnailList(napi_env env, napi_callback_info info);

#endif //PHOTOSEND_CAMERA_DOWNLOAD_H
