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
 * @brief 内部函数：根据"相机中的文件路径"，下载照片到内存，并返回二进制数据
 * @param folder 照片在相机中的文件夹路径（如InternalCapture返回的outFolder）
 * @param filename 照片在相机中的文件名（如InternalCapture返回的outFilename）
 * @param data 输出参数：指向下载后的二进制数据（需调用者后续free释放）
 * @param length 输出参数：下载数据的长度（字节数，即照片大小）
 * @return bool 下载成功返回true，失败返回false
 */
static bool InternalDownloadFile(const char *folder, const char *filename, uint8_t **data, size_t *length) {
    // 未连接相机，直接返回失败
    if (!g_connected)
        return false;

    // CameraFile：libgphoto2结构体，存储从相机下载的文件数据（二进制+元信息）
    CameraFile *file = nullptr;

    // 创建空的CameraFile对象（用于存放下载的数据）
    gp_file_new(&file);

    // 调用libgphoto2文件下载函数：gp_camera_file_get
    // 参数1：已连接的相机对象
    // 参数2：文件夹路径（相机中）
    // 参数3：文件名（相机中）
    // 参数4：文件类型（GP_FILE_TYPE_NORMAL = 原始文件，还有缩略图、元数据等类型）
    // 参数5：存储下载数据的CameraFile对象
    // 参数6：上下文对象
    int ret = gp_camera_file_get(g_camera, folder, filename, GP_FILE_TYPE_NORMAL, file, g_context);

    // 下载失败，释放CameraFile并返回false
    if (ret != GP_OK) {
        gp_file_unref(file); // 减少引用计数，释放内存
        return false;
    }

    // 从CameraFile中提取二进制数据和大小
    const char *fileData = nullptr; // 临时存储文件数据（const，不可修改）
    unsigned long fileSize = 0;     // 临时存储文件大小（libgphoto2用unsigned long）
    // gp_file_get_data_and_size：获取文件的二进制数据指针和大小
    gp_file_get_data_and_size(file, &fileData, &fileSize);

    // 在堆上分配内存，存储下载的数据（供调用者使用）
    *data = (uint8_t *)malloc(fileSize);
    // 将CameraFile中的数据拷贝到分配的内存中
    memcpy(*data, fileData, fileSize);
    // 设置输出参数：数据长度（转换为size_t类型，符合C++标准）
    *length = fileSize;

    // 释放CameraFile对象（不再需要，避免内存泄漏）
    gp_file_unref(file);

    return true; // 下载成功
}




// ###########################################################################
// NAPI接口：下载照片（暴露给ArkTS调用，封装InternalDownloadFile）
// ###########################################################################
/**
 * @brief ArkTS层调用此函数，传入照片路径，下载照片并返回二进制数据
 * @param env NAPI环境
 * @param info NAPI回调信息（包含2个参数：folder、name）
 * @return napi_value 返回ArkTS的Buffer（存储照片二进制数据），失败返回nullptr
 */
napi_value DownloadPhoto(napi_env env, napi_callback_info info) {
    size_t argc = 2;    // 期望接收2个参数（文件夹路径、文件名）
    napi_value args[2]; // 存储ArkTS传入的参数
    // 提取ArkTS传入的参数
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    // 缓冲区：存储转换后的C字符串路径
    char folder[128] = {0};
    char name[128] = {0};

    // 将ArkTS参数转换为C字符串
    napi_get_value_string_utf8(env, args[0], folder, sizeof(folder) - 1, nullptr);
    napi_get_value_string_utf8(env, args[1], name, sizeof(name) - 1, nullptr);

    // 指针：存储下载后的二进制数据（需手动free）
    uint8_t *data = nullptr;
    size_t length = 0; // 存储数据长度

    // 调用内部下载函数
    bool success = InternalDownloadFile(folder, name, &data, &length);

    // 下载失败或无数据，返回nullptr给ArkTS
    if (!success || data == nullptr || length == 0) {
        return nullptr;
    }

    // 创建ArkTS的Buffer：将C++的二进制数据转成ArkTS可操作的Buffer
    // napi_create_buffer_copy：拷贝数据到ArkTS管理的内存（后续无需C++手动释放）
    napi_value buffer;
    napi_create_buffer_copy(env, length, data, nullptr, &buffer);

    // 释放C++堆上的内存（数据已拷贝到ArkTS Buffer，此处需释放避免泄漏）
    free(data);

    // 返回Buffer给ArkTS（ArkTS侧可通过Buffer转成图片显示）
    return buffer;
}



