/**
 * dbscan_cluster_napi.cpp — DBSCAN 聚类 NAPI 绑定
 */
#include <napi/native_api.h>
#include "dbscan_cluster.h"
#include <vector>
#include <string>

using namespace dbscan;

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

static int64_t GetInt64Prop(napi_env env, napi_value obj, const char* key, int64_t defaultVal = 0) {
    napi_value prop;
    napi_status status = napi_get_named_property(env, obj, key, &prop);
    if (status != napi_ok) return defaultVal;
    
    int64_t val;
    status = napi_get_value_int64(env, prop, &val);
    return (status == napi_ok) ? val : defaultVal;
}

static napi_value CreateDouble(napi_env env, double val) {
    napi_value result;
    napi_create_double(env, val, &result);
    return result;
}

static napi_value CreateInt64(napi_env env, int64_t val) {
    napi_value result;
    napi_create_int64(env, val, &result);
    return result;
}

static napi_value CreateString(napi_env env, const std::string& str) {
    napi_value result;
    napi_create_string_utf8(env, str.c_str(), str.length(), &result);
    return result;
}

static napi_value CreateIntArray(napi_env env, const std::vector<int>& arr) {
    napi_value result;
    napi_create_array_with_length(env, arr.size(), &result);
    for (size_t i = 0; i < arr.size(); i++) {
        napi_value val;
        napi_create_int32(env, arr[i], &val);
        napi_set_element(env, result, i, val);
    }
    return result;
}

// ============================================================
// NAPI bindings
// ============================================================

/**
 * dbscan.cluster(points, config?) → ClusterResult[]
 * 
 * points: [{ latitude, longitude, timestamp, accuracy }]
 * config: { epsilonMeters?, minSamples? }
 */
static napi_value RunCluster(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    if (argc < 1) {
        napi_throw_error(env, nullptr, "Expected at least 1 argument: points");
        return nullptr;
    }
    
    // 解析配置
    ClusterConfig config;
    if (argc >= 2) {
        config.epsilonMeters = GetDoubleProp(env, args[1], "epsilonMeters", 50.0);
        config.minSamples = GetIntProp(env, args[1], "minSamples", 10);
    }
    
    // 解析 points 数组
    std::vector<GeoPoint> points;
    uint32_t arrayLen;
    napi_get_array_length(env, args[0], &arrayLen);
    points.reserve(arrayLen);
    
    for (uint32_t i = 0; i < arrayLen; i++) {
        napi_value elem;
        napi_get_element(env, args[0], i, &elem);
        
        GeoPoint p;
        p.latitude = GetDoubleProp(env, elem, "latitude", 0);
        p.longitude = GetDoubleProp(env, elem, "longitude", 0);
        p.timestamp = GetInt64Prop(env, elem, "timestamp", 0);
        p.accuracy = GetDoubleProp(env, elem, "accuracy", 10);
        
        points.push_back(p);
    }
    
    // 执行聚类
    DBSCAN dbscan(config);
    auto results = dbscan.cluster(points);
    
    // 构建返回数组
    napi_value resultArray;
    napi_create_array_with_length(env, results.size(), &resultArray);
    
    for (size_t i = 0; i < results.size(); i++) {
        const auto& cr = results[i];
        
        napi_value obj;
        napi_create_object(env, &obj);
        
        napi_set_named_property(env, obj, "id", CreateString(env, cr.id));
        napi_set_named_property(env, obj, "centerLat", CreateDouble(env, cr.centerLat));
        napi_set_named_property(env, obj, "centerLng", CreateDouble(env, cr.centerLng));
        napi_set_named_property(env, obj, "radiusMeters", CreateDouble(env, cr.radiusMeters));
        napi_set_named_property(env, obj, "pointCount", CreateInt64(env, cr.pointCount));
        napi_set_named_property(env, obj, "firstSeen", CreateInt64(env, cr.firstSeen));
        napi_set_named_property(env, obj, "lastSeen", CreateInt64(env, cr.lastSeen));
        napi_set_named_property(env, obj, "totalStayMs", CreateInt64(env, cr.totalStayMs));
        
        // TimePattern
        napi_value timePattern;
        napi_create_object(env, &timePattern);
        napi_set_named_property(env, timePattern, "weekdayHours", CreateIntArray(env, cr.timePattern.weekdayHours));
        napi_set_named_property(env, timePattern, "weekendHours", CreateIntArray(env, cr.timePattern.weekendHours));
        napi_set_named_property(env, timePattern, "nightCount", CreateInt64(env, cr.timePattern.nightCount));
        napi_set_named_property(env, timePattern, "workdayCount", CreateInt64(env, cr.timePattern.workdayCount));
        napi_set_named_property(env, timePattern, "weekendCount", CreateInt64(env, cr.timePattern.weekendCount));
        napi_set_named_property(env, obj, "timePattern", timePattern);
        
        napi_set_named_property(env, obj, "suggestedCategory", CreateString(env, cr.suggestedCategory));
        napi_set_named_property(env, obj, "suggestedName", CreateString(env, cr.suggestedName));
        napi_set_named_property(env, obj, "confidence", CreateDouble(env, cr.confidence));
        
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
        {"cluster", nullptr, RunCluster, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}

static napi_module dbscan_module = {
    .nm_version = 1,
    .nm_flags = NAPI_MODULE_VERSION,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "dbscan",
    .nm_priv = nullptr,
    .reserved = {0},
};


EXTERN_C_END

extern "C" __attribute__((constructor)) void RegisterDbscanModule(void) {
    napi_module_register(&dbscan_module);
}
