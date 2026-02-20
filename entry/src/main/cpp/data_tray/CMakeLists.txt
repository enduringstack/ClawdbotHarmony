# CMakeLists.txt for data_tray module
cmake_minimum_required(VERSION 3.5.0)

add_library(data_tray SHARED
    data_tray_napi.cpp
)

target_include_directories(data_tray PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${NATIVERENDER_ROOT_PATH}
)

target_link_libraries(data_tray PUBLIC libace_napi.z.so)
