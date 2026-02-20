export const haversineDistance: (lat1: number, lon1: number, lat2: number, lon2: number) => number;
export const isInsideGeofence: (lat: number, lon: number, geofence: {
  latitude: number; longitude: number; radiusMeters: number;
}) => boolean;
export const getGeofencesAtLocation: (lat: number, lon: number, geofences: Array<{
  id: string; latitude: number; longitude: number; radiusMeters: number;
}>) => Array<{ geofenceId: string; distance: number; inside: boolean }>;
export const calculateCenter: (points: Array<{ latitude: number; longitude: number }>) => {
  latitude: number; longitude: number;
};
export const calculateRadius: (
  points: Array<{ latitude: number; longitude: number }>,
  centerLat: number, centerLng: number, percentile?: number
) => number;
