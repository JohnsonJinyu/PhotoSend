// camera_capture.h
// Created on 2025/11/10.
//
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".

#ifndef PHOTOSEND_CAMERA_CAPTURE_H
#define PHOTOSEND_CAMERA_CAPTURE_H

#include <napi/native_api.h>


extern  napi_value TakePhoto(napi_env env, napi_callback_info info);

#endif //PHOTOSEND_CAMERA_CAPTURE_H
