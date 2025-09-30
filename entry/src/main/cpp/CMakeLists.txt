# the minimum version of CMake.
cmake_minimum_required(VERSION 3.5.0)
project(NativeC_Test)

# 定义路径变量
set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

# 添加头文件路径
include_directories(${CMAKE_CURRENT_SOURCE_DIR}/libs/include)

# 添加库文件路径
link_directories(${CMAKE_CURRENT_SOURCE_DIR}/../entry/libs/arm64-v8a)



# 条件包含外部文件。如果已定义，则通过include命令加载该变量指向的文件（可能是包的配置脚本）。
# 作用：用于集成外部依赖包的构建规则。
if(DEFINED PACKAGE_FIND_FILE)
    include(${PACKAGE_FIND_FILE})
endif()

# 添加头文件搜索目录
include_directories(${NATIVERENDER_ROOT_PATH}
                    ${NATIVERENDER_ROOT_PATH}/include)
# 生成动态链接库
# 作用：将napi_init.cpp编译为可被其他程序动态加载的库文件。
add_library(entry SHARED native_camera.cpp)

# 指定entry库在链接阶段需要依赖的外部库libace_napi.z.so
# 作用：确保entry库能正确调用libace_napi.z.so中的函数
target_link_libraries(entry PUBLIC
    gphoto
    gphoto2_port
    libace_napi.z.so)