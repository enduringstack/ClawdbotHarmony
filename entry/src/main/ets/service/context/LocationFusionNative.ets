/**
 * LocationFusionNative.ets — ArkTS wrapper for native location_fusion C++ NAPI module
 */

import locationFusionNative from 'liblocation_fusion.so';

/** 已学习信号 */
export interface LearnedSignals {
  wifiSsids: Record<string, number>;
  btDevices: Record<string, number>;
  totalObservations: number;
}

/** 融合结果 */
export interface FusionResult {
  geofenceId: string;
  confidence: number;
  gpsConfidence: number;
  wifiConfidence: number;
  btConfidence: number;
  source: string;
}

/** 单个围栏置信度计算参数 */
export interface ConfidenceParams {
  geofenceId: string;
  distance: number;
  gpsAccuracy: number;
  currentWifiSsid: string;
  currentBtDevices: string[];
  signals: LearnedSignals;
}

/** 围栏距离 */
export interface GeofenceDistance {
  id: string;
  distance: number;
}

/** 批量计算参数 */
export interface AllConfidencesParams {
  geofenceDistances: GeofenceDistance[];
  gpsAccuracy: number;
  currentWifiSsid: string;
  currentBtDevices: string[];
  allSignals: Record<string, LearnedSignals>;
}

export function calculateConfidence(params: ConfidenceParams): FusionResult {
  return locationFusionNative.calculateConfidence(params) as FusionResult;
}

export function calculateAllConfidences(params: AllConfidencesParams): FusionResult[] {
  return locationFusionNative.calculateAllConfidences(params) as FusionResult[];
}
