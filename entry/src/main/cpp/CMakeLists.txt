# CMakeLists.txt for native modules
cmake_minimum_required(VERSION 3.5.0)
project(native_modules)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

# exec module - shell command execution
add_library(exec SHARED napi_exec.cpp)
target_link_libraries(exec PUBLIC libace_napi.z.so)

# voiceprint module - stub implementation for UI testing
add_subdirectory(voiceprint)

# data_tray module - sensor data caching with TTL
add_subdirectory(data_tray)

# geo_utils module - geographic distance calculations
add_subdirectory(geo_utils)

# dbscan_cluster module - DBSCAN clustering algorithm
add_subdirectory(dbscan_cluster)

# location_fusion module - multi-source location fusion
add_subdirectory(location_fusion)
