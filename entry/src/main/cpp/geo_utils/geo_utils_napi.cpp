/**
 * geo_utils_napi.cpp — 地理计算工具 NAPI 绑定
 */
#include <napi/native_api.h>
#include "geo_utils.h"
#include <vector>
#include <string>

using namespace geo_utils;

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

static napi_value CreateBool(napi_env env, bool val) {
    napi_value result;
    napi_get_boolean(env, val, &result);
    return result;
}

static napi_value CreateString(napi_env env, const std::string& str) {
    napi_value result;
    napi_create_string_utf8(env, str.c_str(), str.length(), &result);
    return result;
}

// ============================================================
// NAPI bindings
// ============================================================

/**
 * geoUtils.haversineDistance(lat1, lon1, lat2, lon2) → meters
 */
static napi_value HaversineDistance(napi_env env, napi_callback_info info) {
    size_t argc = 4;
    napi_value args[4];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    if (argc < 4) {
        napi_throw_error(env, nullptr, "Expected 4 arguments: lat1, lon1, lat2, lon2");
        return nullptr;
    }
    
    double lat1, lon1, lat2, lon2;
    napi_get_value_double(env, args[0], &lat1);
    napi_get_value_double(env, args[1], &lon1);
    napi_get_value_double(env, args[2], &lat2);
    napi_get_value_double(env, args[3], &lon2);
    
    double distance = haversineDistance(lat1, lon1, lat2, lon2);
    
    return CreateDouble(env, distance);
}

/**
 * geoUtils.isInsideGeofence(lat, lon, geofence) → bool
 * geofence: { latitude, longitude, radiusMeters }
 */
static napi_value IsInsideGeofence(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value args[3];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    if (argc < 3) {
        napi_throw_error(env, nullptr, "Expected 3 arguments: lat, lon, geofence");
        return nullptr;
    }
    
    double lat, lon;
    napi_get_value_double(env, args[0], &lat);
    napi_get_value_double(env, args[1], &lon);
    
    Geofence gf;
    gf.latitude = GetDoubleProp(env, args[2], "latitude", 0);
    gf.longitude = GetDoubleProp(env, args[2], "longitude", 0);
    gf.radiusMeters = GetDoubleProp(env, args[2], "radiusMeters", 100);
    
    bool inside = isInsideGeofence(lat, lon, gf);
    
    return CreateBool(env, inside);
}

/**
 * geoUtils.getGeofencesAtLocation(lat, lon, geofences) → [{ geofenceId, distance, inside }]
 * geofences: [{ id, latitude, longitude, radiusMeters, ... }]
 */
static napi_value GetGeofencesAtLocation(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value args[3];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    if (argc < 3) {
        napi_throw_error(env, nullptr, "Expected 3 arguments: lat, lon, geofences");
        return nullptr;
    }
    
    double lat, lon;
    napi_get_value_double(env, args[0], &lat);
    napi_get_value_double(env, args[1], &lon);
    
    // 解析 geofences 数组
    std::vector<Geofence> geofences;
    uint32_t arrayLen;
    napi_get_array_length(env, args[2], &arrayLen);
    
    for (uint32_t i = 0; i < arrayLen; i++) {
        napi_value elem;
        napi_get_element(env, args[2], i, &elem);
        
        Geofence gf;
        gf.id = GetStringProp(env, elem, "id", "");
        gf.latitude = GetDoubleProp(env, elem, "latitude", 0);
        gf.longitude = GetDoubleProp(env, elem, "longitude", 0);
        gf.radiusMeters = GetDoubleProp(env, elem, "radiusMeters", 100);
        
        geofences.push_back(gf);
    }
    
    // 计算
    auto matches = getGeofencesAtLocation(lat, lon, geofences);
    
    // 返回结果数组
    napi_value result;
    napi_create_array_with_length(env, matches.size(), &result);
    
    for (size_t i = 0; i < matches.size(); i++) {
        napi_value obj;
        napi_create_object(env, &obj);
        
        napi_set_named_property(env, obj, "geofenceId", CreateString(env, matches[i].geofenceId));
        napi_set_named_property(env, obj, "distance", CreateDouble(env, matches[i].distance));
        napi_set_named_property(env, obj, "inside", CreateBool(env, matches[i].inside));
        
        napi_set_element(env, result, i, obj);
    }
    
    return result;
}

/**
 * geoUtils.calculateCenter(points) → { latitude, longitude }
 * points: [{ latitude, longitude, ... }]
 */
static napi_value CalculateCenter(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    if (argc < 1) {
        napi_throw_error(env, nullptr, "Expected 1 argument: points");
        return nullptr;
    }
    
    // 解析 points 数组
    std::vector<GeoPoint> points;
    uint32_t arrayLen;
    napi_get_array_length(env, args[0], &arrayLen);
    
    for (uint32_t i = 0; i < arrayLen; i++) {
        napi_value elem;
        napi_get_element(env, args[0], i, &elem);
        
        GeoPoint p;
        p.latitude = GetDoubleProp(env, elem, "latitude", 0);
        p.longitude = GetDoubleProp(env, elem, "longitude", 0);
        
        points.push_back(p);
    }
    
    // 计算
    double centerLat, centerLng;
    calculateCenter(points, centerLat, centerLng);
    
    // 返回
    napi_value result;
    napi_create_object(env, &result);
    
    napi_set_named_property(env, result, "latitude", CreateDouble(env, centerLat));
    napi_set_named_property(env, result, "longitude", CreateDouble(env, centerLng));
    
    return result;
}

/**
 * geoUtils.calculateRadius(points, centerLat, centerLng, percentile) → meters
 */
static napi_value CalculateRadius(napi_env env, napi_callback_info info) {
    size_t argc = 4;
    napi_value args[4];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    if (argc < 3) {
        napi_throw_error(env, nullptr, "Expected 3-4 arguments: points, centerLat, centerLng, percentile");
        return nullptr;
    }
    
    // 解析 points 数组
    std::vector<GeoPoint> points;
    uint32_t arrayLen;
    napi_get_array_length(env, args[0], &arrayLen);
    
    for (uint32_t i = 0; i < arrayLen; i++) {
        napi_value elem;
        napi_get_element(env, args[0], i, &elem);
        
        GeoPoint p;
        p.latitude = GetDoubleProp(env, elem, "latitude", 0);
        p.longitude = GetDoubleProp(env, elem, "longitude", 0);
        
        points.push_back(p);
    }
    
    double centerLat, centerLng;
    napi_get_value_double(env, args[1], &centerLat);
    napi_get_value_double(env, args[2], &centerLng);
    
    double percentile = 0.95;
    if (argc >= 4) {
        napi_get_value_double(env, args[3], &percentile);
    }
    
    double radius = calculatePercentileRadius(points, centerLat, centerLng, percentile);
    
    return CreateDouble(env, radius);
}

// ============================================================
// Module registration
// ============================================================

EXTERN_C_START

static napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        {"haversineDistance", nullptr, HaversineDistance, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"isInsideGeofence", nullptr, IsInsideGeofence, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getGeofencesAtLocation", nullptr, GetGeofencesAtLocation, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"calculateCenter", nullptr, CalculateCenter, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"calculateRadius", nullptr, CalculateRadius, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}

static napi_module geo_utils_module = {
    .nm_version = 1,
    .nm_flags = NAPI_MODULE_VERSION,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "geo_utils",
    .nm_priv = nullptr,
    .reserved = {0},
};


EXTERN_C_END

extern "C" __attribute__((constructor)) void RegisterGeoUtilsModule(void) {
    napi_module_register(&geo_utils_module);
}
