# CMakeLists.txt for native modules
cmake_minimum_required(VERSION 3.5.0)
project(native_modules)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

# Check if CANN LLM so files exist
set(CANN_LLM_ENABLED OFF)
if(EXISTS "${NATIVERENDER_ROOT_PATH}/lib64/libllm_core.so" AND EXISTS "${NATIVERENDER_ROOT_PATH}/lib64/libhiai_llm_engine.so")
    set(CANN_LLM_ENABLED ON)
    message(STATUS "CANN LLM libraries found, enabling cann_llm module with full functionality")
    
    add_library(llm_core SHARED IMPORTED GLOBAL)
    set_target_properties(llm_core PROPERTIES IMPORTED_LOCATION
        ${NATIVERENDER_ROOT_PATH}/lib64/libllm_core.so)

    add_library(hiai_llm_engine SHARED IMPORTED GLOBAL)
    set_target_properties(hiai_llm_engine PROPERTIES IMPORTED_LOCATION
        ${NATIVERENDER_ROOT_PATH}/lib64/libhiai_llm_engine.so)
else()
    message(STATUS "CANN LLM libraries not found, using stub module")
    message(STATUS "To enable full functionality: place libllm_core.so and libhiai_llm_engine.so in entry/src/main/cpp/lib64/")
endif()

# exec module - shell command execution
add_library(exec SHARED napi_exec.cpp)
target_link_libraries(exec PUBLIC libace_napi.z.so)

# cann_llm module - on-device LLM inference
# Use full implementation if so files exist, otherwise use stub
if(CANN_LLM_ENABLED)
    add_subdirectory(cann_llm)
else()
    add_subdirectory(cann_llm_stub)
endif()

# context_engine module - rule engine + MAB + LinUCB
add_subdirectory(context_engine)

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

# motion_detector module - motion state detection + sampling strategy
add_subdirectory(motion_detector)

# place_learner module - place signal learning
add_subdirectory(place_learner)

# sleep_pattern module - sleep time learning
add_subdirectory(sleep_pattern)

# feedback_learner module - user feedback learning
add_subdirectory(feedback_learner)

# training_sync module - training data synchronization
add_subdirectory(training_sync)
