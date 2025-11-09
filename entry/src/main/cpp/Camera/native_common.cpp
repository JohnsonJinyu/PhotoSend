//
// Created on 2025/11/9.
//
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".



#include "native_common.h"
#include <cstdarg>  // 用于可变参数（日志格式化）
#include <hilog//log.h>  // 以Android为例，其他平台可替换为对应日志接口