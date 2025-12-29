// camera_preview.h
// Created on 2025/11/5.
//
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".

#ifndef PHOTOSEND_CAMERA_PREVIEW_H
#define PHOTOSEND_CAMERA_PREVIEW_H

#include <napi/native_api.h>




/**
 * @brief ArkTS层调用此函数，获取相机实时预览画面
 * @param env NAPI环境
 * @param info NAPI回调信息
 * @return napi_value 返回ArkTS的Buffer（预览数据），失败返回nullptr
 */
extern napi_value GetPreviewNapi(napi_env env, napi_callback_info info);

#endif //PHOTOSEND_CAMERA_PREVIEW_H
