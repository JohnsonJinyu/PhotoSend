//
// Created on 2025/11/10.
// 负责从机内下载照片
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".
// C++ 层需要实现的核心功能：获取缩略图列表和下载选中照片
#include "Camera/native_common.h"
#include "gphoto2/gphoto2-list.h"
#include "gphoto2/gphoto2-port-result.h"
#include <cstddef>
#include <cstdint>
#include <hilog/log.h>
#include <string>



// 内部结构体：存储单张照片的缩略图信息
struct ThumbnailInfo {
    std::string folder;   // 相机中的文件夹路径
    std::string fileName; // 文件名
    uint8_t *thumbData;   // 缩略图二进制数据
    size_t thumbSize;     // 缩略图大小
};


/**
 * 内部函数：遍历相机照片目录，获取所有照片的缩略图信息
 * */

static std::vector<ThumbnailInfo> InternalGetThumbnailList() {
    std::vector<ThumbnailInfo> thumbList;
    if (!g_connected || !g_context || !g_camera) {
        OH_LOG_PrintMsg(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "相机未连接，无法获取缩略图");
        return thumbList;
    }

    // 1、获取相机中存储照片的目录
    CameraList *folders = nullptr;
    gp_list_new(&folders);
    int ret = gp_camera_folder_list_folders(g_camera, "/", folders, g_context);
    if (ret != GP_OK) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG,  "获取根目录下的文件夹失败: %{public}s", gp_result_as_string(ret));
        gp_list_free(folders);
        return thumbList;
    }
    
    
    // 2、寻找DCIM目录（照片通常存在这个目录下）
    const char* photoFolder = nullptr;
    int numFolders = gp_list_count(folders);
    for (int i = 0; i < numFolders; i++) {
        const char* folderName;
        gp_list_get_name(folders, i, &folderName);
        OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "根目录下找到文件夹：%{public}s",folderName);
        
        // 筛选包含“DCIM"的目录
        if (strstr(folderName, "DCIM") != nullptr) {
            // 3、获取DCIM目录下的子文件夹
            CameraList* dcimSubFolders = nullptr;
            gp_list_new(&dcimSubFolders);
            // 获取DCIM下的子文件夹
            ret = gp_camera_folder_list_folders(g_camera, folderName, dcimSubFolders, g_context);
            if (ret == GP_OK && gp_list_count(dcimSubFolders) > 0) {
                // 取第一个子文件夹作为照片目录（通常是最新的）
                gp_list_get_name(dcimSubFolders, 0, &photoFolder);
                OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "找到照片存储目录：%{public}s",photoFolder);
                gp_list_free(dcimSubFolders);
                break;
            }
            gp_list_free(dcimSubFolders);
        }
        
    }
    gp_list_free(folders); // 释放根目录文件夹列表;
    
    // 若未找到照片目录，直接返回空列表
    if (!photoFolder) {
        OH_LOG_PrintMsg(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "未找到DCIM或照片存储目录");
        return thumbList;
    }
    
    
    // 4、获取照片目录下的所有文件
    CameraList* files = nullptr;
    gp_list_new(&files);
    ret = gp_camera_folder_list_files(g_camera, photoFolder, files, g_context);
    if (ret != GP_OK) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "获取照片目录下的文件列表失败:%{public}s",gp_result_as_string(ret));
        gp_list_free(files);
        return thumbList;
    }
    
    int numFiles = gp_list_count(files);
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "照片目录下找到%{public}d个文件",numFiles);
    
    // 5、遍历文件，提取每个文件的缩略图
    for (int i = 0; i< numFiles; i++) {
        const char* fileName;
        gp_list_get_name(files, i, &fileName);
        
        // 筛选照片文件(根据Nikon常见照片格式JPEG/NEF)
        if (strstr(fileName,".jpg")==nullptr && strstr(fileName, ".JPG") == nullptr
            && strstr(fileName, ".nef") == nullptr && strstr(fileName, ".NEF") == nullptr) {
            OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "跳过非照片文件：%{public}s",fileName);
            continue;
        }
        
        // 6、虎丘该文件的缩略图(GP_FILE_TYPE_THUMBNAIL)
        CameraFile* thumbFile = nullptr;
        gp_file_new(&thumbFile);
        // ibgphoto2 的类型定义规范：** 缩略图统一通过GP_FILE_TYPE_PREVIEW获取 **
        ret = gp_camera_file_get(g_camera, photoFolder, fileName, GP_FILE_TYPE_PREVIEW, thumbFile, g_context);
        if (ret != GP_OK) {
            OH_LOG_Print(LOG_APP, LOG_WARN, LOG_DOMAIN, LOG_TAG,  "获取 %s 的缩略图失败: %{public}s", fileName, gp_result_as_string(ret));
            gp_file_unref(thumbFile);
            continue;
        }
        
        // 提取缩略图数据和大小（后续逻辑不变）
        const char* thumbData;
        unsigned long thumbSize;
        gp_file_get_data_and_size(thumbFile, &thumbData, &thumbSize);
        if (thumbSize == 0) {
            OH_LOG_Print(LOG_APP, LOG_WARN, LOG_DOMAIN, LOG_TAG, "%{public}s 的缩略图为空", fileName);
            gp_file_unref(thumbFile);
            continue;
        }
        
        
        // 保存到ThumbnailInfo结构体（后续逻辑不变）
        ThumbnailInfo info;
        info.folder = photoFolder;
        info.fileName = fileName;
        info.thumbSize = thumbSize;
        info.thumbData = (uint8_t*)malloc(thumbSize);  // 分配内存存储缩略图数据
        memcpy(info.thumbData, thumbData, thumbSize);
        
        thumbList.push_back(info);
        gp_file_unref(thumbFile);  // 释放缩略图文件对象
    }
    
    gp_list_free(files);  // 释放文件列表
    return thumbList;
    
}



/**
 * NAPI接口：暴露给ArkTS,返回缩略图列表（包含路径、文件名、缩略图数据）
 * 
 * */

napi_value GetThumbnailList(napi_env env,napi_callback_info info){
    // 调用内部函数获取缩略图列表
    std::vector<ThumbnailInfo> thumbList = InternalGetThumbnailList();
    
    // 创建NAPI数组，用于存放所有缩略图信息
    napi_value resultArray;
    napi_create_array(env, &resultArray);
    
    // 遍历缩略图列表，用于存放所有缩略图信息
    for (size_t i = 0; i < thumbList.size(); i++) {
        ThumbnailInfo& info = thumbList[i];
        
        // 创建单个缩略图信息的NAPI对象
        napi_value thumbObj;
        napi_create_object(env, &thumbObj);
        
        // 设置对象属性：folder (相机中的文件夹路径)
        napi_set_named_property(env, thumbObj, "folder", CreateNapiString(env, info.folder.c_str()));
        // 设置对象属性：filename 文件名
        napi_set_named_property(env, thumbObj, "filename", CreateNapiString(env, info.fileName.c_str()));
        // 设置对象属性：thumbnail（缩略图二进制数据，转换为arkts的buffer）
        napi_value thumbBuffer;
        napi_create_buffer_copy(env, info.thumbSize, info.thumbData, nullptr, &thumbBuffer);
        napi_set_named_property(env, thumbObj, "thumbnail", thumbBuffer);
        
        // 将对象添加到数组
        napi_set_element(env, resultArray, i, thumbObj);
    }
    return resultArray;
}