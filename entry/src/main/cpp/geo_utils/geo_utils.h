/**
 * geo_utils.h — 地理计算工具 C++ 实现
 *
 * 高性能地理距离计算和围栏检测
 */
#pragma once

#include <string>
#include <vector>
#include <cmath>

namespace geo_utils {

// ============================================================
// 数据类型
// ============================================================

/** 地理围栏 */
struct Geofence {
    std::string id;
    std::string name;
    double latitude;
    double longitude;
    double radiusMeters;
    std::string category;
};

/** GPS 点 */
struct GeoPoint {
    double latitude;
    double longitude;
    int64_t timestamp;
    double accuracy;
};

/** 聚类结果 */
struct Cluster {
    std::string id;
    double centerLat;
    double centerLng;
    double radiusMeters;
    int pointCount;
    int64_t firstSeen;
    int64_t lastSeen;
    int64_t totalStayMs;
};

/** 围栏匹配结果 */
struct GeofenceMatch {
    std::string geofenceId;
    double distance;
    bool inside;
};

// ============================================================
// 常量
// ============================================================

constexpr double EARTH_RADIUS_METERS = 6371000.0;
constexpr double PI = 3.14159265358979323846;

// ============================================================
// 核心函数
// ============================================================

/**
 * 角度转弧度
 */
inline double toRad(double deg) {
    return deg * PI / 180.0;
}

/**
 * 弧度转角度
 */
inline double toDeg(double rad) {
    return rad * 180.0 / PI;
}

/**
 * Haversine 公式计算两点间距离（米）
 */
inline double haversineDistance(double lat1, double lon1, double lat2, double lon2) {
    double dLat = toRad(lat2 - lat1);
    double dLon = toRad(lon2 - lon1);
    
    double a = std::sin(dLat / 2) * std::sin(dLat / 2) +
               std::cos(toRad(lat1)) * std::cos(toRad(lat2)) *
               std::sin(dLon / 2) * std::sin(dLon / 2);
    
    double c = 2 * std::atan2(std::sqrt(a), std::sqrt(1 - a));
    
    return EARTH_RADIUS_METERS * c;
}

/**
 * 检查点是否在围栏内
 */
inline bool isInsideGeofence(double lat, double lon, const Geofence& gf) {
    double dist = haversineDistance(lat, lon, gf.latitude, gf.longitude);
    return dist <= gf.radiusMeters;
}

/**
 * 获取点所在的所有围栏
 */
inline std::vector<GeofenceMatch> getGeofencesAtLocation(
    double lat, double lon, const std::vector<Geofence>& geofences) {
    
    std::vector<GeofenceMatch> result;
    result.reserve(geofences.size());
    
    for (const auto& gf : geofences) {
        double dist = haversineDistance(lat, lon, gf.latitude, gf.longitude);
        result.push_back({
            gf.id,
            dist,
            dist <= gf.radiusMeters
        });
    }
    
    return result;
}

/**
 * 计算一组点的中心点（质心）
 */
inline void calculateCenter(const std::vector<GeoPoint>& points, double& outLat, double& outLng) {
    if (points.empty()) {
        outLat = 0;
        outLng = 0;
        return;
    }
    
    double sumLat = 0, sumLng = 0;
    for (const auto& p : points) {
        sumLat += p.latitude;
        sumLng += p.longitude;
    }
    
    outLat = sumLat / points.size();
    outLng = sumLng / points.size();
}

/**
 * 计算点到中心的距离百分位数（用于确定围栏半径）
 */
inline double calculatePercentileRadius(
    const std::vector<GeoPoint>& points,
    double centerLat, double centerLng,
    double percentile = 0.95) {
    
    if (points.empty()) return 100.0;  // 默认 100m
    
    std::vector<double> distances;
    distances.reserve(points.size());
    
    for (const auto& p : points) {
        distances.push_back(haversineDistance(centerLat, centerLng, p.latitude, p.longitude));
    }
    
    std::sort(distances.begin(), distances.end());
    
    size_t idx = static_cast<size_t>(distances.size() * percentile);
    if (idx >= distances.size()) idx = distances.size() - 1;
    
    double radius = distances[idx];
    // 限制在 50-500m 范围内
    return std::max(50.0, std::min(500.0, radius));
}

/**
 * 计算两点间的时间差（毫秒）
 */
inline int64_t timeDiffMs(int64_t t1, int64_t t2) {
    return t2 > t1 ? (t2 - t1) : (t1 - t2);
}

}  // namespace geo_utils
