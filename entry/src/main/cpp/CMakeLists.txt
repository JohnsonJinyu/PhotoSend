# 1. 指定 CMake 最小版本
cmake_minimum_required(VERSION 3.5.0)

# 2. 工程名
project("PhotoSend")

# 3. 定义路径变量（保持你的路径逻辑，修正注释）
set(CPP_DIR ${CMAKE_CURRENT_SOURCE_DIR})
set(INCLUDE_DIR ${CPP_DIR}/libs/include)  # 你的头文件目录（正确）
set(LIBS_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../../../libs/arm64-v8a)  # 动态库目录（正确）

# 调试输出路径（保留，方便确认路径是否正确）
message(STATUS "CPP_DIR = ${CPP_DIR}")
message(STATUS "INCLUDE_DIR = ${INCLUDE_DIR}")
message(STATUS "LIBS_DIR = ${LIBS_DIR}")

# 4. 头文件搜索路径（保持不变，正确）
include_directories(
    ${INCLUDE_DIR}
    ${CPP_DIR}
)

# 5. 动态库搜索路径（修正：移除系统库路径，鸿蒙系统库由 NDK 自动处理）
link_directories(
    ${LIBS_DIR}  # 仅保留你的动态库路径
)




# 6. 业务 Native 库（保持不变）
add_library(entry SHARED
Camera/native_camera.h Camera/native_camera.cpp  Camera/camera_device.cpp Camera/camera_device.h Camera/camera_preview.cpp Camera/camera_preview.h Camera/native_common.cpp Camera/native_common.h Camera/native_common.h)

# 7. 链接所有库（关键修改：链接动态库，补充缺失的依赖）
target_link_libraries(entry PUBLIC
    # 核心库：动态库无需加 lib 前缀，直接写库名（对应 libgphoto2.so 等）
    gphoto2          # 对应 libgphoto2.so
    gphoto2_port     # 对应 libgphoto2_port.so
    exif             # 对应 libexif.so（替换原来的 libexif 静态库）
    usb-1.0          # 对应 libusb-1.0.so（替换原来的 libusb-1.0 静态库）
    ltdl             # 对应 libltdl.so（替换原来的 libltdl 静态库） # 关键点：libgphoto2 通过它加载 ptp2.so
    # 补充缺失的依赖库（之前编译的其他库）
    z
    xml2
    ssl
    curl             # 对应 libcurl.so
    #gd               # 对应 libgd.so
    png16            # 对应 libpng16.so
    jpeg             # 对应 libjpeg.so
    # 鸿蒙系统库（保持不变）
    hilog_ndk.z
    ace_napi.z
)

# 8. 保留 NativeRender 配置（不变）
set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})
if(DEFINED PACKAGE_FIND_FILE)
    include(${PACKAGE_FIND_FILE})
endif()