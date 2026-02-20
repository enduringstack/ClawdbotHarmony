/**
 * Geofence Manager
 * 
 * 管理地理围栏，检测用户进入/离开特定区域
 */
import { geoLocationManager } from '@kit.LocationKit';
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { LogService } from '../../common/LogService';
import { Geofence, GeofenceCategory, LocationState } from './ContextModels';
import { ContextEngineService, GeofenceBinding } from './ContextEngine';

/** user_places.json 配置文件结构 */
interface UserPlace {
  id: string;
  name: string;
  latitude: number;
  longitude: number;
  radiusMeters: number;
  category: string;
}
interface UserPlacesConfig {
  version: number;
  places: UserPlace[];
}

const TAG = 'GeofenceManager';
const PREFS_NAME = 'clawdbot_geofences';
const KEY_GEOFENCES = 'geofence_list';

export type GeofenceEventType = 'enter' | 'exit' | 'dwell';

export interface GeofenceEvent {
  type: GeofenceEventType;
  geofence: Geofence;
  timestamp: number;
  location: LocationState;
}

type GeofenceListener = (event: GeofenceEvent) => void;

export class GeofenceManager {
  private static instance: GeofenceManager;
  private log: LogService = LogService.getInstance();
  
  private geofences: Map<string, Geofence> = new Map();
  private currentlyInside: Set<string> = new Set();
  private listeners: GeofenceListener[] = [];
  private initialized: boolean = false;
  
  // 位置监听
  private locationCallback: ((location: geoLocationManager.Location) => void) | undefined;
  private isMonitoring: boolean = false;
  
  private constructor() {}
  
  static getInstance(): GeofenceManager {
    if (!GeofenceManager.instance) {
      GeofenceManager.instance = new GeofenceManager();
    }
    return GeofenceManager.instance;
  }
  
  async init(context: common.UIAbilityContext): Promise<void> {
    if (this.initialized) return;
    
    // 加载保存的围栏
    await this.loadGeofences(context);
    
    // 首次使用：从配置文件加载用户地点
    if (this.geofences.size === 0) {
      await this.loadPlacesFromConfig(context);
    }
    // 初始化后绑定已有围栏到规则引擎
    this.rebindEngineRules();
    
    this.initialized = true;
    this.log.info(TAG, `Initialized with ${this.geofences.size} geofences`);
  }
  
  /**
   * 从 rawfile/config/user_places.json 加载用户地点配置
   * 首次使用时自动加载，之后用户可在管理页面编辑
   */
  private async loadPlacesFromConfig(context: common.UIAbilityContext): Promise<void> {
    try {
      let resourceMgr = context.resourceManager;
      let rawData = await resourceMgr.getRawFileContent('config/user_places.json');
      let bytes = new Uint8Array(rawData.buffer);
      let jsonStr = '';
      for (let i = 0; i < bytes.length; i++) {
        jsonStr += String.fromCharCode(bytes[i]);
      }
      let parsed: Object = JSON.parse(jsonStr);
      let config = parsed as UserPlacesConfig;
      if (config.places) {
        for (let place of config.places) {
          let gf: Geofence = {
            id: place.id,
            name: place.name,
            latitude: place.latitude,
            longitude: place.longitude,
            radiusMeters: place.radiusMeters,
            category: place.category as GeofenceCategory,
          };
          this.geofences.set(gf.id, gf);
        }
        this.log.info(TAG, `Loaded ${config.places.length} places from config`);
        await this.saveGeofences(context);
      }
    } catch (err) {
      this.log.warn(TAG, `loadPlacesFromConfig error: ${(err as Error).message}`);
    }
  }
  
  // ==================== 围栏管理 ====================
  
  addGeofence(geofence: Geofence): void {
    this.geofences.set(geofence.id, geofence);
    this.log.info(TAG, `Added geofence: ${geofence.name} (${geofence.id})`);
    this.rebindEngineRules();
  }
  
  removeGeofence(id: string): boolean {
    let removed = this.geofences.delete(id);
    this.currentlyInside.delete(id);
    if (removed) {
      this.log.info(TAG, `Removed geofence: ${id}`);
      this.rebindEngineRules();
    }
    return removed;
  }

  /** 围栏变更后，重新绑定 C++ 引擎规则中的占位符 */
  private rebindEngineRules(): void {
    let bindings: GeofenceBinding[] = [];
    this.geofences.forEach((gf: Geofence) => {
      let binding: GeofenceBinding = { id: gf.id, category: gf.category };
      bindings.push(binding);
    });
    ContextEngineService.getInstance().rebindGeofences(bindings).catch((err: Error) => {
      this.log.warn(TAG, `rebindEngineRules error: ${err.message}`);
    });
  }
  
  getGeofence(id: string): Geofence | undefined {
    return this.geofences.get(id);
  }
  
  getAllGeofences(): Geofence[] {
    return Array.from(this.geofences.values());
  }
  
  getGeofencesByCategory(category: GeofenceCategory): Geofence[] {
    return this.getAllGeofences().filter(gf => gf.category === category);
  }
  
  // ==================== 位置检测 ====================
  
  /**
   * 检查位置是否在指定围栏内
   */
  isInsideGeofence(lat: number, lon: number, geofence: Geofence): boolean {
    let distance = this.calculateDistance(lat, lon, geofence.latitude, geofence.longitude);
    return distance <= geofence.radiusMeters;
  }
  
  /**
   * 获取位置所在的所有围栏
   */
  getGeofencesAtLocation(lat: number, lon: number): Geofence[] {
    let result: Geofence[] = [];
    for (const gf of this.geofences.values()) {
      if (this.isInsideGeofence(lat, lon, gf)) {
        result.push(gf);
      }
    }
    return result;
  }
  
  /**
   * 更新位置并触发进入/离开事件
   */
  updateLocation(location: LocationState): GeofenceEvent[] {
    let events: GeofenceEvent[] = [];
    let nowInside = new Set<string>();
    
    // 检查当前在哪些围栏内
    for (const gf of this.geofences.values()) {
      if (this.isInsideGeofence(location.latitude, location.longitude, gf)) {
        nowInside.add(gf.id);
        
        // 新进入的围栏
        if (!this.currentlyInside.has(gf.id)) {
          let event: GeofenceEvent = {
            type: 'enter',
            geofence: gf,
            timestamp: Date.now(),
            location,
          };
          events.push(event);
          this.notifyListeners(event);
          this.log.info(TAG, `ENTER: ${gf.name}`);
        }
      }
    }
    
    // 检查离开的围栏
    for (const id of this.currentlyInside) {
      if (!nowInside.has(id)) {
        let gf = this.geofences.get(id);
        if (gf) {
          let event: GeofenceEvent = {
            type: 'exit',
            geofence: gf,
            timestamp: Date.now(),
            location,
          };
          events.push(event);
          this.notifyListeners(event);
          this.log.info(TAG, `EXIT: ${gf.name}`);
        }
      }
    }
    
    this.currentlyInside = nowInside;
    return events;
  }
  
  // ==================== 持续监控 ====================
  
  async startMonitoring(): Promise<boolean> {
    if (this.isMonitoring) return true;
    
    try {
      this.locationCallback = (location: geoLocationManager.Location) => {
        let state: LocationState = {
          latitude: location.latitude,
          longitude: location.longitude,
          accuracy: location.accuracy,
          speed: location.speed || 0,
          timestamp: location.timeStamp,
          insideGeofences: [],
        };
        
        // 更新并获取当前围栏
        this.updateLocation(state);
        state.insideGeofences = Array.from(this.currentlyInside);
      };
      
      let request: geoLocationManager.LocationRequest = {
        priority: geoLocationManager.LocationRequestPriority.FIRST_FIX,
        scenario: geoLocationManager.LocationRequestScenario.UNSET,
        timeInterval: 10,
        distanceInterval: 5,
        maxAccuracy: 100,
      };

      geoLocationManager.on('locationChange', request, this.locationCallback);
      this.isMonitoring = true;
      this.log.info(TAG, 'Started location monitoring');
      return true;
    } catch (err) {
      this.log.error(TAG, `Failed to start monitoring: ${(err as Error).message}`);
      return false;
    }
  }
  
  stopMonitoring(): void {
    if (!this.isMonitoring || !this.locationCallback) return;
    
    try {
      geoLocationManager.off('locationChange', this.locationCallback);
      this.isMonitoring = false;
      this.locationCallback = undefined;
      this.log.info(TAG, 'Stopped location monitoring');
    } catch (err) {
      this.log.warn(TAG, `Error stopping monitoring: ${(err as Error).message}`);
    }
  }
  
  // ==================== 事件监听 ====================
  
  addListener(listener: GeofenceListener): void {
    this.listeners.push(listener);
  }
  
  removeListener(listener: GeofenceListener): void {
    let idx = this.listeners.indexOf(listener);
    if (idx >= 0) this.listeners.splice(idx, 1);
  }
  
  private notifyListeners(event: GeofenceEvent): void {
    for (const listener of this.listeners) {
      try {
        listener(event);
      } catch (err) {
        this.log.warn(TAG, `Listener error: ${(err as Error).message}`);
      }
    }
  }
  
  // ==================== 持久化 ====================
  
  async saveGeofences(context: common.UIAbilityContext): Promise<void> {
    try {
      let store = await preferences.getPreferences(context, PREFS_NAME);
      let data = JSON.stringify(this.getAllGeofences());
      await store.put(KEY_GEOFENCES, data);
      await store.flush();
      this.log.info(TAG, `Saved ${this.geofences.size} geofences`);
    } catch (err) {
      this.log.error(TAG, `Failed to save: ${(err as Error).message}`);
    }
  }
  
  private async loadGeofences(context: common.UIAbilityContext): Promise<void> {
    try {
      let store = await preferences.getPreferences(context, PREFS_NAME);
      let data = await store.get(KEY_GEOFENCES, '[]') as string;
      let list = JSON.parse(data) as Geofence[];
      for (const gf of list) {
        this.geofences.set(gf.id, gf);
      }
      this.log.info(TAG, `Loaded ${list.length} geofences`);
    } catch (err) {
      this.log.warn(TAG, `Failed to load: ${(err as Error).message}`);
    }
  }
  
  // ==================== 工具方法 ====================
  
  /**
   * 计算两点间距离（米）- Haversine公式
   */
  private calculateDistance(lat1: number, lon1: number, lat2: number, lon2: number): number {
    let R = 6371000; // 地球半径（米）
    let dLat = this.toRad(lat2 - lat1);
    let dLon = this.toRad(lon2 - lon1);
    let a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
              Math.cos(this.toRad(lat1)) * Math.cos(this.toRad(lat2)) *
              Math.sin(dLon / 2) * Math.sin(dLon / 2);
    let c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return R * c;
  }
  
  private toRad(deg: number): number {
    return deg * Math.PI / 180;
  }
  
  /**
   * 获取当前状态摘要
   */
  getStatus(): string {
    return `Geofences: ${this.geofences.size}, Inside: [${Array.from(this.currentlyInside).join(', ')}], Monitoring: ${this.isMonitoring}`;
  }
}
