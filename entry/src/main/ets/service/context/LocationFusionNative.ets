/**
 * LocationFusionNative.ets — ArkTS wrapper for native location_fusion C++ NAPI module
 *
 * 多源位置融合
 */

import locationFusionNative from 'liblocation_fusion.so';

/** 已学习信号 */
export interface LearnedSignals {
  wifiSsids: Record<string, number>;   // ssid → count
  btDevices: Record<string, number>;   // device → count
  totalObservations: number;
}

/** 融合结果 */
export interface FusionResult {
  geofenceId: string;
  confidence: number;
  gpsConfidence: number;
  wifiConfidence: number;
  btConfidence: number;
  source: string;  // 'gps' | 'wifi' | 'bt'
}

/**
 * 计算单个围栏的置信度
 */
export function calculateConfidence(params: {
  geofenceId: string;
  distance: number;
  gpsAccuracy: number;
  currentWifiSsid: string;
  currentBtDevices: string[];
  signals: LearnedSignals;
}): FusionResult {
  return locationFusionNative.calculateConfidence(params) as FusionResult;
}

/**
 * 批量计算所有围栏的置信度
 */
export function calculateAllConfidences(params: {
  geofenceDistances: Array<{ id: string; distance: number }>;
  gpsAccuracy: number;
  currentWifiSsid: string;
  currentBtDevices: string[];
  allSignals: Record<string, LearnedSignals>;
}): FusionResult[] {
  return locationFusionNative.calculateAllConfidences(params) as FusionResult[];
}

export default {
  calculateConfidence,
  calculateAllConfidences
};
