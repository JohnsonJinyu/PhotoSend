//
// Created on 2025/11/5.
//
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".

#include "ltdl.h"
#include "native_common.h"



#include "hilog/log.h"
#include "native_common.h"

#define LOG_DOMAIN 0x0003      // 日志域（自定义标识，区分不同模块日志）
#define LOG_TAG "Camera_device" // 日志标签（日志中显示的模块名）




// ###########################################################################
// 核心函数：相机连接逻辑（libgphoto2核心流程，PTP/IP连接关键）
// ###########################################################################
/**
 * @brief 内部函数：用libgphoto2完成相机初始化（驱动加载→型号匹配→端口配置→连接）
 * @param model 相机型号（如"Nikon Zf"，需与libgphoto2支持列表一致）
 * @param path 相机连接路径（PTP/IP格式："ptpip:192.168.1.1:55740"）
 * @return bool 连接成功返回true，失败返回false
 */
bool InternalConnectCamera(const char *model, const char *path) {
    // 打印日志：标记连接开始，输出传入的型号和路径（调试用）
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "开始连接相机: model=%{public}s, path=%{public}s", model,
                 path);

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

    // OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "加载相机能力列表成功");

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
    CameraAbilities abilities; // 存储相机能力（如支持的功能、协议）
    gp_abilities_list_get_abilities(abilities_list, model_index, &abilities);
    // gp_camera_set_abilities：将能力配置绑定到相机对象（告诉相机"你是这个型号"）
    gp_camera_set_abilities(g_camera, abilities);
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "设置相机能力成功");
    // 释放能力列表（后续不再需要）
    gp_abilities_list_free(abilities_list);

    // 第十三步：加载端口列表（识别设备上可用的端口，如USB、IP）
    GPPortInfoList *port_list = nullptr; // 存储端口信息的列表
    gp_port_info_list_new(&port_list);   // 创建空的端口列表
    // gp_port_info_list_load：从IOLIBS路径加载端口模块，扫描可用端口
    gp_port_info_list_load(port_list);

    // OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "加载端口列表成功");
    //  打印端口总数（确认端口模块加载正常，PTP/IP需要至少1个IP端口）
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "加载端口列表成功，共发现 %{public}d 个端口",
                 gp_port_info_list_count(port_list));

    // 第十四步：筛选IP类型端口（PTP/IP连接必需，排除USB等其他端口）
    GPPortInfo temp_port_info;                           // 临时存储单个端口的信息
    int ip_port_index = -1;                              // 存储IP类型端口的索引（<0=未找到）
    int port_count = gp_port_info_list_count(port_list); // 端口总数

    // 遍历所有端口，找到类型为GP_PORT_IP的端口
    for (int i = 0; i < port_count; i++) {
        // 从列表中获取第i个端口的信息
        int get_info_ret = gp_port_info_list_get_info(port_list, i, &temp_port_info);
        if (get_info_ret != GP_OK) { // 获取端口信息失败，跳过该端口
            OH_LOG_Print(LOG_APP, LOG_WARN, LOG_DOMAIN, LOG_TAG, "获取端口 %{public}d 信息失败", i);
            continue;
        }

        // 检查端口类型是否为GP_PORT_IP（PTP/IP连接必需类型）
        GPPortType port_type;
        gp_port_info_get_type(temp_port_info, &port_type); // 获取端口类型
        if (port_type == GP_PORT_IP) {
            ip_port_index = i; // 记录IP端口的索引
            OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "找到IP类型端口，索引: %{public}d", ip_port_index);
            break; // 找到第一个IP端口即可，无需继续遍历
        }
    }

    // 校验是否找到IP端口（PTP/IP连接必需，没找到则返回失败）
    if (ip_port_index == -1) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "端口列表中无GP_PORT_IP类型端口，无法进行PTP/IP连接");
        gp_port_info_list_free(port_list); // 释放端口列表
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
    GPPortInfo port_info; // 存储目标端口的详细信息
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
// 工具函数：检查相机是否处于连接状态（内部逻辑）
// ###########################################################################
/**
 * @brief 内部函数：判断相机是否有效连接（避免仅依赖g_connected的误判）
 * @return bool 有效连接返回true，无效返回false
 */
bool IsCameraConnected() {
    // 1. 基础连接标志检查
    if (!g_connected) {
        return false;
    }
    // 2. 相机句柄有效性检查
    if (!g_camera) {
        g_connected = false;
        return false;
    }
    // 3. 强校验：读取电量配置（通过配置树遍历）
    CameraWidget *rootConfig = nullptr;
    int result = gp_camera_get_config(g_camera, &rootConfig, g_context);
    if (result != GP_OK) {
        g_connected = false;
        return false;
    }

    CameraWidget *batteryWidget = nullptr;
    result = gp_widget_get_child_by_name(rootConfig, "batterylevel", &batteryWidget);
    if (result != GP_OK || !batteryWidget) {
        gp_widget_free(rootConfig); // 释放配置树资源
        g_connected = false;
        return false;
    }

    gp_widget_free(rootConfig); // 释放配置树资源
    // 4. 补充设备能力检查（增强鲁棒性）
    CameraAbilities abilities;
    result = gp_camera_get_abilities(g_camera, &abilities);
    if (result != GP_OK) {
        g_connected = false;
        return false;
    }
    return true;
}