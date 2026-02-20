/**
 * ConfigManager - 统一配置管理
 *
 * 所有配置合并到一个文件：filesDir/clawdbot_config.json
 */
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';
import { LogService } from '../common/LogService';

const TAG = 'ConfigManager';
const CONFIG_FILENAME = 'clawdbot_config.json';

export interface IdentityConfig {
  name: string;
  theme: string;
  emoji: string;
  avatar: string;
  cachedAvatarPath: string;
}

export interface GatewayConfig {
  host: string;
  port: number;
  useTls: boolean;
  token: string;
  password: string;
  operatorEnabled: boolean;
  nodeEnabled: boolean;
}

export interface FeaturesConfig {
  conciseMode: boolean;
  ttsAutoRead: boolean;
  contextAwarenessEnabled: boolean;
}

export interface VoiceprintProfileConfig {
  name: string;
  samples: string[];
  createdAt: number;
  updatedAt: number;
}

export interface VoiceprintConfig {
  profiles: VoiceprintProfileConfig[];
}

export interface GeofenceConfig {
  id: string;
  name: string;
  latitude: number;
  longitude: number;
  radiusMeters: number;
  category: string;
}

export interface LocationPointConfig {
  latitude: number;
  longitude: number;
  timestamp: number;
  accuracy: number;
}

export interface ContextConfig {
  rules: string;
  mabStats: string;
  geofences: GeofenceConfig[];
  locationHistory: LocationPointConfig[];
  lastDiscovery: number;
}

export interface ChatConfig {
  theme: string;
  fontSize: number;
  showTimestamps: boolean;
}

export interface ClawdbotConfig {
  version: number;
  lastUpdated: number;
  displayName: string;
  identity: IdentityConfig;
  gateway: GatewayConfig;
  features: FeaturesConfig;
  voiceprint: VoiceprintConfig;
  context: ContextConfig;
  chat: ChatConfig;
}

function defaultIdentity(): IdentityConfig {
  let id: IdentityConfig = { name: '', theme: '', emoji: '', avatar: '', cachedAvatarPath: '' };
  return id;
}

function defaultGateway(): GatewayConfig {
  let gw: GatewayConfig = { host: '', port: 18789, useTls: false, token: '', password: '', operatorEnabled: true, nodeEnabled: true };
  return gw;
}

function defaultFeatures(): FeaturesConfig {
  let f: FeaturesConfig = { conciseMode: true, ttsAutoRead: false, contextAwarenessEnabled: false };
  return f;
}

function defaultVoiceprint(): VoiceprintConfig {
  let v: VoiceprintConfig = { profiles: [] };
  return v;
}

function defaultContext(): ContextConfig {
  let c: ContextConfig = { rules: '[]', mabStats: '{}', geofences: [], locationHistory: [], lastDiscovery: 0 };
  return c;
}

function defaultChat(): ChatConfig {
  let c: ChatConfig = { theme: 'auto', fontSize: 14, showTimestamps: true };
  return c;
}

function getDefaultConfig(): ClawdbotConfig {
  let cfg: ClawdbotConfig = {
    version: 1,
    lastUpdated: 0,
    displayName: '',
    identity: defaultIdentity(),
    gateway: defaultGateway(),
    features: defaultFeatures(),
    voiceprint: defaultVoiceprint(),
    context: defaultContext(),
    chat: defaultChat()
  };
  return cfg;
}

export class ConfigManager {
  private static instance: ConfigManager;
  private log: LogService = LogService.getInstance();
  private _context: common.UIAbilityContext | null = null;
  private config: ClawdbotConfig = getDefaultConfig();
  private dirty: boolean = false;
  private saveTimer: number = -1;
  private initialized: boolean = false;

  private constructor() {}

  static getInstance(): ConfigManager {
    if (!ConfigManager.instance) {
      ConfigManager.instance = new ConfigManager();
    }
    return ConfigManager.instance;
  }

  async init(context: common.UIAbilityContext): Promise<void> {
    if (this.initialized) return;
    this._context = context;
    await this.load();
    this.initialized = true;
    this.log.info(TAG, `Config loaded, version=${this.config.version}`);
  }

  getConfig(): ClawdbotConfig {
    return this.config;
  }

  // ==================== Identity ====================

  getIdentity(): IdentityConfig {
    return this.config.identity;
  }

  updateIdentity(name: string, theme: string, emoji: string, avatar: string, cachedAvatarPath: string): void {
    this.config.identity.name = name;
    this.config.identity.theme = theme;
    this.config.identity.emoji = emoji;
    this.config.identity.avatar = avatar;
    this.config.identity.cachedAvatarPath = cachedAvatarPath;
    this.markDirty();
  }

  updateCachedAvatarPath(path: string): void {
    this.config.identity.cachedAvatarPath = path;
    this.markDirty();
  }

  // ==================== DisplayName ====================

  getDisplayName(): string {
    return this.config.displayName;
  }

  setDisplayName(name: string): void {
    this.config.displayName = name;
    this.markDirty();
  }

  // ==================== Gateway ====================

  getGateway(): GatewayConfig {
    return this.config.gateway;
  }

  updateGateway(host: string, port: number, useTls: boolean, token: string, password: string, operatorEnabled: boolean, nodeEnabled: boolean): void {
    this.config.gateway.host = host;
    this.config.gateway.port = port;
    this.config.gateway.useTls = useTls;
    this.config.gateway.token = token;
    this.config.gateway.password = password;
    this.config.gateway.operatorEnabled = operatorEnabled;
    this.config.gateway.nodeEnabled = nodeEnabled;
    this.markDirty();
  }

  // ==================== Features ====================

  getFeatures(): FeaturesConfig {
    return this.config.features;
  }

  updateFeatures(conciseMode: boolean, ttsAutoRead: boolean, contextAwarenessEnabled: boolean): void {
    this.config.features.conciseMode = conciseMode;
    this.config.features.ttsAutoRead = ttsAutoRead;
    this.config.features.contextAwarenessEnabled = contextAwarenessEnabled;
    this.markDirty();
  }

  // ==================== Voiceprint ====================

  getVoiceprint(): VoiceprintConfig {
    return this.config.voiceprint;
  }

  setVoiceprintProfiles(profiles: VoiceprintProfileConfig[]): void {
    this.config.voiceprint.profiles = profiles;
    this.markDirty();
  }

  // ==================== Context ====================

  getContextConfig(): ContextConfig {
    return this.config.context;
  }

  setContextRules(rules: string): void {
    this.config.context.rules = rules;
    this.markDirty();
  }

  setContextMabStats(stats: string): void {
    this.config.context.mabStats = stats;
    this.markDirty();
  }

  setContextGeofences(geofences: GeofenceConfig[]): void {
    this.config.context.geofences = geofences;
    this.markDirty();
  }

  setContextLocationHistory(history: LocationPointConfig[]): void {
    this.config.context.locationHistory = history;
    this.markDirty();
  }

  setContextLastDiscovery(ts: number): void {
    this.config.context.lastDiscovery = ts;
    this.markDirty();
  }

  // ==================== Chat ====================

  getChat(): ChatConfig {
    return this.config.chat;
  }

  updateChat(theme: string, fontSize: number, showTimestamps: boolean): void {
    this.config.chat.theme = theme;
    this.config.chat.fontSize = fontSize;
    this.config.chat.showTimestamps = showTimestamps;
    this.markDirty();
  }

  // ==================== IO ====================

  private async load(): Promise<void> {
    if (!this._context) return;
    try {
      let path = `${this._context.filesDir}/${CONFIG_FILENAME}`;
      let file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
      let stat = fileIo.statSync(path);
      let buffer = new ArrayBuffer(stat.size);
      fileIo.readSync(file.fd, buffer);
      fileIo.closeSync(file);

      let decoder = util.TextDecoder.create('utf-8');
      let json = decoder.decodeToString(new Uint8Array(buffer));
      let loaded = JSON.parse(json) as ClawdbotConfig;

      // 合并：加载的值覆盖默认值，确保新字段有默认值
      let def = getDefaultConfig();
      this.config.version = loaded.version ?? def.version;
      this.config.lastUpdated = loaded.lastUpdated ?? def.lastUpdated;
      this.config.displayName = loaded.displayName ?? def.displayName;

      if (loaded.identity) {
        this.config.identity.name = loaded.identity.name ?? '';
        this.config.identity.theme = loaded.identity.theme ?? '';
        this.config.identity.emoji = loaded.identity.emoji ?? '';
        this.config.identity.avatar = loaded.identity.avatar ?? '';
        this.config.identity.cachedAvatarPath = loaded.identity.cachedAvatarPath ?? '';
      }
      if (loaded.gateway) {
        this.config.gateway.host = loaded.gateway.host ?? '';
        this.config.gateway.port = loaded.gateway.port ?? 18789;
        this.config.gateway.useTls = loaded.gateway.useTls ?? false;
        this.config.gateway.token = loaded.gateway.token ?? '';
        this.config.gateway.password = loaded.gateway.password ?? '';
        this.config.gateway.operatorEnabled = loaded.gateway.operatorEnabled ?? true;
        this.config.gateway.nodeEnabled = loaded.gateway.nodeEnabled ?? true;
      }
      if (loaded.features) {
        this.config.features.conciseMode = loaded.features.conciseMode ?? true;
        this.config.features.ttsAutoRead = loaded.features.ttsAutoRead ?? false;
        this.config.features.contextAwarenessEnabled = loaded.features.contextAwarenessEnabled ?? false;
      }
      if (loaded.voiceprint) {
        this.config.voiceprint.profiles = loaded.voiceprint.profiles ?? [];
      }
      if (loaded.context) {
        this.config.context.rules = loaded.context.rules ?? '[]';
        this.config.context.mabStats = loaded.context.mabStats ?? '{}';
        this.config.context.geofences = loaded.context.geofences ?? [];
        this.config.context.locationHistory = loaded.context.locationHistory ?? [];
        this.config.context.lastDiscovery = loaded.context.lastDiscovery ?? 0;
      }
      if (loaded.chat) {
        this.config.chat.theme = loaded.chat.theme ?? 'auto';
        this.config.chat.fontSize = loaded.chat.fontSize ?? 14;
        this.config.chat.showTimestamps = loaded.chat.showTimestamps ?? true;
      }

      this.log.info(TAG, `Loaded config from ${path}`);
    } catch (err) {
      this.log.info(TAG, 'No existing config, using defaults');
      this.config = getDefaultConfig();
    }
  }

  private markDirty(): void {
    this.dirty = true;
    this.config.lastUpdated = Date.now();
    if (this.saveTimer === -1) {
      this.saveTimer = setTimeout(() => {
        this.save();
        this.saveTimer = -1;
      }, 1000);
    }
  }

  async save(): Promise<void> {
    if (!this._context || !this.dirty) return;
    try {
      let path = `${this._context.filesDir}/${CONFIG_FILENAME}`;
      let json = JSON.stringify(this.config);
      let file = fileIo.openSync(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC | fileIo.OpenMode.WRITE_ONLY);
      fileIo.writeSync(file.fd, json);
      fileIo.closeSync(file);
      this.dirty = false;
      this.log.info(TAG, `Saved config (${json.length} bytes)`);
    } catch (err) {
      this.log.error(TAG, `Save failed: ${(err as Error).message}`);
    }
  }

  async flush(): Promise<void> {
    if (this.saveTimer !== -1) {
      clearTimeout(this.saveTimer);
      this.saveTimer = -1;
    }
    this.dirty = true;
    await this.save();
  }

  exportJson(): string {
    return JSON.stringify(this.config);
  }

  async importJson(json: string): Promise<boolean> {
    try {
      let imported = JSON.parse(json) as ClawdbotConfig;
      this.config = imported;
      this.dirty = true;
      await this.save();
      return true;
    } catch (err) {
      this.log.error(TAG, `Import failed: ${(err as Error).message}`);
      return false;
    }
  }
}
