/**
 * PlaceAutoDiscoveryService - 地点自动发现服务
 *
 * 功能：
 * 1. 实时检测用户停留（GPS + WiFi 指纹）
 * 2. 停留超过阈值时，识别为新地点
 * 3. 使用地图 API 反查地点名称
 * 4. 发送通知让用户确认
 * 5. 记录访问历史
 * 6. 下次在附近时提供建议
 *
 * 所有显示字符串通过 I18n 多语言支持
 * 分类配置通过 PlaceCategoryService 管理
 */
import { geoLocationManager } from '@kit.LocationKit';
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { LogService } from '../../common/LogService';
import { I18n } from '../../common/I18n';
import { NotificationHelper } from '../NotificationHelper';
import { GeofenceManager, GeofenceEvent } from './GeofenceManager';
import { LocationFusionService } from './LocationFusionService';
import { GeoCodingService } from './GeoCodingService';
import { PlaceCategoryService } from './PlaceCategoryService';
import * as GeoUtils from './GeoUtils';
import {
  PendingPlace,
  PlaceVisit,
  DiscoveredPlace,
  PlaceDiscoveryConfig,
  DEFAULT_DISCOVERY_CONFIG,
  Geofence,
  GeofenceCategory,
  LocationState,
} from './ContextModels';

const TAG = 'PlaceAutoDiscovery';

interface PlaceDiscoveryData {
  version: number;
  pendingPlaces: PendingPlace[];
  discoveredPlaces: DiscoveredPlace[];
  visitHistory: PlaceVisit[];
  config: PlaceDiscoveryConfig;
}

interface LocationSnapshot {
  latitude: number;
  longitude: number;
  accuracy: number;
  timestamp: number;
  speed: number;
  wifiSsid?: string;
}

interface StayDetectionResult {
  isStaying: boolean;
  stayDurationMs: number;
  centerLat: number;
  centerLng: number;
}

type PlaceConfirmListener = (place: DiscoveredPlace) => void;
type NewPlaceListener = (place: PendingPlace) => void;

export class PlaceAutoDiscoveryService {
  private static instance: PlaceAutoDiscoveryService;
  private log: LogService = LogService.getInstance();

  private context: common.UIAbilityContext | null = null;
  private config: PlaceDiscoveryConfig = DEFAULT_DISCOVERY_CONFIG;
  private initialized: boolean = false;

  private pendingPlaces: Map<string, PendingPlace> = new Map();
  private discoveredPlaces: Map<string, DiscoveredPlace> = new Map();
  private visitHistory: PlaceVisit[] = [];

  private locationBuffer: LocationSnapshot[] = [];
  private currentStay: StayDetectionResult | null = null;
  private currentVisit: PlaceVisit | null = null;
  private lastLocation: LocationSnapshot | null = null;

  private confirmListeners: PlaceConfirmListener[] = [];
  private newPlaceListeners: NewPlaceListener[] = [];

  private checkIntervalId: number = -1;
  private dataPath: string = '';
  private categoryService: PlaceCategoryService = PlaceCategoryService.getInstance();

  private constructor() {}

  static getInstance(): PlaceAutoDiscoveryService {
    if (!PlaceAutoDiscoveryService.instance) {
      PlaceAutoDiscoveryService.instance = new PlaceAutoDiscoveryService();
    }
    return PlaceAutoDiscoveryService.instance;
  }

  async init(context: common.UIAbilityContext): Promise<void> {
    if (this.initialized) return;

    this.context = context;
    this.dataPath = `${context.filesDir}/place_discovery.json`;

    await this.categoryService.init(context);
    
    let stayConfig = this.categoryService.getStayDetectionConfig();
    this.config = {
      enabled: true,
      minStayMinutes: stayConfig.minStayMinutes,
      minGpsAccuracy: stayConfig.minGpsAccuracy,
      gpsDriftThreshold: stayConfig.gpsDriftThreshold,
      notificationEnabled: stayConfig.notificationEnabled,
      autoConfirmAfterVisits: stayConfig.autoConfirmAfterVisits,
    };

    await this.loadData();

    let geofenceManager = GeofenceManager.getInstance();
    geofenceManager.addListener(this.onGeofenceEvent.bind(this));
    geofenceManager.addLocationListener(this.onLocationUpdate.bind(this));

    this.startPeriodicCheck();

    this.initialized = true;
    this.log.info(TAG, `Initialized, ${this.discoveredPlaces.size} discovered, ${this.pendingPlaces.size} pending`);
  }

  private async onLocationUpdate(location: geoLocationManager.Location): Promise<void> {
    if (!this.config.enabled) return;

    let snapshot: LocationSnapshot = {
      latitude: location.latitude,
      longitude: location.longitude,
      accuracy: location.accuracy,
      timestamp: location.timeStamp,
      speed: location.speed,
      wifiSsid: await this.getCurrentWifiSsid(),
    };

    if (snapshot.accuracy > this.config.minGpsAccuracy) {
      this.log.debug(TAG, `Skipping low accuracy: ${snapshot.accuracy}m`);
      return;
    }

    this.locationBuffer.push(snapshot);
    this.lastLocation = snapshot;

    if (this.locationBuffer.length > 100) {
      this.locationBuffer.shift();
    }

    let stayResult = this.detectStay();
    this.currentStay = stayResult;

    if (stayResult.isStaying && stayResult.stayDurationMs >= this.config.minStayMinutes * 60000) {
      await this.checkForNewPlace(stayResult);
    }
  }

  private async onGeofenceEvent(event: GeofenceEvent): Promise<void> {
    if (event.type === 'enter') {
      await this.onEnterGeofence(event);
    } else if (event.type === 'exit') {
      await this.onExitGeofence(event);
    }
  }

  private async onEnterGeofence(event: GeofenceEvent): Promise<void> {
    let gf = event.geofence;
    let categoryLabel = this.categoryService.getCategoryLabel(gf.category);
    this.log.info(TAG, `Entered: ${gf.name} (${categoryLabel})`);

    this.currentVisit = {
      id: `visit_${Date.now()}`,
      geofenceId: gf.id,
      placeName: gf.name,
      latitude: event.location.latitude,
      longitude: event.location.longitude,
      enterTime: event.timestamp,
      stayDurationMs: 0,
      wifiSsid: await this.getCurrentWifiSsid(),
      source: 'auto',
      confirmed: true,
    };

    let discovered = this.discoveredPlaces.get(gf.id);
    if (discovered) {
      discovered.totalVisits++;
    }

    await this.provideNearbySuggestions(event.location);
  }

  private async onExitGeofence(event: GeofenceEvent): Promise<void> {
    let gf = event.geofence;
    this.log.info(TAG, `Exited: ${gf.name}`);

    if (this.currentVisit && this.currentVisit.geofenceId === gf.id) {
      this.currentVisit.exitTime = event.timestamp;
      this.currentVisit.stayDurationMs = event.timestamp - this.currentVisit.enterTime;

      this.visitHistory.push(this.currentVisit);
      this.pruneVisitHistory();

      let discovered = this.discoveredPlaces.get(gf.id);
      if (discovered) {
        discovered.totalStayMs += this.currentVisit.stayDurationMs;
        discovered.visits.push(this.currentVisit);
      }

      await this.saveData();
      this.currentVisit = null;
    }
  }

  private detectStay(): StayDetectionResult {
    if (this.locationBuffer.length < 3) {
      return { isStaying: false, stayDurationMs: 0, centerLat: 0, centerLng: 0 };
    }

    let recentPoints = this.locationBuffer.slice(-20);
    let first = recentPoints[0];
    let last = recentPoints[recentPoints.length - 1];

    let sumLat = 0, sumLng = 0;
    for (let p of recentPoints) {
      sumLat += p.latitude;
      sumLng += p.longitude;
    }
    let centerLat = sumLat / recentPoints.length;
    let centerLng = sumLng / recentPoints.length;

    let maxDrift = 0;
    for (let p of recentPoints) {
      let dist = GeoUtils.haversineDistance(centerLat, centerLng, p.latitude, p.longitude);
      if (dist > maxDrift) maxDrift = dist;
    }

    let hasHighSpeed = recentPoints.some(p => p.speed > 2);
    let isStaying = maxDrift < this.config.gpsDriftThreshold && !hasHighSpeed;
    let stayDurationMs = last.timestamp - first.timestamp;

    return { isStaying, stayDurationMs, centerLat, centerLng };
  }

  private async checkForNewPlace(stay: StayDetectionResult): Promise<void> {
    let geofenceManager = GeofenceManager.getInstance();
    let existingGeofences = geofenceManager.getGeofencesAtLocation(stay.centerLat, stay.centerLng);

    if (existingGeofences.length > 0) {
      return;
    }

    let placeId = this.generatePlaceId(stay.centerLat, stay.centerLng);

    let pending = this.pendingPlaces.get(placeId);
    if (!pending) {
      pending = {
        id: placeId,
        latitude: stay.centerLat,
        longitude: stay.centerLng,
        accuracy: 50,
        firstSeenTime: Date.now() - stay.stayDurationMs,
        wifiSsid: await this.getCurrentWifiSsid(),
        stayDurationMs: stay.stayDurationMs,
        notified: false,
      };

      this.pendingPlaces.set(placeId, pending);
      this.log.info(TAG, `New pending place: ${placeId}`);

      let geoResult = await GeoCodingService.getInstance().reverseGeocode(stay.centerLat, stay.centerLng);
      if (geoResult.success) {
        pending.suggestedName = geoResult.name;
        pending.suggestedCategory = geoResult.category || 'custom';
        pending.address = geoResult.displayName;
      }

      if (this.config.notificationEnabled && !pending.notified) {
        await this.notifyNewPlace(pending);
        pending.notified = true;
      }

      for (let listener of this.newPlaceListeners) {
        listener(pending);
      }

      await this.saveData();
    } else {
      pending.stayDurationMs = stay.stayDurationMs;
    }
  }

  private async notifyNewPlace(place: PendingPlace): Promise<void> {
    let name = place.suggestedName || I18n.t('place.discoveredTitle');
    let categoryLabel = place.suggestedCategory 
      ? this.categoryService.getCategoryLabel(place.suggestedCategory)
      : '';
    let stayText = this.categoryService.formatStayDuration(place.stayDurationMs);

    let title = I18n.t('place.discoveredTitle') + ': ' + name;
    let body = '';
    if (categoryLabel) {
      body += categoryLabel + '，';
    }
    body += I18n.t('place.stayedFor') + ' ' + stayText;
    if (place.address) {
      body += '\n' + place.address.substring(0, 50);
    }
    body += '\n' + I18n.t('place.clickToSave');

    await NotificationHelper.getInstance().send(title, body);
    this.log.info(TAG, `Notified new place: ${name}`);
  }

  private async provideNearbySuggestions(location: LocationState): Promise<void> {
    let nearbyConfig = this.categoryService.getNearbySuggestionConfig();
    let nearbyPlaces: Array<{ place: DiscoveredPlace; distance: number }> = [];

    for (let place of this.discoveredPlaces.values()) {
      let dist = GeoUtils.haversineDistance(
        location.latitude, location.longitude,
        place.latitude, place.longitude
      );

      if (dist < nearbyConfig.radiusMeters) {
        nearbyPlaces.push({ place, distance: dist });
      }
    }

    nearbyPlaces.sort((a, b) => a.distance - b.distance);
    nearbyPlaces = nearbyPlaces.slice(0, nearbyConfig.maxResults);

    if (nearbyPlaces.length > 0) {
      let nearest = nearbyPlaces[0];
      let lastVisit = this.getLastVisit(nearest.place.id);

      if (lastVisit) {
        let timeAgo = this.categoryService.formatTimeAgo(lastVisit.enterTime);
        let categoryLabel = this.categoryService.getCategoryLabel(nearest.place.category);
        
        let title = I18n.t('place.nearbyTitle') + ': ' + nearest.place.name;
        let body = categoryLabel + '，' + I18n.t('place.distance') + ' ' + Math.round(nearest.distance) + 'm';
        body += '，' + I18n.t('place.lastVisit') + ': ' + timeAgo;

        await NotificationHelper.getInstance().send(title, body);
        this.log.info(TAG, `Suggested nearby place: ${nearest.place.name}`);
      }
    }
  }

  async confirmPlace(placeId: string, customName?: string, customCategory?: GeofenceCategory): Promise<boolean> {
    let pending = this.pendingPlaces.get(placeId);
    if (!pending) {
      this.log.warn(TAG, `Place not found: ${placeId}`);
      return false;
    }

    let name = customName || pending.suggestedName || '未命名地点';
    let category = (customCategory || pending.suggestedCategory || 'custom') as GeofenceCategory;

    let discovered: DiscoveredPlace = {
      id: placeId,
      name: name,
      latitude: pending.latitude,
      longitude: pending.longitude,
      radiusMeters: this.categoryService.getDefaultRadius(category),
      category: category,
      discoverySource: pending.wifiSsid ? 'gps_wifi' : 'gps_only',
      discoveredAt: pending.firstSeenTime,
      confirmAt: Date.now(),
      visits: [],
      totalVisits: 1,
      totalStayMs: pending.stayDurationMs,
    };

    this.discoveredPlaces.set(placeId, discovered);
    this.pendingPlaces.delete(placeId);

    let geofence: Geofence = {
      id: placeId,
      name: name,
      latitude: pending.latitude,
      longitude: pending.longitude,
      radiusMeters: this.categoryService.getDefaultRadius(category),
      category: category,
    };
    GeofenceManager.getInstance().addGeofence(geofence);

    await this.saveData();

    for (let listener of this.confirmListeners) {
      listener(discovered);
    }

    this.log.info(TAG, `Confirmed place: ${name}`);
    return true;
  }

  async ignorePlace(placeId: string): Promise<void> {
    this.pendingPlaces.delete(placeId);
    await this.saveData();
    this.log.info(TAG, `Ignored place: ${placeId}`);
  }

  getPendingPlaces(): PendingPlace[] {
    return Array.from(this.pendingPlaces.values());
  }

  getDiscoveredPlaces(): DiscoveredPlace[] {
    return Array.from(this.discoveredPlaces.values());
  }

  getVisitHistory(limit: number = 100): PlaceVisit[] {
    return this.visitHistory.slice(-limit);
  }

  getVisitsForPlace(placeId: string): PlaceVisit[] {
    return this.visitHistory.filter(v => v.geofenceId === placeId);
  }

  getLastVisit(placeId: string): PlaceVisit | undefined {
    let visits = this.getVisitsForPlace(placeId);
    return visits.length > 0 ? visits[visits.length - 1] : undefined;
  }

  updateConfig(config: Partial<PlaceDiscoveryConfig>): void {
    this.config = { ...this.config, ...config };
    this.saveData().catch(() => {});
    this.log.info(TAG, `Config updated`);
  }

  getConfig(): PlaceDiscoveryConfig {
    return { ...this.config };
  }

  addConfirmListener(listener: PlaceConfirmListener): void {
    this.confirmListeners.push(listener);
  }

  addNewPlaceListener(listener: NewPlaceListener): void {
    this.newPlaceListeners.push(listener);
  }

  private async getCurrentWifiSsid(): Promise<string> {
    try {
      return '';
    } catch {
      return '';
    }
  }

  private generatePlaceId(lat: number, lng: number): string {
    let latKey = Math.round(lat * 1000);
    let lngKey = Math.round(lng * 1000);
    return `place_${latKey}_${lngKey}`;
  }

  private startPeriodicCheck(): void {
    this.checkIntervalId = setInterval(() => {
      this.periodicCheck();
    }, 60000);
  }

  private periodicCheck(): void {
    if (this.currentStay && this.currentStay.isStaying) {
      this.checkForNewPlace(this.currentStay).catch(() => {});
    }
  }

  private pruneVisitHistory(): void {
    let maxDays = 30;
    let cutoff = Date.now() - maxDays * 86400000;
    this.visitHistory = this.visitHistory.filter(v => v.enterTime > cutoff);
  }

  private async loadData(): Promise<void> {
    try {
      let stat = fileIo.statSync(this.dataPath);
      if (!stat) return;

      let file = fileIo.openSync(this.dataPath, fileIo.OpenMode.READ_ONLY);
      let buf = new ArrayBuffer(stat.size);
      fileIo.readSync(file.fd, buf);
      fileIo.closeSync(file.fd);

      let decoder = util.TextDecoder.create('utf-8');
      let json = decoder.decodeToString(new Uint8Array(buf));
      let data = JSON.parse(json) as PlaceDiscoveryData;

      if (data.config) this.config = data.config;
      if (data.pendingPlaces) {
        for (let p of data.pendingPlaces) {
          this.pendingPlaces.set(p.id, p);
        }
      }
      if (data.discoveredPlaces) {
        for (let p of data.discoveredPlaces) {
          this.discoveredPlaces.set(p.id, p);
        }
      }
      if (data.visitHistory) {
        this.visitHistory = data.visitHistory;
      }

      this.log.info(TAG, `Loaded ${this.pendingPlaces.size} pending, ${this.discoveredPlaces.size} discovered`);
    } catch (err) {
      this.log.debug(TAG, `Load data: ${(err as Error).message}`);
    }
  }

  private async saveData(): Promise<void> {
    try {
      let data: PlaceDiscoveryData = {
        version: 1,
        pendingPlaces: Array.from(this.pendingPlaces.values()),
        discoveredPlaces: Array.from(this.discoveredPlaces.values()),
        visitHistory: this.visitHistory,
        config: this.config,
      };

      let json = JSON.stringify(data);
      let file = fileIo.openSync(this.dataPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC | fileIo.OpenMode.WRITE_ONLY);
      fileIo.writeSync(file.fd, json);
      fileIo.closeSync(file.fd);
    } catch (err) {
      this.log.error(TAG, `Save error: ${(err as Error).message}`);
    }
  }

  destroy(): void {
    if (this.checkIntervalId >= 0) {
      clearInterval(this.checkIntervalId);
      this.checkIntervalId = -1;
    }
    this.saveData().catch(() => {});
    this.log.info(TAG, 'Destroyed');
  }
}
