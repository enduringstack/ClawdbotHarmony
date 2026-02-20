export const put: (key: string, value: string, quality?: number, source?: string) => void;
export const get: (key: string) => { value: string | null; quality: number; fresh: boolean; ageMs: number };
export const getSnapshot: () => {
  timeOfDay: string; hour: string; dayOfWeek: string; isWeekend: string;
  motionState: string; batteryLevel: string; isCharging: string; networkType: string;
  geofence?: string; latitude?: string; longitude?: string; stepCount?: string;
};
export const setTTL: (key: string, ttlMs: number) => void;
export const getStatus: () => Array<{
  key: string; value: string; ageMs: number; ttlMs: number;
  fresh: boolean; effectiveQuality: number; source: string;
}>;
export const clear: () => void;
export const size: () => number;
