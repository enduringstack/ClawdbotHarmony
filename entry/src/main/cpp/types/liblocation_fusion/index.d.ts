interface LearnedSignals {
  wifiSsids: Record<string, number>;
  btDevices: Record<string, number>;
  totalObservations: number;
}

interface FusionResult {
  geofenceId: string;
  confidence: number;
  gpsConfidence: number;
  wifiConfidence: number;
  btConfidence: number;
  source: string;
}

export const calculateConfidence: (params: {
  geofenceId: string;
  distance: number;
  gpsAccuracy: number;
  currentWifiSsid: string;
  currentBtDevices: string[];
  signals: LearnedSignals;
}) => FusionResult;

export const calculateAllConfidences: (params: {
  geofenceDistances: Array<{ id: string; distance: number }>;
  gpsAccuracy: number;
  currentWifiSsid: string;
  currentBtDevices: string[];
  allSignals: Record<string, LearnedSignals>;
}) => FusionResult[];
