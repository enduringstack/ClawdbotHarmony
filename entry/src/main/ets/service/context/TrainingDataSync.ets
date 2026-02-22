/**
 * TrainingDataSync — 训练数据同步服务
 * 
 * 封装 C++ training_sync 模块
 * 负责网络上传（HarmonyOS HTTP API）
 */
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { http } from '@kit.NetworkKit';
import { LogService } from '../../common/LogService';
import { ContextSnapshot } from './ContextEngine';

const TAG = 'TrainingDataSync';

/** 同步统计 */
export interface SyncStatsInfo {
  pending: number;
  synced: number;
  lastSync: number;
  totalRecords: number;
}

/** 规则匹配数据 */
export interface RuleMatchRecord {
  ruleId: string;
  action: string;
  confidence: number;
  timeOfDay: string;
  hour: number;
  motionState: string;
  prevMotionState: string;
  prevActivityState: string;
  activityDuration: number;
  geofence: string;
  wifiSsid: string;
  batteryLevel: number;
  isCharging: boolean;
}

/** 用户反馈数据 */
export interface UserFeedbackRecord {
  ruleId: string;
  feedbackType: string;
  originalValue: string;
  adjustedValue: string;
  timeOfDay: string;
  hour: number;
  motionState: string;
  prevActivityState: string;
  activityDuration: number;
  geofence: string;
}

/** 状态转换数据 */
export interface StateTransitionRecord {
  prevState: string;
  newState: string;
  duration: number;
  timeOfDay: string;
  hour: number;
  geofence: string;
  wifiSsid: string;
}

/** 围栏特征数据 */
export interface GeofenceFeatureRecord {
  geofenceId: string;
  geofenceName: string;
  wifiSsid: string;
  timeOfDay: string;
  hour: number;
  duration: number;
}

/** 用户反馈记录 (兼容旧接口) */
export interface FeedbackData {
  ruleId: string;
  feedbackType: 'accept' | 'reject' | 'adjust' | 'dismiss';
  originalValue?: string;
  adjustedValue?: string;
  context: ContextSnapshot;
  timestamp: number;
}

/** 状态转换记录 (兼容旧接口) */
export interface StateTransitionData {
  prevState: string;
  newState: string;
  duration: number;
  context: ContextSnapshot;
  timestamp: number;
}

// C++ NAPI 接口
interface TrainingSyncNative {
  init(config: { deviceId: string }): void;
  recordRuleMatch(data: RuleMatchRecord): void;
  recordFeedback(data: UserFeedbackRecord): void;
  recordStateTransition(data: StateTransitionRecord): void;
  recordGeofenceFeature(data: GeofenceFeatureRecord): void;
  exportPending(): string;
  markSynced(ids: string[]): void;
  cleanupSynced(): void;
  getStats(): SyncStatsInfo;
  serialize(): string;
  deserialize(json: string): boolean;
  clear(): void;
  setMaxRecords(max: number): void;
  getDeviceId(): string;
}

export class TrainingDataSync {
  private static instance: TrainingDataSync;
  private log: LogService = LogService.getInstance();
  
  private context: common.UIAbilityContext | undefined;
  private native: TrainingSyncNative | undefined;
  private syncEndpoint: string = '';
  private syncEnabled: boolean = false;
  private prefs: preferences.Preferences | undefined;
  
  private static readonly SYNC_INTERVAL = 60 * 60 * 1000;
  private syncTimer: number = -1;
  
  private constructor() {}
  
  static getInstance(): TrainingDataSync {
    if (!TrainingDataSync.instance) {
      TrainingDataSync.instance = new TrainingDataSync();
    }
    return TrainingDataSync.instance;
  }
  
  async init(context: common.UIAbilityContext, endpoint: string): Promise<void> {
    this.context = context;
    this.syncEndpoint = endpoint;
    
    try {
      this.native = await import('../native/training_sync') as TrainingSyncNative;
      
      let deviceId = context.applicationInfo?.name || 'clawdbot_device';
      this.native.init({ deviceId: deviceId });
      
      this.prefs = await preferences.getPreferences(context, 'training_data_sync');
      this.syncEnabled = await this.prefs.get('sync_enabled', false) as boolean;
      
      let savedData = await this.prefs.get('data', '') as string;
      if (savedData.length > 0) {
        this.native.deserialize(savedData);
      }
      
      this.log.info(TAG, `Init: endpoint=${endpoint}, native=loaded, enabled=${this.syncEnabled}`);
    } catch (err) {
      this.log.error(TAG, `Init failed: ${(err as Error).message}`);
    }
  }
  
  setSyncEnabled(enabled: boolean): void {
    this.syncEnabled = enabled;
    
    if (this.prefs) {
      this.prefs.put('sync_enabled', enabled);
      this.prefs.flush();
    }
    
    if (enabled) {
      this.startSyncTimer();
    } else {
      this.stopSyncTimer();
    }
    
    this.log.info(TAG, `Sync ${enabled ? 'enabled' : 'disabled'}`);
  }
  
  private startSyncTimer(): void {
    if (this.syncTimer !== -1) return;
    
    this.syncTimer = setInterval(() => {
      this.sync();
    }, TrainingDataSync.SYNC_INTERVAL) as number;
  }
  
  private stopSyncTimer(): void {
    if (this.syncTimer !== -1) {
      clearInterval(this.syncTimer);
      this.syncTimer = -1;
    }
  }
  
  recordRuleMatch(snapshot: ContextSnapshot, ruleId: string, action: string, confidence: number): void {
    if (!this.native) return;
    
    let record: RuleMatchRecord = {
      ruleId: ruleId,
      action: action,
      confidence: confidence,
      timeOfDay: snapshot.timeOfDay,
      hour: snapshot.hour,
      motionState: snapshot.motionState,
      prevMotionState: snapshot.prevMotionState || '',
      prevActivityState: snapshot.prevActivityState || '',
      activityDuration: parseInt(snapshot.activityDuration || '0') || 0,
      geofence: snapshot.geofence || '',
      wifiSsid: snapshot.wifiSsid || '',
      batteryLevel: parseInt(snapshot.batteryLevel || '0') || 0,
      isCharging: snapshot.isCharging === 'true'
    };
    
    this.native.recordRuleMatch(record);
    this.persist();
  }
  
  recordFeedback(data: FeedbackData): void {
    if (!this.native) return;
    
    let record: UserFeedbackRecord = {
      ruleId: data.ruleId,
      feedbackType: data.feedbackType,
      originalValue: data.originalValue || '',
      adjustedValue: data.adjustedValue || '',
      timeOfDay: data.context.timeOfDay,
      hour: parseInt(data.context.hour || '0') || 0,
      motionState: data.context.motionState,
      prevActivityState: data.context.prevActivityState || '',
      activityDuration: parseInt(data.context.activityDuration || '0') || 0,
      geofence: data.context.geofence || ''
    };
    
    this.native.recordFeedback(record);
    this.persist();
  }
  
  recordStateTransition(data: StateTransitionData): void {
    if (!this.native) return;
    
    let record: StateTransitionRecord = {
      prevState: data.prevState,
      newState: data.newState,
      duration: data.duration,
      timeOfDay: data.context.timeOfDay,
      hour: parseInt(data.context.hour || '0') || 0,
      geofence: data.context.geofence || '',
      wifiSsid: data.context.wifiSsid || ''
    };
    
    this.native.recordStateTransition(record);
    this.persist();
  }
  
  recordGeofenceFeature(
    geofenceId: string,
    geofenceName: string,
    wifiSsid: string,
    timeOfDay: string,
    hour: number,
    duration: number
  ): void {
    if (!this.native) return;
    
    let record: GeofenceFeatureRecord = {
      geofenceId: geofenceId,
      geofenceName: geofenceName,
      wifiSsid: wifiSsid,
      timeOfDay: timeOfDay,
      hour: hour,
      duration: duration
    };
    
    this.native.recordGeofenceFeature(record);
    this.persist();
  }
  
  async sync(): Promise<boolean> {
    if (!this.syncEnabled || !this.syncEndpoint || !this.native) {
      this.log.debug(TAG, 'Sync skipped: disabled or no endpoint');
      return false;
    }
    
    let pendingJson = this.native.exportPending();
    let data = JSON.parse(pendingJson);
    
    if (!data.records || data.records.length === 0) {
      this.log.debug(TAG, 'No records to sync');
      return true;
    }
    
    this.log.info(TAG, `Syncing ${data.records.length} records to ${this.syncEndpoint}`);
    
    try {
      let request: http.HttpRequest = http.createHttp();
      let response = await request.request(this.syncEndpoint + '/training/upload', {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json'
        },
        extraData: pendingJson,
        connectTimeout: 30000,
        readTimeout: 30000
      });
      
      if (response.responseCode === 200 || response.responseCode === 201) {
        let ids: string[] = [];
        for (let i = 0; i < data.records.length; i++) {
          ids.push(data.records[i].id);
        }
        this.native.markSynced(ids);
        this.native.cleanupSynced();
        this.persist();
        
        this.log.info(TAG, `Sync successful: ${data.records.length} records`);
        return true;
      } else {
        this.log.error(TAG, `Sync failed: HTTP ${response.responseCode}`);
        return false;
      }
    } catch (err) {
      this.log.error(TAG, `Sync error: ${(err as Error).message}`);
      return false;
    }
  }
  
  getStats(): { pending: number; synced: number; lastSync: number } {
    if (!this.native) {
      return { pending: 0, synced: 0, lastSync: 0 };
    }
    let stats = this.native.getStats();
    return {
      pending: stats.pending,
      synced: stats.synced,
      lastSync: stats.lastSync
    };
  }
  
  exportData(): string {
    if (!this.native) return '{}';
    return this.native.serialize();
  }
  
  clear(): void {
    if (!this.native) return;
    this.native.clear();
    this.persist();
  }
  
  setMaxRecords(max: number): void {
    if (!this.native) return;
    this.native.setMaxRecords(max);
  }
  
  private persist(): void {
    if (this.native && this.prefs) {
      let data = this.native.serialize();
      this.prefs.put('data', data);
      this.prefs.flush();
    }
  }
}
