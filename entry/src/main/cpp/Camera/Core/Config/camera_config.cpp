// camera_config.cpp
// Created on 2025/11/9.
//
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".

#include "../../Common/native_common.h"
#include <map>
#include <unistd.h>
#include <vector>
#include <napi/native_api.h>
#include "Camera/Common/Constants.h"
#include "hilog/log.h"
#include "camera_config.h"
#include <Camera/Core/Device/NapiDeviceInterface.h>


#define LOG_DOMAIN ModuleLogs::CameraConfig.domain      // 日志域（自定义标识，区分不同模块日志）
#define LOG_TAG ModuleLogs::CameraConfig.tag            // 日志标签（日志中显示的模块名）








// 定义全局变量（包含相机所有可选配置的），简言之这个变量就是配置树
std::vector<ConfigItem> g_allConfigItems;

// 全局回调函数指针（需在camera_config.h中声明）
ParamCallback g_paramCallback = nullptr;


// 定义结构体保存回调需要的状态（env和ArkTS回调的引用）
struct CallbackState {
    napi_env env;         // NAPI环境
    napi_ref callbackRef; // ArkTS层回调函数的引用
};

// 全局变量保存状态（简单处理，实际项目可考虑更安全的管理方式）
static CallbackState g_callbackState;



// 标准快门档位（单位：秒），按从小到大排序
const float standardShutterSpeeds[] = {
    1 / 8000.0f, 1 / 6400.0f, 1 / 5000.0f, 1 / 4000.0f, 1 / 3200.0f, 1 / 2500.0f, 1 / 2000.0f, 1 / 1600.0f, 1 / 1250.0f,
    1 / 1000.0f, 1 / 800.0f,  1 / 640.0f,  1 / 500.0f,  1 / 400.0f,  1 / 320.0f,  1 / 250.0f,  1 / 200.0f,  1 / 160.0f,
    1 / 125.0f,  1 / 100.0f,  1 / 80.0f,   1 / 60.0f,   1 / 50.0f,   1 / 40.0f,   1 / 30.0f,   1 / 25.0f,   1 / 20.0f,
    1 / 15.0f,   1 / 12.5f,   1 / 10.0f,   0.125f,      0.166f,      0.2f,        0.25f,       0.3f,        0.4f,
    0.5f,        0.6f,        0.8f,        1.0f,        1.3f,        1.6f,        2.0f,        2.5f,        3.2f,
    4.0f,        5.0f,        6.0f,        8.0f,        10.0f};

// 对应的分数显示（与上面的档位一一对应）
const char *standardShutterLabels[] = {
    "1/8000s", "1/6400s", "1/5000s", "1/4000s", "1/3200s", "1/2500s", "1/2000s", "1/1600s", "1/1250s", "1/1000s",
    "1/800s",  "1/640s",  "1/500s",  "1/400s",  "1/320s",  "1/250s",  "1/200s",  "1/160s",  "1/125s",  "1/100s",
    "1/80s",   "1/60s",   "1/50s",   "1/40s",   "1/30s",   "1/25s",   "1/20s",   "1/15s",   "1/12.5s", "1/10s",
    "1/8s",    "1/6s",    "1/5s",    "1/4s",    "1/3s",    "1/2.5s",  "1/2s",    "0.6s",    "0.8s",    "1s",
    "1.3s",    "1.6s",    "2s",      "2.5s",    "3.2s",    "4s",      "5s",      "6s",      "8s",      "10s"};

// 标准档位数量（需与上面数组长度一致）
const int numStandardShutters = sizeof(standardShutterSpeeds) / sizeof(standardShutterSpeeds[0]);





// 在camera_config.cpp中添加
const std::vector<std::string> DEFAULT_PARAMS_TO_EXTRACT = {
    "iso",               // ISO
    "shutterspeed",      // 快门速度
    "f-number",          // 光圈
    "whitebalance",      // 白平衡
    "focusmode",         // 对焦模式
    "expprogram"         // 曝光程序
};





// 常用参数节点名映射（文字节点名 → 数字节点名，用于fallback）
const std::map<std::string, std::string> COMMON_PARAM_NODE_MAP = {
    {"batterylevel", "5001"},    // 电量
    {"f-number", "5007"},        // 光圈
    {"shutterspeed", "500d"},    // 快门
    {"iso", "500f"},             // ISO
    {"exposurecompensation", "5010"}, // 曝光补偿
    {"focusmode", "500a"},       // 对焦模式
    {"expprogram", "500e"},      // 曝光程序
    {"exposuremetermode", "500b"}, // 测光模式
    {"whitebalance", "5005"},    // 白平衡
    {"capturemode", "5013"}      // 拍摄模式
};

















/**
 * 递归遍历配置树节点，收集参数信息（精简版）
 * 功能：只做必要的节点信息提取，减少冗余日志和重复操作
 */
static void TraverseConfigTree(CameraWidget* widget, std::vector<ConfigItem>& items, const std::string& parentPath) {
    if (!widget) return; // 空节点直接返回

    // 1. 获取节点基础信息（名称、类型）
    const char* name = nullptr;
    if (gp_widget_get_name(widget, &name) != GP_OK || !name) {
        OH_LOG_Print(LOG_APP, LOG_WARN, LOG_DOMAIN, LOG_TAG, "节点名称获取失败");
        return;
    }
    std::string fullPath = parentPath.empty() ? name : parentPath + "/" + name;

    CameraWidgetType type;
    if (gp_widget_get_type(widget, &type) != GP_OK) {
        OH_LOG_Print(LOG_APP, LOG_WARN, LOG_DOMAIN, LOG_TAG, "节点类型获取失败：%s", fullPath.c_str());
        return;
    }

    // 2. 跳过文件夹类型节点（只处理参数节点）
    if (type == GP_WIDGET_SECTION || type == GP_WIDGET_WINDOW) {
        // 递归处理子节点（只传必要参数）
        int childCount = gp_widget_count_children(widget);
        for (int i = 0; i < childCount; ++i) {
            CameraWidget* child = nullptr;
            if (gp_widget_get_child(widget, i, &child) == GP_OK) {
                TraverseConfigTree(child, items, fullPath);
            }
        }
        return;
    }

    // 3. 提取参数节点信息（核心逻辑）
    ConfigItem item;
    item.name = name;
    item.label = [&]() { // 简化标签获取逻辑
        const char* label = nullptr;
        gp_widget_get_label(widget, &label);
        return label ? label : "";
    }();

    // 3.1 转换类型为字符串
    switch (type) {
        case GP_WIDGET_MENU: case GP_WIDGET_RADIO: item.type = "choice"; break;
        case GP_WIDGET_TEXT: item.type = "text"; break;
        case GP_WIDGET_RANGE: item.type = "range"; break;
        case GP_WIDGET_TOGGLE: item.type = "toggle"; break;
        default: item.type = "unknown";
    }

    // 3.2 提取当前值（修正指针类型处理）
    switch (type) {
        case GP_WIDGET_TEXT:
        case GP_WIDGET_MENU:
        case GP_WIDGET_RADIO: {
            const char* val = nullptr; // 正确类型：const char*
            if (gp_widget_get_value(widget, &val) == GP_OK) { // 传递const char*的地址
                item.current = val ? val : ""; // 避免nullptr解引用
            }
            break;
        }
        case GP_WIDGET_RANGE: {
            float val = 0.0f; // 正确类型：float
            if (gp_widget_get_value(widget, &val) == GP_OK) { // 传递float的地址
                item.floatValue = val;
                item.current = std::to_string(val);
                // 提取范围参数
                float bottom, top, step;
                if (gp_widget_get_range(widget, &bottom, &top, &step) == GP_OK) {
                    item.bottomFloat = bottom;
                    item.topFloat = top;
                    item.stepFloat = step;
                }
            }
            break;
        }
        case GP_WIDGET_TOGGLE: {
            int val = 0; // 正确类型：int
            if (gp_widget_get_value(widget, &val) == GP_OK) { // 传递int的地址
                item.intValue = val;
                item.current = std::to_string(val);
            }
            break;
        }
        default:
            item.current = "";
            break;
    }

    // 3.3 提取可选值（仅针对choice类型）
    if (item.type == "choice") {
        int choiceCount = gp_widget_count_choices(widget);
        for (int i = 0; i < choiceCount; ++i) {
            const char* choice = nullptr;
            if (gp_widget_get_choice(widget, i, &choice) == GP_OK && choice) {
                item.choices.push_back(choice);
            }
        }
    }

    items.push_back(item); // 加入结果集
}




/**
 * 通用工具函数：批量提取指定参数的可选值
 * @param paramNames 需要提取的参数名列表（如{"iso", "shutterspeed", "whitebalance"}）
 * @return 键值对：参数名 → 可选值数组
 */
std::unordered_map<std::string, std::vector<std::string>> ExtractParamOptions(const std::vector<std::string>& paramNames) {
    std::unordered_map<std::string, std::vector<std::string>> result;
    if (g_allConfigItems.empty()) {
        OH_LOG_Print(LOG_APP, LOG_WARN, LOG_DOMAIN, LOG_TAG, "配置树为空，无法提取可选值");
        return result;
    }

    /*// 遍历配置树，匹配目标参数并提取可选值
    for (const auto& item : g_allConfigItems) {
        // 检查当前参数是否在需要提取的列表中
        if (std::find(paramNames.begin(), paramNames.end(), item.name) != paramNames.end()) {
            result[item.name] = item.choices; // 存储可选值数组
            OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "提取参数[%{public}s]的可选值，共%{public}d项", 
                        item.name.c_str(), (int)item.choices.size());
        }
    }*/
    
    // 遍历配置树，匹配目标参数并提取可选值
    for (const auto& item : g_allConfigItems) {
        // 检查当前参数是否在需要提取的列表中
        if (std::find(paramNames.begin(), paramNames.end(), item.name) != paramNames.end()) {
            result[item.name] = item.choices; // 存储可选值数组
            OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "提取参数[%{public}s]的可选值，共%{public}d项",
                item.name.c_str(), (int)item.choices.size());
            // 新增：遍历并打印每个可选值
            OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "参数[%{public}s]的可选值如下:", item.name.c_str());
            for (const auto& choice : item.choices) {
                OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, " - %{public}s", choice.c_str());
            }
        }
    }
    
    return result;
}





/**
 * 将提取的参数可选值转换为NAPI格式并推送
 */
void PushParamOptionsToArkTS(const std::unordered_map<std::string, std::vector<std::string>>& options) {
    napi_env env = g_callbackState.env;
    if (!env || g_paramCallback == nullptr) {
        OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "环境或回调为空，无法推送参数选项");
        return;
    }

    // 创建NAPI对象存储所有参数的可选值
    napi_value resultObj;
    napi_create_object(env, &resultObj);

    // 遍历可选值map，转换为NAPI数组并设置到对象中
    for (const auto& pair : options) {
        const std::string& paramName = pair.first;
        const std::vector<std::string>& choices = pair.second;

        // 创建可选值数组
        napi_value choicesArray;
        napi_create_array(env, &choicesArray);
        for (size_t i = 0; i < choices.size(); ++i) {
            napi_value choiceStr = CreateNapiString(env, choices[i].c_str());
            napi_set_element(env, choicesArray, i, choiceStr);
        }

        // 将数组绑定到参数名对应的属性
        napi_value key = CreateNapiString(env, paramName.c_str());
        napi_set_property(env, resultObj, key, choicesArray);
    }

    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "准备推送参数选项到ArkTS");

    // 通过回调推送给ArkTS（需确保回调能处理对象类型）
    g_paramCallback(resultObj);
}



bool GetAllConfigItems(std::vector<ConfigItem>& items) {
    items.clear();
    // 1. 连接检查（前置校验）
    if (!g_connected ||!g_camera ||!g_context) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "相机未连接，无法获取配置");
        return false;
    }

    // 2. 获取配置树根节点（核心资源）
    CameraWidget* root = nullptr;
    int ret = gp_camera_get_config(g_camera, &root, g_context);
    if (ret != GP_OK ||!root) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "获取配置树失败：%s{public}", gp_result_as_string(ret));
        return false;
    }

    // 3. 遍历配置树
    TraverseConfigTree(root, items, "");

    // 确认配置树已填充
    if (items.empty()) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "配置树遍历后仍为空，可能存在问题");
        gp_widget_free(root);
        return false;
    }

    

    // 4. 释放资源（确保无论成败都释放）
    gp_widget_free(root);
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "配置树获取完成，共%{public}d个参数", (int)items.size());
    return true;
}



/**
 * NAPI接口：获取配置树（保持与上层交互的兼容性）
 */
napi_value GetCameraConfig(napi_env env, napi_callback_info info) {
    std::vector<ConfigItem> items;
    bool success = GetAllConfigItems(items);

    napi_value resultArray;
    napi_create_array(env, &resultArray);

    if (success) {
        for (size_t i = 0; i < items.size(); ++i) {
            const ConfigItem& item = items[i];
            napi_value obj;
            napi_create_object(env, &obj);

            // 只设置必要的属性（与ConfigItem对应）
            napi_set_named_property(env, obj, "name", CreateNapiString(env, item.name.c_str()));
            napi_set_named_property(env, obj, "label", CreateNapiString(env, item.label.c_str()));
            napi_set_named_property(env, obj, "type", CreateNapiString(env, item.type.c_str()));
            napi_set_named_property(env, obj, "current", CreateNapiString(env, item.current.c_str()));

            // 可选值列表（仅当有值时添加）
            if (!item.choices.empty()) {
                napi_value choicesArray;
                napi_create_array(env, &choicesArray);
                for (size_t j = 0; j < item.choices.size(); ++j) {
                    napi_set_element(env, choicesArray, j, CreateNapiString(env, item.choices[j].c_str()));
                }
                napi_set_named_property(env, obj, "choices", choicesArray);
            }

            napi_set_element(env, resultArray, i, obj);
        }
    }

    return resultArray;
}










// ###########################################################################
// 新增：工具函数 - 递归查找配置树中的目标节点
// ###########################################################################
/**
 * @brief 递归遍历CameraWidget树，根据节点名查找目标Widget
 * @param root 配置树根节点
 * @param targetName 目标节点名（如"batterylevel"）
 * @param outWidget 输出参数：找到的目标节点（未找到则为nullptr）
 */
static void RecursiveFindWidget(CameraWidget *root, const char *targetName, CameraWidget **outWidget,
                                const char *parentPath) {
    // 终止条件：当前节点为空，或已找到目标节点，直接返回
    if (!root || *outWidget)
        return;

    const char *currentName = nullptr;
    gp_widget_get_name(root, &currentName);
    // 拼接当前节点的完整路径（父路径 + 当前节点名），方便日志定位
    char currentPath[256] = {0};
    snprintf(currentPath, sizeof(currentPath) - 1, "%s/%s", parentPath, currentName ? currentName : "null");

    // 1. 打印当前节点信息（原逻辑保留）
    CameraWidgetType type;
    gp_widget_get_type(root, &type);
    const char *valueStr = "N/A";
    if (type == GP_WIDGET_TEXT) {
        const char *val;
        if (gp_widget_get_value(root, &val) == GP_OK)
            valueStr = val;
    } else if (type == GP_WIDGET_RADIO || type == GP_WIDGET_MENU) {
        const char *val;
        if (gp_widget_get_value(root, &val) == GP_OK)
            valueStr = val;
    } else if (type == GP_WIDGET_TOGGLE) {
        int val;
        if (gp_widget_get_value(root, &val) == GP_OK) {
            static char buf[32];
            snprintf(buf, sizeof(buf), "%d", val);
            valueStr = buf;
        }
    }
    /*OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG,
                 "节点路径：%{public}s，名称：%{public}s，类型：%{public}d，值：%{public}s", currentPath, currentName,
                 type, valueStr);*/

    // 2. 关键补充：检查当前节点是否为目标节点（原逻辑可能缺失，需补充）
    if (currentName && strcmp(currentName, targetName) == 0) {
        *outWidget = root; // 找到目标节点，赋值给输出参数
        return;            // 找到后直接返回，无需继续遍历
    }

    // 3. 关键补充：遍历当前节点的所有子节点（递归核心）
    int childCount = gp_widget_count_children(root); // 获取子节点数量
    for (int i = 0; i < childCount; i++) {           // 循环遍历每个子节点
        CameraWidget *child = nullptr;
        gp_widget_get_child(root, i, &child); // 获取第i个子节点
        // 递归调用自身，处理子节点（父路径传入当前节点的完整路径）
        RecursiveFindWidget(child, targetName, outWidget, currentPath);
        if (*outWidget)
            return; // 若子节点中已找到目标，直接返回
    }
}


/**
 * @brief 内部函数：获取相机所有状态和可调节参数
 * @return CameraInfo 存储所有信息的结构体
 */
CameraInfo InternalGetCameraInfo() {
    CameraInfo info = {0};
    info.isSuccess = false;
    memset(&info, 0, sizeof(CameraInfo)); // 初始化结构体，避免随机值

    // 1. 前置检查：相机必须连接
    if (!g_connected || !g_camera || !g_context) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "获取相机状态失败：相机未连接");
        return info;
    }

    // 2. 获取配置树根节点（仅一次，后续所有参数查找基于此根节点）
    CameraWidget *root = nullptr;
    int ret = gp_camera_get_config(g_camera, &root, g_context);
    if (ret != GP_OK || !root) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "获取配置树失败，错误码：%{public}d", ret);
        return info;
    }

    // ------------------------------
    // 工具函数：查找参数节点（文字节点优先，失败试数字节点）
    // ------------------------------
    auto FindParamWidget = [&](const std::string& textNodeName) -> CameraWidget* {
        CameraWidget* widget = nullptr;
        // 1. 先查文字节点（如"f-number"）
        RecursiveFindWidget(root, textNodeName.c_str(), &widget, "");
        if (widget) return widget;

        // 2. 文字节点查不到，试数字节点（如"5007"）
        auto it = COMMON_PARAM_NODE_MAP.find(textNodeName);
        if (it != COMMON_PARAM_NODE_MAP.end()) {
            const std::string& numNodeName = it->second;
            RecursiveFindWidget(root, numNodeName.c_str(), &widget, "");
            if (widget) {
                OH_LOG_Print(LOG_APP, LOG_WARN, LOG_DOMAIN, LOG_TAG, "文字节点%{public}s未找到，使用数字节点%{public}s", 
                    textNodeName.c_str(), numNodeName.c_str());
            }
        }
        return widget;
    };

    // ------------------------------
    // 3. 逐个获取所有常用参数当前值（按表格顺序）
    // ------------------------------
    CameraWidget* targetWidget = nullptr;

    // 3.1 电量（batterylevel / 5001）
    targetWidget = FindParamWidget("batterylevel");
    if (targetWidget) {
        CameraWidgetType type;
        gp_widget_get_type(targetWidget, &type);
        if (type == GP_WIDGET_TOGGLE) { // 数字节点：1~100（对应百分比）
            int batteryVal = 0;
            if (gp_widget_get_value(targetWidget, &batteryVal) == GP_OK) {
                snprintf(info.batteryLevel, sizeof(info.batteryLevel)-1, "%d%%", batteryVal);
            }
        } else if (type == GP_WIDGET_TEXT) { // 文字节点：如"100%"
            const char* batteryStr = nullptr;
            if (gp_widget_get_value(targetWidget, &batteryStr) == GP_OK && batteryStr) {
                strncpy(info.batteryLevel, batteryStr, sizeof(info.batteryLevel)-1);
            }
        }
    } else {
        strncpy(info.batteryLevel, "未知", sizeof(info.batteryLevel)-1);
    }

    // 3.2 光圈（f-number / 5007）
    targetWidget = FindParamWidget("f-number");
    if (targetWidget) {
        CameraWidgetType type;
        gp_widget_get_type(targetWidget, &type);
        if (type == GP_WIDGET_RADIO || type == GP_WIDGET_MENU) {
            const char* apertureStr = nullptr;
            if (gp_widget_get_value(targetWidget, &apertureStr) == GP_OK && apertureStr) {
                // 文字节点：直接用"f/4"；数字节点：400→f/4
                if (strstr(apertureStr, "f/") != nullptr) { // 文字节点值（如"f/4"）
                    strncpy(info.aperture, apertureStr, sizeof(info.aperture)-1);
                } else { // 数字节点值（如"400"→f/4）
                    int apertureVal = atoi(apertureStr);
                    snprintf(info.aperture, sizeof(info.aperture)-1, "f/%.1f", apertureVal / 100.0f);
                }
            }
        }
    } else {
        strncpy(info.aperture, "未知", sizeof(info.aperture)-1);
    }

    // 3.3 快门速度（shutterspeed / 500d）
    targetWidget = FindParamWidget("shutterspeed");
    if (targetWidget) {
        CameraWidgetType type;
        gp_widget_get_type(targetWidget, &type);
        if (type == GP_WIDGET_RADIO || type == GP_WIDGET_MENU) {
            const char* shutterStr = nullptr;
            if (gp_widget_get_value(targetWidget, &shutterStr) == GP_OK && shutterStr) {
                if (strcmp(shutterStr, "Auto") == 0 || strcmp(shutterStr, "auto") == 0) {
                    strncpy(info.shutter, "Auto", sizeof(info.shutter)-1);
                } else {
                    // 解析原始值（如"0.0040s"→0.004秒→1/250s）
                    char shutterValStr[32] = {0};
                    if (strstr(shutterStr, "/") != nullptr) {
                        strncpy(shutterValStr, shutterStr, strlen(shutterStr));
                    } else {
                        strncpy(shutterValStr, shutterStr, strlen(shutterStr)-1); // 去掉"s"
                    }
                    float shutterSec = atof(shutterValStr);
                    if (shutterSec > 0) {
                        // 匹配标准快门标签（如0.004→1/250s）
                        int bestIdx = 0;
                        float minDiff = fabsf(shutterSec - standardShutterSpeeds[0]);
                        for (int i=1; i<numStandardShutters; i++) {
                            float diff = fabsf(shutterSec - standardShutterSpeeds[i]);
                            if (diff < minDiff) { minDiff = diff; bestIdx = i; }
                        }
                        strncpy(info.shutter, standardShutterLabels[bestIdx], sizeof(info.shutter)-1);
                    } else {
                        strncpy(info.shutter, "未知", sizeof(info.shutter)-1);
                    }
                }
            }
        }
    } else {
        strncpy(info.shutter, "未知", sizeof(info.shutter)-1);
    }

    // 3.4 ISO（iso / 500f）
    targetWidget = FindParamWidget("iso");
    if (targetWidget) {
        CameraWidgetType type;
        gp_widget_get_type(targetWidget, &type);
        if (type == GP_WIDGET_RADIO || type == GP_WIDGET_MENU) {
            const char* isoStr = nullptr;
            if (gp_widget_get_value(targetWidget, &isoStr) == GP_OK && isoStr) {
                // 文字/数字节点值一致（如"100"），直接拼接"ISO "
                snprintf(info.iso, sizeof(info.iso)-1, "ISO %s", isoStr);
            }
        }
    } else {
        strncpy(info.iso, "未知", sizeof(info.iso)-1);
    }

    // 3.5 曝光补偿（exposurecompensation / 5010）
    targetWidget = FindParamWidget("exposurecompensation");
    if (targetWidget) {
        CameraWidgetType type;
        gp_widget_get_type(targetWidget, &type);
        if (type == GP_WIDGET_RADIO || type == GP_WIDGET_MENU) {
            const char* ecStr = nullptr;
            if (gp_widget_get_value(targetWidget, &ecStr) == GP_OK && ecStr) {
                // 文字节点：如"0.333"→0.3档；数字节点：333→0.3档
                float ecVal = atof(ecStr);
                if (ecVal > 100 || ecVal < -100) { // 数字节点（千倍映射：333→0.333）
                    ecVal /= 1000.0f;
                }
                snprintf(info.exposureComp, sizeof(info.exposureComp)-1, "%.1f 档", ecVal);
            }
        }
    } else {
        strncpy(info.exposureComp, "未知", sizeof(info.exposureComp)-1);
    }

    // 3.6 对焦模式（focusmode / 500a）
    targetWidget = FindParamWidget("focusmode");
    if (targetWidget) {
        CameraWidgetType type;
        gp_widget_get_type(targetWidget, &type);
        if (type == GP_WIDGET_RADIO || type == GP_WIDGET_MENU) {
            const char* focusStr = nullptr;
            if (gp_widget_get_value(targetWidget, &focusStr) == GP_OK && focusStr) {
                // 映射数字节点值→中文（如32785→AF-C）
                std::map<std::string, std::string> focusMap = {
                    {"1", "手动对焦（MF）"}, {"32784", "单次自动对焦（AF-S）"},
                    {"32785", "连续自动对焦（AF-C）"}, {"32787", "自动自动对焦（AF-F）"},
                    {"AF-S", "单次自动对焦（AF-S）"}, {"AF-C", "连续自动对焦（AF-C）"},
                    {"AF-F", "自动自动对焦（AF-F）"}, {"Manual", "手动对焦（MF）"}
                };
                auto it = focusMap.find(focusStr);
                if (it != focusMap.end()) {
                    strncpy(info.focusMode, it->second.c_str(), sizeof(info.focusMode)-1);
                } else {
                    strncpy(info.focusMode, focusStr, sizeof(info.focusMode)-1);
                }
            }
        }
    } else {
        strncpy(info.focusMode, "未知", sizeof(info.focusMode)-1);
    }

    // 3.7 曝光程序（expprogram / 500e）
    targetWidget = FindParamWidget("expprogram");
    if (targetWidget) {
        CameraWidgetType type;
        gp_widget_get_type(targetWidget, &type);
        if (type == GP_WIDGET_RADIO || type == GP_WIDGET_MENU) {
            const char* expProgStr = nullptr;
            if (gp_widget_get_value(targetWidget, &expProgStr) == GP_OK && expProgStr) {
                std::map<std::string, std::string> expProgMap = {
                    {"1", "M（手动）"}, {"2", "P（程序自动）"}, {"3", "A（光圈优先）"},
                    {"4", "S（快门优先）"}, {"32784", "AUTO（自动）"},
                    {"M", "M（手动）"}, {"P", "P（程序自动）"}, {"A", "A（光圈优先）"},
                    {"S", "S（快门优先）"}, {"Auto", "AUTO（自动）"}
                };
                auto it = expProgMap.find(expProgStr);
                if (it != expProgMap.end()) {
                    strncpy(info.exposureProgram, it->second.c_str(), sizeof(info.exposureProgram)-1);
                } else {
                    strncpy(info.exposureProgram, expProgStr, sizeof(info.exposureProgram)-1);
                }
            }
        }
    } else {
        strncpy(info.exposureProgram, "未知", sizeof(info.exposureProgram)-1);
    }

    // 3.8 测光模式（exposuremetermode / 500b）
    targetWidget = FindParamWidget("exposuremetermode");
    if (targetWidget) {
        CameraWidgetType type;
        gp_widget_get_type(targetWidget, &type);
        if (type == GP_WIDGET_RADIO || type == GP_WIDGET_MENU) {
            const char* meterStr = nullptr;
            if (gp_widget_get_value(targetWidget, &meterStr) == GP_OK && meterStr) {
                std::map<std::string, std::string> meterMap = {
                    {"2", "中央重点测光"}, {"3", "多点测光"}, {"4", "点测光"},
                    {"32784", "矩阵测光（Unknown 8010）"}, {"8010", "矩阵测光"},
                    {"Center Weighted", "中央重点测光"}, {"Multi Spot", "多点测光"},
                    {"Center Spot", "点测光"}, {"Unknown value 8010", "矩阵测光"}
                };
                auto it = meterMap.find(meterStr);
                if (it != meterMap.end()) {
                    strncpy(info.exposureMeterMode, it->second.c_str(), sizeof(info.exposureMeterMode)-1);
                } else {
                    strncpy(info.exposureMeterMode, meterStr, sizeof(info.exposureMeterMode)-1);
                }
            }
        }
    } else {
        strncpy(info.exposureMeterMode, "未知", sizeof(info.exposureMeterMode)-1);
    }

    // 3.9 白平衡（whitebalance / 5005）
    targetWidget = FindParamWidget("whitebalance");
    if (targetWidget) {
        CameraWidgetType type;
        gp_widget_get_type(targetWidget, &type);
        if (type == GP_WIDGET_RADIO || type == GP_WIDGET_MENU) {
            const char* wbStr = nullptr;
            if (gp_widget_get_value(targetWidget, &wbStr) == GP_OK && wbStr) {
                std::map<std::string, std::string> wbMap = {
                    {"2", "自动（Automatic）"}, {"4", "阴天（Cloudy）"}, {"5", "日光（Daylight）"},
                    {"6", "钨丝灯（Tungsten）"}, {"7", "闪光灯（Flash）"},
                    {"32784", "色温（Color Temperature）"}, {"32785", "预设（Preset）"},
                    {"32786", "阴影（Shade）"}, {"32787", "荧光灯（Fluorescent）"},
                    {"Automatic", "自动"}, {"Daylight", "日光"}, {"Cloudy", "阴天"},
                    {"Tungsten", "钨丝灯"}, {"Flash", "闪光灯"}
                };
                auto it = wbMap.find(wbStr);
                if (it != wbMap.end()) {
                    strncpy(info.whiteBalance, it->second.c_str(), sizeof(info.whiteBalance)-1);
                } else {
                    strncpy(info.whiteBalance, wbStr, sizeof(info.whiteBalance)-1);
                }
            }
        }
    } else {
        strncpy(info.whiteBalance, "未知", sizeof(info.whiteBalance)-1);
    }

    // 3.10 拍摄模式（capturemode / 5013）
    targetWidget = FindParamWidget("capturemode");
    if (targetWidget) {
        CameraWidgetType type;
        gp_widget_get_type(targetWidget, &type);
        if (type == GP_WIDGET_RADIO || type == GP_WIDGET_MENU) {
            const char* modeStr = nullptr;
            if (gp_widget_get_value(targetWidget, &modeStr) == GP_OK && modeStr) {
                std::map<std::string, std::string> modeMap = {
                    {"1", "单拍（Single Shot）"}, {"2", "连拍（Burst）"},
                    {"32784", "低速连拍（Continuous Low Speed）"}, {"32785", "定时（Timer）"},
                    {"Single Shot", "单拍"}, {"Burst", "连拍"}, {"Continuous Low Speed", "低速连拍"},
                    {"Timer", "定时"}
                };
                auto it = modeMap.find(modeStr);
                if (it != modeMap.end()) {
                    strncpy(info.captureMode, it->second.c_str(), sizeof(info.captureMode)-1);
                } else {
                    strncpy(info.captureMode, modeStr, sizeof(info.captureMode)-1);
                }
            }
        }
    } else {
        strncpy(info.captureMode, "未知", sizeof(info.captureMode)-1);
    }

    // 3.11 剩余空间（freespace）
    targetWidget = FindParamWidget("freespace");
    if (targetWidget) {
        CameraWidgetType type;
        gp_widget_get_type(targetWidget, &type);
        if (type == GP_WIDGET_TEXT) {
            const char* spaceStr = nullptr;
            if (gp_widget_get_value(targetWidget, &spaceStr) == GP_OK && spaceStr) {
                info.freeSpaceBytes = atoll(spaceStr); // 转字节数
            }
        } else if (type == GP_WIDGET_TOGGLE) {
            long long spaceVal = 0;
            if (gp_widget_get_value(targetWidget, &spaceVal) == GP_OK) {
                info.freeSpaceBytes = spaceVal;
            }
        }
    }

    // 3.12 剩余可拍张数（freespaceimages）
    targetWidget = FindParamWidget("freespaceimages");
    if (targetWidget) {
        CameraWidgetType type;
        gp_widget_get_type(targetWidget, &type);
        if (type == GP_WIDGET_TEXT) {
            const char* picStr = nullptr;
            if (gp_widget_get_value(targetWidget, &picStr) == GP_OK && picStr) {
                info.remainingPictures = atoi(picStr);
            }
        } else if (type == GP_WIDGET_TOGGLE) {
            int picCount = 0;
            if (gp_widget_get_value(targetWidget, &picCount) == GP_OK) {
                info.remainingPictures = picCount;
            }
        }
    }

    // 4. 资源释放+状态标记
    gp_widget_free(root);
    info.isSuccess = true;
    return info;
}




























// camera_config.cpp 新增NAPI接口
napi_value GetParamOptions(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    char paramName[128] = {0};
    napi_get_value_string_utf8(env, args[0], paramName, sizeof(paramName)-1, nullptr);

    napi_value resultArray;
    napi_create_array(env, &resultArray);

    // 遍历g_allConfigItems，找到指定参数的可选值
    for (const auto& item : g_allConfigItems) {
        if (item.name == paramName) {
            for (size_t i=0; i<item.choices.size(); ++i) {
                napi_set_element(env, resultArray, i, CreateNapiString(env, item.choices[i].c_str()));
            }
            break;
        }
    }
    return resultArray;
}








// ###########################################################################
// 新增：NAPI接口 - 获取相机信息（暴露给ArkTS）
// ###########################################################################
/**
 * @brief ArkTS层调用此函数，获取相机电量、光圈、快门等所有信息
 * @param env NAPI环境
 * @param info NAPI回调信息
 * @return napi_value 返回ArkTS对象（包含所有相机信息属性）
 */
napi_value GetCameraStatus(napi_env env, napi_callback_info info) {
    // 1. 调用内部函数获取相机信息
    CameraInfo camInfo = InternalGetCameraInfo();

    // 2. 创建ArkTS对象，用于返回所有信息
    napi_value result;
    napi_create_object(env, &result);

    // 3. 给对象添加属性（与结构体字段一一对应）
    napi_set_named_property(env, result, "isSuccess", CreateNapiString(env, camInfo.isSuccess ? "true" : "false"));
    napi_set_named_property(env, result, "batteryLevel", CreateNapiString(env, camInfo.batteryLevel));
    napi_set_named_property(env, result, "aperture", CreateNapiString(env, camInfo.aperture));
    napi_set_named_property(env, result, "shutter", CreateNapiString(env, camInfo.shutter));
    napi_set_named_property(env, result, "iso", CreateNapiString(env, camInfo.iso));
    napi_set_named_property(env, result, "exposureCompensation", CreateNapiString(env, camInfo.exposureComp));
    napi_set_named_property(env, result, "whiteBalance", CreateNapiString(env, camInfo.whiteBalance));
    napi_set_named_property(env, result, "captureMode", CreateNapiString(env, camInfo.captureMode));
    // 在返回对象中添加曝光模式属性
    napi_set_named_property(env, result, "exposureProgram", CreateNapiString(env, camInfo.exposureProgram));
    napi_set_named_property(env, result, "focusMode", CreateNapiString(env, camInfo.focusMode));
    napi_set_named_property(env, result, "exposureMeterMode", CreateNapiString(env, camInfo.exposureMeterMode));

    // 数值型属性（单独处理，避免转字符串丢失精度）
    napi_value freeSpaceVal;
    napi_create_int64(env, camInfo.freeSpaceBytes, &freeSpaceVal);
    napi_set_named_property(env, result, "freeSpaceBytes", freeSpaceVal);

    napi_value remainingPicVal;
    napi_create_int32(env, camInfo.remainingPictures, &remainingPicVal);
    napi_set_named_property(env, result, "remainingPictures", remainingPicVal);

    return result;
}




































// ###########################################################################
// 核心函数：设置相机参数（内部逻辑，如闪光灯、ISO等）
// ###########################################################################
/**
 * @brief 内部函数：设置相机的配置参数（如闪光灯模式、ISO、白平衡等）
 * @param key 参数名（如"flash"=闪光灯，"iso"=ISO，需与libgphoto2参数名一致）
 * @param value 参数值（如"on"=闪光灯开启，"400"=ISO400）
 * @return bool 设置成功返回true，失败返回false
 */
static bool SetConfig(const char *key, const char *value) {
    if (!g_connected)
        return false;

    CameraWidget *root = nullptr;
    if (gp_camera_get_config(g_camera, &root, g_context) != GP_OK) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "获取配置树失败");
        return false;
    }

    CameraWidget *child = nullptr;
    int ret = gp_widget_get_child_by_name(root, key, &child);
    if (ret != GP_OK) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "未找到参数: %{public}s", key);
        gp_widget_free(root);
        return false;
    }

    // 设置参数值（自动适配类型：选项/文本/开关等）
    ret = gp_widget_set_value(child, value);
    if (ret != GP_OK) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "设置参数值失败: %{public}s", gp_result_as_string(ret));
        gp_widget_free(root);
        return false;
    }

    // 应用配置到相机
    ret = gp_camera_set_config(g_camera, root, g_context);
    gp_widget_free(root);
    if (ret != GP_OK) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "应用配置失败: %{public}s", gp_result_as_string(ret));
        return false;
    }

    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "参数 %{public}s 设置为 %{public}s 成功", key, value);
    return true;
}


// ###########################################################################
// NAPI接口：设置相机参数（暴露给ArkTS调用，封装SetConfig）
// ###########################################################################
/**
 * @brief ArkTS层调用此函数，传入参数名和值，设置相机配置
 * @param env NAPI环境
 * @param info NAPI回调信息（包含2个参数：key、value）
 * @return napi_value 返回布尔值给ArkTS（true=设置成功，false=失败）
 */
napi_value SetCameraParameter(napi_env env, napi_callback_info info) {
    size_t argc = 2;    // 期望接收2个参数（key、value）
    napi_value args[2]; // 存储ArkTS传入的参数
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











// 静态函数，符合ParamCallback的类型
static void StaticParamCallback(napi_value params) {
    // 从全局状态中获取env和callbackRef
    napi_env env = g_callbackState.env;
    napi_ref callbackRef = g_callbackState.callbackRef;

    if (env == nullptr || callbackRef == nullptr) {
        OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "回调状态无效，env或callbackRef为空");
        return; // 状态无效，直接返回
    }
    
    

    // 调用ArkTS层的回调函数（与之前lambda中的逻辑一致）
    napi_value callback;
    napi_get_reference_value(env, callbackRef, &callback);

    napi_value global;
    napi_get_global(env, &global);

    napi_value result;
    napi_call_function(env, global, callback, 1, &params, &result);
}





// 实现注册回调：保存ArkTS层传递的回调函数
napi_value RegisterParamCallback(napi_env env, napi_callback_info info) {
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "进入RegisterParamCallback函数");
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    

    // 创建ArkTS回调的引用（与之前一致）
    napi_ref callbackRef;
    napi_create_reference(env, args[0], 1, &callbackRef);

    // 保存状态到全局结构体
    g_callbackState.env = env;
    g_callbackState.callbackRef = callbackRef;

    // 赋值静态函数（符合ParamCallback类型）
    g_paramCallback = StaticParamCallback;
    
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "回调注册成功");
    return nullptr;
}