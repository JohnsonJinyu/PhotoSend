// ###########################################################################
// 1. 头文件引入：依赖库的核心接口定义
// ###########################################################################
// 基础内存/字符串操作库
#include <cstddef>
#include <cstdlib>
#include <cstring>
#include <string>
// NAPI头文件：ArkTS与C++交互的核心接口（定义数据类型、函数调用规则）
#include <napi/native_api.h>
#include "napi/native_api.h"
// libgphoto2头文件：相机操作核心接口（相机对象、文件、配置、端口管理）
#include <gphoto2/gphoto2.h>
#include <gphoto2/gphoto2-camera.h>
#include <gphoto2/gphoto2-file.h>
#include <gphoto2/gphoto2-widget.h>
// ltdl头文件：动态库加载器（加载相机驱动、端口模块）
#include <ltdl.h>
// HarmonyOS日志头文件：打印调试信息
#include <hilog/log.h>


// ###########################################################################
// 2. 宏定义：日志配置（固定格式，方便定位日志来源）
// ###########################################################################
#define LOG_DOMAIN 0x0001    // 日志域（自定义标识，区分不同模块日志）
#define LOG_TAG "NativeCamera"  // 日志标签（日志中显示的模块名）


// ###########################################################################
// 3. 全局变量：跨函数共享相机状态（避免重复创建/泄漏，需谨慎管理）
// ###########################################################################
// 相机对象指针：指向已初始化的相机实例（nullptr = 未连接）
// （libgphoto2中，Camera是所有相机操作的核心载体）
static Camera *g_camera = nullptr;
// 相机上下文指针：管理相机操作的环境（内存、线程、错误回调等）
// （所有libgphoto2函数都需要传入上下文，确保线程安全和资源跟踪）
static GPContext *g_context = nullptr;
// 连接状态标记：true = 已连接，false = 未连接（简化状态判断）
static bool g_connected = false;

// 动态库路径：存储ArkTS层传入的"驱动/端口模块"存放路径（如/data/storage/.../arm64）
static std::string g_camLibDir;


// ###########################################################################
// 4. 工具函数：NAPI数据类型转换（C++ → ArkTS）
// ###########################################################################
/**
 * @brief 将C语言字符串（const char*）转换为ArkTS可识别的napi_value字符串
 * @param env NAPI环境（每个NAPI函数都需要，关联ArkTS上下文）
 * @param str 待转换的C字符串（nullptr时返回空字符串）
 * @return napi_value ArkTS侧的字符串对象
 */
static napi_value CreateNapiString(napi_env env, const char *str) {
    napi_value result;  // 存储转换后的ArkTS字符串
    // napi_create_string_utf8：NAPI内置函数，将UTF-8格式C字符串转ArkTS字符串
    // NAPI_AUTO_LENGTH：自动计算字符串长度（无需手动传strlen）
    napi_create_string_utf8(env, str ? str : "", NAPI_AUTO_LENGTH, &result);
    return result;  // 返回给ArkTS层
}


// ###########################################################################
// 5. NAPI接口：从ArkTS获取动态库路径（驱动/端口模块存放位置）
// ###########################################################################
/**
 * @brief ArkTS层调用此函数，传入设备上"驱动/端口模块"的路径，存到全局变量g_camLibDir
 * @param env NAPI环境
 * @param info NAPI回调信息（包含ArkTS传入的参数）
 * @return napi_value 返回true给ArkTS，标识路径已接收
 */
extern napi_value SetGPhotoLibDirs(napi_env env, napi_callback_info info) {
    size_t argc = 1;          // 期望接收1个参数（动态库路径字符串）
    napi_value args[1];       // 存储ArkTS传入的参数
    // napi_get_cb_info：从回调信息中提取ArkTS传入的参数，存入args数组
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    char camDir[256];         // 缓冲区：存储转换后的C字符串（长度256足够存路径）
    // napi_get_value_string_utf8：将ArkTS字符串参数转C字符串，存入camDir
    napi_get_value_string_utf8(env, args[0], camDir, sizeof(camDir) - 1, nullptr);

    g_camLibDir = camDir;     // 存入全局变量，供后续驱动加载使用
    // 打印日志：确认路径已正确接收（方便调试路径是否正确）
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "g_camLibDir的值为：%{public}s", g_camLibDir.c_str());

    napi_value result;        // 返回结果给ArkTS
    napi_get_boolean(env, true, &result);  // 生成ArkTS的布尔值true
    return result;
}


// ###########################################################################
// 6. 待实现函数：从ArkTS获取相机IP（当前未实现，预留接口）
// ###########################################################################
/**
 * @brief 预留接口：计划从ArkTS获取相机IP，供端口扫描使用
 * @param env NAPI环境
 * @param info NAPI回调信息
 * @return napi_value 暂返回nullptr（未实现）
 */
static napi_value GetCameraIp(napi_env env, napi_callback_info info) {
    return nullptr;  // 待后续实现IP获取逻辑
}


// ###########################################################################
// 7. 核心函数：相机连接逻辑（libgphoto2核心流程，PTP/IP连接关键）
// ###########################################################################
/**
 * @brief 内部函数：用libgphoto2完成相机初始化（驱动加载→型号匹配→端口配置→连接）
 * @param model 相机型号（如"Nikon Zf"，需与libgphoto2支持列表一致）
 * @param path 相机连接路径（PTP/IP格式："ptpip:192.168.1.1:55740"）
 * @return bool 连接成功返回true，失败返回false
 */
static bool InternalConnectCamera(const char *model, const char *path) {
    // 打印日志：标记连接开始，输出传入的型号和路径（调试用）
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "开始连接相机: model=%{public}s, path=%{public}s", model, path);

    // 第一步：释放已有连接资源（避免重复连接导致内存泄漏）
    if (g_camera || g_context) {
        OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "释放已有连接资源");
        if (g_camera) {
            // gp_camera_exit：通知相机结束当前会话（关闭端口、释放相机侧资源）
            gp_camera_exit(g_camera, g_context);
        }
        if (g_camera) {
            // gp_camera_unref：减少相机对象引用计数（计数为0时自动释放内存）
            gp_camera_unref(g_camera);
        }
        if (g_context) {
            // gp_context_unref：减少上下文引用计数（同上，避免内存泄漏）
            gp_context_unref(g_context);
        }
        // 指针置空：避免悬空指针（防止后续误判为有效对象）
        g_camera = nullptr;
        g_context = nullptr;
    }

    // 第二步：创建libgphoto2上下文（所有相机操作的基础环境）
    g_context = gp_context_new();
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "创建上下文成功");

    // 第三步：创建相机对象（Camera是相机操作的核心载体）
    gp_camera_new(&g_camera);
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "创建相机对象成功");

    // 第四步：初始化"相机能力列表"（存储libgphoto2支持的所有相机型号）
    CameraAbilitiesList *abilities_list = nullptr;
    // gp_abilities_list_new：创建空的能力列表对象
    gp_abilities_list_new(&abilities_list);

    // 第五步：初始化动态库加载器ltdl（加载相机驱动、端口模块必需）
    // ltdl是libtool的动态库加载工具，libgphoto2依赖它加载插件
    int ltdl_init_ret = lt_dlinit();
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "ltdl初始化结果: %{public}d（0=成功）", ltdl_init_ret);
    // 初始化失败直接返回（后续无法加载驱动）
    if (ltdl_init_ret != 0) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "ltdl初始化失败: %{public}s", lt_dlerror());
        return false;
    }

    // 第六步：设置环境变量（告诉libgphoto2驱动和端口模块的路径）
    // CAMLIBS：相机驱动路径（如ptp2.so存放位置）
    setenv("CAMLIBS", g_camLibDir.c_str(), 1);
    // IOLIBS：端口模块路径（如ptpip.so存放位置，PTP/IP连接必需）
    setenv("IOLIBS", g_camLibDir.c_str(), 1);

    // 打印CAMLIBS路径（确认环境变量设置正确）
    const char *camlibs_value = getenv("CAMLIBS");
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "CAMLIBS的默认值为: %{public}s", camlibs_value);

    // 第七步：加载相机能力列表（从CAMLIBS路径加载驱动，识别支持的相机型号）
    // gp_abilities_list_load：扫描驱动，将支持的相机型号存入abilities_list
    // 返回值：成功加载的驱动模块数量（0=未加载到驱动，正数=加载成功数量）
    int load_ret = gp_abilities_list_load(abilities_list, g_context);

    // 第八步：检查ltdl加载驱动时是否有错误（辅助调试驱动加载问题）
    const char *err = lt_dlerror();
    if (err) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "ltdl查找驱动时错误: %{public}s", err);
    } else {
        OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "ltdl查找驱动无错误");
    }

    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "加载相机能力列表成功");

    // 第九步：校验能力列表加载结果（失败则释放资源返回）
    if (load_ret != GP_OK) {
        // gp_result_as_string：将libgphoto2错误码转成可读字符串（方便定位问题）
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "能力列表加载失败！错误码：%{public}d，原因：%{public}s",
                     load_ret, gp_result_as_string(load_ret));
        // 释放能力列表内存（避免泄漏）
        gp_abilities_list_free(abilities_list);
        return false;
    }
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "加载相机能力列表成功（真实返回值：%{public}d）", load_ret);

    // 第十步：打印支持的相机总数（调试用，确认驱动加载正常）
    int abilities_count = gp_abilities_list_count(abilities_list);
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "支持的相机型号总数: %{public}d", abilities_count);

    // 第十一步：查找指定相机型号在能力列表中的索引（匹配传入的model）
    // gp_abilities_list_lookup_model：根据型号名查找索引（<0=未找到）
    int model_index = gp_abilities_list_lookup_model(abilities_list, model);
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "查找型号索引: %{public}d", model_index);
    // 型号未找到（驱动不支持该相机），释放资源返回
    if (model_index < 0) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "找不到相机型号: %{public}s", model);
        gp_abilities_list_free(abilities_list);
        return false;
    }

    // 第十二步：获取指定型号的能力配置，并设置到相机对象
    CameraAbilities abilities;  // 存储相机能力（如支持的功能、协议）
    // gp_abilities_list_get_abilities：从列表中获取指定索引的相机能力
    gp_abilities_list_get_abilities(abilities_list, model_index, &abilities);
    // gp_camera_set_abilities：将能力配置绑定到相机对象（告诉相机"你是这个型号"）
    gp_camera_set_abilities(g_camera, abilities);
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "设置相机能力成功");
    // 释放能力列表（后续不再需要）
    gp_abilities_list_free(abilities_list);

    // 第十三步：加载端口列表（识别设备上可用的端口，如USB、IP）
    GPPortInfoList *port_list = nullptr;  // 存储端口信息的列表
    gp_port_info_list_new(&port_list);    // 创建空的端口列表
    // gp_port_info_list_load：从IOLIBS路径加载端口模块，扫描可用端口
    gp_port_info_list_load(port_list);

    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "加载端口列表成功");
    // 打印端口总数（确认端口模块加载正常，PTP/IP需要至少1个IP端口）
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "加载端口列表成功，共发现 %{public}d 个端口",
                 gp_port_info_list_count(port_list));

    // 第十四步：筛选IP类型端口（PTP/IP连接必需，排除USB等其他端口）
    GPPortInfo temp_port_info;  // 临时存储单个端口的信息
    int ip_port_index = -1;     // 存储IP类型端口的索引（<0=未找到）
    int port_count = gp_port_info_list_count(port_list);  // 端口总数

    // 遍历所有端口，找到类型为GP_PORT_IP的端口
    for (int i = 0; i < port_count; i++) {
        // 从列表中获取第i个端口的信息
        int get_info_ret = gp_port_info_list_get_info(port_list, i, &temp_port_info);
        if (get_info_ret != GP_OK) {  // 获取端口信息失败，跳过该端口
            OH_LOG_Print(LOG_APP, LOG_WARN, LOG_DOMAIN, LOG_TAG, "获取端口 %{public}d 信息失败", i);
            continue;
        }

        // 检查端口类型是否为GP_PORT_IP（PTP/IP连接必需类型）
        GPPortType port_type;
        gp_port_info_get_type(temp_port_info, &port_type);  // 获取端口类型
        if (port_type == GP_PORT_IP) {
            ip_port_index = i;  // 记录IP端口的索引
            OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "找到IP类型端口，索引: %{public}d", ip_port_index);
            break;  // 找到第一个IP端口即可，无需继续遍历
        }
    }

    // 校验是否找到IP端口（PTP/IP连接必需，没找到则返回失败）
    if (ip_port_index == -1) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "端口列表中无GP_PORT_IP类型端口，无法进行PTP/IP连接");
        gp_port_info_list_free(port_list);  // 释放端口列表
        return false;
    }

    // 第十五步：查找传入的"PTP/IP路径"在端口列表中的索引
    // gp_port_info_list_lookup_path：根据路径（如ptpip:192.168.1.1）查找端口索引
    int port_index = gp_port_info_list_lookup_path(port_list, path);
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "查找端口索引: %{public}d", port_index);
    // 路径未找到（可能路径格式错误），释放资源返回
    if (port_index < 0) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "找不到端口路径: %{public}s", path);
        gp_port_info_list_free(port_list);
        return false;
    }

    // 第十六步：获取端口信息，并设置到相机对象
    GPPortInfo port_info;  // 存储目标端口的详细信息
    // 从列表中获取指定索引的端口信息
    gp_port_info_list_get_info(port_list, port_index, &port_info);
    // 将端口信息绑定到相机对象（告诉相机"用这个端口连接"）
    gp_camera_set_port_info(g_camera, port_info);
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "设置端口信息成功");
    // 释放端口列表（后续不再需要）
    gp_port_info_list_free(port_list);

    // 第十七步：初始化相机连接（核心步骤，建立与相机的实际通信）
    // gp_camera_init：libgphoto2核心函数，完成相机握手、协议初始化
    int ret = gp_camera_init(g_camera, g_context);
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "初始化相机返回值: %{public}d", ret);
    // 连接失败（如相机未开机、网络不通），更新状态返回
    if (ret != GP_OK) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "相机初始化失败，错误码: %{public}d", ret);
        g_connected = false;
        return false;
    }

    // 第十八步：连接成功，更新全局状态
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "相机连接成功");
    g_connected = true;
    return true;
}


// ###########################################################################
// 8. 核心函数：触发相机拍照（内部逻辑，不直接暴露给ArkTS）
// ###########################################################################
/**
 * @brief 内部函数：触发已连接的相机拍照，并返回照片在相机中的存储路径
 * @param outFolder 输出参数：存储照片的文件夹路径（如"/store_00010001/DCIM/100NIKON"）
 * @param outFilename 输出参数：照片文件名（如"DSC_0001.JPG"）
 * @return bool 拍照成功返回true，失败返回false
 */
static bool InternalCapture(char *outFolder, char *outFilename) {
    // 未连接相机，直接返回失败
    if (!g_connected)
        return false;

    // CameraFilePath：libgphoto2结构体，存储相机中文件的路径（文件夹+文件名）
    CameraFilePath path;

    // 调用libgphoto2拍照函数：gp_camera_capture
    // 参数1：已连接的相机对象
    // 参数2：拍摄类型（GP_CAPTURE_IMAGE = 静态照片，还有视频、音频等类型）
    // 参数3：输出参数，存储拍照后的文件路径
    // 参数4：上下文对象
    int ret = gp_camera_capture(g_camera, GP_CAPTURE_IMAGE, &path, g_context);

    // 拍照失败（如相机忙、无存储空间），返回false
    if (ret != GP_OK)
        return false;

    // 将相机返回的路径拷贝到输出参数（供后续下载使用）
    strcpy(outFolder, path.folder);    // 拷贝文件夹路径
    strcpy(outFilename, path.name);    // 拷贝文件名
    return true;  // 拍照成功
}


// ###########################################################################
// 9. 核心函数：从相机下载照片（内部逻辑，不直接暴露给ArkTS）
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
        gp_file_unref(file);  // 减少引用计数，释放内存
        return false;
    }

    // 从CameraFile中提取二进制数据和大小
    const char *fileData = nullptr;    // 临时存储文件数据（const，不可修改）
    unsigned long fileSize = 0;        // 临时存储文件大小（libgphoto2用unsigned long）
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

    return true;  // 下载成功
}


// ###########################################################################
// 10. NAPI接口：断开相机连接（暴露给ArkTS调用）
// ###########################################################################
/**
 * @brief ArkTS层调用此函数，断开相机连接并释放所有资源
 * @param env NAPI环境
 * @param info NAPI回调信息
 * @return napi_value 返回true给ArkTS，标识已断开
 */
static napi_value Disconnect(napi_env env, napi_callback_info info) {
    // 若相机对象存在，先结束会话并释放
    if (g_camera) {
        // gp_camera_exit：通知相机结束连接（关闭端口、清理会话）
        gp_camera_exit(g_camera, g_context);
        // gp_camera_unref：释放相机对象（引用计数为0时自动销毁）
        gp_camera_unref(g_camera);
        g_camera = nullptr;  // 指针置空，避免悬空
    }
    // 若上下文对象存在，释放上下文
    if (g_context) {
        gp_context_unref(g_context);  // 释放上下文
        g_context = nullptr;          // 指针置空
    }
    // 更新连接状态为未连接
    g_connected = false;

    // 返回true给ArkTS
    napi_value result;
    napi_get_boolean(env, true, &result);
    return result;
}


// ###########################################################################
// 11. 工具函数：检查相机是否处于连接状态（内部逻辑）
// ###########################################################################
/**
 * @brief 内部函数：判断相机是否有效连接（避免仅依赖g_connected的误判）
 * @return bool 有效连接返回true，无效返回false
 */
static bool IsCameraConnected() {
    // 相机/上下文对象为空，直接判定为未连接
    if (!g_camera || !g_context)
        return false;
    // 调用gp_camera_get_summary：尝试获取相机摘要信息（测试通信是否正常）
    // 若返回GP_OK，说明连接有效；否则为无效连接
    return (gp_camera_get_summary(g_camera, nullptr, g_context) == GP_OK);
}


// ###########################################################################
// 12. NAPI接口：检查相机连接状态（暴露给ArkTS调用）
// ###########################################################################
/**
 * @brief ArkTS层调用此函数，获取当前相机连接状态
 * @param env NAPI环境
 * @param info NAPI回调信息
 * @return napi_value 返回布尔值给ArkTS（true=已连接，false=未连接）
 */
static napi_value IsCameraConnectedNapi(napi_env env, napi_callback_info info) {
    // 调用内部函数获取连接状态
    bool connected = IsCameraConnected();

    // 转换为ArkTS的布尔值并返回
    napi_value result;
    napi_get_boolean(env, connected, &result);
    return result;
}


// ###########################################################################
// 13. NAPI接口：连接相机（暴露给ArkTS调用，封装InternalConnectCamera）
// ###########################################################################
/**
 * @brief ArkTS层调用此函数，传入相机型号和PTP/IP路径，触发连接
 * @param env NAPI环境
 * @param info NAPI回调信息（包含2个参数：型号、路径）
 * @return napi_value 返回布尔值给ArkTS（true=连接成功，false=失败）
 */
static napi_value ConnectCamera(napi_env env, napi_callback_info info) {
    size_t argc = 2;          // 期望接收2个参数（型号、路径）
    napi_value args[2];       // 存储ArkTS传入的参数
    // 提取ArkTS传入的参数
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    char model[128] = {0};    // 缓冲区：存储相机型号（如"Nikon Zf"）
    char path[128] = {0};     // 缓冲区：存储PTP/IP路径（如"ptpip:192.168.1.1:55740"）

    // 将ArkTS参数转换为C字符串
    napi_get_value_string_utf8(env, args[0], model, sizeof(model) - 1, nullptr);
    napi_get_value_string_utf8(env, args[1], path, sizeof(path) - 1, nullptr);

    // 调用内部连接函数，传入型号和路径
    bool success = InternalConnectCamera(model, path);

    // 转换结果为ArkTS布尔值并返回
    napi_value result;
    napi_get_boolean(env, success, &result);
    return result;
}


// ###########################################################################
// 14. NAPI接口：触发拍照（暴露给ArkTS调用，封装InternalCapture）
// ###########################################################################
/**
 * @brief ArkTS层调用此函数，触发相机拍照，并返回照片路径信息
 * @param env NAPI环境
 * @param info NAPI回调信息
 * @return napi_value 返回ArkTS对象（包含success、folder、name三个属性）
 */
static napi_value TakePhoto(napi_env env, napi_callback_info info) {
    // 缓冲区：存储拍照后的文件夹路径和文件名
    char folder[128] = {0};
    char name[128] = {0};

    // 调用内部拍照函数
    bool success = InternalCapture(folder, name);

    // 创建ArkTS对象：用于返回多个结果（success、folder、name）
    napi_value result;
    napi_create_object(env, &result);

    // 给对象添加属性：success（拍照是否成功）
    napi_set_named_property(env, result, "success", CreateNapiString(env, success ? "true" : "false"));
    // 给对象添加属性：folder（照片在相机中的文件夹路径）
    napi_set_named_property(env, result, "folder", CreateNapiString(env, folder));
    // 给对象添加属性：name（照片在相机中的文件名）
    napi_set_named_property(env, result, "name", CreateNapiString(env, name));

    // 返回对象给ArkTS（ArkTS侧可通过result.folder获取路径）
    return result;
}


// ###########################################################################
// 15. NAPI接口：下载照片（暴露给ArkTS调用，封装InternalDownloadFile）
// ###########################################################################
/**
 * @brief ArkTS层调用此函数，传入照片路径，下载照片并返回二进制数据
 * @param env NAPI环境
 * @param info NAPI回调信息（包含2个参数：folder、name）
 * @return napi_value 返回ArkTS的Buffer（存储照片二进制数据），失败返回nullptr
 */
static napi_value DownloadPhoto(napi_env env, napi_callback_info info) {
    size_t argc = 2;          // 期望接收2个参数（文件夹路径、文件名）
    napi_value args[2];       // 存储ArkTS传入的参数
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
    size_t length = 0;        // 存储数据长度

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


// ###########################################################################
// 16. 核心函数：设置相机参数（内部逻辑，如闪光灯、ISO等）
// ###########################################################################
/**
 * @brief 内部函数：设置相机的配置参数（如闪光灯模式、ISO、白平衡等）
 * @param key 参数名（如"flash"=闪光灯，"iso"=ISO，需与libgphoto2参数名一致）
 * @param value 参数值（如"on"=闪光灯开启，"400"=ISO400）
 * @return bool 设置成功返回true，失败返回false
 */
static bool SetConfig(const char *key, const char *value) {
    // 未连接相机，直接返回失败
    if (!g_connected)
        return false;

    // CameraWidget：libgphoto2结构体，存储相机配置参数（树形结构，如root→flash→on）
    CameraWidget *root = nullptr;

    // 获取相机的配置树（root为根节点，包含所有可配置参数）
    gp_camera_get_config(g_camera, &root, g_context);

    // CameraWidget *child：存储目标参数节点（如"flash"节点）
    CameraWidget *child = nullptr;

    // 在配置树中根据参数名查找目标节点
    if (gp_widget_get_child_by_name(root, key, &child) != GP_OK) {
        gp_widget_free(root);  // 未找到节点，释放配置树
        return false;
    }

    // 设置目标节点的参数值（如将"flash"节点的值设为"on"）
    gp_widget_set_value(child, value);
    // 将修改后的配置树应用到相机（实际生效）
    int ret = gp_camera_set_config(g_camera, root, g_context);

    // 释放配置树内存（避免泄漏）
    gp_widget_free(root);

    // 返回设置结果（GP_OK=成功）
    return (ret == GP_OK);
}


// ###########################################################################
// 17. NAPI接口：设置相机参数（暴露给ArkTS调用，封装SetConfig）
// ###########################################################################
/**
 * @brief ArkTS层调用此函数，传入参数名和值，设置相机配置
 * @param env NAPI环境
 * @param info NAPI回调信息（包含2个参数：key、value）
 * @return napi_value 返回布尔值给ArkTS（true=设置成功，false=失败）
 */
static napi_value SetCameraParameter(napi_env env, napi_callback_info info) {
    size_t argc = 2;          // 期望接收2个参数（key、value）
    napi_value args[2];       // 存储ArkTS传入的参数
    // 提取ArkTS传入的参数
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    // 缓冲区：存储转换后的C字符串参数
    char key[128] = {0};
    char value[128] = {0};

    // 将ArkTS参数转换为C字符串
    napi_get_value_string_utf8(env, args[0], key, sizeof(key) - 1, nullptr);
    napi_get_value_string_utf8(env, args[1], value, sizeof(value) - 1, nullptr);

    // 调用内部设置函数
    bool success = SetConfig(key, value);

    // 转换结果为ArkTS布尔值并返回
    napi_value result;
    napi_get_boolean(env, success, &result);
    return result;
}


// ###########################################################################
// 18. 核心函数：获取相机实时预览（内部逻辑，如取景框画面）
// ###########################################################################
/**
 * @brief 内部函数：获取相机实时预览画面（二进制数据，通常为JPEG格式）
 * @param data 输出参数：指向预览数据（需调用者后续free释放）
 * @param length 输出参数：预览数据长度（字节数）
 * @return bool 获取成功返回true，失败返回false
 */
static bool GetPreview(uint8_t **data, size_t *length) {
    // 未连接相机，直接返回失败
    if (!g_connected)
        return false;

    // CameraFile：存储预览数据（预览通常是压缩后的小尺寸图片）
    CameraFile *file = nullptr;

    // 创建空的CameraFile对象
    gp_file_new(&file);

    // 调用libgphoto2预览函数：gp_camera_capture_preview
    // 实时获取相机取景框画面（非拍照，无存储）
    int ret = gp_camera_capture_preview(g_camera, file, g_context);

    // 获取预览失败，释放CameraFile并返回false
    if (ret != GP_OK) {
        gp_file_unref(file);
        return false;
    }

    // 从CameraFile中提取预览数据和大小
    const char *previewData = nullptr;
    unsigned long previewSize = 0;
    gp_file_get_data_and_size(file, &previewData, &previewSize);

    // 分配内存存储预览数据
    *data = (uint8_t *)malloc(previewSize);
    // 拷贝数据到分配的内存
    memcpy(*data, previewData, previewSize);
    // 设置数据长度
    *length = previewSize;

    // 释放CameraFile对象
    gp_file_unref(file);

    return true;  // 获取预览成功
}


// ###########################################################################
// 19. NAPI接口：获取相机预览（暴露给ArkTS调用，封装GetPreview）
// ###########################################################################
/**
 * @brief ArkTS层调用此函数，获取相机实时预览画面
 * @param env NAPI环境
 * @param info NAPI回调信息
 * @return napi_value 返回ArkTS的Buffer（预览数据），失败返回nullptr
 */
static napi_value GetPreviewNapi(napi_env env, napi_callback_info info) {
    // 指针：存储预览数据
    uint8_t *data = nullptr;
    size_t length = 0;        // 预览数据长度

    // 调用内部获取预览函数
    bool success = GetPreview(&data, &length);

    // 失败或无数据，返回nullptr
    if (!success || data == nullptr || length == 0)
        return nullptr;

    // 创建ArkTS Buffer，拷贝预览数据
    napi_value buffer;
    napi_create_buffer_copy(env, length, data, nullptr, &buffer);

    // 释放C++内存
    free(data);

    // 返回Buffer给ArkTS（ArkTS侧可渲染为预览画面）
    return buffer;
}


// ###########################################################################
// 20. NAPI模块注册：将C++函数映射为ArkTS可调用的接口（关键步骤）
// ###########################################################################
// EXTERN_C_START/EXTERN_C_END：确保函数按C语言规则编译（避免C++名称修饰）
// （NAPI框架依赖C语言函数名查找接口，C++会修改函数名，导致找不到）
EXTERN_C_START
/**
 * @brief 模块初始化函数：so库被加载时，NAPI框架自动调用此函数
 * @param env NAPI环境
 * @param exports ArkTS侧的"module.exports"对象（用于挂载接口）
 * @return napi_value 返回挂载好接口的exports对象
 */
static napi_value Init(napi_env env, napi_value exports) {
    // napi_property_descriptor：NAPI结构体，定义"ArkTS函数名→C++函数"的映射关系
    napi_property_descriptor api_list[] = {
        // 格式：{ArkTS侧函数名, 无, C++侧函数名, 无, 无, 无, 默认行为, 无}
        {"SetGPhotoLibDirs", nullptr, SetGPhotoLibDirs, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"ConnectCamera", nullptr, ConnectCamera, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"Disconnect", nullptr, Disconnect, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"IsCameraConnected", nullptr, IsCameraConnectedNapi, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"TakePhoto", nullptr, TakePhoto, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"DownloadPhoto", nullptr, DownloadPhoto, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"SetCameraParameter", nullptr, SetCameraParameter, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"GetPreview", nullptr, GetPreviewNapi, nullptr, nullptr, nullptr, napi_default, nullptr},
    };

    // 将接口映射表挂载到exports对象（ArkTS侧通过import获取这些函数）
    napi_define_properties(
        env,                                    // NAPI环境
        exports,                                // 目标对象（module.exports）
        sizeof(api_list) / sizeof(api_list[0]), // 接口数量（自动计算，避免硬编码）
        api_list                                // 接口映射表
    );

    // 打印日志：确认模块初始化成功
    OH_LOG_PrintMsg(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "InitModule: NativeCamera模块初始化成功");
    return exports;  // 返回exports给NAPI框架
}
EXTERN_C_END


// ###########################################################################
// 21. NAPI模块信息：定义模块的基本属性（ArkTS侧识别模块的关键）
// ###########################################################################
static napi_module cameraModule = {
    .nm_version = 1,          // NAPI模块版本（固定为1）
    .nm_flags = 0,            // 标志位（0=默认，无特殊配置）
    .nm_filename = nullptr,   // 模块文件名（可选，通常为nullptr）
    .nm_register_func = Init, // 模块初始化函数（指向上面的Init函数）
    .nm_modname = "entry",    // 模块名（必须与ArkTS工程的oh-package.json5中"name"一致）
    .nm_priv = ((void *)0),   // 私有数据（无特殊需求时为nullptr）
    .reserved = {0},          // 保留字段（必须为0）
};


// ###########################################################################
// 22. 模块注册入口：so库加载时自动注册NAPI模块
// ###########################################################################
/**
 * @brief 构造函数属性（__attribute__((constructor))）：so库被加载时自动执行
 * 作用：将上面定义的cameraModule注册到NAPI框架，让ArkTS能找到模块
 */
extern "C" __attribute__((constructor)) void RegisterEntryModule(void) {
    // napi_module_register：NAPI框架函数，注册模块
    napi_module_register(&cameraModule);
}