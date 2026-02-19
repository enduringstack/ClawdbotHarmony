/**
 * In-memory log service for runtime debugging.
 * Stores log entries that can be viewed in the LogPage.
 * Also outputs to console.info/warn/error for HiLog capture.
 *
 * Three-tier logging system:
 * - SYSTEM: Always recorded (connection/crash/critical errors)
 * - INFO: Always recorded (message flow/operations)
 * - DEBUG: Only when debugEnabled (detailed protocol/VAD frames/large objects)
 */

import { preferences } from '@kit.ArkData';
import { Context } from '@kit.AbilityKit';

export class LogEntry {
  timestamp: number = 0;
  level: string = 'INFO';
  tag: string = '';
  message: string = '';

  constructor(level: string, tag: string, message: string) {
    this.timestamp = Date.now();
    this.level = level;
    this.tag = tag;
    this.message = message;
  }

  format(): string {
    let d = new Date(this.timestamp);
    let h = d.getHours().toString().padStart(2, '0');
    let m = d.getMinutes().toString().padStart(2, '0');
    let s = d.getSeconds().toString().padStart(2, '0');
    let ms = d.getMilliseconds().toString().padStart(3, '0');
    return `${h}:${m}:${s}.${ms} [${this.level}] ${this.tag}: ${this.message}`;
  }

  /** Get level color for UI display */
  getLevelColor(): string {
    switch (this.level) {
      case 'SYSTEM': return '#FF6B6B';
      case 'ERROR': return '#FF6B6B';
      case 'WARN': return '#FFB347';
      case 'INFO': return '#4ECDC4';
      case 'DEBUG': return '#95A5A6';
      default: return '#95A5A6';
    }
  }
}

const MAX_LOG_ENTRIES = 500;
const PREFS_NAME = 'clawdbot_settings';
const KEY_DEBUG = 'log_debug_enabled';

export class LogService {
  private static instance: LogService | undefined = undefined;
  private entries: LogEntry[] = [];
  private listeners: Array<() => void> = [];
  private _enabled: boolean = false;
  private _debugEnabled: boolean = false;
  private _context: Context | undefined = undefined;

  static getInstance(): LogService {
    if (!LogService.instance) {
      LogService.instance = new LogService();
    }
    return LogService.instance;
  }

  /** Call once with app context to enable preferences persistence */
  initContext(context: Context): void {
    this._context = context;
    this.loadPreferences();
  }

  /** Whether log recording is enabled (legacy, controls WARN level) */
  get enabled(): boolean {
    return this._enabled;
  }

  set enabled(val: boolean) {
    this._enabled = val;
  }

  /** Whether debug logging is enabled */
  get debugEnabled(): boolean {
    return this._debugEnabled;
  }

  set debugEnabled(val: boolean) {
    this._debugEnabled = val;
    this.saveDebugPreference();
  }

  /**
   * SYSTEM level — Always recorded for stability monitoring.
   * Connection state, crashes, permission failures, background task failures.
   */
  system(tag: string, message: string): void {
    this.addAlways('SYSTEM', tag, message);
    console.error(`[SYSTEM][${tag}] ${message}`);
  }

  /**
   * INFO level — Always recorded for operational logging.
   * Message flow, capability calls, user operations.
   */
  info(tag: string, message: string): void {
    this.addAlways('INFO', tag, message);
    console.info(`[${tag}] ${message}`);
  }

  warn(tag: string, message: string): void {
    this.addAlways('WARN', tag, message);
    console.warn(`[${tag}] ${message}`);
  }

  error(tag: string, message: string): void {
    this.addAlways('ERROR', tag, message);
    console.error(`[${tag}] ${message}`);
  }

  /**
   * DEBUG level — Only recorded when debugEnabled is true.
   * Protocol details, VAD frames, large JSON objects, high-frequency logs.
   */
  debug(tag: string, message: string): void {
    if (!this._debugEnabled) {
      return;
    }
    this.addAlways('DEBUG', tag, message);
    console.debug(`[${tag}] ${message}`);
  }

  getAll(): LogEntry[] {
    return this.entries.slice();
  }

  getFiltered(level?: string, tag?: string): LogEntry[] {
    let result = this.entries;
    if (level && level !== 'ALL') {
      result = result.filter((e): boolean => e.level === level);
    }
    if (tag && tag.length > 0) {
      result = result.filter((e): boolean => e.tag.indexOf(tag) >= 0);
    }
    return result;
  }

  clear(): void {
    this.entries = [];
    this.notifyListeners();
  }

  addListener(fn: () => void): void {
    this.listeners.push(fn);
  }

  removeListener(fn: () => void): void {
    let idx = this.listeners.indexOf(fn);
    if (idx >= 0) {
      this.listeners.splice(idx, 1);
    }
  }

  get count(): number {
    return this.entries.length;
  }

  private loadPreferences(): void {
    if (!this._context) {
      return;
    }
    try {
      let store = preferences.getPreferencesSync(this._context, { name: PREFS_NAME });
      let val = store.getSync(KEY_DEBUG, false);
      this._debugEnabled = val as boolean;
    } catch (_e) {
      this._debugEnabled = false;
    }
  }

  private saveDebugPreference(): void {
    if (!this._context) {
      return;
    }
    try {
      let store = preferences.getPreferencesSync(this._context, { name: PREFS_NAME });
      store.putSync(KEY_DEBUG, this._debugEnabled);
      store.flush();
    } catch (_e) {
      // ignore
    }
  }

  private addAlways(level: string, tag: string, message: string): void {
    let entry = new LogEntry(level, tag, message);
    this.entries.push(entry);
    if (this.entries.length > MAX_LOG_ENTRIES) {
      this.entries = this.entries.slice(this.entries.length - MAX_LOG_ENTRIES);
    }
    this.notifyListeners();
  }

  private notifyListeners(): void {
    for (let listener of this.listeners) {
      try { listener(); } catch { /* ignore */ }
    }
  }
}

/** Convenience shortcut */
export const Log = LogService.getInstance();
