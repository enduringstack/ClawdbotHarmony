/**
 * location_fusion.h — 多源位置融合 C++ 实现
 *
 * 融合 GPS、WiFi、蓝牙信号，输出置信度 0~1
 */
#pragma once

#include <string>
#include <vector>
#include <unordered_map>
#include <cmath>

namespace location_fusion {

// ============================================================
// 数据类型
// ============================================================

/** 已学习信号 */
struct LearnedSignals {
    std::unordered_map<std::string, int> wifiSsids;    // ssid → 观测次数
    std::unordered_map<std::string, int> btDevices;    // deviceName → 观测次数
    int totalObservations;
};

/** 融合结果 */
struct FusionResult {
    std::string geofenceId;
    double confidence;        // 0~1
    double gpsConfidence;
    double wifiConfidence;
    double btConfidence;
    std::string source;       // "gps" | "wifi" | "bt"
};

/** 融合配置 */
struct FusionConfig {
    double gpsHighConfidenceRadius = 50.0;    // 50m 内 → 1.0
    double gpsDecayScale = 200.0;             // 指数衰减尺度
    double gpsMinConfidence = 0.05;           // 最低 GPS 置信度
    double wifiMatchConfidence = 0.95;
    double wifiNoMatchConfidence = 0.1;
    double btMatchConfidence = 0.8;
    int learningMinObservations = 3;          // 最少观测次数
    double learningGpsAccuracyThreshold = 30.0;  // GPS 精度阈值
};

// ============================================================
// 位置融合器
// ============================================================

class LocationFusion {
public:
    explicit LocationFusion(const FusionConfig& config = FusionConfig{})
        : config_(config) {}
    
    /**
     * 计算单点融合置信度
     * @param geofenceId 围栏ID
     * @param distance GPS 距离围栏中心的距离（米）
     * @param gpsAccuracy GPS 精度（米）
     * @param currentWifiSsid 当前 WiFi SSID
     * @param currentBtDevices 当前蓝牙设备列表
     * @param signals 已学习信号
     */
    FusionResult calculateConfidence(
        const std::string& geofenceId,
        double distance,
        double gpsAccuracy,
        const std::string& currentWifiSsid,
        const std::vector<std::string>& currentBtDevices,
        const LearnedSignals& signals) {
        
        FusionResult result;
        result.geofenceId = geofenceId;
        
        // GPS 置信度
        result.gpsConfidence = calcGpsConfidence(distance, gpsAccuracy);
        
        // WiFi 置信度
        result.wifiConfidence = calcWifiConfidence(currentWifiSsid, signals);
        
        // BT 置信度
        result.btConfidence = calcBtConfidence(currentBtDevices, signals);
        
        // 融合：取最大值
        result.confidence = std::max({result.gpsConfidence, result.wifiConfidence, result.btConfidence});
        
        // GPS 低质量时，WiFi/BT 提升权重
        bool gpsLowQuality = gpsAccuracy > 100;
        if (gpsLowQuality && (result.wifiConfidence > 0.5 || result.btConfidence > 0.5)) {
            double nonGpsMax = std::max(result.wifiConfidence, result.btConfidence);
            result.confidence = std::max(result.confidence, std::min(nonGpsMax + 0.05, 1.0));
        }
        
        // 确定主要来源
        if (result.wifiConfidence >= result.gpsConfidence && result.wifiConfidence >= result.btConfidence) {
            result.source = "wifi";
        } else if (result.btConfidence >= result.gpsConfidence && result.btConfidence >= result.wifiConfidence) {
            result.source = "bt";
        } else {
            result.source = "gps";
        }
        
        return result;
    }
    
    /**
     * 批量计算所有围栏的置信度
     */
    std::vector<FusionResult> calculateAllConfidences(
        const std::vector<std::pair<std::string, double>>& geofenceDistances,  // (id, distance)
        double gpsAccuracy,
        const std::string& currentWifiSsid,
        const std::vector<std::string>& currentBtDevices,
        const std::unordered_map<std::string, LearnedSignals>& allSignals) {
        
        std::vector<FusionResult> results;
        results.reserve(geofenceDistances.size());
        
        for (const auto& [gfId, distance] : geofenceDistances) {
            auto it = allSignals.find(gfId);
            const LearnedSignals& signals = (it != allSignals.end()) ? it->second : LearnedSignals{};
            
            auto result = calculateConfidence(gfId, distance, gpsAccuracy, 
                                             currentWifiSsid, currentBtDevices, signals);
            results.push_back(result);
        }
        
        return results;
    }
    
    /**
     * 学习信号（当 GPS 高精度确认在围栏内时调用）
     */
    static void learnSignal(
        LearnedSignals& signals,
        const std::string& wifiSsid,
        const std::vector<std::string>& btDevices) {
        
        if (!wifiSsid.empty()) {
            signals.wifiSsids[wifiSsid]++;
        }
        
        for (const auto& device : btDevices) {
            if (!device.empty()) {
                signals.btDevices[device]++;
            }
        }
        
        signals.totalObservations++;
    }

private:
    FusionConfig config_;
    
    /**
     * 计算 GPS 置信度
     */
    double calcGpsConfidence(double distance, double accuracy) {
        if (distance < config_.gpsHighConfidenceRadius) {
            return 1.0;
        }
        
        if (distance < config_.gpsDecayScale * 3) {
            // 指数衰减
            return std::max(std::exp(-distance / config_.gpsDecayScale), 
                           config_.gpsMinConfidence);
        }
        
        return config_.gpsMinConfidence;
    }
    
    /**
     * 计算 WiFi 置信度
     */
    double calcWifiConfidence(const std::string& currentSsid, const LearnedSignals& signals) {
        if (currentSsid.empty()) return 0;
        
        if (signals.totalObservations < config_.learningMinObservations) {
            return 0;  // 观测不足
        }
        
        auto it = signals.wifiSsids.find(currentSsid);
        if (it != signals.wifiSsids.end() && it->second >= config_.learningMinObservations) {
            return config_.wifiMatchConfidence;
        }
        
        // 有已学习的 WiFi 但当前不匹配
        if (!signals.wifiSsids.empty()) {
            return config_.wifiNoMatchConfidence;
        }
        
        return 0;
    }
    
    /**
     * 计算蓝牙置信度
     */
    double calcBtConfidence(const std::vector<std::string>& currentDevices, 
                           const LearnedSignals& signals) {
        if (currentDevices.empty()) return 0;
        
        if (signals.totalObservations < config_.learningMinObservations) {
            return 0;
        }
        
        // 任一已学习的 BT 设备匹配即可
        for (const auto& device : currentDevices) {
            auto it = signals.btDevices.find(device);
            if (it != signals.btDevices.end() && it->second >= config_.learningMinObservations) {
                return config_.btMatchConfidence;
            }
        }
        
        return 0;
    }
};

}  // namespace location_fusion
