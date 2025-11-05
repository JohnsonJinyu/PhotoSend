//
// Created on 2025/11/4.
// 公共定义（枚举、结构体、错误码等）
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".

#ifndef PHOTOSEND_CAMERA_COMMON_H
#define PHOTOSEND_CAMERA_COMMON_H

#endif //PHOTOSEND_CAMERA_COMMON_H



// 错误码（覆盖设备、配置、处理等场景）
typedef enum {
    CAMERA_OK = 0,
    CAMERA_ERROR_INVALID_PARAM = -1,  // 参数无效
    CAMERA_ERROR_DEVICE_NOT_FOUND = -2,  // 设备未找到
    CAMERA_ERROR_DEVICE_OPEN_FAILED = -3,  // 设备打开失败
    CAMERA_ERROR_CONFIG_LOAD_FAILED = -4,  // 配置加载失败
    // ... 其他错误码
} CameraErrorCode;

// 相机类型（按接口区分）
typedef enum {
    CAMERA_TYPE_USB = 0,
    CAMERA_TYPE_GMSL,
    CAMERA_TYPE_MIPI,
    CAMERA_TYPE_NETWORK
} CameraType;

// 帧数据格式
typedef enum {
    FRAME_FORMAT_RGB888 = 0,
    FRAME_FORMAT_YUV420,
    FRAME_FORMAT_JPEG,
    FRAME_FORMAT_RAW
} FrameFormat;

// 通用宏（如日志打印、断言）
#define CAMERA_LOG(tag, fmt, ...) printf("[%s] " fmt "\n", tag, ##__VA_ARGS__)
#define CAMERA_ASSERT(cond) if (!(cond)) { CAMERA_LOG("ERROR", "Assert failed: %s", #cond); }