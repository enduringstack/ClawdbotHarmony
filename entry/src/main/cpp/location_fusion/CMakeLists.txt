# CMakeLists.txt for location_fusion module
cmake_minimum_required(VERSION 3.5.0)

add_library(location_fusion SHARED
    location_fusion_napi.cpp
)

target_include_directories(location_fusion PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${NATIVERENDER_ROOT_PATH}
)

target_link_libraries(location_fusion PUBLIC libace_napi.z.so)
