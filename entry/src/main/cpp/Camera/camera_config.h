//
// Created on 2025/11/9.
//
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".

#ifndef PHOTOSEND_CAMERA_CONFIG_H
#define PHOTOSEND_CAMERA_CONFIG_H
#include "Camera/native_common.h"
#include <napi/native_api.h>
#include <vector>


extern napi_value GetCameraConfig(napi_env env, napi_callback_info info);



// 定义结构体：存储所有需要的相机信息
typedef struct {
    char batteryLevel[32];      // 电量（如"Full"、"50%"）
    char aperture[32];          // 光圈（如"2.8"、"Auto"）
    char shutter[32];           // 快门速度（如"1/1000"、"0.001"）
    char iso[32];               // ISO（如"400"、"Auto"）
    char exposureComp[32];      // 曝光补偿（如"0.3"、"-1.0"）
    char whiteBalance[32];      // 白平衡（如"Auto"、"Daylight"）
    char captureMode[32];       // 拍摄模式（如"Program"、"Aperture Priority"）
    char focusMode[32];         // 对焦模式（如“AF-C”→“连续自动对焦”）
    char exposureMeterMode[32]; // 测光模式（如“8010”→“矩阵测光”）
    long long freeSpaceBytes;   // 剩余空间（字节）
    int remainingPictures;      // 剩余可拍张数
    char exposureProgram[32];   // 曝光模式（M/A/S/P/AUTO）
    bool isSuccess;             // 是否获取成功
} CameraInfo;







// 仅声明（不初始化）
extern const float standardShutterSpeeds[];
extern const char* standardShutterLabels[];
extern const int numStandardShutters;


// 在camera_config.h中添加
extern const std::vector<std::string> DEFAULT_PARAMS_TO_EXTRACT;

// 定义回调函数类型：接收napi_value类型的参数（推送的参数可选值对象）
typedef void (*ParamCallback)(napi_value);  // 关键：补充类型定义

// 之后再声明全局回调指针
extern ParamCallback g_paramCallback;

//  声明储存所有配置信息的全局变量
extern std::vector<ConfigItem> g_allConfigItems;

/**
 * @brief 内部函数：获取相机所有状态和可调节参数
 * @return CameraInfo 存储所有信息的结构体
 */
extern CameraInfo InternalGetCameraInfo();



/**
 * @brief ArkTS层调用此函数，获取相机电量、光圈、快门等所有信息
 * @param env NAPI环境
 * @param info NAPI回调信息
 * @return napi_value 返回ArkTS对象（包含所有相机信息属性）
 */
extern napi_value GetCameraStatus(napi_env env, napi_callback_info info);


/**
 * @brief ArkTS层调用此函数，传入参数名和值，设置相机配置
 * @param env NAPI环境
 * @param info NAPI回调信息（包含2个参数：key、value）
 * @return napi_value 返回布尔值给ArkTS（true=设置成功，false=失败）
 */
extern napi_value SetCameraParameter(napi_env env, napi_callback_info info);





extern napi_value GetParamOptions(napi_env env, napi_callback_info info);


// 声明注册回调的NAPI接口
extern napi_value RegisterParamCallback(napi_env env, napi_callback_info info);


bool GetAllConfigItems(std::vector<ConfigItem> &items);


#endif //PHOTOSEND_CAMERA_CONFIG_H


