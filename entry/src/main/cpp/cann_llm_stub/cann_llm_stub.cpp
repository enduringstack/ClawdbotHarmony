#include "napi/native_api.h"
#include <hilog/log.h>

#undef LOG_DOMAIN
#define LOG_DOMAIN 0x0000

#undef LOG_TAG
#define LOG_TAG "CANN_LLM_STUB"

static napi_value IsAvailable(napi_env env, napi_callback_info info) {
    napi_value result;
    napi_get_boolean(env, false, &result);
    OH_LOG_INFO(LOG_APP, "[CANN_LLM_STUB] isAvailable: false (so files not found)");
    return result;
}

static napi_value Loadmodel(napi_env env, napi_callback_info info) {
    napi_value result;
    napi_create_string_utf8(env, "CANN LLM not available: so files not found. Please place libllm_core.so and libhiai_llm_engine.so in entry/src/main/cpp/lib64/", NAPI_AUTO_LENGTH, &result);
    return result;
}

static napi_value IsInitialized(napi_env env, napi_callback_info info) {
    napi_value result;
    napi_get_boolean(env, false, &result);
    return result;
}

static napi_value GetLastError(napi_env env, napi_callback_info info) {
    napi_value result;
    napi_create_string_utf8(env, "CANN LLM not available: so files not found", NAPI_AUTO_LENGTH, &result);
    return result;
}

static napi_value Answerget(napi_env env, napi_callback_info info) {
    return nullptr;
}

static napi_value Modelinfer(napi_env env, napi_callback_info info) {
    return nullptr;
}

static napi_value Deinitmodel(napi_env env, napi_callback_info info) {
    return nullptr;
}

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        { "isAvailable", nullptr, IsAvailable, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "loadmodel", nullptr, Loadmodel, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "isInitialized", nullptr, IsInitialized, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "getLastError", nullptr, GetLastError, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "answerget", nullptr, Answerget, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "modelinfer", nullptr, Modelinfer, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "deinitmodel", nullptr, Deinitmodel, nullptr, nullptr, nullptr, napi_default, nullptr },
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}
EXTERN_C_END

static napi_module cannLlmModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "cann_llm",
    .nm_priv = ((void*)0),
    .reserved = { 0 },
};

extern "C" __attribute__((constructor)) void RegisterCannLlmModule(void) {
    napi_module_register(&cannLlmModule);
}
