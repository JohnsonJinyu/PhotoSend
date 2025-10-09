# 1. 指定 CMake 最小版本
cmake_minimum_required(VERSION 3.5.0)

# 2. 工程名
project("PhotoSendNative")

# 3. 定义路径变量
set(CPP_DIR ${CMAKE_CURRENT_SOURCE_DIR})
set(INCLUDE_DIR ${CPP_DIR}/libs/include)

#
set(LIBS_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../../../libs/arm64-v8a)

# 调试输出路径
message(STATUS "CPP_DIR = ${CPP_DIR}")
message(STATUS "INCLUDE_DIR = ${INCLUDE_DIR}")
message(STATUS "LIBS_DIR = ${LIBS_DIR}")

# 4. 头文件搜索路径
include_directories(
    ${INCLUDE_DIR}
    ${CPP_DIR}
)

# 5. 静态库搜索路径
link_directories(
    ${LIBS_DIR}  # 你的项目私有库路径（libusb、libgphoto2 等）
    # ✅ 新增：SDK 系统库路径（arm64-v8a 架构的系统库，如 hilog）
    ${CMAKE_SYSROOT}/usr/lib/arm64-v8a
)
# 6. 导入静态库
add_library(libusb-1.0 STATIC IMPORTED)
set_target_properties(libusb-1.0 PROPERTIES IMPORTED_LOCATION
    ${LIBS_DIR}/libusb-1.0.a
)

add_library(libexif STATIC IMPORTED)
set_target_properties(libexif PROPERTIES IMPORTED_LOCATION
    ${LIBS_DIR}/libexif.a
)

add_library(libltdl STATIC IMPORTED)
set_target_properties(libltdl PROPERTIES IMPORTED_LOCATION
    ${LIBS_DIR}/libltdl.a
)

add_library(libgphoto2 STATIC IMPORTED)
set_target_properties(libgphoto2 PROPERTIES IMPORTED_LOCATION
    ${LIBS_DIR}/libgphoto2.a
)

add_library(libgphoto2_port STATIC IMPORTED)
set_target_properties(libgphoto2_port PROPERTIES IMPORTED_LOCATION
    ${LIBS_DIR}/libgphoto2_port.a
)

# 7. 业务 Native 库
add_library(entry SHARED native_camera.cpp)

# 8. 链接所有库
target_link_libraries(entry PUBLIC
    libusb-1.0
    libexif
    libltdl
    libgphoto2
    libgphoto2_port
    hilog
    libace_napi.z.so
)

# 9. 保留 NativeRender 配置
set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})
if(DEFINED PACKAGE_FIND_FILE)
    include(${PACKAGE_FIND_FILE})
endif()