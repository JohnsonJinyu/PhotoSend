#include "gphoto2/gphoto2-list.h"
#include <napi/native_api.h>

#include <gphoto2/gphoto2.h> // 包含 libgphoto2 核心定义

#define LOG_DOMAIN 0x0001
#define LOG_TAG "NativeCamera"

#include <hilog/log.h>

// 示例，调用 libgphoto2 获取相机列表  获取相机列表的桥接函数
// napi_value 是 NAPI 定义的一种 通用类型，用于在 C/C++ 代码中表示 ArkTS/JS 中的任何值（包括数字、字符串、对象、数组、函数等
static napi_value GetCameraList(napi_env env,napi_callback_info info){
    // 初始化libgphoto2的上下文
    GPContext *context = gp_context_new(); // libgphoto2 的上下文对象,定义并初始化了一个指向 GPContext 的指针变量 
    if (context == nullptr) {
        OH_LOG_PrintMsg(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "gp_context_new failed: context is null");
        return nullptr;
    }
    
    // 初始化相机列表
    CameraList *list = nullptr;
    int ret = gp_list_new(&list); // 初始化相机列表(libgphoto2函数)
    if(ret != 0 || list == nullptr){

        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "gp_list_new failed, error code: %d",ret);
        gp_context_unref(context);
        return nullptr;
    }
    
    
    // 检测相机，获取链接的相机列表
    ret = gp_camera_autodetect(list, context);
    if(ret != 0){
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "gp_camera_autodetect failed, error code: %d",ret);
        gp_list_free(list);
        gp_context_unref(context);
        return nullptr;
    }
    
    
    // 将结果转换为ArkTS可以识别的数组
    napi_value result;
    napi_create_array(env, &result);
    
      // 释放资源（libgphoto2 需手动释放内存）  
    gp_list_free(list);
    gp_context_unref(context);
    
    return result;
    
}


// 注册NAPI接口(类似官方模板)
EXTERN_C_START
static napi_value Init(napi_env env,napi_value exports){
    napi_property_descriptor desc[]={
        {"GetCameraList",nullptr,GetCameraList,nullptr,nullptr,nullptr,napi_default,nullptr}
    };
    napi_define_properties(env, exports, sizeof(desc)/sizeof(desc[0]), desc);
    return exports;
}

EXTERN_C_END


    

NAPI_MODULE(entry, Init)