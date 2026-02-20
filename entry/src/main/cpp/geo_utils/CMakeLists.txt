# CMakeLists.txt for geo_utils module
cmake_minimum_required(VERSION 3.5.0)

add_library(geo_utils SHARED
    geo_utils_napi.cpp
)

target_include_directories(geo_utils PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${NATIVERENDER_ROOT_PATH}
)

target_link_libraries(geo_utils PUBLIC libace_napi.z.so)
