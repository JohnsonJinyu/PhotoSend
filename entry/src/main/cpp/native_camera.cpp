#include "napi/native_api.h"

static napi_value Add(napi_env env, napi_callback_info info)
{
    size_t argc = 2;                      // 期望接收 2 个参数
    napi_value args[2] = {nullptr};       // 用来存放传入的参数

    // 从 JS/ArkTS 调用传入的参数中获取实际参数列表
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    // 检查第一个参数的类型
    napi_valuetype valuetype0;
    napi_typeof(env, args[0], &valuetype0);

    // 检查第二个参数的类型
    napi_valuetype valuetype1;
    napi_typeof(env, args[1], &valuetype1);

    // 将第一个参数转换为 double
    double value0;
    napi_get_value_double(env, args[0], &value0);

    // 将第二个参数转换为 double
    double value1;
    napi_get_value_double(env, args[1], &value1);

    // 创建一个新的 napi_value 来存放结果
    napi_value sum;
    napi_create_double(env, value0 + value1, &sum);

    // 返回结果给 ArkTS/JS
    return sum;
}

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports)
{
    // 定义一个属性描述符，把 C++ 的 Add 函数映射为 JS 的 "add" 方法
    napi_property_descriptor desc[] = {
        { "add", nullptr, Add, nullptr, nullptr, nullptr, napi_default, nullptr }
    };

    // 把这个属性挂载到 exports 对象上
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);

    // 返回 exports 对象（即模块导出对象）
    return exports;
}
EXTERN_C_END

//这里定义了一个 napi_module 结构体，描述了这个原生模块的基本信息。
//关键点是 .nm_modname = "entry"，它决定了 ArkTS 导入时的模块名。

static napi_module demoModule = {
    .nm_version = 1,              // 模块版本
    .nm_flags = 0,                // 标志位（一般为 0）
    .nm_filename = nullptr,       // 文件名（可选）
    .nm_register_func = Init,     // 模块初始化函数
    .nm_modname = "entry",        // 模块名，必须和 oh-package.json5 的 name 一致
    .nm_priv = ((void*)0),        // 私有数据（一般不用）
    .reserved = { 0 },            // 保留字段
};

/**
 * 
 * 这是一个构造函数属性（__attribute__((constructor))），意思是：
- 当 so 库被加载时，这个函数会自动执行。
- 它调用 napi_module_register，把上面定义的 demoModule 注册到 NAPI 框架里。
- 这样 ArkTS 才能通过 import native from 'libentry.so'; 找到并使用这个模块。

 * */
extern "C" __attribute__((constructor)) void RegisterEntryModule(void)
{
    napi_module_register(&demoModule);
}
