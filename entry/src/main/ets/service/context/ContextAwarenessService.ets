/**
 * Context Awareness Service
 * 
 * 核心服务：整合传感器、地理围栏、行为记录和推荐
 */
import { sensor } from '@kit.SensorServiceKit';
import { batteryInfo } from '@kit.BasicServicesKit';
import { wifiManager } from '@kit.ConnectivityKit';
import { geoLocationManager } from '@kit.LocationKit';
import { common, abilityAccessCtrl } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { LogService } from '../../common/LogService';
import { Constants } from '../../common/Constants';
import { I18n } from '../../common/I18n';
import { GeofenceManager, GeofenceEvent } from './GeofenceManager';
import { BehaviorLogger } from './BehaviorLogger';
import { ContextEngineService, ContextSnapshot, ContextRule as EngineRule, ContextCondition as EngineCondition, ContextAction as EngineAction, MatchResult, GeofenceBinding } from './ContextEngine';
import { LocationDiscoveryService, GeofenceSuggestion, DiscoveryStatsInfo } from './LocationDiscoveryService';
import { FeedbackService } from './FeedbackService';
import { LocationFusionService, LearnedSignalsSummary } from './LocationFusionService';
import { DigitalWorldService } from './DigitalWorldService';
import DataTray, { DataTray as SensorDataTray, TrayStatus } from './DataTray';
import {
  EnvironmentContext,
  MotionState,
  TimeOfDay,
  NetworkType,
  UserAction,
  ActionOutcome,
  ContextRule,
  RuleTrigger,
  Geofence,
  LocationState,
  FeedbackStats,
  LLMRecommendation,
  GeofenceCategory,
} from './ContextModels';
import { LLMFallbackService } from './LLMFallbackService';
import { TrainingDataSync } from './TrainingDataSync';

const TAG = 'ContextService';

export interface ContextRecommendation {
  rule: ContextRule;
  action: UserAction;
  reason: string;
}

type RecommendationListener = (rec: ContextRecommendation) => void;
type SuggestionListener = (suggestions: GeofenceSuggestion[]) => void;

/** Persisted state for geofence suggestion filtering */
interface GeofenceSuggestionState {
  /** Cluster IDs the user permanently ignored */
  blacklist: string[];
  /** Cluster ID → timestamp when deferred ("以后再说"), resurface after 7 days */
  deferred: Record<string, number>;
  /** Cluster ID → timestamp of last suggestion shown, max once per day */
  lastShown: Record<string, number>;
}

const SUGGEST_PREFS_KEY = 'geofence_suggestion_state';
const DEFER_DURATION_MS = 7 * 24 * 3600 * 1000;     // 7 days
const DAILY_COOLDOWN_MS = 24 * 3600 * 1000;          // 24 hours

/** 加速度传感器数据接口 */
interface AccelerometerData {
  x: number;
  y: number;
  z: number;
  timestamp: number;
}

/** 加速度历史采样点 */
interface AccelSample {
  magnitude: number;
  gravityAngle: number;  // 重力方向与Z轴夹角
  timestamp: number;
}

export class ContextAwarenessService {
  private static instance: ContextAwarenessService;
  private log: LogService = LogService.getInstance();
  
  private geofenceMgr: GeofenceManager;
  private behaviorLog: BehaviorLogger;
  private feedbackSvc: FeedbackService;
  
  private initialized: boolean = false;
  private initializing: boolean = false;
  private isRunning: boolean = false;
  private starting: boolean = false;
  private context: common.UIAbilityContext | undefined;
  
  // 当前状态
  private currentContext: EnvironmentContext | undefined;
  private lastLocation: LocationState | undefined;
  private lastMotionState: MotionState = 'unknown';
  
  // 状态历史 (用于规则判断)
  private prevMotionState: MotionState = 'unknown';
  private prevActivityState: string = 'unknown';  // 'sitting', 'sleeping', 'walking', 'active'
  private activityState: string = 'unknown';      // 当前活动状态
  private activityStateTimestamp: number = 0;     // 状态开始时间
  private activityStateDuration: number = 0;      // 持续时间(ms)
  
  // 传感器数据
  private accelerometerData: AccelerometerData = { x: 0, y: 0, z: 0, timestamp: 0 } as AccelerometerData;
  private stepCount: number = 0;
  
  // 拿起手机检测
  private accelHistory: AccelSample[] = [];
  private static readonly ACCEL_HISTORY_SIZE = 30;
  private pickupStartTime: number = 0;
  private isPickupState: boolean = false;
  private lastStableGravityAngle: number = 90;  // 90° = held in hand; avoid false pickup at startup (0° = flat would trigger immediately)
  private pickupConfirmed: boolean = false;
  private static readonly PICKUP_PULSE_THRESHOLD = 10.5;
  private static readonly PICKUP_ANGLE_CHANGE_THRESHOLD = 20;
  private static readonly PICKUP_MAX_DURATION_MS = 3000;
  private static readonly MOTION_MIN_DURATION_MS = 10000;
  private motionStartTime: number = 0;
  private motionStepCountStart: number = 0;
  
  // WiFi 状态跟踪
  private lastWifiSsid: string = '';
  private wifiLostWorkTimestamp: number = 0;  // backward compat
  private wifiLostTimestamps: Map<string, number> = new Map();  // category → timestamp
  private static readonly WIFI_LOST_TTL_MS = 10 * 60 * 1000;  // WiFi丢失标记保持10分钟
  
  // 推荐监听器
  private recommendationListeners: RecommendationListener[] = [];
  
  // C++ 规则引擎
  private engine: ContextEngineService = ContextEngineService.getInstance();
  private evaluationTimer: number = -1;
  private static readonly EVALUATION_INTERVAL_MS = 2 * 60 * 1000;  // 2分钟评估一次
  
  // 防抖：避免重复推荐
  private lastRecommendations: Map<string, number> = new Map();
  private lastDigitalData: Record<string, string> = {};

  // LLM fallback dedup: don't repeat same recommendation without feedback
  private lastLlmPayload: string = '';
  private lastLlmRuleId: string = '';
  private lastLlmFeedbackReceived: boolean = false;
  private static readonly RECOMMENDATION_COOLDOWN_MS = 5 * 60 * 1000;  // 5分钟冷却

  // 积极探索模式：每个新状态指纹都触发 LLM 建议
  private exploreMode: boolean = false;
  private exploredFingerprints: Set<string> = new Set();
  
  // 位置自动发现
  private locationDiscovery: LocationDiscoveryService = LocationDiscoveryService.getInstance();
  private discoveryTimer: number = -1;
  private static readonly DISCOVERY_INTERVAL_MS = 60 * 60 * 1000;  // 1小时发现一次

  // LLM 兜底服务
  private llmFallback: LLMFallbackService = LLMFallbackService.getInstance();
  // 多源位置融合
  private locationFusion: LocationFusionService = LocationFusionService.getInstance();
  // 围栏建议管理
  private suggestionListeners: SuggestionListener[] = [];
  private suggestionState: GeofenceSuggestionState = { blacklist: [], deferred: {}, lastShown: {} };
  private suggestionStateLoaded: boolean = false;
  // A2UI 监听器 (本地UI分发)
  private a2uiListeners: ((type: string, content: string) => void)[] = [];
  // 新地点自动发现
  private newPlaceDetectionStart: number = 0;
  private newPlaceLastLat: number = 0;
  private newPlaceLastLng: number = 0;
  private newPlaceWifiSsid: string = '';
  private static readonly NEW_PLACE_STABLE_MS = 5 * 60 * 1000;
  private static readonly NEW_PLACE_MAX_DRIFT_M = 100;
  // CellID 跟踪 (用于低功耗位置变化检测)
  private lastCellId: string = '';
  private lastCellIdTime: number = 0;
  
  // ==================== 多级采集策略 (功耗优化) ====================
  // GPS间隔
  private locationTimer: number = -1;
  private locationIntervalMs: number = 60 * 1000;
  private static readonly GPS_STATIONARY = 5 * 60 * 1000;      // 静止: 5分钟
  private static readonly GPS_WALKING = 30 * 1000;             // 步行: 30秒
  private static readonly GPS_RUNNING = 15 * 1000;             // 跑步: 15秒
  private static readonly GPS_DRIVING = 5 * 1000;              // 驾驶: 5秒
  private static readonly GPS_UNKNOWN = 60 * 1000;             // 未知: 1分钟
  
  // WiFi扫描间隔
  private wifiTimer: number = -1;
  private wifiIntervalMs: number = 2 * 60 * 1000;
  private static readonly WIFI_STATIONARY = 5 * 60 * 1000;     // 静止: 5分钟
  private static readonly WIFI_WALKING = 2 * 60 * 1000;        // 步行: 2分钟
  private static readonly WIFI_RUNNING = 5 * 60 * 1000;        // 跑步: 5分钟 (不太可能连WiFi)
  private static readonly WIFI_DRIVING = 0;                     // 驾驶: 关闭
  private static readonly WIFI_UNKNOWN = 2 * 60 * 1000;
  
  // 加速度计间隔 (纳秒)
  private accelIntervalNs: number = 1000000000;  // 1秒
  private static readonly ACCEL_STATIONARY = 5000000000;       // 静止: 5秒
  private static readonly ACCEL_WALKING = 1000000000;          // 步行: 1秒
  private static readonly ACCEL_RUNNING = 500000000;           // 跑步: 500ms
  private static readonly ACCEL_DRIVING = 2000000000;          // 驾驶: 2秒
  private static readonly ACCEL_UNKNOWN = 1000000000;
  
  // 数字世界感知
  private digitalWorld: DigitalWorldService = DigitalWorldService.getInstance();
  // 传感器数据托盘
  private tray: SensorDataTray = DataTray;
  // 训练数据同步
  private trainingSync: TrainingDataSync = TrainingDataSync.getInstance();

  private constructor() {
    this.geofenceMgr = GeofenceManager.getInstance();
    this.behaviorLog = BehaviorLogger.getInstance();
    this.feedbackSvc = FeedbackService.getInstance();
  }
  
  static getInstance(): ContextAwarenessService {
    if (!ContextAwarenessService.instance) {
      ContextAwarenessService.instance = new ContextAwarenessService();
    }
    return ContextAwarenessService.instance;
  }
  
  async init(context: common.UIAbilityContext): Promise<void> {
    if (this.initialized || this.initializing) return;
    this.initializing = true;
    this.context = context;
    
    await this.geofenceMgr.init(context);
    await this.behaviorLog.init(context);
    
    // 初始化 C++ 规则引擎
    await this.engine.init(context);
    if (this.engine.getRuleCount() === 0) {
      await this.engine.loadDefaultRules();
      this.log.info(TAG, `Loaded default rules: ${this.engine.getRuleCount()}`);
    }
    
    // 初始化多源位置融合
    await this.locationFusion.init(context);

    // 初始化位置发现服务
    await this.locationDiscovery.init(context);
    await this.feedbackSvc.init(context);
    // Register callback so FeedbackService can notify us of LLM feedback (avoids circular import)
    this.feedbackSvc.setLlmFeedbackCallback((ruleId: string) => {
      this.markLlmFeedbackReceived(ruleId);
    });
    await this.loadSuggestionState();

    // 初始化 LLM 兜底服务
    this.llmFallback.init(context);

    // 数字世界感知服务：延迟到 start() 里权限请求之后再 init
    // 这样 WearablePlugin 请求 READ_HEALTH_DATA 时 UI 已就绪，弹窗能正常显示

    // 加载积极探索模式状态
    await this.loadExploreMode();

    // 初始化训练数据同步 (服务端与 Gateway 同机，端口 18790)
    await this.trainingSync.init(context, 'http://192.168.1.76:18790');

    // 监听地理围栏事件
    this.geofenceMgr.addListener((event) => this.onGeofenceEvent(event));

    this.initialized = true;
    this.log.info(TAG, `Context Awareness Service initialized, rules: ${this.engine.getRuleCount()}`);
  }
  
  
  async start(): Promise<boolean> {
    if (this.isRunning) return true;
    if (!this.initialized) {
      this.log.warn(TAG, 'Service not initialized yet, skipping start');
      return false;
    }
    if (this.starting) return true;
    this.starting = true;
    
    try {
      // 请求位置权限
      let locationGranted = await this.requestLocationPermission();
      
      // 请求运动传感器权限并启动
      await this.requestMotionPermission();
      this.startMotionSensors();
      
      // 启动WiFi定时扫描 (多级采集)
      this.startWifiTimer();
      
      // 启动定时规则评估
      this.startPeriodicEvaluation();

      // 启动智能位置获取（多级采集）
      if (locationGranted) {
        this.startSmartLocationTimer();
        this.startLocationDiscovery();
      } else {
        this.log.warn(TAG, 'Location permission denied, location features disabled');
      }

      // 核心功能已就绪，标记 isRunning 以启用定时评估
      this.isRunning = true;
      this.log.info(TAG, 'Context Awareness Service started (multi-tier sensing enabled)');

      // 初始化 + 启动数字世界感知（非关键路径，失败不影响规则评估）
      try {
        await this.digitalWorld.init(this.context as common.UIAbilityContext);
        this.digitalWorld.start();
      } catch (dwErr) {
        this.log.warn(TAG, `DigitalWorld init/start failed (non-fatal): ${(dwErr as Error).message}`);
      }

      return true;
    } catch (err) {
      this.log.error(TAG, `Failed to start: ${(err as Error).message}`);
      this.starting = false;  // 允许重试
      return false;
    }
  }
  
  stop(): void {
    if (!this.isRunning) return;
    
    this.stopSmartLocationTimer();
    this.stopWifiTimer();
    this.stopMotionSensors();
    this.stopPeriodicEvaluation();
    this.stopLocationDiscovery();
    this.digitalWorld.stop();

    this.isRunning = false;
    this.log.info(TAG, 'Context Awareness Service stopped');
  }
  
  
  // ==================== WiFi 连接事件处理 ====================
  
  private onWifiDisconnected(): void {
    let lostSsid = this.lastWifiSsid;
    this.log.info(TAG, `WiFi disconnected, last SSID: ${lostSsid}`);

    if (lostSsid.length === 0) return;

    // 遍历所有围栏，检查丢失的 WiFi 是否匹配任何围栏的学习信号
    let allGeofences = this.geofenceMgr.getAllGeofences();
    let matchedCategory = '';

    for (let gf of allGeofences) {
      let summary = this.locationFusion.getLearnedSignalsSummary(gf);
      if (summary && summary.wifiSsids.includes(lostSsid)) {
        matchedCategory = gf.category;
        break;
      }
    }

    if (matchedCategory.length > 0) {
      let now = Date.now();
      this.log.info(TAG, `WiFi lost: ${lostSsid} — leaving ${matchedCategory} geofence`);
      this.wifiLostTimestamps.set(matchedCategory, now);

      // 设置通用丢失标记
      this.tray.put('wifiLost', 'true', 0.8, 'wifi');
      this.tray.put('wifiLostCategory', matchedCategory, 0.8, 'wifi');

      // 向后兼容：work 类别同时设置 wifiLostWork
      if (matchedCategory === 'work') {
        this.wifiLostWorkTimestamp = now;
        this.tray.put('wifiLostWork', 'true', 0.8, 'wifi');
      }

      this.engine.pushEvent('wifi_lost_' + matchedCategory);

      // 立即触发评估
      this.refreshTray().then(() => {
        let snapshot = this.augmentSnapshot(this.tray.getSnapshot());
        this.evaluateAndDeliver(snapshot);
      });
    }

    // 清除当前 WiFi 围栏匹配
    this.tray.put('wifiGeofence', '', 0, 'wifi');
    this.lastWifiSsid = '';
  }
  
  private onWifiConnected(): void {
    // WiFi 重新连接，清除丢失标记
    this.wifiLostWorkTimestamp = 0;
    this.wifiLostTimestamps.clear();

    // 尝试获取当前 SSID 并匹配围栏
    try {
      wifiManager.getLinkedInfo().then((info) => {
        let ssid = info.ssid || '';
        if (ssid.startsWith('"') && ssid.endsWith('"')) {
          ssid = ssid.substring(1, ssid.length - 1);
        }
        if (ssid.length === 0) return;

        this.lastWifiSsid = ssid;
        this.tray.put('wifiSsid', ssid, 1.0, 'wifi');

        // 遍历所有围栏查找匹配
        let allGeofences = this.geofenceMgr.getAllGeofences();
        for (let gf of allGeofences) {
          let summary = this.locationFusion.getLearnedSignalsSummary(gf);
          if (summary && summary.wifiSsids.includes(ssid)) {
            this.log.info(TAG, `WiFi connected: ${ssid} matches ${gf.category} geofence`);
            this.tray.put('wifiGeofence', gf.category, 0.9, 'wifi');
            this.engine.pushEvent('wifi_arrive_' + gf.category);

            // 立即触发评估
            this.refreshTray().then(() => {
              let snapshot = this.augmentSnapshot(this.tray.getSnapshot());
              this.evaluateAndDeliver(snapshot);
            });
            return;
          }
        }
      });
    } catch (err) {
      this.log.debug(TAG, `WiFi connected, get info failed: ${(err as Error).message}`);
    }
  }
  
  /**
   * 增强 snapshot：补充 WiFi 围栏丢失标记（基于 wifiLostTimestamps 的 TTL）
   */
  private augmentSnapshot(snapshot: ContextSnapshot): ContextSnapshot {
    let now = Date.now();
    // 检查所有 WiFi 丢失时间戳，找最近的未过期记录
    let latestCategory = '';
    let latestTime = 0;
    this.wifiLostTimestamps.forEach((ts: number, category: string) => {
      if (now - ts < ContextAwarenessService.WIFI_LOST_TTL_MS && ts > latestTime) {
        latestCategory = category;
        latestTime = ts;
      }
    });
    if (latestCategory.length > 0) {
      snapshot.wifiLost = 'true';
      snapshot.wifiLostCategory = latestCategory;
      if (latestCategory === 'work') {
        snapshot.wifiLostWork = 'true';
      }
    }
    return snapshot;
  }

  private async requestMotionPermission(): Promise<boolean> {
    try {
      let atManager = abilityAccessCtrl.createAtManager();
      // READ_HEALTH_DATA 由 WearablePlugin.init() 单独请求，避免重复弹窗
      let result = await atManager.requestPermissionsFromUser(this.context as common.UIAbilityContext,
        ['ohos.permission.ACTIVITY_MOTION']);
      let motionGranted = result.authResults[0] === 0;
      this.log.info(TAG, `ACTIVITY_MOTION permission: ${motionGranted ? 'granted' : 'denied'}`);
      return motionGranted;
    } catch (err) {
      this.log.warn(TAG, `Motion permission request failed: ${(err as Error).message}`);
      return false;
    }
  }

  private async requestLocationPermission(): Promise<boolean> {
    try {
      let atManager = abilityAccessCtrl.createAtManager();
      let result = await atManager.requestPermissionsFromUser(this.context as common.UIAbilityContext,
        ['ohos.permission.APPROXIMATELY_LOCATION', 'ohos.permission.LOCATION']);
      let approxGranted = result.authResults[0] === 0;
      let preciseGranted = result.authResults.length > 1 && result.authResults[1] === 0;
      this.log.info(TAG, `Location permission: approx=${approxGranted ? 'granted' : 'denied'}, precise=${preciseGranted ? 'granted' : 'denied'}`);
      return approxGranted || preciseGranted;
    } catch (err) {
      this.log.warn(TAG, `Location permission request failed: ${(err as Error).message}`);
      return false;
    }
  }

  private startMotionSensors(): void {
    try {
      sensor.on(sensor.SensorId.ACCELEROMETER, (data: sensor.AccelerometerResponse) => {
        this.accelerometerData = { x: data.x, y: data.y, z: data.z, timestamp: Date.now() };
        this.recordAccelSample();
        this.updateMotionState();
      }, { interval: 1000000000 });
      
      sensor.on(sensor.SensorId.PEDOMETER, (data: sensor.PedometerResponse) => {
        this.stepCount = data.steps;  // 仅内部使用（pickup检测），显示由 StepCounterPlugin 负责
      }, { interval: 5000000000 });
      
      this.log.info(TAG, 'Motion sensors started');
    } catch (err) {
      this.log.warn(TAG, `Sensor error: ${(err as Error).message}`);
    }
  }
  
  private stopMotionSensors(): void {
    try {
      sensor.off(sensor.SensorId.ACCELEROMETER);
      sensor.off(sensor.SensorId.PEDOMETER);
    } catch {
      // ignore
    }
}
  
  private recordAccelSample(): void {
    let x = this.accelerometerData.x;
    let y = this.accelerometerData.y;
    let z = this.accelerometerData.z;
    let magnitude = Math.sqrt(x * x + y * y + z * z);
    let gravityAngle = Math.acos(z / magnitude) * 180 / Math.PI;
    
    this.accelHistory.push({
      magnitude: magnitude,
      gravityAngle: gravityAngle,
      timestamp: this.accelerometerData.timestamp
    });
    
    if (this.accelHistory.length > ContextAwarenessService.ACCEL_HISTORY_SIZE) {
      this.accelHistory.shift();
    }
  }
  
  private detectPickup(): boolean {
    if (this.accelHistory.length < 3) return false;

    let now = Date.now();
    let recent = this.accelHistory.slice(-5);
    let current = recent[recent.length - 1];
    let prev = recent.length > 1 ? recent[recent.length - 2] : current;

    let hasPulse = current.magnitude > ContextAwarenessService.PICKUP_PULSE_THRESHOLD;
    let angleChange = Math.abs(current.gravityAngle - this.lastStableGravityAngle);
    let hasAngleChange = angleChange > ContextAwarenessService.PICKUP_ANGLE_CHANGE_THRESHOLD;

    // 只在手机之前是平放状态时才触发 pickup（区分拿起 vs 放下）
    // 平放: gravityAngle < 25°(正面朝上) 或 > 155°(正面朝下)
    let wasFlat = this.lastStableGravityAngle < 25 || this.lastStableGravityAngle > 155;

    if (hasPulse && hasAngleChange && wasFlat && !this.isPickupState) {
      this.pickupStartTime = now;
      this.isPickupState = true;
      this.pickupConfirmed = false;
      this.log.debug(TAG, `Pickup detected: mag=${current.magnitude.toFixed(1)}, angle=${angleChange.toFixed(1)}, stableAngle=${this.lastStableGravityAngle.toFixed(1)}`);
    }
    
    if (this.isPickupState) {
      let pickupDuration = now - this.pickupStartTime;
      
      let stillMoving = current.magnitude > 10.5;
      let stepsIncreased = this.stepCount > this.motionStepCountStart + 5;
      let gpsMoving = (this.lastLocation?.speed ?? 0) > 0.5;
      
      if (pickupDuration > ContextAwarenessService.MOTION_MIN_DURATION_MS && (stillMoving || stepsIncreased || gpsMoving)) {
        this.log.info(TAG, `Pickup -> Motion: duration=${pickupDuration}ms, steps=+${this.stepCount - this.motionStepCountStart}`);
        this.isPickupState = false;
        this.pickupConfirmed = false;
        return false;
      }
      
      if (pickupDuration < ContextAwarenessService.PICKUP_MAX_DURATION_MS) {
        return true;
      }
      
      if (!stillMoving && pickupDuration >= ContextAwarenessService.PICKUP_MAX_DURATION_MS) {
        this.log.info(TAG, `Pickup confirmed: brief glance, duration=${pickupDuration}ms`);
        this.pickupConfirmed = true;
        this.isPickupState = false;
        return true;
      }
      
      this.isPickupState = false;
      return false;
    }
    
    return false;
  }
  
  /**
   * 基于加速度计数据和GPS速度综合判断运动状态
   * 解决：开车/高铁匀速时加速度小但速度快的问题
   */
  private updateMotionState(): void {
    let x = this.accelerometerData.x;
    let y = this.accelerometerData.y;
    let z = this.accelerometerData.z;
    let magnitude = Math.sqrt(x * x + y * y + z * z);
    let gpsSpeed = this.lastLocation?.speed ?? 0;
    
    let isPickup = this.detectPickup();
    
    if (isPickup || this.pickupConfirmed) {
      this.tray.put('motionState', 'pickup', 0.85, 'accelerometer');

      if (this.lastMotionState !== 'pickup') {
        this.log.info(TAG, `Motion state: ${this.lastMotionState} -> pickup (brief glance)`);
        this.engine.pushEvent('motion_pickup');
        this.lastMotionState = 'pickup';
      }
      this.pickupConfirmed = false;
      // 拿起手机不触发GPS — 只是瞬间查看，不需要位置更新
      return;
    }

    if (this.accelHistory.length >= 3) {
      let recent = this.accelHistory.slice(-3);
      let avgMag = recent.reduce((sum, s) => sum + s.magnitude, 0) / recent.length;
      if (avgMag < 10.3) {
        this.lastStableGravityAngle = recent[recent.length - 1].gravityAngle;
      }
    }
    
    let newState: MotionState;
    
    if (gpsSpeed > 20) {
      newState = 'driving';
    } else if (gpsSpeed > 5) {
      newState = 'driving';
    } else if (gpsSpeed > 1.5) {
      newState = magnitude > 12 ? 'running' : 'walking';
    } else {
      if (magnitude < 10.5) {
        newState = 'stationary';
      } else if (magnitude < 12) {
        newState = 'walking';
      } else if (magnitude < 15) {
        newState = 'running';
      } else {
        newState = 'driving';
      }
    }
    
    if (newState !== 'stationary') {
      if (this.motionStartTime === 0) {
        this.motionStartTime = Date.now();
        this.motionStepCountStart = this.stepCount;
      }
    } else {
      this.motionStartTime = 0;
      this.motionStepCountStart = 0;
    }
    
    this.tray.put('motionState', newState, 0.9, 'accelerometer');
    this.tray.put('gpsSpeed', gpsSpeed.toFixed(2), 0.85, 'gps');

    if (newState !== this.lastMotionState) {
      this.log.info(TAG, `Motion state: ${this.lastMotionState} -> ${newState}, gpsSpeed=${gpsSpeed.toFixed(1)}m/s`);

      // 放下手机：从 pickup 转为其他状态
      if (this.lastMotionState === 'pickup') {
        this.engine.pushEvent('motion_putdown');
        this.log.info(TAG, 'Putdown: pickup -> ' + newState);
      }

      // 更新状态历史
      this.updateActivityState(newState);

      this.engine.pushEvent('motion_' + newState);
      this.prevMotionState = this.lastMotionState;
      this.lastMotionState = newState;
      this.adjustLocationInterval(newState);
    }
  }
  
  /**
   * 更新活动状态 (状态机)
   * 
   * 活动状态: 'sleeping', 'sitting', 'standing', 'walking', 'active', 'driving'
   */
  private updateActivityState(motionState: MotionState): void {
    let newActivityState = this.activityState;
    let now = Date.now();
    
    // 根据运动状态推断活动状态
    switch (motionState) {
      case 'stationary':
        // 静止状态需要根据上下文判断是睡觉还是坐着
        let hour = new Date().getHours();
        let geofence = this.tray.get('geofence')?.value;
        
        // 夜间在家 → 睡觉
        if ((hour >= 22 || hour < 6) && geofence === 'home') {
          newActivityState = 'sleeping';
        } 
        // 之前在睡觉 → 继续睡觉
        else if (this.activityState === 'sleeping') {
          // 检查心率判断是否醒来
          let heartRate = this.getHeartRateFromWearable();
          if (heartRate > 0 && heartRate < 60) {
            newActivityState = 'sleeping';
          } else if (heartRate >= 60) {
            newActivityState = 'sitting';  // 醒来但还躺着/坐着
          } else {
            // 没有心率数据，保持之前状态
            newActivityState = this.activityState;
          }
        }
        // 其他情况 → 坐着
        else {
          newActivityState = 'sitting';
        }
        break;
        
      case 'walking':
        newActivityState = 'walking';
        break;
        
      case 'running':
        newActivityState = 'active';
        break;
        
      case 'driving':
        newActivityState = 'driving';
        break;
        
      case 'pickup':
        // 拿起手机不改变活动状态
        return;
        
      default:
        newActivityState = 'unknown';
    }
    
    // 状态变化时记录
    if (newActivityState !== this.activityState) {
      this.log.info(TAG, `Activity: ${this.activityState} -> ${newActivityState}`);
      
      // 计算上一个状态的持续时间
      let duration = this.activityStateTimestamp > 0 ? now - this.activityStateTimestamp : 0;
      
      // 记录状态转换到训练数据
      let snapshot = this.augmentSnapshot(this.tray.getSnapshot());
      this.trainingSync.recordStateTransition({
        prevState: this.activityState,
        newState: newActivityState,
        duration: duration,
        context: snapshot,
        timestamp: now
      });
      
      this.prevActivityState = this.activityState;
      this.activityState = newActivityState;
      this.activityStateTimestamp = now;
    }
  }
  
  /**
   * 从穿戴设备获取心率
   */
  private getHeartRateFromWearable(): number {
    let digitalData = this.digitalWorld.getDigitalData();
    if (digitalData['heart_rate']) {
      return parseInt(digitalData['heart_rate']) || 0;
    }
    return 0;
  }

  /**
   * 检测是否在睡觉
   */
  private detectSleepingState(ctx: EnvironmentContext, hour: number): string {
    // 夜间时段 (22:00 - 06:00)
    if (hour >= 22 || hour < 6) {
      // 在家 + 静止 = 睡觉
      if (ctx.currentGeofence?.id === 'home' && ctx.motionState === 'stationary') {
        return 'true';
      }
    }
    // 检查活动状态
    if (this.activityState === 'sleeping') {
      return 'true';
    }
    return 'false';
  }

  /**
   * 根据运动状态调整所有传感器采样间隔 (多级采集)
   * pickup 状态将 GPS 降到静止频率以节省功耗
   */
  private adjustLocationInterval(state: MotionState): void {
    let newGpsInterval: number;
    let newWifiInterval: number;
    let newAccelInterval: number;

    switch (state) {
      case 'stationary':
        newGpsInterval = ContextAwarenessService.GPS_STATIONARY;
        newWifiInterval = ContextAwarenessService.WIFI_STATIONARY;
        newAccelInterval = ContextAwarenessService.ACCEL_STATIONARY;
        break;
      case 'walking':
        newGpsInterval = ContextAwarenessService.GPS_WALKING;
        newWifiInterval = ContextAwarenessService.WIFI_WALKING;
        newAccelInterval = ContextAwarenessService.ACCEL_WALKING;
        break;
      case 'running':
        newGpsInterval = ContextAwarenessService.GPS_RUNNING;
        newWifiInterval = ContextAwarenessService.WIFI_RUNNING;
        newAccelInterval = ContextAwarenessService.ACCEL_RUNNING;
        break;
      case 'driving':
        newGpsInterval = ContextAwarenessService.GPS_DRIVING;
        newWifiInterval = ContextAwarenessService.WIFI_DRIVING;
        newAccelInterval = ContextAwarenessService.ACCEL_DRIVING;
        break;
      default:
        newGpsInterval = ContextAwarenessService.GPS_UNKNOWN;
        newWifiInterval = ContextAwarenessService.WIFI_UNKNOWN;
        newAccelInterval = ContextAwarenessService.ACCEL_UNKNOWN;
    }
    
    // 调整GPS采集
    if (newGpsInterval !== this.locationIntervalMs) {
      this.locationIntervalMs = newGpsInterval;
      this.log.info(TAG, `GPS interval: ${newGpsInterval / 1000}s for ${state}`);
      this.restartLocationTimer();
    }
    
    // 调整WiFi扫描
    if (newWifiInterval !== this.wifiIntervalMs) {
      this.wifiIntervalMs = newWifiInterval;
      this.log.info(TAG, `WiFi interval: ${newWifiInterval / 1000}s for ${state}`);
      this.restartWifiTimer();
    }
    
    // 调整加速度计
    if (newAccelInterval !== this.accelIntervalNs) {
      this.accelIntervalNs = newAccelInterval;
      this.log.info(TAG, `Accel interval: ${newAccelInterval / 1000000}ms for ${state}`);
      this.restartAccelerometer();
    }
  }

  /**
   * 启动智能位置获取定时器
   */
  private startSmartLocationTimer(): void {
    if (this.locationTimer !== -1) return;
    
    this.locationTimer = setInterval(() => {
      this.fetchSingleLocation();
    }, this.locationIntervalMs);
    
    this.log.info(TAG, `GPS timer started: ${this.locationIntervalMs / 1000}s`);
    this.fetchSingleLocation();
  }

  private stopSmartLocationTimer(): void {
    if (this.locationTimer !== -1) {
      clearInterval(this.locationTimer);
      this.locationTimer = -1;
    }
  }

  private restartLocationTimer(): void {
    this.stopSmartLocationTimer();
    if (this.locationIntervalMs > 0) {
      this.startSmartLocationTimer();
    }
  }

  /**
   * WiFi扫描定时器 (多级采集)
   */
  private startWifiTimer(): void {
    if (this.wifiTimer !== -1 || this.wifiIntervalMs === 0) return;
    
    this.wifiTimer = setInterval(() => {
      this.scanWifi();
    }, this.wifiIntervalMs);
    
    this.log.info(TAG, `WiFi timer started: ${this.wifiIntervalMs / 1000}s`);
    this.scanWifi();
  }

  private stopWifiTimer(): void {
    if (this.wifiTimer !== -1) {
      clearInterval(this.wifiTimer);
      this.wifiTimer = -1;
    }
  }

  private restartWifiTimer(): void {
    this.stopWifiTimer();
    if (this.wifiIntervalMs > 0) {
      this.startWifiTimer();
    }
  }

  private scanWifi(): void {
    try {
      wifiManager.getLinkedInfo().then((info) => {
        let ssid = info.ssid ?? '';
        this.tray.put('wifiSsid', ssid, 0.9, 'wifi');
        
        if (ssid !== this.lastWifiSsid) {
          this.log.info(TAG, `WiFi: ${this.lastWifiSsid} -> ${ssid}`);
          this.engine.pushEvent('wifi_change');
        }
        this.lastWifiSsid = ssid;
      }).catch(() => {});
    } catch {
      // ignore
    }
  }

  /**
   * 重启加速度计 (多级采集)
   */
  private restartAccelerometer(): void {
    try {
      sensor.off(sensor.SensorId.ACCELEROMETER);
    } catch {
      // ignore
    }
    try {
      sensor.on(sensor.SensorId.ACCELEROMETER, (data: sensor.AccelerometerResponse) => {
        this.accelerometerData = { x: data.x, y: data.y, z: data.z, timestamp: Date.now() };
        this.recordAccelSample();
        this.updateMotionState();
      }, { interval: this.accelIntervalNs });
    } catch (err) {
      this.log.warn(TAG, `Accelerometer restart failed: ${(err as Error).message}`);
    }
  }

  /**
   * 获取单次位置并处理 (CellID优化：如果基站没变且静止，跳过GPS)
   */
  private async fetchSingleLocation(): Promise<void> {
    try {
      // 先获取WiFi信息
      this.refreshWifiSync();
      
      // CellID优化：如果静止且CellID没变，跳过GPS请求
      if (this.lastMotionState === 'stationary') {
        let cellIdChanged = await this.checkCellIdChanged();
        if (!cellIdChanged && this.lastLocation) {
          // CellID没变，用户可能还在同一位置，使用缓存位置
          this.log.debug(TAG, 'CellID unchanged, using cached location');
          this.checkForNewPlaceSmart(this.lastLocation.latitude, this.lastLocation.longitude);
          return;
        }
      }
      
      // CellID变了或不在静止状态，请求GPS
      let request: geoLocationManager.CurrentLocationRequest = {
        priority: geoLocationManager.LocationRequestPriority.FIRST_FIX,
        scenario: geoLocationManager.LocationRequestScenario.UNSET,
        maxAccuracy: 100,
      };
      
      let location = await geoLocationManager.getCurrentLocation(request);
      if (location) {
        this.handleLocationUpdate(location);
      }
    } catch (err) {
      this.log.warn(TAG, `Location fetch failed: ${(err as Error).message}`);
    }
  }

  /**
   * 同步获取WiFi信息
   */
  private refreshWifiSync(): void {
    try {
      wifiManager.getLinkedInfo().then((info) => {
        let ssid = info.ssid ?? '';
        this.tray.put('wifiSsid', ssid, 0.9, 'wifi');
        if (ssid !== this.lastWifiSsid) {
          this.log.info(TAG, `WiFi: ${this.lastWifiSsid} -> ${ssid}`);
          this.engine.pushEvent('wifi_change');
        }
        this.lastWifiSsid = ssid;
      }).catch(() => {});
    } catch {
      // ignore
    }
  }

  /**
   * 异步获取WiFi信息
   */
  private async refreshWifiAsync(): Promise<void> {
    try {
      let info = await wifiManager.getLinkedInfo();
      let ssid = info.ssid ?? '';
      this.tray.put('wifiSsid', ssid, 0.9, 'wifi');
      if (ssid !== this.lastWifiSsid) {
        this.log.info(TAG, `WiFi: ${this.lastWifiSsid} -> ${ssid}`);
        this.engine.pushEvent('wifi_change');
      }
      this.lastWifiSsid = ssid;
    } catch {
      // ignore
    }
  }

  /**
   * 处理位置更新
   */
  private handleLocationUpdate(location: geoLocationManager.Location): void {
    let lat = location.latitude;
    let lng = location.longitude;
    let speed = location.speed ?? 0;
    let accuracy = location.accuracy ?? 100;
    
    // 更新数据托盘
    this.tray.put('latitude', lat.toFixed(6), 1.0, 'gps');
    this.tray.put('longitude', lng.toFixed(6), 1.0, 'gps');
    this.tray.put('locationAccuracy', accuracy.toFixed(0), 0.8, 'gps');
    
    // 检查围栏
    let locState: LocationState = {
      latitude: lat,
      longitude: lng,
      speed: speed,
      accuracy: accuracy,
      timestamp: Date.now(),
      insideGeofences: []
    };
    this.geofenceMgr.updateLocation(locState);
    this.lastLocation = locState;
    
    this.log.debug(TAG, `Location update: (${lat.toFixed(4)}, ${lng.toFixed(4)}) speed=${speed.toFixed(1)}m/s wifi=${this.lastWifiSsid}`);
    
    // 检查新地点（停留5分钟+WiFi）- 异步执行
    this.checkForNewPlaceSmart(lat, lng);
  }

  /**
   * 获取当前CellID (用于低功耗位置变化检测)
   * Note: GET_TELEPHONY_STATE is a system_basic permission unavailable to consumer apps.
   * Returns empty string — checkCellIdChanged() uses WiFi SSID as fallback.
   */
  private async getCurrentCellId(): Promise<string> {
    return '';
  }

  /**
   * 检查CellID是否变化 (用于决定是否需要请求GPS)
   * @return true=变化了需要GPS, false=没变化可以跳过GPS
   */
  private async checkCellIdChanged(): Promise<boolean> {
    let currentCellId = await this.getCurrentCellId();
    if (currentCellId.length === 0) {
      // CellID unavailable — use WiFi SSID as fallback stationarity signal
      if (this.lastWifiSsid.length > 0 && this.lastLocation) {
        return false; // WiFi connected + have cached location → likely stationary
      }
      return true; // No WiFi → conservative, request GPS
    }

    this.tray.put('cellId', currentCellId, 0.9, 'cellular');

    if (currentCellId !== this.lastCellId) {
      this.log.info(TAG, `CellID changed: ${this.lastCellId} -> ${currentCellId}`);
      this.lastCellId = currentCellId;
      this.lastCellIdTime = Date.now();
      return true;
    }

    // CellID没变，可能还在同一位置
    return false;
  }
  private startPeriodicEvaluation(): void {
    if (this.evaluationTimer !== -1) return;
    this.evaluationTimer = setInterval(() => {
      this.periodicEvaluate();
    }, ContextAwarenessService.EVALUATION_INTERVAL_MS);
    this.log.info(TAG, 'Started periodic evaluation');
  }

  private stopPeriodicEvaluation(): void {
    if (this.evaluationTimer !== -1) {
      clearInterval(this.evaluationTimer);
      this.evaluationTimer = -1;
      this.log.info(TAG, 'Stopped periodic evaluation');
    }
  }

  private async periodicEvaluate(): Promise<void> {
    if (!this.isRunning) return;
    // Refresh tray with latest sensor data, then read snapshot from tray
    await this.refreshTray();
    let snapshot = this.tray.getSnapshot();
    await this.evaluateAndDeliver(snapshot);
  }


  private startLocationDiscovery(): void {
    if (this.discoveryTimer !== -1) return;

    // 监听位置变化，记录到发现服务
    this.geofenceMgr.addLocationListener((location) => {
      this.log.info(TAG, `Location update: (${location.latitude.toFixed(4)}, ${location.longitude.toFixed(4)})`);
      this.locationDiscovery.recordLocation(location);
      // 检测新地点
      let ssid = this.lastWifiSsid ?? '';
      this.checkForNewPlace(location.latitude, location.longitude, ssid);
    });

    // 定时运行聚类发现
    this.discoveryTimer = setInterval(() => {
      this.runLocationDiscovery();
    }, ContextAwarenessService.DISCOVERY_INTERVAL_MS);

    this.log.info(TAG, 'Started location discovery');
  }

  private stopLocationDiscovery(): void {
    if (this.discoveryTimer !== -1) {
      clearInterval(this.discoveryTimer);
      this.discoveryTimer = -1;
      this.log.info(TAG, 'Stopped location discovery');
    }
  }

  private async runLocationDiscovery(): Promise<void> {
    if (!this.isRunning) return;
    let allSuggestions = await this.locationDiscovery.runDiscovery();
    if (allSuggestions.length === 0) return;

    let filtered = this.filterSuggestions(allSuggestions);
    if (filtered.length === 0) {
      this.log.info(TAG, `Discovery found ${allSuggestions.length} raw, all filtered out`);
      return;
    }

    // Mark as shown today
    let now = Date.now();
    for (let i = 0; i < filtered.length; i++) {
      this.suggestionState.lastShown[filtered[i].id] = now;
    }
    this.saveSuggestionState();

    this.log.info(TAG, `Emitting ${filtered.length} geofence suggestions`);
    this.notifySuggestionListeners(filtered);
  }

  /** 获取位置发现建议 */
  getLocationSuggestions(): GeofenceSuggestion[] {
    return this.locationDiscovery.getSuggestions();
  }

  /** 获取位置发现统计 */
  getLocationDiscoveryStats(): DiscoveryStatsInfo {
    return this.locationDiscovery.getStats();
  }

  
  /**
   * 刷新托盘：将所有可轮询的传感器数据写入托盘
   * 事件驱动的数据（加速度计、围栏）由回调直接写入。
   */
  private async refreshTray(): Promise<void> {
    let now = new Date();
    let hour = now.getHours();

    // 时间（实时计算，TTL=∞）
    let timeOfDay: TimeOfDay;
    if (hour >= 5 && hour < 12) timeOfDay = 'morning';
    else if (hour >= 12 && hour < 17) timeOfDay = 'afternoon';
    else if (hour >= 17 && hour < 21) timeOfDay = 'evening';
    else timeOfDay = 'night';

    let dayOfWeek = now.getDay();
    let isWeekend = dayOfWeek === 0 || dayOfWeek === 6;

    this.tray.put('hour', hour.toString(), 1.0, 'system');
    this.tray.put('timeOfDay', timeOfDay, 1.0, 'system');
    this.tray.put('dayOfWeek', dayOfWeek.toString(), 1.0, 'system');
    this.tray.put('isWeekend', isWeekend ? 'true' : 'false', 1.0, 'system');

    // 电池
    try {
      this.tray.put('batteryLevel', batteryInfo.batterySOC.toString(), 1.0, 'battery');
      let charging = batteryInfo.chargingStatus === batteryInfo.BatteryChargeState.ENABLE;
      this.tray.put('isCharging', charging ? 'true' : 'false', 1.0, 'battery');
    } catch {
      // ignore
    }

    // 网络 + WiFi SSID
    try {
      if (wifiManager.isWifiActive()) {
        this.tray.put('networkType', 'wifi', 1.0, 'wifi');
        try {
          let info = await wifiManager.getLinkedInfo();
          let ssid = info.ssid || '';
          if (ssid.startsWith('"') && ssid.endsWith('"')) {
            ssid = ssid.substring(1, ssid.length - 1);
          }
          if (ssid.length > 0) {
            this.tray.put('wifiSsid', ssid, 1.0, 'wifi');
            this.lastWifiSsid = ssid;
          }
        } catch { /* ignore */ }
      } else {
        this.tray.put('networkType', 'cellular', 0.8, 'network');
      }
    } catch {
      // ignore
    }
    
    // WiFi丢失标记（遍历所有类别，有效期内）
    let nowMs = Date.now();
    this.wifiLostTimestamps.forEach((ts: number, category: string) => {
      if (nowMs - ts < ContextAwarenessService.WIFI_LOST_TTL_MS) {
        this.tray.put('wifiLost', 'true', 0.8, 'wifi');
        this.tray.put('wifiLostCategory', category, 0.8, 'wifi');
        // 向后兼容
        if (category === 'work') {
          this.tray.put('wifiLostWork', 'true', 0.8, 'wifi');
        }
      }
    });

    // 位置 / 围栏
    if (this.lastLocation) {
      this.tray.put('latitude', this.lastLocation.latitude.toString(), 1.0, 'gps');
      this.tray.put('longitude', this.lastLocation.longitude.toString(), 1.0, 'gps');

      let geofences = this.geofenceMgr.getGeofencesAtLocation(
        this.lastLocation.latitude,
        this.lastLocation.longitude
      );
      if (geofences.length > 0) {
        this.tray.put('geofence', geofences[0].id, 1.0, 'geofence');
      }
    }

    // 步数：由 StepCounterPlugin 通过插件路径写入（step_count_today），CAS 不再重复写入

    // 运动状态（加速度计回调已写入，这里确保有值）
    if (this.lastMotionState !== 'unknown') {
      this.tray.put('motionState', this.lastMotionState, 0.9, 'accelerometer');
    }
    // 拿起手机状态（基于当前运动状态判断，不依赖瞬时检测器）
    this.tray.put('isPickup', this.lastMotionState === 'pickup' ? 'true' : 'false', 0.9, 'accelerometer');

    // CellID
    if (this.lastCellId.length > 0) {
      this.tray.put('cellId', this.lastCellId, 0.9, 'cellular');
    } else {
      this.tray.put('cellId', '(unavailable)', 0.3, 'cellular');
    }

    // 插件数据 → 托盘（按物理/数字世界分类）
    // 物理世界插件：传感器类（bluetooth, wearable, audio, media, posture, screen, stepCounter）
    // 数字世界插件：应用/信息类（calendar, appUsage, foregroundApp, notification）
    let pluginSkip: string[] = [
      'wifi_ssid', 'wifi_connected', 'wifi_rssi', 'wifi_frequency',  // 已有 wifiSsid / networkType
      'step_count', 'is_active',                                      // 已有 stepCount / motionState
      'screen_on', 'screen_locked', 'user_active',                   // 内部状态
      'init_error', 'data_source', 'device_name', 'device_connected' // 元数据噪声
    ];
    let digitalPluginNames: string[] = ['calendar', 'appUsage', 'foregroundApp', 'notification'];
    let physicalSourceMap: Record<string, string> = {
      'bluetooth': 'bluetooth', 'wearable': 'wearable', 'ambientSound': 'audio',
      'media': 'media', 'posture': 'posture', 'screen': 'screen', 'stepCounter': 'pedometer',
      'wifi': 'wifi'
    };
    let pluginStatuses = this.digitalWorld.getPluginStatus();
    for (let i = 0; i < pluginStatuses.length; i++) {
      let ps = pluginStatuses[i];
      if (!ps.enabled || !ps.hasData) continue;
      let snapshot = this.digitalWorld.getPluginSnapshot(ps.name);
      if (!snapshot) continue;
      let isDigital = digitalPluginNames.includes(ps.name);
      let source = isDigital ? 'digital' : (physicalSourceMap[ps.name] ?? ps.name);
      let keys = Object.keys(snapshot.data);
      for (let j = 0; j < keys.length; j++) {
        let k = keys[j];
        let v = snapshot.data[k];
        if (v.length > 0 && !pluginSkip.includes(k)) {
          this.tray.put(k, v, 0.8, source);
        }
      }
    }
    // 保留 lastDigitalData 供兼容
    this.lastDigitalData = this.digitalWorld.getDigitalData();
  }

  /**
   * 获取当前完整的环境上下文
   * 保留供反馈路径和兼容旧 API 使用。内部同时刷新托盘。
   */
  async getCurrentContext(): Promise<EnvironmentContext> {
    // 刷新托盘（所有传感器数据写入）
    await this.refreshTray();

    let now = new Date();
    let hour = now.getHours();

    let timeOfDay: TimeOfDay;
    if (hour >= 5 && hour < 12) timeOfDay = 'morning';
    else if (hour >= 12 && hour < 17) timeOfDay = 'afternoon';
    else if (hour >= 17 && hour < 21) timeOfDay = 'evening';
    else timeOfDay = 'night';

    let dayOfWeek = now.getDay();
    let isWeekend = dayOfWeek === 0 || dayOfWeek === 6;

    // 设备状态
    let batteryLevel = 100;
    let isCharging = false;
    try {
      batteryLevel = batteryInfo.batterySOC;
      isCharging = batteryInfo.chargingStatus === batteryInfo.BatteryChargeState.ENABLE;
    } catch {
      // ignore
    }

    // 网络状态
    let networkType: NetworkType = 'none';
    try {
      if (wifiManager.isWifiActive()) {
        networkType = 'wifi';
      } else {
        networkType = 'cellular';
      }
    } catch {
      // ignore
    }
    
    // 当前围栏（多源融合）

    // 当前围栏
    let currentGeofence: Geofence | undefined;
    let allGeofences = this.geofenceMgr.getAllGeofences();
    let fusionResult = await this.locationFusion.getBestMatch(allGeofences, this.lastLocation);
    if (fusionResult) {
      currentGeofence = this.geofenceMgr.getGeofence(fusionResult.geofenceId);
      this.log.debug(TAG,
        `Fused location: ${fusionResult.geofenceId} conf=${fusionResult.confidence.toFixed(2)} src=${fusionResult.source}`);
    } else if (this.lastLocation) {
      // 降级：融合无结果时用原始 GPS
      let gpsGeofences = this.geofenceMgr.getGeofencesAtLocation(
        this.lastLocation.latitude,
        this.lastLocation.longitude
      );
      currentGeofence = gpsGeofences[0];
    }

    let ctx: EnvironmentContext = {
      timestamp: Date.now(),
      location: this.lastLocation,
      currentGeofence,
      motionState: this.lastMotionState,
      stepCount: this.stepCount,
      timeOfDay,
      dayOfWeek,
      isWeekend,
      batteryLevel,
      isCharging,
      networkType,
      screenOn: true,
    };

    this.currentContext = ctx;
    return ctx;
  }

  /**
   * 构建 C++ 规则引擎需要的快照格式
   *
   * TODO [Digital World Integration Point]:
   * Digital world data from DigitalWorldService is merged into the snapshot here.
   * The C++ engine's ContextSnapshot currently uses a fixed set of keys (timeOfDay,
   * hour, motionState, etc.), but the evaluate() method passes JSON so additional
   * digital-world keys (cal_hasUpcoming, audio_inCall, screen_locked, etc.) can be
   * matched by rules that reference these keys. New rules can use conditions like:
   *   { key: 'cal_inMeeting', op: 'eq', value: 'true' }
   *   { key: 'audio_inCall', op: 'eq', value: 'true' }
   *   { key: 'screen_locked', op: 'eq', value: 'true' }
   *
   * To fully wire this up:
   * 1. Extend ContextSnapshot interface in ContextEngine.ets with optional digital fields
   * 2. Add built-in rules that reference digital-world keys
   * 3. Connect DigitalWorldService lifecycle to this service (done — see init/start/stop)
   */
  private buildSnapshot(ctx: EnvironmentContext): ContextSnapshot {
    let now = new Date();
    let hour = now.getHours();
    let dayOfWeek = now.getDay();

    // 计算活动持续时间
    let activityDuration = 0;
    if (this.activityStateTimestamp > 0) {
      activityDuration = Math.floor((Date.now() - this.activityStateTimestamp) / 1000);
    }

    let snapshot: ContextSnapshot = {
      timeOfDay: ctx.timeOfDay,
      hour: hour.toString(),
      dayOfWeek: dayOfWeek.toString(),
      isWeekend: ctx.isWeekend ? 'true' : 'false',
      motionState: ctx.motionState || 'unknown',
      batteryLevel: ctx.batteryLevel.toString(),
      isCharging: ctx.isCharging ? 'true' : 'false',
      networkType: ctx.networkType || 'none',
      geofence: ctx.currentGeofence?.id,
      latitude: ctx.location?.latitude?.toString(),
      longitude: ctx.location?.longitude?.toString(),
      stepCount: ctx.stepCount?.toString(),
      isSleeping: this.detectSleepingState(ctx, hour),
      // 状态历史
      prevMotionState: this.prevMotionState,
      prevActivityState: this.prevActivityState,
      activityDuration: activityDuration.toString(),
      activityState: this.activityState
    };

    // Merge digital world plugin data into snapshot for rule evaluation
    // Digital data is merged via JSON since ContextSnapshot has fixed keys
    let digitalData = this.digitalWorld.getDigitalData();
    this.lastDigitalData = digitalData;

    return snapshot;
  }

  /**
   * 评估并推送推荐，无匹配时调用 LLM 兜底
   * 评估并推送推荐
   */
  private async evaluateAndDeliver(snapshot: ContextSnapshot): Promise<void> {
    let results = this.engine.evaluate(snapshot, 3);

    // 积极探索模式：新状态指纹 → 强制触发 LLM（即使有引擎匹配也不跳过）
    let exploreTriggered = false;
    if (this.exploreMode) {
      let fp = this.computeFingerprint(snapshot);
      if (!this.exploredFingerprints.has(fp)) {
        this.exploredFingerprints.add(fp);
        this.saveExploredFingerprints();
        exploreTriggered = true;
        this.log.info(TAG, `Explore mode: new fingerprint "${fp}", will trigger LLM`);
      }
    }

    if (results.length > 0) {
      let top = results[0];
      if (!this.isOnCooldown(top.ruleId)) {
        let rec: ContextRecommendation = {
          rule: {
            id: top.ruleId,
            trigger: {} as RuleTrigger,
            action: top.action as UserAction,
            confidence: top.confidence,
            triggerCount: 0,
            acceptCount: 0,
            createdAt: Date.now(),
            updatedAt: Date.now(),
            enabled: true
          },
          action: top.action as UserAction,
          reason: `基于当前情景推荐 (${Math.round(top.confidence * 100)}% 匹配)`
        };

        this.notifyRecommendation(rec);
        this.setOnCooldown(top.ruleId);

        // 记录训练数据
        this.trainingSync.recordRuleMatch(snapshot, top.ruleId, top.action.type || 'suggestion', top.confidence);
      }

      // 非探索模式或已探索过的指纹：有引擎结果就够了
      if (!exploreTriggered) return;
    }

    // C++ engine returned no matches — try LLM fallback
    this.log.info(TAG, 'No engine matches, trying LLM fallback');
    let llmResult = await this.llmFallback.analyzeContext(snapshot);
    if (!llmResult) return;

    if (this.isOnCooldown('llm_fallback')) return;

    // Don't repeat same LLM recommendation if user didn't give feedback on the last one
    let llmPayload = `${llmResult.title}: ${llmResult.content}`;
    if (this.lastLlmPayload.length > 0 && this.lastLlmPayload === llmPayload && !this.lastLlmFeedbackReceived) {
      // Same recommendation, no feedback yet — just update timestamp, don't show again
      this.log.info(TAG, `Skipping repeat LLM recommendation: "${llmResult.title}"`);
      this.setOnCooldown('llm_fallback');
      return;
    }

    let now = new Date();
    let dateStr = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')} ${String(now.getHours()).padStart(2, '0')}:${String(now.getMinutes()).padStart(2, '0')}:${String(now.getSeconds()).padStart(2, '0')}`;
    let llmRuleId = `user_llm_${dateStr}`;
    this.lastLlmPayload = llmPayload;
    this.lastLlmRuleId = llmRuleId;
    this.lastLlmFeedbackReceived = false;

    let rec: ContextRecommendation = {
      rule: {
        id: llmRuleId,
        trigger: {} as RuleTrigger,
        action: { type: 'show_info', target: 'llm_suggestion' } as UserAction,
        confidence: llmResult.priority === 'high' ? 0.9 : llmResult.priority === 'medium' ? 0.7 : 0.5,
        triggerCount: 0,
        acceptCount: 0,
        createdAt: Date.now(),
        updatedAt: Date.now(),
        enabled: true
      },
      action: { type: 'show_info', target: 'llm_suggestion' } as UserAction,
      reason: llmPayload
    };

    this.notifyRecommendation(rec);
    this.setOnCooldown('llm_fallback');

    // === Store LLM result as PENDING rule (only promoted on positive feedback) ===
    try {
      let conditions: EngineCondition[] = this.snapshotToConditions(snapshot);
      let cooldownMs = llmResult.priority === 'high' ? 3600000 : llmResult.priority === 'medium' ? 14400000 : 28800000;

      let newRule: EngineRule = {
        id: llmRuleId,
        name: llmResult.title,
        conditions: conditions,
        action: { id: `llm_action_${dateStr}`, type: 'suggestion', payload: llmPayload } as EngineAction,
        priority: llmResult.priority === 'high' ? 2.0 : llmResult.priority === 'medium' ? 1.5 : 1.0,
        cooldownMs: cooldownMs,
        enabled: true,
      };

      let engine = ContextEngineService.getInstance();
      engine.addPendingRule(newRule);
      this.log.info(TAG, `LLM rule stored as pending: id=${llmRuleId}, name=${llmResult.title}`);
    } catch (err) {
      this.log.warn(TAG, `Failed to store pending LLM rule: ${(err as Error).message}`);
    }

    // Log to BehaviorLogger with source='llm'
    let ctx = this.currentContext ?? await this.getCurrentContext();
    let llmAction: UserAction = { type: 'show_info', target: 'llm_suggestion', params: { 'source': 'llm', 'title': llmResult.title } };
    await this.behaviorLog.logBehavior(ctx, llmAction);
    this.log.info(TAG, `LLM fallback delivered (pending): ${llmResult.title}`);
  }

  /**
   * 检测新地点：GPS + WiFi 稳定 5 分钟且不在任何已知围栏内
   */
  private async checkForNewPlace(lat: number, lng: number, wifiSsid: string): Promise<void> {
    // 检查是否在任何已知围栏内
    let allGeofences = this.geofenceMgr.getAllGeofences();
    let inKnownGeofence = false;
    for (let i = 0; i < allGeofences.length; i++) {
      let gf = allGeofences[i];
      let dist = this.haversineDistance(lat, lng, gf.latitude, gf.longitude);
      if (dist < gf.radiusMeters) {
        inKnownGeofence = true;
        break;
      }
    }
    
    if (inKnownGeofence) {
      // 在已知围栏内，重置检测
      this.newPlaceDetectionStart = 0;
      return;
    }
    
    let now = Date.now();
    
    // 检查位置是否稳定（与上次记录的差异 < 100m）
    if (this.newPlaceDetectionStart > 0) {
      let drift = this.haversineDistance(lat, lng, this.newPlaceLastLat, this.newPlaceLastLng);
      if (drift > ContextAwarenessService.NEW_PLACE_MAX_DRIFT_M) {
        // 位置漂移太大，重置
        this.log.info(TAG, `New place reset: drifted ${Math.round(drift)}m`);
        this.newPlaceDetectionStart = 0;
        return;
      }
    }
    
    // 开始新检测或继续现有检测
    if (this.newPlaceDetectionStart === 0) {
      this.newPlaceDetectionStart = now;
      this.newPlaceLastLat = lat;
      this.newPlaceLastLng = lng;
      this.newPlaceWifiSsid = wifiSsid;
      this.log.info(TAG, `New place detection started at (${lat.toFixed(4)}, ${lng.toFixed(4)})`);
      return;
    }
    
    // 检查是否稳定足够时间
    let stableMs = now - this.newPlaceDetectionStart;
    if (stableMs < ContextAwarenessService.NEW_PLACE_STABLE_MS) {
      this.log.debug(TAG, `New place stable for ${Math.round(stableMs / 1000)}s, need ${ContextAwarenessService.NEW_PLACE_STABLE_MS / 1000}s`);
      return;
    }
    
    // 稳定 5 分钟，检测到新地点！
    this.log.info(TAG, `New place detected! (${lat.toFixed(4)}, ${lng.toFixed(4)}) WiFi=${wifiSsid}`);
    this.newPlaceDetectionStart = 0;  // 重置防止重复
    
    // 尝试逆地理编码获取地点名
    let placeName = await this.reverseGeocode(lat, lng);
    
    // 显示 A2UI 卡片让用户确认
    this.showNewPlaceCard(lat, lng, wifiSsid, placeName);
  }

  /**
   * 实时检测新地点（结合当前WiFi状态）
   * 停留5分钟+有WiFi连接 → 立即发现，不等聚类
   */
  private async checkForNewPlaceSmart(lat: number, lng: number): Promise<void> {
    // 同时学习当前围栏的特征（会先获取WiFi）
    await this.learnPlaceSignals(lat, lng);
    
    // 检测新地点
    await this.checkForNewPlace(lat, lng, this.lastWifiSsid);
  }

  /**
   * 学习围栏特征信号：在围栏内时，记录WiFi/蓝牙等特征
   */
  private async learnPlaceSignals(lat: number, lng: number): Promise<void> {
    let allGeofences = this.geofenceMgr.getAllGeofences();
    
    // 如果WiFi信息为空，尝试同步获取
    if (!this.lastWifiSsid || this.lastWifiSsid.length === 0) {
      await this.refreshWifiAsync();
    }
    
    this.log.debug(TAG, `learnPlaceSignals: checking ${allGeofences.length} geofences, wifi=${this.lastWifiSsid}`);
    
    for (let i = 0; i < allGeofences.length; i++) {
      let gf = allGeofences[i];
      let dist = this.haversineDistance(lat, lng, gf.latitude, gf.longitude);
      
      if (dist < gf.radiusMeters) {
        this.log.info(TAG, `Inside geofence: ${gf.name}, dist=${Math.round(dist)}m, wifi=${this.lastWifiSsid}, cellId=${this.lastCellId}`);
        
        // 在此围栏内，学习信号
        let signals = gf.learnedSignals ?? {
          wifiSSIDs: [],
          bluetoothDevices: [],
          cellIds: [],
          typicalTimes: [],
          lastSeen: 0,
          visitCount: 0
        };
        
        let updated = false;
        
        // 学习WiFi SSID
        if (this.lastWifiSsid && this.lastWifiSsid.length > 0) {
          if (!signals.wifiSSIDs!.includes(this.lastWifiSsid)) {
            signals.wifiSSIDs!.push(this.lastWifiSsid);
            this.log.info(TAG, `Learned WiFi for ${gf.name}: ${this.lastWifiSsid}`);
            this.notifyGeofenceFeatureLearned(gf.name, 'WiFi', this.lastWifiSsid);
            updated = true;
          }
        }
        
        // 学习CellID
        if (this.lastCellId && this.lastCellId.length > 0) {
          if (!signals.cellIds!.includes(this.lastCellId)) {
            signals.cellIds!.push(this.lastCellId);
            this.log.info(TAG, `Learned CellID for ${gf.name}: ${this.lastCellId}`);
            updated = true;
          }
        }
        
        // 更新访问统计
        signals.visitCount = (signals.visitCount ?? 0) + 1;
        signals.lastSeen = Date.now();
        
        // 学习典型时间
        let hour = new Date().getHours();
        let timeRange = `${hour}:00-${hour + 1}:00`;
        if (!signals.typicalTimes!.some(t => t.start === timeRange)) {
          signals.typicalTimes!.push({ start: timeRange, end: `${hour + 1}:00` });
          if (signals.typicalTimes!.length > 5) {
            signals.typicalTimes!.shift();
          }
          updated = true;
        }
        
        // 保存更新
        if (updated || signals.visitCount === 1) {
          gf.learnedSignals = signals;
          this.geofenceMgr.saveToFile();
        }
        
        // 只处理第一个匹配的围栏
        break;
      }
    }
  }

  /**
   * 通知围栏学习到新特征
   */
  private notifyGeofenceFeatureLearned(geofenceName: string, featureType: string, featureValue: string): void {
    let titleText = I18n.t('context.geofence.learned');
    let wifiLabelText = I18n.t('context.geofence.newWifi');
    
    let jsonl = '{"type":"form","id":"gf_learn_' + Date.now() + '","children":[' +
      '{"type":"text","text":"🔗 ' + titleText + '","style":{"fontSize":16,"fontWeight":"bold"}},' +
      '{"type":"text","text":"' + geofenceName + '"},' +
      '{"type":"text","text":"' + wifiLabelText + ': ' + featureValue + '","style":{"fontSize":12,"color":"#666"}}' +
      ']}';
    
    this.dispatchA2UI('push', jsonl);
  }

  /**
   * 逆地理编码：坐标 → 地点名
   */
  private async reverseGeocode(lat: number, lng: number): Promise<string> {
    try {
      // 使用 HarmonyOS 逆地理编码 API
      let request: geoLocationManager.ReverseGeoCodeRequest = {
        latitude: lat,
        longitude: lng,
        maxItems: 1,
        locale: 'zh'
      };
      let results = await geoLocationManager.getAddressesFromLocation(request);
      if (results && results.length > 0) {
        let addr = results[0];
        // 优先使用地标名，其次街道地址
        let name = addr.placeName ?? addr.roadName ?? '';
        if (name.length === 0 && addr.locality) {
          name = addr.locality;
        }
        if (name.length > 0) {
          this.log.info(TAG, `Reverse geocode: ${name}`);
          return name;
        }
      }
    } catch (err) {
      this.log.warn(TAG, `Reverse geocode failed: ${(err as Error).message}`);
    }
    // 失败时用坐标生成名称
    return `新地点 (${lat.toFixed(3)}, ${lng.toFixed(3)})`;
  }

  /**
   * 显示新地点确认卡片
   */
  private showNewPlaceCard(lat: number, lng: number, wifiSsid: string, placeName: string): void {
    let escapedName = placeName.replace(/"/g, "'");
    let escapedWifi = wifiSsid.replace(/"/g, "'");
    
    // 推断类别
    let category = this.inferCategoryFromTime();
    
    let titleText = I18n.t('context.newPlace.title');
    let wifiLabel = I18n.t('context.newPlace.wifi');
    let saveAsLabel = I18n.t('context.newPlace.saveAs');
    let renameLabel = I18n.t('context.newPlace.rename');
    let ignoreLabel = I18n.t('context.newPlace.ignore');
    
    let jsonl = '{"type":"form","id":"new_place_' + Date.now() + '","children":[' +
      '{"type":"text","text":"📍 ' + titleText + '","style":{"fontSize":18,"fontWeight":"bold"}},' +
      '{"type":"text","text":"' + escapedName + '"},' +
      '{"type":"text","text":"' + wifiLabel + ': ' + escapedWifi + '","style":{"fontSize":12,"color":"#666"}}},' +
      '{"type":"row","children":[' +
        '{"type":"button","label":"✅ ' + saveAsLabel + ' ' + category + '","action":{"event":{"name":"new_place_save","context":{"lat":' + lat + ',"lng":' + lng + ',"wifi":"' + escapedWifi + '","name":"' + escapedName + '","category":"' + category + '"}}},"style":"primary"},' +
        '{"type":"button","label":"✏️ ' + renameLabel + '","action":{"event":{"name":"new_place_rename","context":{"lat":' + lat + ',"lng":' + lng + '}}}},"style":"secondary"},' +
        '{"type":"button","label":"❌ ' + ignoreLabel + '","action":{"event":{"name":"new_place_ignore","context":{}}}},"style":"secondary"}' +
      ']}]}';
    
    this.dispatchA2UI('push', jsonl);
    this.log.info(TAG, `New place card shown: ${placeName}`);
  }

  /**
   * 根据当前时间推断地点类别
   */
  private inferCategoryFromTime(): string {
    let hour = new Date().getHours();
    let dayOfWeek = new Date().getDay();
    let isWeekend = dayOfWeek === 0 || dayOfWeek === 6;
    
    if (!isWeekend && hour >= 9 && hour < 18) {
      return 'work';
    }
    if (hour >= 22 || hour < 6) {
      return 'home';
    }
    if (hour >= 11 && hour < 14) {
      return 'restaurant';
    }
    if (isWeekend && hour >= 8 && hour < 20) {
      return 'gym';
    }
    return 'other';
  }

  /**
   * 计算两点距离（米）
   */
  private haversineDistance(lat1: number, lng1: number, lat2: number, lng2: number): number {
    let R = 6371000; // 地球半径（米）
    let dLat = (lat2 - lat1) * Math.PI / 180;
    let dLng = (lng2 - lng1) * Math.PI / 180;
    let a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
            Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
            Math.sin(dLng / 2) * Math.sin(dLng / 2);
    let c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return R * c;
  }

  
  private async onGeofenceEvent(event: GeofenceEvent): Promise<void> {
    this.log.info(TAG, `Geofence ${event.type}: ${event.geofence.name}`);

    // 更新位置
    this.lastLocation = event.location;

    // 写入托盘
    this.tray.put('latitude', event.location.latitude.toString(), 1.0, 'gps');
    this.tray.put('longitude', event.location.longitude.toString(), 1.0, 'gps');
    if (event.type === 'enter') {
      this.tray.put('geofence', event.geofence.id, 1.0, 'geofence');
    }

    // Push event to engine buffer for temporal/sequence rules
    let eventType = event.type === 'enter' ? 'geofence_enter' : 'geofence_exit';
    this.engine.pushEvent(eventType);

    // GPS 高精度进入围栏时，学习 WiFi/BT 信号
    if (event.type === 'enter') {
      this.locationFusion.learnSignals(event.geofence.id, event.location);
    }

    // 只处理进入事件
    if (event.type !== 'enter') return;

    // 刷新托盘 + 通过 C++ 规则引擎评估
    await this.refreshTray();
    let snapshot = this.tray.getSnapshot();
    this.log.info(TAG, `Geofence trigger evaluate: geofence=${snapshot.geofence ?? 'none'}`);
    await this.evaluateAndDeliver(snapshot);
    
    this.evaluateAndDeliver(snapshot);

    // 同时尝试旧的 BehaviorLogger 匹配（兼容过渡）
    let ctx = await this.getCurrentContext();
    let rules = this.behaviorLog.getMatchingRules(ctx);
    if (rules.length > 0) {
      let topRule = rules[0];
      if (!this.isOnCooldown(topRule.id)) {
        let rec: ContextRecommendation = {
          rule: topRule,
          action: topRule.action,
          reason: this.buildRecommendationReason(topRule, event.geofence),
        };
        this.notifyRecommendation(rec);
        this.setOnCooldown(topRule.id);
      }
    } else {
      this.handleNewLocationWithoutRules(event.geofence, ctx);
    }
  }
  
  /**
   * 处理没有规则的新位置 - 基于位置类型的默认推荐
   */
  private handleNewLocationWithoutRules(geofence: Geofence, ctx: EnvironmentContext): void {
    let defaultAction: UserAction | undefined;
    let reason: string = '';
    
    switch (geofence.category) {
      case 'transit':
        defaultAction = { type: 'show_qrcode', target: 'transit_code' };
        reason = `到达 ${geofence.name}，需要乘车码吗？`;
        break;
        
      case 'shopping':
        let store = (geofence.metadata && geofence.metadata['store']) ? geofence.metadata['store'] as string : 'store';
        defaultAction = { type: 'show_info', target: `deals_${store}` };
        reason = `到达 ${geofence.name}，查看今日优惠？`;
        break;
        
      case 'work':
        defaultAction = { type: 'show_info', target: 'calendar_today' };
        reason = `到达办公室，查看今日日程？`;
        break;
        
      default:
        return;  // 不推荐
    }
    
    if (defaultAction && !this.isOnCooldown(`default_${geofence.id}`)) {
      let rec: ContextRecommendation = {
        rule: {
          id: `default_${geofence.id}`,
          trigger: { geofenceIds: [geofence.id] },
          action: defaultAction,
          confidence: 0.5,  // 默认推荐的初始置信度
          triggerCount: 0,
          acceptCount: 0,
          createdAt: Date.now(),
          updatedAt: Date.now(),
          enabled: true,
        },
        action: defaultAction,
        reason,
      };
      
      this.notifyRecommendation(rec);
      this.setOnCooldown(`default_${geofence.id}`);
    }
  }
  
  private buildRecommendationReason(rule: ContextRule, geofence: Geofence): string {
    let conf = Math.round(rule.confidence * 100);
    
    if (rule.action.type === 'show_qrcode') {
      return `到达 ${geofence.name}，显示乘车码？(${conf}% 匹配)`;
    } else if (rule.action.type === 'show_info') {
      return `到达 ${geofence.name}，为你准备了相关信息 (${conf}% 匹配)`;
    } else {
      return `基于你的习惯，推荐此操作 (${conf}% 匹配)`;
    }
  }
  
  
  /**
   * Convert a ContextSnapshot into ContextCondition[] for rule persistence.
   * Extracts the key fields that defined this context moment.
   */
  private snapshotToConditions(snapshot: ContextSnapshot): EngineCondition[] {
    let conditions: EngineCondition[] = [];

    // Time of day
    conditions.push({ key: 'timeOfDay', op: 'eq', value: snapshot.timeOfDay });

    // Hour range: ±1 hour for flexibility
    let hour = parseInt(snapshot.hour);
    if (!isNaN(hour)) {
      let low = Math.max(0, hour - 1);
      let high = Math.min(23, hour + 1);
      conditions.push({ key: 'hour', op: 'range', value: `${low},${high}` });
    }

    // Weekend
    conditions.push({ key: 'isWeekend', op: 'eq', value: snapshot.isWeekend });

    // Motion state
    if (snapshot.motionState && snapshot.motionState !== 'unknown') {
      conditions.push({ key: 'motionState', op: 'eq', value: snapshot.motionState });
    }

    // Battery (only if notably low)
    let battery = parseInt(snapshot.batteryLevel);
    if (!isNaN(battery) && battery <= 20) {
      conditions.push({ key: 'batteryLevel', op: 'lte', value: '20' });
    }

    // Charging
    if (snapshot.isCharging === 'true') {
      conditions.push({ key: 'isCharging', op: 'eq', value: 'true' });
    }

    // Network
    if (snapshot.networkType && snapshot.networkType !== 'unknown') {
      conditions.push({ key: 'networkType', op: 'eq', value: snapshot.networkType });
    }

    // Geofence
    if (snapshot.geofence && snapshot.geofence.length > 0) {
      conditions.push({ key: 'geofence', op: 'eq', value: snapshot.geofence });
    }

    return conditions;
  }

  private isOnCooldown(ruleId: string): boolean {
    let lastTime = this.lastRecommendations.get(ruleId);
    if (!lastTime) return false;
    return Date.now() - lastTime < ContextAwarenessService.RECOMMENDATION_COOLDOWN_MS;
  }
  
  private setOnCooldown(ruleId: string): void {
    this.lastRecommendations.set(ruleId, Date.now());
  }
  

  /**
   * Mark that the user gave feedback on an LLM recommendation.
   * Called by FeedbackService so we know whether to repeat the recommendation.
   */
  markLlmFeedbackReceived(ruleId: string): void {
    if (ruleId === this.lastLlmRuleId || ruleId.startsWith('user_llm_')) {
      this.lastLlmFeedbackReceived = true;
    }
  }

  // ==================== 积极探索模式 ====================

  /** 获取积极探索模式状态 */
  isExploreMode(): boolean {
    return this.exploreMode;
  }

  /** 设置积极探索模式 */
  async setExploreMode(enabled: boolean): Promise<void> {
    this.exploreMode = enabled;
    if (this.context) {
      try {
        let prefs = await preferences.getPreferences(this.context, 'context_awareness');
        await prefs.put('explore_mode', enabled);
        await prefs.flush();
      } catch (err) {
        this.log.warn(TAG, `Failed to persist explore mode: ${(err as Error).message}`);
      }
    }
    this.log.info(TAG, `Explore mode ${enabled ? 'enabled' : 'disabled'}, explored ${this.exploredFingerprints.size} fingerprints`);
  }

  /** 加载积极探索模式持久化状态 */
  private async loadExploreMode(): Promise<void> {
    if (!this.context) return;
    try {
      let prefs = await preferences.getPreferences(this.context, 'context_awareness');
      this.exploreMode = await prefs.get('explore_mode', false) as boolean;
      let fpJson = await prefs.get('explored_fingerprints', '[]') as string;
      let fpArr: string[] = JSON.parse(fpJson) as string[];
      for (let i = 0; i < fpArr.length; i++) {
        this.exploredFingerprints.add(fpArr[i]);
      }
    } catch (err) {
      this.log.warn(TAG, `Failed to load explore mode: ${(err as Error).message}`);
    }
  }

  /** 持久化已探索指纹 */
  private async saveExploredFingerprints(): Promise<void> {
    if (!this.context) return;
    try {
      let prefs = await preferences.getPreferences(this.context, 'context_awareness');
      let arr: string[] = [];
      this.exploredFingerprints.forEach((fp: string) => {
        arr.push(fp);
      });
      await prefs.put('explored_fingerprints', JSON.stringify(arr));
      await prefs.flush();
    } catch (err) {
      this.log.warn(TAG, `Failed to save fingerprints: ${(err as Error).message}`);
    }
  }

  /** 计算状态指纹：只取核心维度 */
  private computeFingerprint(snapshot: ContextSnapshot): string {
    return `${snapshot.timeOfDay || 'unknown'}|${snapshot.isWeekend || 'false'}|${snapshot.motionState || 'unknown'}|${snapshot.geofence || 'none'}`;
  }

  /**
   * 用户对推荐的反馈（保留旧 API 兼容性）
   */
  async onRecommendationFeedback(
    rec: ContextRecommendation,
    accepted: boolean
  ): Promise<void> {
    let ctx = this.currentContext ?? await this.getCurrentContext();

    let outcome: ActionOutcome = {
      accepted,
      feedback: accepted ? 1 : -1,
    };

    // 记录行为
    await this.behaviorLog.logBehavior(ctx, rec.action, outcome);

    this.log.info(TAG, 'Recommendation feedback: ' + rec.rule.id + ' accepted=' + accepted.toString());
  }

  /**
   * 卡片展示时通知 FeedbackService（启动超时定时器）
   */
  onCardShown(rec: ContextRecommendation): void {
    this.feedbackSvc.onCardShown(rec);
  }

  /**
   * 👍 反馈 → reward +1.0
   */
  async onThumbsUp(ruleId: string): Promise<void> {
    let ctx = this.currentContext ?? await this.getCurrentContext();
    await this.feedbackSvc.onThumbsUp(ruleId, ctx);
  }

  /**
   * 👎 反馈 → reward -0.5
   */
  async onThumbsDown(ruleId: string): Promise<void> {
    let ctx = this.currentContext ?? await this.getCurrentContext();
    await this.feedbackSvc.onThumbsDown(ruleId, ctx);
  }

  /**
   * 用户执行推荐动作 → reward +0.8
   */
  async onActionTaken(ruleId: string): Promise<void> {
    let ctx = this.currentContext ?? await this.getCurrentContext();
    await this.feedbackSvc.onActionTaken(ruleId, ctx);
  }

  /**
   * 用户滑走卡片 → 5min 后 reward -0.1
   */
  onCardDismissed(ruleId: string): void {
    this.feedbackSvc.onCardDismissed(ruleId);
  }

  /**
   * 获取反馈统计
   */
  getFeedbackStats(): FeedbackStats {
    return this.feedbackSvc.getStats();
  }
  
  
  addRecommendationListener(listener: RecommendationListener): void {
    this.recommendationListeners.push(listener);
  }
  
  removeRecommendationListener(listener: RecommendationListener): void {
    let idx = this.recommendationListeners.indexOf(listener);
    if (idx >= 0) this.recommendationListeners.splice(idx, 1);
  }
  
  private notifyRecommendation(rec: ContextRecommendation): void {
    this.log.info(TAG, 'Recommendation: ' + rec.reason);
    // 注册卡片到 FeedbackService（启动超时定时器）
    this.feedbackSvc.onCardShown(rec);
    for (let i = 0; i < this.recommendationListeners.length; i++) {
      try {
        this.recommendationListeners[i](rec);
      } catch (err) {
        this.log.warn(TAG, 'Listener error: ' + (err as Error).message);
      }
    }
  }
  
  // ==================== A2UI 本地分发 ====================
  
  addA2UIListener(listener: (type: string, content: string) => void): void {
    this.a2uiListeners.push(listener);
  }
  
  removeA2UIListener(listener: (type: string, content: string) => void): void {
    let idx = this.a2uiListeners.indexOf(listener);
    if (idx >= 0) this.a2uiListeners.splice(idx, 1);
  }
  
  dispatchA2UI(type: string, content: string): void {
    this.log.info(TAG, `dispatchA2UI: type=${type} contentLen=${content.length} listeners=${this.a2uiListeners.length}`);
    for (let i = 0; i < this.a2uiListeners.length; i++) {
      try {
        this.a2uiListeners[i](type, content);
      } catch (err) {
        this.log.warn(TAG, 'A2UI listener error: ' + (err as Error).message);
      }
    }
  }
  
  
  /**
   * 手动记录用户行为（用于学习用户习惯）
   */
  async recordUserAction(action: UserAction, accepted: boolean = true): Promise<void> {
    let ctx = await this.getCurrentContext();
    let outcome: ActionOutcome = { accepted, feedback: accepted ? 1 : 0 };
    await this.behaviorLog.logBehavior(ctx, action, outcome);
  }
  
  
  addGeofence(geofence: Geofence): void {
    this.geofenceMgr.addGeofence(geofence);
    this.geofenceMgr.saveToFile();
    this.rebindAfterGeofenceChange();
  }
  
  removeGeofence(id: string): boolean {
    let result = this.geofenceMgr.removeGeofence(id);
    if (result) {
      this.geofenceMgr.saveToFile();
      this.rebindAfterGeofenceChange();
    }
    return result;
  }

  private rebindAfterGeofenceChange(): void {
    try {
      let geofences = this.geofenceMgr.getAllGeofences();
      let bindings: GeofenceBinding[] = [];
      for (let i = 0; i < geofences.length; i++) {
        bindings.push({ id: geofences[i].id, category: geofences[i].category });
      }
      this.engine.rebindGeofences(bindings);
      this.log.info(TAG, `围栏变更后重新绑定规则，围栏数: ${geofences.length}`);
    } catch (err) {
      this.log.warn(TAG, `rebind failed: ${(err as Error).message}`);
    }
  }
  
  getAllGeofences(): Geofence[] {
    return this.geofenceMgr.getAllGeofences();
  }
  
  

  /** 获取所有围栏的已学习信号摘要（用于设置页展示） */
  getLearnedSignalsSummaries(): LearnedSignalsSummary[] {
    return this.locationFusion.getLearnedSignalsSummaries(this.geofenceMgr.getAllGeofences());
  }

  /** 清除某个围栏的已学习信号 */
  async clearLearnedSignals(geofenceId: string): Promise<void> {
    await this.locationFusion.clearLearnedSignals(geofenceId);
  }

  /** 清除所有已学习信号 */
  async clearAllLearnedSignals(): Promise<void> {
    await this.locationFusion.clearAllLearnedSignals();
  }



  addSuggestionListener(listener: SuggestionListener): void {
    this.suggestionListeners.push(listener);
  }

  removeSuggestionListener(listener: SuggestionListener): void {
    let idx = this.suggestionListeners.indexOf(listener);
    if (idx >= 0) this.suggestionListeners.splice(idx, 1);
  }

  private notifySuggestionListeners(suggestions: GeofenceSuggestion[]): void {
    for (let i = 0; i < this.suggestionListeners.length; i++) {
      try {
        this.suggestionListeners[i](suggestions);
      } catch (err) {
        this.log.warn(TAG, 'Suggestion listener error: ' + (err as Error).message);
      }
    }
  }

  /**
   * Filter raw suggestions: remove blacklisted, deferred (< 7 days), daily-cooled,
   * and clusters that already have a matching geofence.
   */
  private filterSuggestions(raw: GeofenceSuggestion[]): GeofenceSuggestion[] {
    let now = Date.now();
    let existingGeofences = this.geofenceMgr.getAllGeofences();
    let result: GeofenceSuggestion[] = [];

    for (let i = 0; i < raw.length; i++) {
      let s = raw[i];

      // Skip blacklisted
      if (this.suggestionState.blacklist.indexOf(s.id) >= 0) continue;

      // Skip deferred (within 7 days)
      let deferredAt = this.suggestionState.deferred[s.id];
      if (deferredAt !== undefined && (now - deferredAt) < DEFER_DURATION_MS) continue;

      // Skip daily cooldown (already shown today)
      let lastShown = this.suggestionState.lastShown[s.id];
      if (lastShown !== undefined && (now - lastShown) < DAILY_COOLDOWN_MS) continue;

      // Skip if a geofence already covers this cluster (within 200m)
      let alreadyCovered = false;
      for (let gi = 0; gi < existingGeofences.length; gi++) {
        let gf = existingGeofences[gi];
        let dist = this.haversineDistance(s.latitude, s.longitude, gf.latitude, gf.longitude);
        if (dist < 200) {
          alreadyCovered = true;
          break;
        }
      }
      if (alreadyCovered) continue;

      result.push(s);
    }

    return result;
  }

  /**
   * Accept a suggestion: create geofence with the user's chosen name/category.
   */
  acceptSuggestion(suggestion: GeofenceSuggestion, name: string, category: string): void {
    let gf: Geofence = {
      id: 'auto_' + Date.now().toString(),
      name: name,
      latitude: suggestion.latitude,
      longitude: suggestion.longitude,
      radiusMeters: suggestion.radiusMeters,
      category: category as GeofenceCategory,
    };
    this.addGeofence(gf);
    this.log.info(TAG, `Accepted suggestion "${name}" as geofence ${gf.id}`);
  }

  /**
   * Ignore a suggestion permanently (blacklist).
   */
  ignoreSuggestion(clusterId: string): void {
    if (this.suggestionState.blacklist.indexOf(clusterId) < 0) {
      this.suggestionState.blacklist.push(clusterId);
    }
    // Clean up deferred/lastShown entries
    this.suggestionState.deferred[clusterId] = 0;
    this.suggestionState.lastShown[clusterId] = 0;
    this.saveSuggestionState();
    this.log.info(TAG, `Blacklisted suggestion: ${clusterId}`);
  }

  /**
   * Defer a suggestion ("以后再说") — may resurface after 7 days.
   */
  deferSuggestion(clusterId: string): void {
    this.suggestionState.deferred[clusterId] = Date.now();
    this.saveSuggestionState();
    this.log.info(TAG, `Deferred suggestion: ${clusterId}`);
  }

  /**
   * Get currently actionable suggestions (filtered).
   */
  getFilteredSuggestions(): GeofenceSuggestion[] {
    let raw = this.locationDiscovery.getSuggestions();
    return this.filterSuggestions(raw);
  }


  private async loadSuggestionState(): Promise<void> {
    if (!this.context) return;
    try {
      let store = await preferences.getPreferences(this.context, Constants.PREFS_GEOFENCE_SUGGEST);
      let json = (await store.get(SUGGEST_PREFS_KEY, '')) as string;
      if (json.length > 0) {
        let parsed = JSON.parse(json) as GeofenceSuggestionState;
        this.suggestionState = {
          blacklist: parsed.blacklist || [],
          deferred: parsed.deferred || {},
          lastShown: parsed.lastShown || {},
        };
      }
      this.suggestionStateLoaded = true;
      this.log.info(TAG, `Loaded suggestion state: ${this.suggestionState.blacklist.length} blacklisted`);
    } catch (err) {
      this.log.warn(TAG, `Failed to load suggestion state: ${(err as Error).message}`);
      this.suggestionStateLoaded = true;
    }
  }

  private saveSuggestionState(): void {
    if (!this.context) return;
    let json = JSON.stringify(this.suggestionState);
    preferences.getPreferences(this.context, Constants.PREFS_GEOFENCE_SUGGEST).then((store) => {
      return store.put(SUGGEST_PREFS_KEY, json).then(() => store.flush());
    }).catch((err: Error) => {
      this.log.warn(TAG, `Failed to save suggestion state: ${err.message}`);
    });
  }


  /**
   * 模拟情景智能完整 UI 提醒流程（含 cooldown 检查、notifyRecommendation、系统通知）
   * 用于调试：与 evaluateAndDeliver 走相同路径，但返回匹配结果供调用方检查。
   */
  async simulateContext(snapshot: ContextSnapshot): Promise<MatchResult[]> {
    await this.evaluateAndDeliver(snapshot);
    // 返回引擎匹配结果（evaluateAndDeliver 内部已处理推送）
    return this.engine.evaluate(snapshot, 3);
  }

  getStatus(): string {
    let stats = this.behaviorLog.getStats();
    return `Running: ${this.isRunning}, ` +
           `Geofences: ${this.geofenceMgr.getAllGeofences().length}, ` +
           `Records: ${stats.totalRecords}, ` +
           `Rules: ${stats.enabledRules}/${stats.totalRules}, ` +
           `AvgConf: ${(stats.avgConfidence * 100).toFixed(0)}%`;
  }

  /** 获取数据托盘状态（调试用） */
  getTrayStatus(): TrayStatus[] {
    return this.tray.getStatus();
  }
  
  isActive(): boolean {
    return this.isRunning;
  }

  /** Access digital world service for plugin status/control */
  getDigitalWorldService(): DigitalWorldService {
    return this.digitalWorld;
  }

  /** Get last collected digital plugin data (merged key-value pairs) */
  getLastDigitalData(): Record<string, string> {
    return this.lastDigitalData;
  }
}
