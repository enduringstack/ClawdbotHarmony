cmake_minimum_required(VERSION 3.5.0)
project(cann_llm)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR}/..)

include_directories(
    ${CMAKE_CURRENT_SOURCE_DIR}
)

add_library(cann_llm SHARED cann_wrapper.cpp)

target_link_libraries(cann_llm PUBLIC
    libace_napi.z.so
    libhilog_ndk.z.so
    llm_core
    hiai_llm_engine
)
