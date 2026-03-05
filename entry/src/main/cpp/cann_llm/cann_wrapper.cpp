#include "napi/native_api.h"
#include <hilog/log.h>
#include <string>
#include <thread>
#include "llm_core.h"

#undef LOG_DOMAIN
#define LOG_DOMAIN 0x0000

#undef LOG_TAG
#define LOG_TAG "CANN_LLM"

static napi_threadsafe_function g_tsf = nullptr;
static napi_env g_env = nullptr;

struct CallbackData {
    napi_ref callback = nullptr;
    std::string question = "";
};

static LLMCore_Config g_config;

static void InitDefaultConfig() {
    g_config.inferType = 1;
    g_config.modelPath = "/data/storage/el2/base/haps/entry/files/chs_7b_target_model/chs_7b_target_model.omc";
    g_config.weightDir = "/data/storage/el2/base/haps/entry/files/chs_7b_target_model";
    g_config.tokenizerPath = "/data/storage/el2/base/haps/entry/files/chs_7b_target_model/tokenizer.model";
    g_config.specModelPath = "/data/storage/el2/base/haps/entry/files/chs_7b_draft_model/chs_7b_draft_model.omc";
    g_config.specWeightDir = "/data/storage/el2/base/haps/entry/files/chs_7b_draft_model";
    g_config.loraCfgPath = "/data/storage/el2/base/haps/entry/files/chs_7b_target_model/chs_7b_target_model.omc.loraconf";
    g_config.specLoraCfgPath = "";
    g_config.isAsync = true;
    g_config.maxGenTokens = 512;
    g_config.seed = 99;
    g_config.topK = 16;
    g_config.topP = 0.8f;
    g_config.temperature = 0.7f;
    g_config.repetitionPenalty = 1.0f;
    g_config.doSample = false;
    g_config.gamma = 3;
    g_config.topHeadStr = "1,2,2";
    g_config.topKSpecStr = "6,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1;2,2,1,1,1,1,1,1,1,1,1,1,1,1,1,1;1,1,1,1,1,1,1,1,1,1,1,1,1,1,1";
    g_config.draftThreshold = 0.05f;
    g_config.typicalScaling = 1.0f;
    g_config.stopSeqStr = "[unused10]";
}

static std::string g_strModelPath;
static std::string g_strWeightDir;
static std::string g_strTokenizerPath;
static std::string g_strSpecModelPath;
static std::string g_strSpecWeightDir;
static std::string g_strLoraCfgPath;

static void CallJsCallback(napi_env env, napi_value jsCb, void *context, void *data) {
    if (env == nullptr || jsCb == nullptr || data == nullptr) {
        return;
    }

    char* token = static_cast<char*>(data);
    napi_value js_partial;
    napi_create_string_utf8(env, token, NAPI_AUTO_LENGTH, &js_partial);

    napi_value result;
    napi_call_function(env, nullptr, jsCb, 1, &js_partial, &result);
    
    delete[] token;
}

static void onTokenCallback(const char* token, void* userData) {
    if (g_tsf && token) {
        OH_LOG_INFO(LOG_APP, "[Token Output] %{public}s", token);
        char* tokenCopy = new char[strlen(token) + 1];
        strcpy(tokenCopy, token);
        napi_call_threadsafe_function(g_tsf, tokenCopy, napi_tsfn_nonblocking);
    }
}

static void onDoneCallback(void* userData) {
    OH_LOG_INFO(LOG_APP, "Generation done callback");
}

static napi_value LoadModel(napi_env env, napi_callback_info info) {
    OH_LOG_INFO(LOG_APP, "========== LoadModel START ==========");
    
    InitDefaultConfig();
    
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    if (argc >= 1) {
        napi_value configObj = args[0];
        napi_value tmp;
        size_t len;
        
        auto getStringProp = [&](const char* name, std::string& out) {
            napi_value prop;
            if (napi_get_named_property(env, configObj, name, &prop) == napi_ok) {
                size_t strLen;
                napi_get_value_string_utf8(env, prop, nullptr, 0, &strLen);
                out.resize(strLen);
                napi_get_value_string_utf8(env, prop, &out[0], strLen + 1, &strLen);
                return true;
            }
            return false;
        };
        
        if (getStringProp("modelPath", g_strModelPath)) {
            g_config.modelPath = g_strModelPath.c_str();
            OH_LOG_INFO(LOG_APP, "LoadModel: modelPath=%{public}s", g_config.modelPath);
        }
        if (getStringProp("weightDir", g_strWeightDir)) {
            g_config.weightDir = g_strWeightDir.c_str();
        }
        if (getStringProp("tokenizerPath", g_strTokenizerPath)) {
            g_config.tokenizerPath = g_strTokenizerPath.c_str();
        }
        if (getStringProp("specModelPath", g_strSpecModelPath)) {
            g_config.specModelPath = g_strSpecModelPath.c_str();
        }
        if (getStringProp("specWeightDir", g_strSpecWeightDir)) {
            g_config.specWeightDir = g_strSpecWeightDir.c_str();
        }
        if (getStringProp("loraCfgPath", g_strLoraCfgPath)) {
            g_config.loraCfgPath = g_strLoraCfgPath.c_str();
        }
        
        napi_value intVal;
        if (napi_get_named_property(env, configObj, "maxGenTokens", &intVal) == napi_ok) {
            int32_t maxTokens;
            if (napi_get_value_int32(env, intVal, &maxTokens) == napi_ok) {
                g_config.maxGenTokens = maxTokens;
            }
        }
        
        napi_value floatVal;
        if (napi_get_named_property(env, configObj, "temperature", &floatVal) == napi_ok) {
            double temp;
            if (napi_get_value_double(env, floatVal, &temp) == napi_ok) {
                g_config.temperature = (float)temp;
            }
        }
    }
    
    OH_LOG_INFO(LOG_APP, "LoadModel: calling LLMCore_Init...");
    int ret = LLMCore_Init(&g_config);
    
    std::string result;
    if (ret == 0) {
        result = "模型加载完毕，可以提问了。(Pangu 7B + Speculative Inference + LoRA)";
    } else {
        result = std::string("模型加载失败: ") + LLMCore_GetLastError();
    }
    
    napi_value js_result;
    napi_create_string_utf8(env, result.c_str(), result.size(), &js_result);
    return js_result;
}

static napi_value AnswerGet(napi_env env, napi_callback_info info) {
    OH_LOG_INFO(LOG_APP, "AnswerGet start");
    
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    napi_value resourceName = nullptr;
    napi_create_string_utf8(env, "Thread-safe Function", NAPI_AUTO_LENGTH, &resourceName);

    napi_create_threadsafe_function(env, args[0], nullptr, resourceName, 0, 1, nullptr, nullptr, nullptr, 
        CallJsCallback, &g_tsf);
    
    return nullptr;
}

static napi_value ModelInfer(napi_env env, napi_callback_info info) {
    OH_LOG_INFO(LOG_APP, "========== ModelInfer START ==========");
    
    if (!LLMCore_IsInitialized()) {
        OH_LOG_ERROR(LOG_APP, "Model not initialized, call loadmodel first");
        return nullptr;
    }
    
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    size_t strLength;
    napi_get_value_string_utf8(env, args[0], nullptr, 0, &strLength);
    char* strBuffer = new char[strLength + 1];
    napi_get_value_string_utf8(env, args[0], strBuffer, strLength + 1, &strLength);
    
    std::string prompt(strBuffer);
    delete[] strBuffer;
    
    OH_LOG_INFO(LOG_APP, "User Input (from UI): %{public}s", prompt.c_str());
    OH_LOG_INFO(LOG_APP, "User Input length: %{public}zu chars", strLength);
    
    std::thread([prompt]() {
        LLMCore_Infer(prompt.c_str(), onTokenCallback, onDoneCallback, nullptr);
    }).detach();
    
    return nullptr;
}

static napi_value DeinitModel(napi_env env, napi_callback_info info) {
    OH_LOG_INFO(LOG_APP, "DeinitModel start");
    LLMCore_Deinit();
    return nullptr;
}

static napi_value IsInitialized(napi_env env, napi_callback_info info) {
    napi_value result;
    napi_get_boolean(env, LLMCore_IsInitialized(), &result);
    return result;
}

static napi_value GetLastError(napi_env env, napi_callback_info info) {
    const char* err = LLMCore_GetLastError();
    napi_value result;
    napi_create_string_utf8(env, err ? err : "", NAPI_AUTO_LENGTH, &result);
    return result;
}

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        { "loadmodel", nullptr, LoadModel, nullptr, nullptr, nullptr, napi_default, nullptr},
        { "modelinfer", nullptr, ModelInfer, nullptr, nullptr, nullptr, napi_default, nullptr},
        { "answerget", nullptr, AnswerGet, nullptr, nullptr, nullptr, napi_default, nullptr},
        { "deinitmodel", nullptr, DeinitModel, nullptr, nullptr, nullptr, napi_default, nullptr},
        { "isInitialized", nullptr, IsInitialized, nullptr, nullptr, nullptr, napi_default, nullptr},
        { "getLastError", nullptr, GetLastError, nullptr, nullptr, nullptr, napi_default, nullptr},
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
