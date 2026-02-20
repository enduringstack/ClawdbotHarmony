export const cluster: (
  points: Array<{ latitude: number; longitude: number; timestamp: number; accuracy: number }>,
  config?: { epsilonMeters?: number; minSamples?: number }
) => Array<{
  id: string;
  centerLat: number;
  centerLng: number;
  radiusMeters: number;
  pointCount: number;
  firstSeen: number;
  lastSeen: number;
  totalStayMs: number;
  timePattern: {
    weekdayHours: number[];
    weekendHours: number[];
    nightCount: number;
    workdayCount: number;
    weekendCount: number;
  };
  suggestedCategory: string;
  suggestedName: string;
  confidence: number;
}>;
