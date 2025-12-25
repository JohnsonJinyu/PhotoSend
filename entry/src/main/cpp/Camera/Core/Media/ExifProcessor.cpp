// exif_reader.cpp
// Created on 2025/12/16.
//
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".


#include <napi/native_api.h>
#include "hilog/log.h"
#include "libraw/libraw_const.h"
#include "ExifProcessor.h"
#include <libexif/exif-data.h>
#include <libexif/exif-loader.h>
#include <cstring>
#include <string>
#include <libraw/libraw.h>

#define LOG_DOMAIN 0x0006       // 日志域（自定义标识，区分不同模块日志）
#define LOG_TAG "exif_reader" // 日志标签（日志中显示的模块名）

/**
 * @brief 内部函数：读取图片的EXIF方向信息
 */
static int get_image_orientation(const char* filepath){
    ExifData* exifData = exif_data_new_from_file(filepath);
    if (!exifData) {
        OH_LOG_Print(LOG_APP, LOG_WARN, LOG_DOMAIN, LOG_TAG, 
                     "无法读取文件EXIF数据: %{public}s", filepath);
        return 1; // 默认方向
    }
    
    int orientation = 1; // 默认值
    
    // 查找方向标签 (0x0112)
    ExifEntry* entry = exif_data_get_entry(exifData, EXIF_TAG_ORIENTATION);
    if (entry && entry->data && entry->size >= 2) {
        // 读取short类型（2字节）
        ExifByteOrder byteOrder = exif_data_get_byte_order(exifData);
        orientation = exif_get_short(entry->data, byteOrder);
        
        OH_LOG_Print(LOG_APP, LOG_DEBUG, LOG_DOMAIN, LOG_TAG,
                    "文件 %{public}s 的EXIF方向: %{public}d", filepath, orientation);
    } else {
        OH_LOG_Print(LOG_APP, LOG_DEBUG, LOG_DOMAIN, LOG_TAG,
                    "文件 %{public}s 没有方向标签，使用默认值", filepath);
    }
    
    exif_data_unref(exifData);
    return orientation;
}



/**
 * @brief 内部函数：读取图片的EXIF信息
 */
static bool get_image_exif_info(const char* filepath, 
                                int* orientation, 
                                int* width, 
                                int* height,
                                char* make, size_t make_size,
                                char* model, size_t model_size) {
    ExifData* exifData = exif_data_new_from_file(filepath);
    if (!exifData) {
        return false;
    }
    
    // 默认值
    *orientation = 1;
    *width = 0;
    *height = 0;
    if (make && make_size > 0) make[0] = '\0';
    if (model && model_size > 0) model[0] = '\0';
    
    ExifByteOrder byteOrder = exif_data_get_byte_order(exifData);
    
    // 1. 读取方向
    ExifEntry* orientationEntry = exif_data_get_entry(exifData, EXIF_TAG_ORIENTATION);
    if (orientationEntry && orientationEntry->data && orientationEntry->size >= 2) {
        *orientation = exif_get_short(orientationEntry->data, byteOrder);
    }
    
    // 2. 读取宽度
    ExifEntry* widthEntry = exif_data_get_entry(exifData, EXIF_TAG_IMAGE_WIDTH);
    if (widthEntry && widthEntry->data) {
        if (widthEntry->format == EXIF_FORMAT_SHORT) {
            *width = exif_get_short(widthEntry->data, byteOrder);
        } else if (widthEntry->format == EXIF_FORMAT_LONG) {
            *width = exif_get_long(widthEntry->data, byteOrder);
        }
    }
    
    // 3. 读取高度
    ExifEntry* heightEntry = exif_data_get_entry(exifData, EXIF_TAG_IMAGE_LENGTH);
    if (heightEntry && heightEntry->data) {
        if (heightEntry->format == EXIF_FORMAT_SHORT) {
            *height = exif_get_short(heightEntry->data, byteOrder);
        } else if (heightEntry->format == EXIF_FORMAT_LONG) {
            *height = exif_get_long(heightEntry->data, byteOrder);
        }
    }
    
    // 4. 读取制造商
    ExifEntry* makeEntry = exif_data_get_entry(exifData, EXIF_TAG_MAKE);
    if (makeEntry && makeEntry->data && make && make_size > 0) {
        size_t copySize = (makeEntry->size < make_size - 1) ? makeEntry->size : make_size - 1;
        strncpy(make, reinterpret_cast<char*>(makeEntry->data), copySize);
        make[copySize] = '\0';
    }
    
    // 5. 读取型号
    ExifEntry* modelEntry = exif_data_get_entry(exifData, EXIF_TAG_MODEL);
    if (modelEntry && modelEntry->data && model && model_size > 0) {
        size_t copySize = (modelEntry->size < model_size - 1) ? modelEntry->size : model_size - 1;
        strncpy(model, reinterpret_cast<char*>(modelEntry->data), copySize);
        model[copySize] = '\0';
    }
    
    exif_data_unref(exifData);
    return true;
}



/**
 * @brief NAPI接口：获取图片方向
 */
napi_value GetImageOrientationNapi(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    if (argc < 1) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "参数不足");
        napi_value result;
        napi_create_int32(env, -1, &result);
        return result;
    }
    
    // 获取文件路径参数
    size_t str_len = 0;
    napi_get_value_string_utf8(env, args[0], nullptr, 0, &str_len);
    
    char* filepath = new char[str_len + 1];
    napi_get_value_string_utf8(env, args[0], filepath, str_len + 1, &str_len);
    
    // 读取方向信息
    int orientation = get_image_orientation(filepath);
    
    delete[] filepath;
    
    // 返回结果
    napi_value result;
    napi_create_int32(env, orientation, &result);
    return result;
}



/**
 * @brief NAPI接口：获取完整EXIF信息
 */
napi_value GetImageExifInfoNapi(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    if (argc < 1) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "参数不足");
        return nullptr;
    }
    
    // 获取文件路径参数
    size_t str_len = 0;
    napi_get_value_string_utf8(env, args[0], nullptr, 0, &str_len);
    
    char* filepath = new char[str_len + 1];
    napi_get_value_string_utf8(env, args[0], filepath, str_len + 1, &str_len);
    
    // 读取EXIF信息
    int orientation = 1;
    int width = 0;
    int height = 0;
    char make[64] = {0};
    char model[64] = {0};
    
    bool success = get_image_exif_info(filepath, &orientation, &width, &height, 
                                      make, sizeof(make), model, sizeof(model));
    
    delete[] filepath;
    
    if (!success) {
        OH_LOG_Print(LOG_APP, LOG_WARN, LOG_DOMAIN, LOG_TAG, 
                     "获取EXIF信息失败，使用默认值");
    }
    
    // 创建返回的JS对象
    napi_value result;
    napi_create_object(env, &result);
    
    // 添加orientation属性
    napi_value orientationValue;
    napi_create_int32(env, orientation, &orientationValue);
    napi_set_named_property(env, result, "orientation", orientationValue);
    
    // 添加width属性
    napi_value widthValue;
    napi_create_int32(env, width, &widthValue);
    napi_set_named_property(env, result, "width", widthValue);
    
    // 添加height属性
    napi_value heightValue;
    napi_create_int32(env, height, &heightValue);
    napi_set_named_property(env, result, "height", heightValue);
    
    // 添加make属性
    napi_value makeValue;
    napi_create_string_utf8(env, make, strlen(make), &makeValue);
    napi_set_named_property(env, result, "make", makeValue);
    
    // 添加model属性
    napi_value modelValue;
    napi_create_string_utf8(env, model, strlen(model), &modelValue);
    napi_set_named_property(env, result, "model", modelValue);
    
    return result;
}


/**
 * @brief 内部函数：使用LibRaw读取RAW文件的EXIF信息
 */
static bool get_raw_exif_info(const char* filepath, 
                              int* orientation, 
                              int* width, 
                              int* height,
                              char* make, size_t make_size,
                              char* model, size_t model_size){
    
    // 初始化LibRaw处理器
    libraw_data_t *processor = libraw_init(0);
    if (!processor) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, 
                     "LibRaw初始化失败");
        return false;
    }
    
    // 打开Raw文件（只读取元数据，不解码图像，节省内存）
    if (libraw_open_file(processor, filepath) !=LIBRAW_SUCCESS  ) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG,
                     "无法打开RAW文件: %{public}s", filepath);
        libraw_close(processor);
        return false;
    }
    
    
    // 设置默认值
    *orientation = 1;
    *width = 0;
    *height = 0;
    if (make && make_size > 0) make[0] = '\0';
    if (model && model_size > 0) model[0] = '\0';
    
    // 1. 读取方向信息 (关键修正：使用 processor->sizes.flip)
    int flip = processor->sizes.flip;
    
    // Nikon相机常见的映射关系（根据实际测试可能需要调整）
    // LibRaw flip值 -> EXIF方向值 (1-8)
    // 注：不同相机厂商可能有不同的映射，这里以Nikon为例
    switch (flip) {
        case 0:  *orientation = 1; break; // 正常
        case 3:  *orientation = 3; break; // 180度
        case 5:  *orientation = 8; break; // 调整：flip5 -> 方向8（逆时针90度）
        case 6:  *orientation = 6; break; // 顺时针90度
        case 7:  *orientation = 5; break; // 调整：flip7 -> 方向5（顺时针90度+翻转）
        case 8:  *orientation = 7; break; // 调整：flip8 -> 方向7（逆时针90度+翻转）
        default: *orientation = 1; break;
    }
    
    // 2. 读取图像尺寸（关键：有多个尺寸，含义不同）
    // 选择逻辑：优先使用去黑边后的“有效”图像尺寸
    if (processor->sizes.width > 0 && processor->sizes.height > 0) {
        *width = processor->sizes.width;
        *height = processor->sizes.height;
        OH_LOG_Print(LOG_APP, LOG_DEBUG, LOG_DOMAIN, LOG_TAG, "使用有效图像尺寸: %{public}dx%{public}d", *width, *height);
    }
     // 备选：原始传感器尺寸
    else if (processor->sizes.raw_width > 0 && processor->sizes.raw_height > 0) {
        *width = processor->sizes.raw_width;
        *height = processor->sizes.raw_height;
        OH_LOG_Print(LOG_APP, LOG_DEBUG, LOG_DOMAIN, LOG_TAG, "使用原始传感器尺寸: %{public}dx%{public}d", *width, *height);
    }
    // 最后备选：处理后的输出尺寸
    else {
        *width = processor->sizes.iwidth;
        *height = processor->sizes.iheight;
        OH_LOG_Print(LOG_APP, LOG_DEBUG, LOG_DOMAIN, LOG_TAG, "使用输出尺寸: %{public}dx%{public}d", *width, *height);
    }
    
    
    // 3. 读取制造商和型号（关键：它们是字符数组，不是指针）
    // idata.make 和 idata.model 是固定大小的char数组
    if (processor->idata.make[0] && make && make_size > 0) {
        // 安全拷贝：使用 strncpy 并确保以 null 结尾
        size_t copy_len = strlen(processor->idata.make);
        copy_len = (copy_len < make_size - 1) ? copy_len : make_size - 1;
        strncpy(make, processor->idata.make, copy_len);
        make[copy_len] = '\0'; // 确保字符串终止
    }
    
    if (processor->idata.model[0] && model && model_size > 0) {
        size_t copy_len = strlen(processor->idata.model);
        copy_len = (copy_len < model_size - 1) ? copy_len : model_size - 1;
        strncpy(model, processor->idata.model, copy_len);
        model[copy_len] = '\0';
    }
    
    // 调试日志（可选，但强烈建议保留）
    OH_LOG_Print(LOG_APP, LOG_DEBUG, LOG_DOMAIN, LOG_TAG,
                "RAW文件[%{public}s] EXIF: %{public}dx%{public}d, 方向=%{public}d, 相机=[%{public}s][%{public}s], LibRaw_flip=%{public}d",
                filepath, *width, *height, *orientation, 
                (make[0]?make:"(空)"), (model[0]?model:"(空)"), flip);
    
    // 清理资源
    libraw_close(processor);
    return true;
}



/**
 * @brief NAPI接口：获取RAW文件方向
 */
napi_value GetRawImageOrientationNapi(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    if (argc < 1) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "参数不足");
        napi_value result;
        napi_create_int32(env, -1, &result);
        return result;
    }
    
    // 获取文件路径参数
    size_t str_len = 0;
    napi_get_value_string_utf8(env, args[0], nullptr, 0, &str_len);
    
    char* filepath = new char[str_len + 1];
    napi_get_value_string_utf8(env, args[0], filepath, str_len + 1, &str_len);
    
    // 使用LibRaw读取方向信息
    libraw_data_t *processor = libraw_init(0);
    int orientation = 1;
    
    if (processor) {
        if (libraw_open_file(processor, filepath) == LIBRAW_SUCCESS) {
            int flip = processor->sizes.flip;
            // 方向映射
            switch (flip) {
                case 0: orientation = 1; break;
                case 3: orientation = 3; break;
                case 5: orientation = 8; break;  // 调整
                case 6: orientation = 6; break;
                case 7: orientation = 5; break;  // 调整
                case 8: orientation = 7; break;  // 调整
                default: orientation = 1; break;
            }
            OH_LOG_Print(LOG_APP, LOG_DEBUG, LOG_DOMAIN, LOG_TAG,
                        "RAW文件 %{public}s 方向: %{public}d (flip=%{public}d)", 
                        filepath, orientation, flip);
        } else {
            OH_LOG_Print(LOG_APP, LOG_WARN, LOG_DOMAIN, LOG_TAG,
                        "无法打开RAW文件: %{public}s", filepath);
        }
        libraw_close(processor);
    }
    
    delete[] filepath;
    
    // 返回结果
    napi_value result;
    napi_create_int32(env, orientation, &result);
    return result;
}


/**
 * @brief NAPI接口：获取RAW文件完整EXIF信息
 */
napi_value GetRawImageExifInfoNapi(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    if (argc < 1) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "参数不足");
        return nullptr;
    }
    
    // 获取文件路径参数
    size_t str_len = 0;
    napi_get_value_string_utf8(env, args[0], nullptr, 0, &str_len);
    
    char* filepath = new char[str_len + 1];
    napi_get_value_string_utf8(env, args[0], filepath, str_len + 1, &str_len);
    
    // 读取EXIF信息
    int orientation = 1;
    int width = 0;
    int height = 0;
    char make[64] = {0};
    char model[64] = {0};
    
    bool success = get_raw_exif_info(filepath, &orientation, &width, &height, 
                                    make, sizeof(make), model, sizeof(model));
    
    delete[] filepath;
    
    if (!success) {
        OH_LOG_Print(LOG_APP, LOG_WARN, LOG_DOMAIN, LOG_TAG, 
                     "获取RAW EXIF信息失败，使用默认值");
    }
    
    // 创建返回的JS对象
    napi_value result;
    napi_create_object(env, &result);
    
    // 添加各属性
    napi_value orientationValue, widthValue, heightValue, makeValue, modelValue;
    napi_create_int32(env, orientation, &orientationValue);
    napi_create_int32(env, width, &widthValue);
    napi_create_int32(env, height, &heightValue);
    napi_create_string_utf8(env, make, strlen(make), &makeValue);
    napi_create_string_utf8(env, model, strlen(model), &modelValue);
    
    napi_set_named_property(env, result, "orientation", orientationValue);
    napi_set_named_property(env, result, "width", widthValue);
    napi_set_named_property(env, result, "height", heightValue);
    napi_set_named_property(env, result, "make", makeValue);
    napi_set_named_property(env, result, "model", modelValue);
    
    return result;
}