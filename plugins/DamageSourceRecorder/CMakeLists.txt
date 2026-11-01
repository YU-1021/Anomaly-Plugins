cmake_minimum_required(VERSION 3.22)

project(AnomalyDamageSourceRecorder LANGUAGES CXX)

# Anomaly 插件是 Windows x64 原生动态库。
if(NOT WIN32 OR NOT CMAKE_SIZEOF_VOID_P EQUAL 8)
    message(FATAL_ERROR "Anomaly plugins target Windows x64")
endif()

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# 消费已安装的 Anomaly SDK 包。配置时把 AnomalySDK_DIR 指向
# <sdk>/lib/cmake/AnomalySDK（本仓库默认指向 D:/project/Anomaly/Anomaly-sdk）。
find_package(AnomalySDK CONFIG REQUIRED)

set(DSR_PACKAGE_DIR "${CMAKE_BINARY_DIR}/package/DamageSourceRecorder")

# anomaly_add_plugin 由 SDK 提供：输出 plugin.dll，并把 manifest.json / locales / assets
# 同步到包目录，包目录就是最终要复制到 Anomaly\plugins\ 的内容。
anomaly_add_plugin(anomaly_damage_source_recorder
    SOURCES src/plugin.cpp
    MANIFEST manifest.json
    PACKAGE_NAME DamageSourceRecorder
    OUTPUT_DIRECTORY "${DSR_PACKAGE_DIR}")

target_compile_definitions(anomaly_damage_source_recorder PRIVATE
    UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)

# 源文件是 UTF-8（含中文界面文案）：强制 MSVC 以 UTF-8 读取并按 UTF-8 生成执行字符集，
# 否则中文 Windows（代码页 936）会把源码里的中文误解析成 GBK 而编译失败或产生乱码。
if(MSVC)
    target_compile_options(anomaly_damage_source_recorder PRIVATE /utf-8)
endif()
