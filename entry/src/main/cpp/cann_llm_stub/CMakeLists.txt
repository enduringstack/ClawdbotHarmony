cmake_minimum_required(VERSION 3.5.0)
project(cann_llm_stub)

add_library(cann_llm SHARED cann_llm_stub.cpp)

target_link_libraries(cann_llm PUBLIC
    libace_napi.z.so
    libhilog_ndk.z.so
)
