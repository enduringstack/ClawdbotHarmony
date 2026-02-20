/**
 * dbscan_cluster.h — DBSCAN 聚类算法 C++ 实现
 *
 * 基于 GPS 历史点自动发现常去位置
 */
#pragma once

#include "geo_utils.h"
#include <vector>
#include <unordered_set>
#include <string>
#include <algorithm>
#include <cstdint>

namespace dbscan {

// 使用 geo_utils 的特定函数而非整个命名空间
using geo_utils::GeoPoint;
using geo_utils::haversineDistance;
using geo_utils::calculateCenter;
using geo_utils::calculatePercentileRadius;

// ============================================================
// 数据类型
// ============================================================

/** 时间模式 */
struct TimePattern {
    std::vector<int> weekdayHours;   // 工作日出现的小时
    std::vector<int> weekendHours;   // 周末出现的小时
    int nightCount;                  // 22:00-06:00 出现次数
    int workdayCount;                // 工作日 09:00-18:00 出现次数
    int weekendCount;                // 周末出现次数
};

/** 聚类结果（扩展） */
struct ClusterResult {
    std::string id;
    double centerLat;
    double centerLng;
    double radiusMeters;
    int pointCount;
    int64_t firstSeen;
    int64_t lastSeen;
    int64_t totalStayMs;
    TimePattern timePattern;
    std::string suggestedCategory;
    std::string suggestedName;
    double confidence;
};

/** 聚类配置 */
struct ClusterConfig {
    double epsilonMeters = 50.0;      // DBSCAN 半径
    int minSamples = 10;               // 最小点数
    int64_t maxStayGapMs = 3600000;   // 1小时内视为连续停留
};

// ============================================================
// DBSCAN 算法
// ============================================================

class DBSCAN {
public:
    explicit DBSCAN(const ClusterConfig& config = ClusterConfig{})
        : config_(config) {}
    
    /**
     * 对点集进行聚类
     * @param points 输入点集
     * @return 聚类结果列表
     */
    std::vector<ClusterResult> cluster(const std::vector<GeoPoint>& points) {
        std::vector<ClusterResult> results;
        
        if (points.size() < static_cast<size_t>(config_.minSamples)) {
            return results;
        }
        
        // 访问标记
        std::vector<int> labels(points.size(), -1);  // -1 = unclassified, -2 = noise, >=0 = cluster id
        int clusterId = 0;
        
        // DBSCAN 主循环
        for (size_t i = 0; i < points.size(); i++) {
            if (labels[i] != -1) continue;  // already processed
            
            auto neighbors = getNeighbors(points, i);
            if (neighbors.size() < static_cast<size_t>(config_.minSamples)) {
                labels[i] = -2;  // noise
                continue;
            }
            
            // 扩展聚类
            expandCluster(points, i, neighbors, labels, clusterId);
            clusterId++;
        }
        
        // 构建聚类结果
        for (int cid = 0; cid < clusterId; cid++) {
            std::vector<size_t> indices;
            for (size_t i = 0; i < points.size(); i++) {
                if (labels[i] == cid) {
                    indices.push_back(i);
                }
            }
            
            if (indices.size() >= static_cast<size_t>(config_.minSamples)) {
                auto result = buildClusterResult(points, indices, cid);
                results.push_back(result);
            }
        }
        
        return results;
    }

private:
    ClusterConfig config_;
    
    /**
     * 获取邻居点
     */
    std::vector<size_t> getNeighbors(const std::vector<GeoPoint>& points, size_t idx) {
        std::vector<size_t> neighbors;
        const auto& p = points[idx];
        
        for (size_t i = 0; i < points.size(); i++) {
            if (i == idx) continue;
            
            double dist = haversineDistance(p.latitude, p.longitude, 
                                           points[i].latitude, points[i].longitude);
            if (dist <= config_.epsilonMeters) {
                neighbors.push_back(i);
            }
        }
        
        return neighbors;
    }
    
    /**
     * 扩展聚类
     */
    void expandCluster(const std::vector<GeoPoint>& points,
                       size_t idx,
                       std::vector<size_t>& neighbors,
                       std::vector<int>& labels,
                       int clusterId) {
        labels[idx] = clusterId;
        
        std::vector<size_t> queue = neighbors;
        size_t queueIdx = 0;
        
        while (queueIdx < queue.size()) {
            size_t current = queue[queueIdx];
            queueIdx++;
            
            if (labels[current] == -2) {
                labels[current] = clusterId;  // change noise to border point
            }
            
            if (labels[current] != -1) continue;  // already processed
            
            labels[current] = clusterId;
            
            auto currentNeighbors = getNeighbors(points, current);
            if (currentNeighbors.size() >= static_cast<size_t>(config_.minSamples)) {
                // 添加新邻居到队列
                for (size_t n : currentNeighbors) {
                    if (labels[n] == -1 || labels[n] == -2) {
                        bool found = false;
                        for (size_t q : queue) {
                            if (q == n) { found = true; break; }
                        }
                        if (!found) {
                            queue.push_back(n);
                        }
                    }
                }
            }
        }
    }
    
    /**
     * 构建聚类结果
     */
    ClusterResult buildClusterResult(const std::vector<GeoPoint>& points,
                                     const std::vector<size_t>& indices,
                                     int clusterId) {
        ClusterResult result;
        result.id = "cluster_" + std::to_string(clusterId);
        
        // 提取点
        std::vector<GeoPoint> clusterPoints;
        clusterPoints.reserve(indices.size());
        for (size_t idx : indices) {
            clusterPoints.push_back(points[idx]);
        }
        
        // 计算中心
        calculateCenter(clusterPoints, result.centerLat, result.centerLng);
        
        // 计算半径
        result.radiusMeters = calculatePercentileRadius(clusterPoints, 
                                                        result.centerLat, 
                                                        result.centerLng, 0.95);
        
        result.pointCount = static_cast<int>(clusterPoints.size());
        
        // 时间戳
        std::vector<int64_t> timestamps;
        timestamps.reserve(clusterPoints.size());
        for (const auto& p : clusterPoints) {
            timestamps.push_back(p.timestamp);
        }
        std::sort(timestamps.begin(), timestamps.end());
        
        result.firstSeen = timestamps.front();
        result.lastSeen = timestamps.back();
        
        // 计算停留时间
        int64_t totalStay = 0;
        for (size_t i = 1; i < timestamps.size(); i++) {
            int64_t gap = timestamps[i] - timestamps[i - 1];
            if (gap < config_.maxStayGapMs) {
                totalStay += gap;
            }
        }
        result.totalStayMs = totalStay;
        
        // 分析时间模式
        result.timePattern = analyzeTimePattern(clusterPoints);
        
        // 推断类别
        result.suggestedCategory = inferCategory(result.timePattern, result.pointCount);
        
        // 生成名称
        result.suggestedName = generateName(result.suggestedCategory);
        
        // 计算置信度
        result.confidence = calculateConfidence(result);
        
        return result;
    }
    
    /**
     * 分析时间模式
     */
    TimePattern analyzeTimePattern(const std::vector<GeoPoint>& points) {
        TimePattern pattern;
        
        for (const auto& p : points) {
            // 简化：假设 timestamp 是 Unix 毫秒
            int64_t seconds = p.timestamp / 1000;
            int hour = (seconds / 3600) % 24;
            int dayOfWeek = ((seconds / 86400) + 4) % 7;  // 1970-01-01 是周四
            
            bool isWeekend = (dayOfWeek == 0 || dayOfWeek == 6);
            bool isNight = (hour >= 22 || hour < 6);
            bool isWorkHour = (hour >= 9 && hour < 18);
            
            if (isWeekend) {
                if (std::find(pattern.weekendHours.begin(), pattern.weekendHours.end(), hour) 
                    == pattern.weekendHours.end()) {
                    pattern.weekendHours.push_back(hour);
                }
                pattern.weekendCount++;
            } else {
                if (std::find(pattern.weekdayHours.begin(), pattern.weekdayHours.end(), hour) 
                    == pattern.weekdayHours.end()) {
                    pattern.weekdayHours.push_back(hour);
                }
                if (isWorkHour) {
                    pattern.workdayCount++;
                }
            }
            
            if (isNight) {
                pattern.nightCount++;
            }
        }
        
        return pattern;
    }
    
    /**
     * 推断类别
     */
    std::string inferCategory(const TimePattern& pattern, int totalPoints) {
        double nightRatio = static_cast<double>(pattern.nightCount) / totalPoints;
        double workdayRatio = static_cast<double>(pattern.workdayCount) / totalPoints;
        double weekendRatio = static_cast<double>(pattern.weekendCount) / totalPoints;
        
        if (nightRatio > 0.4) return "home";
        if (workdayRatio > 0.5 && weekendRatio < 0.2) return "work";
        if (weekendRatio > 0.4) return "gym";
        if (!pattern.weekdayHours.empty()) {
            for (int h : pattern.weekdayHours) {
                if (h >= 11 && h <= 14) return "restaurant";
            }
        }
        
        return "other";
    }
    
    /**
     * 生成名称
     */
    std::string generateName(const std::string& category) {
        static const std::unordered_map<std::string, std::string> names = {
            {"home", "家"},
            {"work", "公司"},
            {"gym", "健身房"},
            {"restaurant", "常去餐厅"},
            {"other", "常去地点"}
        };
        
        auto it = names.find(category);
        return it != names.end() ? it->second : "常去地点";
    }
    
    /**
     * 计算置信度
     */
    double calculateConfidence(const ClusterResult& result) {
        double score = 0;
        
        // 点数
        score += std::min(result.pointCount / 100.0, 0.3);
        
        // 停留时间（7天满分）
        score += std::min(result.totalStayMs / (86400000.0 * 7), 0.3);
        
        // 时间规律性
        double regularity = 0;
        if (!result.timePattern.weekdayHours.empty()) regularity += 0.2;
        if (!result.timePattern.weekendHours.empty()) regularity += 0.2;
        score += regularity;
        
        return std::min(score, 1.0);
    }
};

}  // namespace dbscan
