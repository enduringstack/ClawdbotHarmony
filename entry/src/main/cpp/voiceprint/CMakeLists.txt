# CMakeLists.txt for voiceprint (speaker embedding) native module
# Uses sherpa-onnx for speaker identification
cmake_minimum_required(VERSION 3.5.0)
project(voiceprint)

set(VOICEPRINT_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

# sherpa-onnx library path (populated by scripts/download_sherpa_onnx.sh)
set(SHERPA_ONNX_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../sherpa_onnx)

add_library(voiceprint SHARED voiceprint_napi.cpp)

# Link NAPI (required for all HarmonyOS native modules)
target_link_libraries(voiceprint PUBLIC libace_napi.z.so)

# TODO: Uncomment after downloading sherpa-onnx via scripts/download_sherpa_onnx.sh
# Check if sherpa-onnx is available
# if(EXISTS "${SHERPA_ONNX_DIR}/lib/${OHOS_ARCH}/libsherpa-onnx-c-api.so")
#     target_include_directories(voiceprint PRIVATE ${SHERPA_ONNX_DIR}/include)
#     target_link_directories(voiceprint PRIVATE ${SHERPA_ONNX_DIR}/lib/${OHOS_ARCH})
#     target_link_libraries(voiceprint PRIVATE
#         sherpa-onnx-c-api
#         sherpa-onnx-core
#         onnxruntime
#     )
#     target_compile_definitions(voiceprint PRIVATE SHERPA_ONNX_AVAILABLE=1)
#     message(STATUS "sherpa-onnx found at ${SHERPA_ONNX_DIR}")
# else()
#     message(WARNING "sherpa-onnx not found. Voiceprint module will use stub implementations.")
#     message(WARNING "Run scripts/download_sherpa_onnx.sh to download sherpa-onnx.")
# endif()
