/**
 * GeoUtils.ets — ArkTS wrapper for native geo_utils C++ NAPI module
 *
 * 高性能地理计算
 */

import geoUtilsNative from 'libgeo_utils.so';

/** 围栏 */
export interface Geofence {
  id: string;
  name: string;
  latitude: number;
  longitude: number;
  radiusMeters: number;
  category: string;
}

/** GPS 点 */
export interface GeoPoint {
  latitude: number;
  longitude: number;
  timestamp?: number;
  accuracy?: number;
}

/** 围栏匹配结果 */
export interface GeofenceMatch {
  geofenceId: string;
  distance: number;
  inside: boolean;
}

/**
 * 计算两点间距离（Haversine 公式）
 */
export function haversineDistance(lat1: number, lon1: number, lat2: number, lon2: number): number {
  return geoUtilsNative.haversineDistance(lat1, lon1, lat2, lon2) as number;
}

/**
 * 检查点是否在围栏内
 */
export function isInsideGeofence(lat: number, lon: number, geofence: Geofence): boolean {
  return geoUtilsNative.isInsideGeofence(lat, lon, geofence) as boolean;
}

/**
 * 获取点所在的所有围栏
 */
export function getGeofencesAtLocation(lat: number, lon: number, geofences: Geofence[]): GeofenceMatch[] {
  return geoUtilsNative.getGeofencesAtLocation(lat, lon, geofences) as GeofenceMatch[];
}

/**
 * 计算一组点的中心点
 */
export function calculateCenter(points: GeoPoint[]): { latitude: number; longitude: number } {
  return geoUtilsNative.calculateCenter(points) as { latitude: number; longitude: number };
}

/**
 * 计算围栏半径（百分位数）
 */
export function calculateRadius(
  points: GeoPoint[],
  centerLat: number,
  centerLng: number,
  percentile: number = 0.95
): number {
  return geoUtilsNative.calculateRadius(points, centerLat, centerLng, percentile) as number;
}

export default {
  haversineDistance,
  isInsideGeofence,
  getGeofencesAtLocation,
  calculateCenter,
  calculateRadius
};
