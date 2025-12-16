// exif_reader.h
// Created on 2025/12/16.
//
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".

#ifndef PHOTOSEND_EXIF_READER_H
#define PHOTOSEND_EXIF_READER_H

#include <napi/native_api.h>


/**
 * @brief 读取图片的EXIF方向信息
 * @param env NAPI环境
 * @param info NAPI回调信息（参数1: 文件路径）
 * @return napi_value 方向值（1-8），失败返回-1
 */
napi_value GetImageOrientationNapi(napi_env env, napi_callback_info info);



/**
 * @brief 读取图片的完整EXIF信息
 * @param env NAPI环境
 * @param info NAPI回调信息（参数1: 文件路径）
 * @return napi_value JS对象，包含orientation, width, height等信息
 */
napi_value GetImageExifInfoNapi(napi_env env, napi_callback_info info);

#endif //PHOTOSEND_EXIF_READER_H
