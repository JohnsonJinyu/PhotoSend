//
// Created on 2025/11/9.
//
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".

#include "native_common.h"
#include <vector>
#include <napi/native_api.h>
#include "hilog/log.h"


#define LOG_DOMAIN 0x0002      // 日志域（自定义标识，区分不同模块日志）
#define LOG_TAG "Camera_Config" // 日志标签（日志中显示的模块名）







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
                if (gp_widget_get_choice(widget, i, &choice) == GP_OK) {
                    item.choices.push_back(choice);
                }
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