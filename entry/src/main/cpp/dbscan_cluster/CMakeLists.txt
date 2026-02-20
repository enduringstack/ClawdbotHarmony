# CMakeLists.txt for dbscan_cluster module
cmake_minimum_required(VERSION 3.5.0)

add_library(dbscan SHARED
    dbscan_cluster_napi.cpp
)

target_include_directories(dbscan PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/../geo_utils
    ${NATIVERENDER_ROOT_PATH}
)

target_link_libraries(dbscan PUBLIC libace_napi.z.so)
