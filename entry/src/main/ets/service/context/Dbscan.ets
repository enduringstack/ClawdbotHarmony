/**
 * Dbscan.ets — ArkTS wrapper for native dbscan C++ NAPI module
 */

import dbscanNative from 'libdbscan.so';

/** GPS 点 */
export interface ClusterPoint {
  latitude: number;
  longitude: number;
  timestamp: number;
  accuracy: number;
}

/** 时间模式 */
export interface TimePattern {
  weekdayHours: number[];
  weekendHours: number[];
  nightCount: number;
  workdayCount: number;
  weekendCount: number;
}

/** 聚类结果 */
export interface ClusterResult {
  id: string;
  centerLat: number;
  centerLng: number;
  radiusMeters: number;
  pointCount: number;
  firstSeen: number;
  lastSeen: number;
  totalStayMs: number;
  timePattern: TimePattern;
  suggestedCategory: string;
  suggestedName: string;
  confidence: number;
}

/** 聚类配置 */
export class ClusterConfig {
  epsilonMeters: number = 50;
  minSamples: number = 10;
}

export function cluster(points: ClusterPoint[], config?: ClusterConfig): ClusterResult[] {
  if (config) {
    return dbscanNative.cluster(points, config) as ClusterResult[];
  }
  return dbscanNative.cluster(points) as ClusterResult[];
}
