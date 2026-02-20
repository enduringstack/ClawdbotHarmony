/**
 * location_fusion_napi.cpp — 多源位置融合 NAPI 绑定
 */
#include <napi/native_api.h>
#include "location_fusion.h"
#include <vector>
#include <string>
#include <unordered_map>

using namespace location_fusion;

// ============================================================
// Helper functions
// ============================================================

static double GetDoubleProp(napi_env env, napi_value obj, const char* key, double defaultVal = 0.0) {
    napi_value prop;
    napi_status status = napi_get_named_property(env, obj, key, &prop);
    if (status != napi_ok) return defaultVal;
    
    double val;
    status = napi_get_value_double(env, prop, &val);
    return (status == napi_ok) ? val : defaultVal;
}

static int GetIntProp(napi_env env, napi_value obj, const char* key, int defaultVal = 0) {
    napi_value prop;
    napi_status status = napi_get_named_property(env, obj, key, &prop);
    if (status != napi_ok) return defaultVal;
    
    int32_t val;
    status = napi_get_value_int32(env, prop, &val);
    return (status == napi_ok) ? val : defaultVal;
}

static std::string GetStringProp(napi_env env, napi_value obj, const char* key, const std::string& defaultVal = "") {
    napi_value prop;
    napi_status status = napi_get_named_property(env, obj, key, &prop);
    if (status != napi_ok) return defaultVal;
    
    size_t len;
    status = napi_get_value_string_utf8(env, prop, nullptr, 0, &len);
    if (status != napi_ok || len == 0) return defaultVal;
    
    std::string result(len, '\0');
    status = napi_get_value_string_utf8(env, prop, &result[0], len + 1, &len);
    return (status == napi_ok) ? result : defaultVal;
}

static napi_value CreateDouble(napi_env env, double val) {
    napi_value result;
    napi_create_double(env, val, &result);
    return result;
}

static napi_value CreateString(napi_env env, const std::string& str) {
    napi_value result;
    napi_create_string_utf8(env, str.c_str(), str.length(), &result);
    return result;
}

// 解析 LearnedSignals 对象
static LearnedSignals parseLearnedSignals(napi_env env, napi_value obj) {
    LearnedSignals signals;
    
    // wifiSsids: { [ssid: string]: number }
    napi_value wifiProp;
    if (napi_get_named_property(env, obj, "wifiSsids", &wifiProp) == napi_ok) {
        napi_value keys;
        napi_get_property_names(env, wifiProp, &keys);
        uint32_t keysLen;
        napi_get_array_length(env, keys, &keysLen);
        
        for (uint32_t i = 0; i < keysLen; i++) {
            napi_value key;
            napi_get_element(env, keys, i, &key);
            
            std::string ssid = GetStringProp(env, key, "");
            napi_value val;
            napi_get_property(env, wifiProp, key, &val);
            
            int32_t count;
            napi_get_value_int32(env, val, &count);
            
            if (!ssid.empty()) {
                signals.wifiSsids[ssid] = count;
            }
        }
    }
    
    // btDevices: { [device: string]: number }
    napi_value btProp;
    if (napi_get_named_property(env, obj, "btDevices", &btProp) == napi_ok) {
        napi_value keys;
        napi_get_property_names(env, btProp, &keys);
        uint32_t keysLen;
        napi_get_array_length(env, keys, &keysLen);
        
        for (uint32_t i = 0; i < keysLen; i++) {
            napi_value key;
            napi_get_element(env, keys, i, &key);
            
            std::string device = GetStringProp(env, key, "");
            napi_value val;
            napi_get_property(env, btProp, key, &val);
            
            int32_t count;
            napi_get_value_int32(env, val, &count);
            
            if (!device.empty()) {
                signals.btDevices[device] = count;
            }
        }
    }
    
    signals.totalObservations = GetIntProp(env, obj, "totalObservations", 0);
    
    return signals;
}

// ============================================================
// NAPI bindings
// ============================================================

/**
 * locationFusion.calculateConfidence(params) → FusionResult
 * 
 * params: {
 *   geofenceId, distance, gpsAccuracy, currentWifiSsid, currentBtDevices[],
 *   signals: { wifiSsids: {}, btDevices: {}, totalObservations }
 * }
 */
static napi_value CalculateConfidence(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    if (argc < 1) {
        napi_throw_error(env, nullptr, "Expected 1 argument: params");
        return nullptr;
    }
    
    std::string geofenceId = GetStringProp(env, args[0], "geofenceId", "");
    double distance = GetDoubleProp(env, args[0], "distance", 9999);
    double gpsAccuracy = GetDoubleProp(env, args[0], "gpsAccuracy", 100);
    std::string currentWifiSsid = GetStringProp(env, args[0], "currentWifiSsid", "");
    
    // 解析 currentBtDevices 数组
    std::vector<std::string> currentBtDevices;
    napi_value btArray;
    if (napi_get_named_property(env, args[0], "currentBtDevices", &btArray) == napi_ok) {
        uint32_t len;
        napi_get_array_length(env, btArray, &len);
        for (uint32_t i = 0; i < len; i++) {
            napi_value elem;
            napi_get_element(env, btArray, i, &elem);
            currentBtDevices.push_back(GetStringProp(env, elem, ""));
        }
    }
    
    // 解析 signals
    napi_value signalsObj;
    LearnedSignals signals;
    if (napi_get_named_property(env, args[0], "signals", &signalsObj) == napi_ok) {
        signals = parseLearnedSignals(env, signalsObj);
    }
    
    // 计算
    LocationFusion fusion;
    auto result = fusion.calculateConfidence(geofenceId, distance, gpsAccuracy,
                                             currentWifiSsid, currentBtDevices, signals);
    
    // 返回
    napi_value obj;
    napi_create_object(env, &obj);
    
    napi_set_named_property(env, obj, "geofenceId", CreateString(env, result.geofenceId));
    napi_set_named_property(env, obj, "confidence", CreateDouble(env, result.confidence));
    napi_set_named_property(env, obj, "gpsConfidence", CreateDouble(env, result.gpsConfidence));
    napi_set_named_property(env, obj, "wifiConfidence", CreateDouble(env, result.wifiConfidence));
    napi_set_named_property(env, obj, "btConfidence", CreateDouble(env, result.btConfidence));
    napi_set_named_property(env, obj, "source", CreateString(env, result.source));
    
    return obj;
}

/**
 * locationFusion.calculateAllConfidences(params) → FusionResult[]
 */
static napi_value CalculateAllConfidences(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    if (argc < 1) {
        napi_throw_error(env, nullptr, "Expected 1 argument: params");
        return nullptr;
    }
    
    double gpsAccuracy = GetDoubleProp(env, args[0], "gpsAccuracy", 100);
    std::string currentWifiSsid = GetStringProp(env, args[0], "currentWifiSsid", "");
    
    // 解析 currentBtDevices
    std::vector<std::string> currentBtDevices;
    napi_value btArray;
    if (napi_get_named_property(env, args[0], "currentBtDevices", &btArray) == napi_ok) {
        uint32_t len;
        napi_get_array_length(env, btArray, &len);
        for (uint32_t i = 0; i < len; i++) {
            napi_value elem;
            napi_get_element(env, btArray, i, &elem);
            currentBtDevices.push_back(GetStringProp(env, elem, ""));
        }
    }
    
    // 解析 geofenceDistances: [{ id, distance }]
    std::vector<std::pair<std::string, double>> geofenceDistances;
    napi_value distArray;
    if (napi_get_named_property(env, args[0], "geofenceDistances", &distArray) == napi_ok) {
        uint32_t len;
        napi_get_array_length(env, distArray, &len);
        for (uint32_t i = 0; i < len; i++) {
            napi_value elem;
            napi_get_element(env, distArray, i, &elem);
            std::string id = GetStringProp(env, elem, "id", "");
            double dist = GetDoubleProp(env, elem, "distance", 9999);
            geofenceDistances.push_back({id, dist});
        }
    }
    
    // 解析 allSignals: { [geofenceId]: LearnedSignals }
    std::unordered_map<std::string, LearnedSignals> allSignals;
    napi_value signalsObj;
    if (napi_get_named_property(env, args[0], "allSignals", &signalsObj) == napi_ok) {
        napi_value keys;
        napi_get_property_names(env, signalsObj, &keys);
        uint32_t keysLen;
        napi_get_array_length(env, keys, &keysLen);
        
        for (uint32_t i = 0; i < keysLen; i++) {
            napi_value key;
            napi_get_element(env, keys, i, &key);
            std::string gfId = GetStringProp(env, key, "");
            
            napi_value sigObj;
            napi_get_property(env, signalsObj, key, &sigObj);
            
            allSignals[gfId] = parseLearnedSignals(env, sigObj);
        }
    }
    
    // 计算
    LocationFusion fusion;
    auto results = fusion.calculateAllConfidences(geofenceDistances, gpsAccuracy,
                                                  currentWifiSsid, currentBtDevices, allSignals);
    
    // 返回数组
    napi_value resultArray;
    napi_create_array_with_length(env, results.size(), &resultArray);
    
    for (size_t i = 0; i < results.size(); i++) {
        const auto& r = results[i];
        
        napi_value obj;
        napi_create_object(env, &obj);
        
        napi_set_named_property(env, obj, "geofenceId", CreateString(env, r.geofenceId));
        napi_set_named_property(env, obj, "confidence", CreateDouble(env, r.confidence));
        napi_set_named_property(env, obj, "gpsConfidence", CreateDouble(env, r.gpsConfidence));
        napi_set_named_property(env, obj, "wifiConfidence", CreateDouble(env, r.wifiConfidence));
        napi_set_named_property(env, obj, "btConfidence", CreateDouble(env, r.btConfidence));
        napi_set_named_property(env, obj, "source", CreateString(env, r.source));
        
        napi_set_element(env, resultArray, i, obj);
    }
    
    return resultArray;
}

// ============================================================
// Module registration
// ============================================================

EXTERN_C_START

static napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        {"calculateConfidence", nullptr, CalculateConfidence, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"calculateAllConfidences", nullptr, CalculateAllConfidences, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}

static napi_module location_fusion_module = {
    .nm_version = 1,
    .nm_flags = NAPI_MODULE_VERSION,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "location_fusion",
    .nm_priv = nullptr,
    .reserved = {0},
};

napi_module_import(&location_fusion_module);

EXTERN_C_END
