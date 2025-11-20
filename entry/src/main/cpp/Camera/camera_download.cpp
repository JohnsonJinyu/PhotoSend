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

#define LOG_DOMAIN 0x0005         // 日志域（自定义标识，区分不同模块日志）
#define LOG_TAG "Camera_Download" // 日志标签（日志中显示的模块名）

// 内部结构体：存储单张照片的缩略图信息
struct ThumbnailInfo {
    std::string folder;   // 相机中的文件夹路径
    std::string fileName; // 文件名
    uint8_t *thumbData;   // 缩略图二进制数据
    size_t thumbSize;     // 缩略图大小
};

// 存储异步任务所需数据（输入参数、结果、回调）
struct AsyncThumbnailData {
    napi_env env;                      // NAPI环境
    napi_ref callback;                 // ArkTS层传入的回调函数引用
    std::vector<ThumbnailInfo> result; // 异步操作结果
    int errorCode;                     // 错误码（0表示成功）
    std::string errorMsg;              // 错误信息
};





// 主线程回调函数（处理结果并通知ArkTS）
static void CompleteAsyncWork(napi_env env, napi_status status, void *data) {
    AsyncThumbnailData *asyncData = static_cast<AsyncThumbnailData *>(data);
    if (!asyncData || !asyncData->callback) {
        return;
    }

    // 1. 创建回调参数（[error, result]）
    napi_value args[2];
    // 错误信息（null表示无错误）
    napi_get_null(env, &args[0]);
    // 结果数组（默认空）
    napi_value resultArray;
    napi_create_array(env, &resultArray);

    if (asyncData->errorCode == 0) {
        // 2. 转换结果为NAPI数组（与原同步逻辑一致）
        for (size_t i = 0; i < asyncData->result.size(); i++) {
            ThumbnailInfo &info = asyncData->result[i];
            napi_value thumbObj;
            napi_create_object(env, &thumbObj);

            napi_set_named_property(env, thumbObj, "folder", CreateNapiString(env, info.folder.c_str()));
            napi_set_named_property(env, thumbObj, "filename", CreateNapiString(env, info.fileName.c_str()));

            napi_value thumbBuffer = nullptr; // 显式初始化为nullptr

            OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG,
                         "文件 %{public}s 的thumbData地址：%{public}p，准备包装为外部缓冲区", 
                         info.fileName.c_str(), info.thumbData);
            
            // 关键修改：使用napi_create_external_buffer包装已有内存
            // 定义finalize回调函数：当ArkTS层不再使用该缓冲区时释放内存
            auto finalize = [](napi_env env, void *data, void *hint) {
                OH_LOG_PrintMsg(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "自动释放缩略图内存");
                free(data); // 释放malloc分配的内存
            };
            
            // 创建外部缓冲区（不复制数据，直接包装info.thumbData）
            napi_status createStatus = napi_create_external_buffer(
                env,
                info.thumbSize,       // 数据长度
                info.thumbData,       // 已分配的内存指针（malloc的结果）
                finalize,             // 内存释放回调
                nullptr,              // 回调参数（无需求时为nullptr）
                &thumbBuffer          // 输出的Buffer对象
            );
            
            // 检查创建是否成功
            if (createStatus != napi_ok) {
                OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG,
                             "文件 %{public}s 的外部缓冲区创建失败，状态码：%{public}d", 
                             info.fileName.c_str(), createStatus);
                free(info.thumbData); // 若创建失败，手动释放内存
                continue;
            }
            
            // 设置缩略图属性
            napi_set_named_property(env, thumbObj, "thumbnail", thumbBuffer);
            napi_set_element(env, resultArray, i, thumbObj);


        }
        args[1] = resultArray;
    } else {
        // 3. 处理错误（将错误信息作为第一个参数）
        napi_create_string_utf8(env, asyncData->errorMsg.c_str(), NAPI_AUTO_LENGTH, &args[0]);
        napi_get_null(env, &args[1]); // 结果为null
    }

    // 4. 调用ArkTS层回调函数
    napi_value callback;
    napi_get_reference_value(env, asyncData->callback, &callback);
    napi_value global;
    // napi_get_global(env, &global);
    napi_status envStatus = napi_get_global(env, &global);
    if (envStatus != napi_ok) {
        OH_LOG_PrintMsg(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "env已失效！");
        return;
    }

    napi_make_callback(env, nullptr, global, callback, 2, args, nullptr);

    // 5. 释放资源
    napi_delete_reference(env, asyncData->callback);
    delete asyncData;
}


/**
 * 内部函数：遍历相机照片目录，获取所有照片的缩略图信息
 * */

static std::vector<ThumbnailInfo> InternalGetThumbnailList() {
    std::vector<ThumbnailInfo> thumbList;
    if (!g_connected || !g_context || !g_camera) {
        OH_LOG_PrintMsg(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "相机未连接，无法获取缩略图");
        return thumbList;
    }

    // 1、获取相机根目录下的所有文件夹（如store_00010001，对应存储卡根目录）
    CameraList *rootFolders = nullptr;
    gp_list_new(&rootFolders);
    int ret = gp_camera_folder_list_folders(g_camera, "/", rootFolders, g_context);
    if (ret != GP_OK) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "获取根目录下的文件夹失败: %{public}s",
                     gp_result_as_string(ret));
        gp_list_free(rootFolders);
        return thumbList;
    }


    // 2、遍历根目录下的文件夹（如store_00010001），在其中寻找DCIM目录
    std::string dcimFolder; // 关键修改：用std::string存储，避免野指针 ，存储找到的DCIM目录完整路径
    int numRootFolders = gp_list_count(rootFolders);
    for (int i = 0; i < numRootFolders; i++) {
        const char *storageFolder; // 根目录下的存储文件夹（如store_00010001）
        gp_list_get_name(rootFolders, i, &storageFolder);
        OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "根目录下找到文件夹：%{public}s", storageFolder);

        // 将相对路径转化为据对路径（添加前缀“/”）
        std::string absoluteStoragePath = '/' + std::string(storageFolder); // 转换为"/store_00010001"
        OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "转换为绝对路径：%{public}s", absoluteStoragePath.c_str());


        // 2.1 获取该存储文件夹下的子目录（检查是否有DCIM）
        CameraList *storageSubFolders = nullptr;
        gp_list_new(&storageSubFolders);
        // 关键修改：传入绝对路径absoluteStoragePath.c_str()
        ret = gp_camera_folder_list_folders(g_camera, absoluteStoragePath.c_str(), storageSubFolders, g_context);
        if (ret != GP_OK) {
            OH_LOG_Print(LOG_APP, LOG_WARN, LOG_DOMAIN, LOG_TAG, "获取 %{public}s 下的子目录失败: %{public}s",
                         absoluteStoragePath.c_str(), gp_result_as_string(ret));
            gp_list_free(storageSubFolders);
            continue;
        }

        // 2.2 在存储文件夹的子目录中寻找DCIM
        int numStorageSubFolders = gp_list_count(storageSubFolders);
        for (int j = 0; j < numStorageSubFolders; j++) {
            const char *subFolderName;
            gp_list_get_name(storageSubFolders, j, &subFolderName);
            OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "%{public}s下找到子目录：%{public}s",
                         absoluteStoragePath.c_str(), subFolderName);


            // 找到DCIM目录，拼接完整绝对路径（如"/store_00010001/DCIM"）
            if (strstr(subFolderName, "DCIM") != nullptr) {
                // 直接用std::string存储dcimFolder，避免依赖局部变量
                dcimFolder = absoluteStoragePath + "/" + subFolderName;
                OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "找到DCIM目录：%{public}s", dcimFolder.c_str());
                gp_list_free(storageSubFolders);
                goto found_dcim;
            }
        }


        gp_list_free(storageSubFolders);
    }
found_dcim:

    gp_list_free(rootFolders); // 释放根目录文件夹列表

    // 若未找到照片目录，直接返回空列表
    if (dcimFolder.empty()) { // 检查字符串是否为空，而非指针是否为null
        OH_LOG_PrintMsg(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "未找到DCIM或照片存储目录");
        return thumbList;
    }


    // 3、获取DCIM目录下的子文件夹（如100NCZ_F，用户自定义）
    // const char* photoFolder = nullptr;
    std::string photoFolder; // 关键修改：用std::string存储，避免野指针
    CameraList *dcimSubFolders = nullptr;
    gp_list_new(&dcimSubFolders);
    ret = gp_camera_folder_list_folders(g_camera, dcimFolder.c_str(), dcimSubFolders, g_context);
    if (ret == GP_OK && gp_list_count(dcimSubFolders) > 0) {
        // 取第一个子文件夹名称（相对路径，如100NCZ_F）
        const char *subFolderName;
        gp_list_get_name(dcimSubFolders, 0, &subFolderName);

        // 关键修改1：处理dcimFolder尾部可能的斜杠，避免拼接后出现双斜杠
        std::string dcimPathStr = dcimFolder;
        if (!dcimPathStr.empty() && dcimPathStr.back() == '/') {
            dcimPathStr.pop_back(); // 移除尾部斜杠
        }

        // 关键修改2：拼接绝对路径，确保无连续斜杠
        // std::string absolutePhotoPath = dcimPathStr + "/" + subFolderName;

        // 拼接绝对路径（用std::string存储，确保有效）
        photoFolder = dcimPathStr + "/" + subFolderName;

        // 关键修改3：再次验证路径格式（以/开头，无连续斜杠）
        if (photoFolder.empty() || photoFolder[0] != '/') {
            OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "照片目录路径格式错误（不以/开头）：%{public}s",
                         photoFolder.c_str());
            gp_list_free(dcimSubFolders);
            return thumbList;
        }
        if (photoFolder.find("//") != std::string::npos) {
            OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "照片目录路径包含连续斜杠：%{public}s",
                         photoFolder.c_str());
            gp_list_free(dcimSubFolders);
            return thumbList;
        }

        // photoFolder = absolutePhotoPath.c_str();
        OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "找到照片存储目录（绝对路径，已校验）：%{public}s",
                     photoFolder.c_str());
    } else {
        // 极端情况：DCIM下无子目录，直接用DCIM作为照片目录（确保无尾部斜杠）
        std::string dcimPathStr = dcimFolder;
        if (!dcimPathStr.empty() && dcimPathStr.back() == '/') {
            dcimPathStr.pop_back(); // 移除尾部斜杠
        }
        // photoFolder = dcimPathStr.c_str();
        photoFolder = dcimPathStr; // 直接用std::string赋值
        OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "DCIM下无子目录，使用DCIM作为照片目录：%{public}s",
                     photoFolder.c_str());
    }
    gp_list_free(dcimSubFolders);


    // 4、获取照片目录下的所有文件
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "准备获取文件列表的路径：%{public}s", photoFolder.c_str());
    CameraList *files = nullptr;
    gp_list_new(&files);
    ret = gp_camera_folder_list_files(g_camera, photoFolder.c_str(), files, g_context);
    if (ret != GP_OK) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "获取照片目录下的文件列表失败:%{public}s",
                     gp_result_as_string(ret));
        gp_list_free(files);
        return thumbList;
    }

    int numFiles = gp_list_count(files);
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "照片目录下找到%{public}d个文件", numFiles);

    // 5、遍历文件，提取每个文件的缩略图
    for (int i = 0; i < numFiles; i++) {
        const char *fileName;
        gp_list_get_name(files, i, &fileName);

        // 筛选照片文件(根据Nikon常见照片格式JPEG/NEF)
        if (strstr(fileName, ".jpg") == nullptr && strstr(fileName, ".JPG") == nullptr &&
            strstr(fileName, ".nef") == nullptr && strstr(fileName, ".NEF") == nullptr) {
            OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "跳过非照片文件：%{public}s", fileName);
            continue;
        }

        // 6、虎丘该文件的缩略图(GP_FILE_TYPE_THUMBNAIL)
        CameraFile *thumbFile = nullptr;
        gp_file_new(&thumbFile);
        // ibgphoto2 的类型定义规范：** 缩略图统一通过GP_FILE_TYPE_PREVIEW获取 **
        ret = gp_camera_file_get(g_camera, photoFolder.c_str(), fileName, GP_FILE_TYPE_PREVIEW, thumbFile, g_context);
        if (ret != GP_OK) {
            OH_LOG_Print(LOG_APP, LOG_WARN, LOG_DOMAIN, LOG_TAG, "获取 %{public}s 的缩略图失败: %{public}s", fileName,
                         gp_result_as_string(ret));
            gp_file_unref(thumbFile);
            continue;
        }

        // 提取缩略图数据和大小（后续逻辑不变）
        const char *thumbData;
        unsigned long thumbSize;
        gp_file_get_data_and_size(thumbFile, &thumbData, &thumbSize);
        if (thumbData == nullptr || thumbSize == 0) {
            OH_LOG_Print(LOG_APP, LOG_WARN, LOG_DOMAIN, LOG_TAG, "%{public}s 的缩略图数据无效（指针为空或大小为0）",
                         fileName);
            gp_file_unref(thumbFile);
            continue;
        }


        OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG,
                     "文件 %{public}s 的缩略图大小：%{public}lu 字节，数据指针：%{public}p", fileName, thumbSize,
                     thumbData);

        // 保存到ThumbnailInfo结构体（后续逻辑不变）
        ThumbnailInfo info;
        info.folder = photoFolder;
        info.fileName = fileName;
        info.thumbSize = thumbSize;
        info.thumbData = (uint8_t *)malloc(thumbSize); // 分配内存存储缩略图数据

        if (info.thumbData == nullptr) {
            OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG,
                         "文件 %{public}s 分配缩略图内存失败（大小：%{public}lu）", fileName, thumbSize);
            continue;
        }

        memcpy(info.thumbData, thumbData, thumbSize);

        if (thumbSize >= 2) {
            OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG,
                         "文件 %{public}s 复制后的数据头：0x%{public}02X%{public}02X", fileName, info.thumbData[0],
                         info.thumbData[1]);
        }

        // 验证JPEG格式（关键：避免无效数据传入ArkTS）
        if (thumbSize < 2 || info.thumbData[0] != 0xFF || info.thumbData[1] != 0xD8) {
            OH_LOG_Print(LOG_APP, LOG_WARN, LOG_DOMAIN, LOG_TAG, "%{public}s 不是有效的JPEG缩略图", fileName);
            free(info.thumbData); // 释放无效数据
            continue;
        }

        thumbList.push_back(info);
        gp_file_unref(thumbFile); // 释放缩略图文件对象
    }

    gp_list_free(files); // 释放文件列表
    return thumbList;
}


// 后台线程执行的函数（耗时操作）
static void ExecuteAsyncWork(napi_env env, void *data) {
    AsyncThumbnailData *asyncData = static_cast<AsyncThumbnailData *>(data);
    try {
        // 执行耗时操作（获取缩略图列表）
        asyncData->result = InternalGetThumbnailList();

        asyncData->errorCode = 0;
    } catch (const std::exception &e) {
        // 捕获异常，记录错误信息
        asyncData->errorCode = -1;
        asyncData->errorMsg = e.what();
    }
}


/**
 * 异步NAPI接口：接收ArkTS层的回调函数，在后台获取缩略图列表后触发回调
 * 调用方式（ArkTS）：GetThumbnailList((err, list) => { ... })
 */
napi_value GetThumbnailList(napi_env env, napi_callback_info info) {
    // 1. 解析输入参数（获取ArkTS层传入的回调函数）
    size_t argc = 1;
    napi_value args[1];
    napi_value thisArg;
    napi_status status = napi_get_cb_info(env, info, &argc, args, &thisArg, nullptr);
    if (status != napi_ok || argc < 1) {
        OH_LOG_PrintMsg(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "参数错误：需要传入回调函数");
        return nullptr;
    }

    // 2. 验证回调函数类型
    napi_valuetype argType;
    napi_typeof(env, args[0], &argType);
    if (argType != napi_function) {
        OH_LOG_PrintMsg(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "参数错误：第一个参数必须是函数");
        return nullptr;
    }

    // 3. 创建异步任务数据
    AsyncThumbnailData *asyncData = new AsyncThumbnailData();
    asyncData->env = env;
    // 保存回调函数引用（延长生命周期）
    napi_create_reference(env, args[0], 1, &asyncData->callback);

    // 4. 创建异步工作项
    napi_value workName;
    napi_create_string_utf8(env, "GetThumbnailListAsync", NAPI_AUTO_LENGTH, &workName);
    napi_async_work work;
    napi_create_async_work(env, nullptr, workName,
                           ExecuteAsyncWork,  // 后台执行函数
                           CompleteAsyncWork, // 主线程完成回调
                           asyncData, &work);

    // 5. 队列化异步工作（立即执行）
    napi_queue_async_work(env, work);

    // 6. 返回undefined（异步接口无需同步返回结果）
    napi_value result;
    napi_get_undefined(env, &result);
    return result;
}








// ###########################################################################
// 核心函数：从相机下载照片（内部逻辑，不直接暴露给ArkTS）
// ###########################################################################
/**
 * @brief 内部函数：根据"相机中的文件路径"，下载照片到内存，并通过输出参数返回
 * @param folder 照片在相机中的文件夹路径（如："/DCIM/100NIKON"）
 * @param filename 照片在相机中的文件名（如："DSC_0001.JPG"）
 * @param[out] data 输出参数：二级指针（指向存储照片二进制数据的指针）
 *                  函数内部会分配内存存储照片数据，最终将内存地址通过此参数传出
 *                  调用者（DownloadPhoto）使用完后必须手动free释放，避免内存泄漏
 * @param[out] length 输出参数：一级指针（指向存储照片数据长度的变量）
 *                    函数内部会将照片的字节数通过此参数传出
 * @return bool 下载成功返回true，失败返回false（仅表示下载结果，不返回数据）
 */
static bool InternalDownloadFile(const char *folder, const char *filename, uint8_t **data, size_t *length) {
    // 1. 先检查相机是否已连接，未连接直接返回失败
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "InternalDownloadFile中g_connected:%{public}d,",g_connected);
    if (!g_connected)
        return false;

    // 2. 定义libgphoto2的文件对象：用于暂存从相机下载的文件（二进制数据+元信息）
    CameraFile *file = nullptr;  // 初始化为空指针

    // 3. 创建空的CameraFile对象（相当于创建一个"空容器"，准备装下载的照片数据）
    int ret = gp_file_new(&file);  // 传入指针的地址，让函数内部给file分配内存
    if (ret != GP_OK) {  // 检查创建是否成功（失败概率低，但必须处理）
        OH_LOG_PrintMsg(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "Failed to create CameraFile object");
        return false;
    }

    // 4. 打印日志：确认要下载的文件路径和名称
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "获取的文件路径为:%{public}s,文件名为%{public}s",folder,filename);
    
    // 5. 调用libgphoto2核心下载接口：将相机中的文件下载到上面创建的CameraFile对象中
    // 参数说明：
    // - g_camera：全局相机对象（已在连接时初始化，代表当前连接的相机）
    // - folder：相机中的文件夹路径（入参）
    // - filename：相机中的文件名（入参）
    // - GP_FILE_TYPE_NORMAL：下载原始文件（不压缩、不缩略，完整照片数据）
    // - file：接收数据的CameraFile对象（上面创建的"容器"）
    // - g_context：全局上下文对象（libgphoto2用于处理回调、进度的必备参数）
    ret = gp_camera_file_get(g_camera, folder, filename, GP_FILE_TYPE_NORMAL, file, g_context);
    
    // 6. 检查下载是否成功：失败则释放CameraFile对象，返回false
    if (ret != GP_OK) {
        OH_LOG_PrintMsg(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "Failed to download file");
        gp_file_unref(file);  // 释放CameraFile的内存（避免泄漏）
        return false;
    }

    // 7. 从CameraFile对象中提取核心数据：二进制数据指针 + 数据长度
    const char *fileData = nullptr;  // 临时存储文件二进制数据（libgphoto2内部缓冲区地址）
    unsigned long fileSize = 0;      // 临时存储文件大小（字节数，libgphoto2用unsigned long类型）
    // 调用libgphoto2接口：安全获取CameraFile内部的数据流和大小
    // 注意：fileData指向的是libgphoto2管理的内存，不能手动free，也不能修改（const修饰）
    gp_file_get_data_and_size(file, &fileData, &fileSize);

    // 8. 检查提取的数据是否有效（空数据直接返回失败）
    if (fileData == nullptr || fileSize == 0) {
        OH_LOG_PrintMsg(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "Downloaded file is empty");
        gp_file_unref(file);  // 释放CameraFile对象
        return false;
    }

    // 9. 为输出数据分配独立内存：将libgphoto2管理的数据拷贝到自己的内存中
    // 为什么要分配新内存？因为fileData指向的内存会在gp_file_unref(file)后被释放
    // 我们需要把数据转移到"自己管理"的内存，才能传递给调用者（DownloadPhoto）
    *data = (uint8_t *)malloc(fileSize);  // 分配fileSize字节的堆内存，返回内存地址给*data
    if (*data == nullptr) {  // 检查内存分配是否成功（内存不足时malloc返回nullptr）
        OH_LOG_PrintMsg(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "Failed to allocate memory for file data");
        gp_file_unref(file);  // 释放CameraFile对象
        return false;
    }

    // 10. 拷贝数据：将libgphoto2的fileData（相机照片数据）拷贝到自己分配的*data内存中
    // memcpy(目标地址, 源地址, 拷贝字节数)：二进制数据直接拷贝，不改变数据内容
    memcpy(*data, fileData, fileSize);
    
    // 11. 设置输出参数length：将照片大小（字节数）传递给调用者
    *length = fileSize;  // 把libgphoto2返回的unsigned long转换成size_t（C++标准长度类型）

    // 12. 释放CameraFile对象：数据已经拷贝到自己的内存，这个"临时容器"没用了
    gp_file_unref(file);  // 减少引用计数，libgphoto2会自动释放其内部内存

    // 13. 下载成功：返回true（数据已经通过data和length两个输出参数传递出去了）
    return true;
}

// ###########################################################################
// NAPI接口：下载照片（暴露给ArkTS调用，封装InternalDownloadFile）
// ###########################################################################
/**
 * @brief ArkTS层调用此函数，传入照片路径，下载照片并返回二进制数据
 * @param env NAPI环境对象（必选参数，封装了ArkTS和C++的交互上下文）
 * @param info NAPI回调信息对象（必选参数，存储了ArkTS传入的参数、this指针等）
 * @return napi_value 返回ArkTS的Buffer类型（存储照片二进制数据），失败返回nullptr（ArkTS侧接收为null）
 *         NAPI是ArkTS和C++的"桥梁"，负责两种语言的数据类型转换
 */
napi_value DownloadPhoto(napi_env env, napi_callback_info info) {
    // 1. 定义变量：接收ArkTS传入的参数（期望2个：folder和name）
    size_t argc = 2;                // 期望接收的参数个数
    napi_value args[2];             // 存储ArkTS传入的参数（napi_value是NAPI的通用数据类型，可代表任意ArkTS类型）
    // 2. 提取ArkTS传入的参数：通过NAPI接口从info中获取参数到args数组
    // 函数作用：把ArkTS传入的参数拷贝到args数组，argc会被更新为实际接收的参数个数
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    // 3. 检查参数个数：如果实际传入的参数少于2个，返回null（ArkTS侧接收为null）
    if (argc < 2) {
        OH_LOG_PrintMsg(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "DownloadPhoto requires 2 arguments");
        return nullptr;
    }

    // 4. 定义缓冲区：存储从ArkTS参数转换来的C字符串（文件夹路径和文件名）
    char folder[128] = {0};  // 初始化全0，避免垃圾数据
    char name[128] = {0};    // 缓冲区大小128字节，足够存储常规文件路径

    // 5. 转换参数：将ArkTS的字符串类型（napi_value）转换为C++的char*字符串
    // napi_get_value_string_utf8：NAPI提供的字符串转换接口，将UTF-8编码的ArkTS字符串转成C字符串
    // 参数说明：env（环境）、args[0]（ArkTS传入的第一个参数，folder）、folder（目标C字符串缓冲区）
    //           sizeof(folder)（缓冲区大小）、nullptr（忽略实际转换的字节数）
    napi_get_value_string_utf8(env, args[0], folder, sizeof(folder), nullptr);
    napi_get_value_string_utf8(env, args[1], name, sizeof(name), nullptr);
    
    // 6. 打印日志：确认转换后的文件路径和名称（方便调试）
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "Downloading file: %{public}s/%{public}s", folder, name);

    // 7. 定义变量：接收InternalDownloadFile的输出数据（核心！数据传递的关键）
    uint8_t *photo_data = nullptr;  // 指针：用于接收下载的照片二进制数据（指向自己分配的堆内存）
    size_t photo_length = 0;        // 变量：用于接收照片数据的长度（字节数）

    // 8. 调用内部下载函数：核心数据传递步骤
    // 关键说明：
    // - 传入&photo_data（photo_data的地址，即二级指针）：让InternalDownloadFile能修改photo_data的值
    //   InternalDownloadFile内部会给*data（也就是这里的photo_data）赋值为malloc分配的内存地址
    // - 传入&photo_length（photo_length的地址）：让InternalDownloadFile能修改photo_length的值
    // - 返回值success仅表示下载是否成功，实际照片数据存在photo_data中，长度存在photo_length中
    bool success = InternalDownloadFile(folder, name, &photo_data, &photo_length);

    // 9. 检查下载结果：失败或数据为空，返回null
    if (!success || photo_data == nullptr || photo_length == 0) {
        OH_LOG_PrintMsg(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "Failed to download photo or data is empty");
        // 安全处理：如果已经分配了内存（photo_data不为null），必须free释放，避免内存泄漏
        if (photo_data) {
            free(photo_data);
        }
        return nullptr;  // ArkTS侧接收为null
    }

    // 10. 转换数据：将C++的二进制数据（photo_data）转换成ArkTS能识别的Buffer类型
    napi_value buffer;  // 存储转换后的NAPI Buffer对象（对应ArkTS的Buffer类型）
    // napi_create_buffer_copy：NAPI提供的缓冲区转换接口，核心作用：
    // - 从C++的uint8_t数组（photo_data）拷贝数据到ArkTS管理的内存中
    // - 转换后的数据所有权交给ArkTS（后续由ArkTS负责释放内存，不需要C++手动处理）
    // 参数说明：env（环境）、photo_length（数据长度）、photo_data（源数据指针）
    //           nullptr（忽略新缓冲区的内存地址）、&buffer（输出转换后的Buffer对象）
    napi_status status = napi_create_buffer_copy(env, photo_length, photo_data, nullptr, &buffer);

    // 11. 释放C++的内存：数据已经拷贝到ArkTS的Buffer中，自己分配的photo_data可以释放了
    free(photo_data);  // 必须释放！否则会导致内存泄漏（因为photo_data是malloc分配的）

    // 12. 检查Buffer创建是否成功：失败返回null
    if (status != napi_ok) {
        OH_LOG_PrintMsg(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "Failed to create NAPI buffer");
        return nullptr;
    }

    // 13. 返回结果：将NAPI Buffer对象返回给ArkTS（ArkTS侧接收为Buffer类型）
    return buffer;
}

// ###########################################################################
// 关键逻辑总结（帮你彻底搞懂）
// ###########################################################################
/*
1. 数据传递流程（从相机 → C++内部 → ArkTS）：
   相机 → gp_camera_file_get → CameraFile对象（libgphoto2管理）→ 
   gp_file_get_data_and_size提取 → malloc分配独立内存 → memcpy拷贝 → 
   photo_data（DownloadPhoto的变量）→ napi_create_buffer_copy → ArkTS的Buffer

2. 核心传递原理（为什么用二级指针uint8_t** data）：
   - C++中，函数参数默认是"值传递"，普通指针（uint8_t*）只能传递数据，不能修改指针本身的地址
   - 二级指针（uint8_t**）本质是"指针的指针"，可以让InternalDownloadFile内部修改外部指针（photo_data）的地址
   - 简单说：InternalDownloadFile在内部分配内存后，把内存地址通过*data传给photo_data，这样DownloadPhoto就能拿到数据了

3. 返回给ArkTS的数据类型：
   - 是ArkTS的【Buffer类型】（二进制缓冲区），不是普通字符串或对象
   - ArkTS侧可以通过Buffer操作二进制数据，比如：
     - 转成Uint8Array：new Uint8Array(buffer) → 操作单个字节
     - 显示图片：通过Image组件的src属性加载（需配合Blob或Base64转换）
     - 保存文件：通过文件系统API将Buffer写入本地文件（如.jpg格式）
*/