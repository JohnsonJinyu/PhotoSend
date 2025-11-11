//
// Created on 2025/11/9.
//
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".

#include "native_common.h"
#include <vector>
#include <napi/native_api.h>
#include "hilog/log.h"
#include "camera_config.h"

#define LOG_DOMAIN 0x0002       // 日志域（自定义标识，区分不同模块日志）
#define LOG_TAG "Camera_Config" // 日志标签（日志中显示的模块名）












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


/**
 * 递归遍历配置树节点，收集参数信息
 * @param widget 配置树节点
 * @param items 存储结果的数组
 */
static void TraverseConfigTree(CameraWidget *widget, std::vector<ConfigItem> &items) {
    if (!widget)
        return;

    // 获取节点类型（如GP_WIDGET_MENU=选项，GP_WIDGET_TEXT=文本等）
    CameraWidgetType type;
    gp_widget_get_type(widget, &type);

    // 只处理可设置的参数节点（跳过文件夹类型）
    if (type != GP_WIDGET_SECTION && type != GP_WIDGET_WINDOW) {
        ConfigItem item;
        // 获取参数名称和显示标签
        const char *name_ptr = nullptr;        // 中间变量，接收C字符串地址
        gp_widget_get_name(widget, &name_ptr); // 传递二级指针，类型匹配
        item.name = name_ptr ? name_ptr : "";  // 转换为std::string

        // 同理处理标签（假设gp_widget_get_label也有相同问题）
        const char *label_ptr = nullptr;
        gp_widget_get_label(widget, &label_ptr);
        item.label = label_ptr ? label_ptr : "";

        // 转换类型为字符串
        switch (type) {
        case GP_WIDGET_MENU:
            item.type = "choice";
            break;
        case GP_WIDGET_TEXT:
            item.type = "text";
            break;
        case GP_WIDGET_RANGE:
            item.type = "range";
            break;
        case GP_WIDGET_TOGGLE:
            item.type = "toggle";
            break;
        default:
            item.type = "unknown";
        }

        // 获取当前值
        const char *value;
        if (gp_widget_get_value(widget, &value) == GP_OK) {
            item.current = value ? value : "";
        }

        // 对于选项类型，获取所有可选值
        if (type == GP_WIDGET_MENU) {
            int choiceCount = gp_widget_count_choices(widget);
            for (int i = 0; i < choiceCount; i++) {
                const char *choice;
                if (gp_widget_get_choice(widget, i, &choice) == GP_OK && choice != nullptr) {
                    item.choices.push_back(choice);
                } else {
                    item.choices.push_back(""); // 用空字符串替代null
                }
                OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, 
            "配置项: %{public}s, 当前值: %{public}s, 选项数: %{public}zu", 
            item.name.c_str(), item.current.c_str(), item.choices.size());
            }
        }

        items.push_back(item);
    }

    // 递归处理子节点
    int childCount = gp_widget_count_children(widget);
    for (int i = 0; i < childCount; i++) {
        CameraWidget *child;
        if (gp_widget_get_child(widget, i, &child) == GP_OK) {
            TraverseConfigTree(child, items);
        }
    }
}


/**
 * 内部函数：获取所有相机配置参数
 * @param items 输出参数：存储配置参数的数组
 * @return 是否成功
 */
static bool GetAllConfigItems(std::vector<ConfigItem> &items) {
    if (!g_connected || !g_camera || !g_context) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "相机未连接，无法获取配置");
        return false;
    }

    // 获取配置树根节点
    CameraWidget *root = nullptr;
    int ret = gp_camera_get_config(g_camera, &root, g_context);
    if (ret != GP_OK) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "获取配置树失败: %{public}s", gp_result_as_string(ret));
        return false;
    }

    // 遍历配置树
    TraverseConfigTree(root, items);

    // 释放配置树
    gp_widget_free(root);
    return true;
}


/**
 * NAPI接口：获取相机所有配置参数（含可选值和当前值）
 * @return ArkTS数组，每个元素为{name, label, type, current, choices}
 */
napi_value GetCameraConfig(napi_env env, napi_callback_info info) {
    std::vector<ConfigItem> items;
    bool success = GetAllConfigItems(items);

    // 创建ArkTS数组
    napi_value resultArray;
    napi_create_array(env, &resultArray);

    if (success) {
        for (size_t i = 0; i < items.size(); i++) {
            const ConfigItem &item = items[i];
            // 创建单个参数对象
            napi_value obj;
            napi_create_object(env, &obj);

            // 设置name属性
            napi_set_named_property(env, obj, "name", CreateNapiString(env, item.name.c_str()));
            // 设置label属性
            napi_set_named_property(env, obj, "label", CreateNapiString(env, item.label.c_str()));
            // 设置type属性
            napi_set_named_property(env, obj, "type", CreateNapiString(env, item.type.c_str()));
            // 设置current属性
            napi_set_named_property(env, obj, "current", CreateNapiString(env, item.current.c_str()));

            // 创建choices数组
            napi_value choicesArray;
            napi_create_array(env, &choicesArray);
            for (size_t j = 0; j < item.choices.size(); j++) {
                napi_value choice = CreateNapiString(env, item.choices[j].c_str());
                napi_set_element(env, choicesArray, j, choice);
            }
            napi_set_named_property(env, obj, "choices", choicesArray);

            // 将对象添加到结果数组
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

    // 1. 检查相机是否已连接
    if (!g_connected || !g_camera || !g_context) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "获取相机信息失败：相机未连接");
        return info;
    }

    // 2. 获取配置树根节点（核心：所有参数都在这个树里）
    CameraWidget *root = nullptr;
    int ret = gp_camera_get_config(g_camera, &root, g_context);
    if (ret != GP_OK || !root) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "获取配置树失败，错误码：%{public}d", ret);
        return info;
    }

    // 3. 逐个查找目标节点并读取值（按信息类型处理）
    CameraWidget *targetWidget = nullptr;

    // 3.1 电量（正确类型：GP_WIDGET_TOGGLE）
    targetWidget = nullptr;
    RecursiveFindWidget(root, "batterylevel", &targetWidget, "");
    if (targetWidget) {
        CameraWidgetType type;
        gp_widget_get_type(targetWidget, &type);
        // OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "电量节点类型：%{public}d", type); // 调试：打印实际类型

        if (type == GP_WIDGET_TOGGLE) { // 正确类型：整数（如80=80%）
            int batteryVal = 0;
            gp_widget_get_value(targetWidget, &batteryVal); // 获取整数
            snprintf(info.batteryLevel, sizeof(info.batteryLevel) - 1, "%d%%", batteryVal);
        } else if (type == GP_WIDGET_TEXT) { // 兼容文本类型（如"Full"）
            const char *batteryStr = nullptr;
            gp_widget_get_value(targetWidget, &batteryStr);
            if (batteryStr)
                strncpy(info.batteryLevel, batteryStr, sizeof(info.batteryLevel) - 1);
        }
    }

    // 3.2 光圈（正确类型：GP_WIDGET_RADIO，值为字符串）
    targetWidget = nullptr;
    RecursiveFindWidget(root, "f-number", &targetWidget, "");
    if (targetWidget) {
        CameraWidgetType type;
        gp_widget_get_type(targetWidget, &type);
        // OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "光圈节点类型：%{public}d", type);

        if (type == GP_WIDGET_RADIO || type == GP_WIDGET_MENU) { // 枚举类型，值为选项名
            const char *apertureStr = nullptr;
            gp_widget_get_value(targetWidget, &apertureStr); // 获取字符串（如"f/1.8"）
            if (apertureStr)
                strncpy(info.aperture, apertureStr, sizeof(info.aperture) - 1);
        } else if (type == GP_WIDGET_RANGE) { // 兼容范围类型（部分相机）
            float apertureVal = 0.0f;
            gp_widget_get_value(targetWidget, &apertureVal);
            snprintf(info.aperture, sizeof(info.aperture) - 1, "f/%.1f", apertureVal);
        }
    }

// 3.3 快门速度（修正：匹配标准档位，解决偏差问题）
    targetWidget = nullptr;
    RecursiveFindWidget(root, "shutterspeed", &targetWidget, "");
    if (targetWidget) {
        CameraWidgetType type;
        gp_widget_get_type(targetWidget, &type);
        if (type == GP_WIDGET_RADIO || type == GP_WIDGET_MENU) {
            const char *shutterStr = nullptr;
            gp_widget_get_value(targetWidget, &shutterStr);
            if (shutterStr) {
                // 1. 处理Auto模式
                if (strcmp(shutterStr, "Auto") == 0 || strcmp(shutterStr, "auto") == 0) {
                    strncpy(info.shutter, "Auto", sizeof(info.shutter) - 1);
                    info.shutter[sizeof(info.shutter) - 1] = '\0';
                    // continue; // 跳过后续计算
                }

                // 2. 解析原始快门值（单位：秒）
                char shutterValStr[32] = {0};
                // 处理两种格式："0.0015s"（小数）或"1/640s"（分数，部分相机可能返回）
                if (strstr(shutterStr, "/") != nullptr) {
                    // 若原始值是分数格式（如"1/640s"），直接提取
                    strncpy(shutterValStr, shutterStr, strlen(shutterStr));
                } else {
                    // 若原始值是小数格式（如"0.0015s"），去掉"s"并转换为浮点数
                    strncpy(shutterValStr, shutterStr, strlen(shutterStr) - 1); // 去掉末尾的"s"
                }
                float shutterSec = atof(shutterValStr); // 转换为秒数（如0.0015625）

                // 3. 找到与原始值最接近的标准档位
                if (shutterSec > 0) { // 确保值有效
                    int bestMatchIndex = 0;
                    float minDiff = fabsf(shutterSec - standardShutterSpeeds[0]);

                    // 遍历所有标准档位，找差值最小的
                    for (int i = 1; i < numStandardShutters; i++) {
                        float diff = fabsf(shutterSec - standardShutterSpeeds[i]);
                        if (diff < minDiff) {
                            minDiff = diff;
                            bestMatchIndex = i;
                        }
                    }

                    // 4. 使用标准档位的标签作为显示值
                    strncpy(info.shutter, standardShutterLabels[bestMatchIndex], sizeof(info.shutter) - 1);
                    info.shutter[sizeof(info.shutter) - 1] = '\0';
                } else {
                    // 无效值处理
                    strncpy(info.shutter, "未知", sizeof(info.shutter) - 1);
                    info.shutter[sizeof(info.shutter) - 1] = '\0';
                }
            }
        }
    }


    // 3.4 ISO（正确类型：GP_WIDGET_RADIO，值为选项名）
    targetWidget = nullptr;
    RecursiveFindWidget(root, "iso", &targetWidget, "");
    if (targetWidget) {
        CameraWidgetType type;
        gp_widget_get_type(targetWidget, &type);
        // OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "ISO节点类型：%{public}d", type);

        if (type == GP_WIDGET_RADIO || type == GP_WIDGET_MENU) {
            const char *isoStr = nullptr;
            gp_widget_get_value(targetWidget, &isoStr); // 获取字符串（如"ISO 800"）
            if (isoStr)
                strncpy(info.iso, isoStr, sizeof(info.iso) - 1);
        }
    }


    // 3.5 曝光补偿（正确类型：GP_WIDGET_RADIO，值为选项名）
    targetWidget = nullptr;
    RecursiveFindWidget(root, "exposurecompensation", &targetWidget, "");
    if (targetWidget) {
        CameraWidgetType type;
        gp_widget_get_type(targetWidget, &type);
        // OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "曝光补偿节点类型：%{public}d", type);

        if (type == GP_WIDGET_RADIO || type == GP_WIDGET_MENU) {
            const char *ecStr = nullptr;
            gp_widget_get_value(targetWidget, &ecStr); // 获取字符串（如"0.0 stops"）
            if (ecStr)
                strncpy(info.exposureComp, ecStr, sizeof(info.exposureComp) - 1);
        }
    }

    // 3.6 白平衡（字符串枚举型，如"Auto"、"Daylight"）
    targetWidget = nullptr;
    RecursiveFindWidget(root, "whitebalance", &targetWidget, "");
    if (targetWidget) {
        const char *wbVal = nullptr;
        gp_widget_get_value(targetWidget, &wbVal);
        if (wbVal) {
            // 转换Nikon的枚举值为可读名称（如2→Automatic，4→Cloudy，从summary提取对应关系）
            if (strcmp(wbVal, "2") == 0)
                strncpy(info.whiteBalance, "Automatic", sizeof(info.whiteBalance) - 1);
            else if (strcmp(wbVal, "4") == 0)
                strncpy(info.whiteBalance, "Cloudy", sizeof(info.whiteBalance) - 1);
            else if (strcmp(wbVal, "5") == 0)
                strncpy(info.whiteBalance, "Daylight", sizeof(info.whiteBalance) - 1);
            else
                strncpy(info.whiteBalance, wbVal, sizeof(info.whiteBalance) - 1);
        }
        // OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "白平衡：%{public}s", info.whiteBalance);
    } else {
        // OH_LOG_Print(LOG_APP, LOG_WARN, LOG_DOMAIN, LOG_TAG, "未找到白平衡节点（whitebalance）");
    }

    // 3.7 拍摄模式（正确类型：GP_WIDGET_RADIO，值为选项名）
    targetWidget = nullptr;
    RecursiveFindWidget(root, "capturemode", &targetWidget, "");
    if (targetWidget) {
        CameraWidgetType type;
        gp_widget_get_type(targetWidget, &type);
        // OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "拍摄模式节点类型：%{public}d", type);

        if (type == GP_WIDGET_RADIO || type == GP_WIDGET_MENU) {
            const char *modeStr = nullptr;
            gp_widget_get_value(targetWidget, &modeStr); // 获取字符串（如"Single Shot"）
            if (modeStr) {
                // 映射为中文描述
                if (strcmp(modeStr, "Single Shot") == 0) {
                    strncpy(info.captureMode, "单拍", sizeof(info.captureMode) - 1);
                } else if (strcmp(modeStr, "Continuous") == 0) {
                    strncpy(info.captureMode, "连拍", sizeof(info.captureMode) - 1);
                } else if (strcmp(modeStr, "Burst") == 0) {
                    strncpy(info.captureMode, "高速连拍", sizeof(info.captureMode) - 1);
                } else {
                    strncpy(info.captureMode, modeStr, sizeof(info.captureMode) - 1);
                }
            }
        }
    }

    // 3.8 剩余空间（可能是文本或整数）
    targetWidget = nullptr;
    RecursiveFindWidget(root, "freespace", &targetWidget, "");
    if (targetWidget) {
        CameraWidgetType type;
        gp_widget_get_type(targetWidget, &type);
        if (type == GP_WIDGET_TEXT) { // 文本类型（如"120861491200"）
            const char *spaceStr = nullptr;
            gp_widget_get_value(targetWidget, &spaceStr);
            if (spaceStr)
                info.freeSpaceBytes = atoll(spaceStr); // 转换为长整数
        } else if (type == GP_WIDGET_TOGGLE) {         // 整数类型
            long long spaceVal = 0;
            gp_widget_get_value(targetWidget, &spaceVal);
            info.freeSpaceBytes = spaceVal;
        }
    }

    // 3.9 剩余可拍张数（同理）
    targetWidget = nullptr;
    RecursiveFindWidget(root, "freespaceimages", &targetWidget, "");
    if (targetWidget) {
        CameraWidgetType type;
        gp_widget_get_type(targetWidget, &type);
        if (type == GP_WIDGET_TEXT) {
            const char *picStr = nullptr;
            gp_widget_get_value(targetWidget, &picStr);
            if (picStr)
                info.remainingPictures = atoi(picStr);
        } else if (type == GP_WIDGET_TOGGLE) {
            int picCount = 0;
            gp_widget_get_value(targetWidget, &picCount);
            info.remainingPictures = picCount;
        }
    }


    // 3.10：曝光模式（M/A/S/P/AUTO）
    targetWidget = nullptr;
    RecursiveFindWidget(root, "expprogram", &targetWidget, ""); // 对应日志中的"expprogram"节点
    if (targetWidget) {
        const char *expProgStr = nullptr;
        gp_widget_get_value(targetWidget, &expProgStr);
        if (expProgStr) {
            // 映射为专业档位（根据相机返回值调整，日志中为"A"）
            if (strcmp(expProgStr, "A") == 0) {
                strncpy(info.exposureProgram, "A（光圈优先）", sizeof(info.exposureProgram) - 1);
            } else if (strcmp(expProgStr, "M") == 0) {
                strncpy(info.exposureProgram, "M（手动）", sizeof(info.exposureProgram) - 1);
            } else if (strcmp(expProgStr, "S") == 0) {
                strncpy(info.exposureProgram, "S（快门优先）", sizeof(info.exposureProgram) - 1);
            } else if (strcmp(expProgStr, "P") == 0) {
                strncpy(info.exposureProgram, "P（程序自动）", sizeof(info.exposureProgram) - 1);
            } else if (strcmp(expProgStr, "Auto") == 0) {
                strncpy(info.exposureProgram, "AUTO（自动）", sizeof(info.exposureProgram) - 1);
            } else {
                strncpy(info.exposureProgram, expProgStr, sizeof(info.exposureProgram) - 1); // 未知值直接显示
            }
        }
    }

    // 3.11：对焦模式（focusmode节点）
    targetWidget = nullptr;
    RecursiveFindWidget(root, "focusmode", &targetWidget, ""); // 节点名称与日志一致
    if (targetWidget) {
        const char *focusStr = nullptr;
        gp_widget_get_value(targetWidget, &focusStr);
        if (focusStr) {
            // 映射为中文描述（根据相机实际返回值补充，以下为常见映射）
            if (strcmp(focusStr, "AF-S") == 0) {
                strncpy(info.focusMode, "单次自动对焦（AF-S）", sizeof(info.focusMode) - 1);
            } else if (strcmp(focusStr, "AF-C") == 0) {
                strncpy(info.focusMode, "连续自动对焦（AF-C）", sizeof(info.focusMode) - 1);
            } else if (strcmp(focusStr, "AF-A") == 0) {
                strncpy(info.focusMode, "自动自动对焦（AF-A）", sizeof(info.focusMode) - 1);
            } else if (strcmp(focusStr, "MF") == 0) {
                strncpy(info.focusMode, "手动对焦（MF）", sizeof(info.focusMode) - 1);
            } else {
                // 未知值直接显示原始值（如“AF-F”等）
                snprintf(info.focusMode, sizeof(info.focusMode) - 1, "%s", focusStr);
            }
            info.focusMode[sizeof(info.focusMode) - 1] = '\0'; // 手动加结束符
        }
    }


    // 新增：测光模式（exposuremetermode节点）
    targetWidget = nullptr;
    RecursiveFindWidget(root, "exposuremetermode", &targetWidget, ""); // 节点名称与日志一致
    if (targetWidget) {
        const char *meterStr = nullptr;
        gp_widget_get_value(targetWidget, &meterStr);
        if (meterStr) {
            // 处理两种情况：1. 数值字符串（如"8010"）；2. 直接描述（如"Matrix"）
            // 以下为Nikon相机数值映射（参考官方文档）
            if (strcmp(meterStr, "8010") == 0) {
                strncpy(info.exposureMeterMode, "亮部重点测光", sizeof(info.exposureMeterMode) - 1);
            } else if (strcmp(meterStr, "8011") == 0) {
                strncpy(info.exposureMeterMode, "中央重点测光", sizeof(info.exposureMeterMode) - 1);
            } else if (strcmp(meterStr, "8012") == 0) {
                strncpy(info.exposureMeterMode, "点测光", sizeof(info.exposureMeterMode) - 1);
            } else if (strcmp(meterStr, "8013") == 0) {
                strncpy(info.exposureMeterMode, "平均测光", sizeof(info.exposureMeterMode) - 1);
            } else {
                // 未知值显示原始值（如日志中的"Unknown value 8010"）
                snprintf(info.exposureMeterMode, sizeof(info.exposureMeterMode) - 1, "%s", meterStr);
            }
            info.exposureMeterMode[sizeof(info.exposureMeterMode) - 1] = '\0'; // 手动加结束符
        }
    }

    // 4. 释放配置树资源（避免内存泄漏）
    gp_widget_free(root);
    info.isSuccess = true;
    return info;
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
