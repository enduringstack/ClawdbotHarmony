/**
 * GeoUtils.ets — ArkTS wrapper for native geo_utils C++ NAPI module
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

/** 中心点 */
export interface CenterResult {
  latitude: number;
  longitude: number;
}

export function haversineDistance(lat1: number, lon1: number, lat2: number, lon2: number): number {
  return geoUtilsNative.haversineDistance(lat1, lon1, lat2, lon2) as number;
}

export function isInsideGeofence(lat: number, lon: number, geofence: Geofence): boolean {
  return geoUtilsNative.isInsideGeofence(lat, lon, geofence) as boolean;
}

export function getGeofencesAtLocation(lat: number, lon: number, geofences: Geofence[]): GeofenceMatch[] {
  return geoUtilsNative.getGeofencesAtLocation(lat, lon, geofences) as GeofenceMatch[];
}

export function calculateCenter(points: GeoPoint[]): CenterResult {
  return geoUtilsNative.calculateCenter(points) as CenterResult;
}

export function calculateRadius(
  points: GeoPoint[],
  centerLat: number,
  centerLng: number,
  percentile: number = 0.95
): number {
  return geoUtilsNative.calculateRadius(points, centerLat, centerLng, percentile) as number;
}
