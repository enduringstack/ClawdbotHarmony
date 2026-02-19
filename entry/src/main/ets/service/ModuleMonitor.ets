/**
 * Module resource monitoring service
 * Tracks activity, uptime, call counts, and last activity time for core modules
 */

export interface ModuleStat {
  name: string;
  isActive: boolean;
  cumulativeRuntimeMs: number;
  callCount: number;
  lastActiveTime: number; // timestamp
}

interface ModuleState {
  isActive: boolean;
  startTime: number;
  cumulativeRuntimeMs: number;
  callCount: number;
  lastActiveTime: number;
}

export class ModuleMonitor {
  private static instance: ModuleMonitor | undefined = undefined;

  // Core modules to monitor
  private modules: Map<string, ModuleState> = new Map();

  static getInstance(): ModuleMonitor {
    if (!ModuleMonitor.instance) {
      ModuleMonitor.instance = new ModuleMonitor();
    }
    return ModuleMonitor.instance;
  }

  constructor() {
    this.initializeModules();
  }

  private initializeModules(): void {
    let coreModules = [
      'Gateway',           // WebSocket连接
      'SilentMode',       // 语音监听/VAD  
      'Speaker',          // TTS播放
      'Camera',           // 相机功能
      'Location',         // 定位功能
      'BackgroundTask',   // 后台保活
      'ContextAwareness'  // 情景智能
    ];

    for (let moduleName of coreModules) {
      this.modules.set(moduleName, {
        isActive: false,
        startTime: 0,
        cumulativeRuntimeMs: 0,
        callCount: 0,
        lastActiveTime: 0
      });
    }
  }

  /**
   * Start module activity tracking
   */
  startModule(moduleName: string): void {
    let now = Date.now();
    let state = this.modules.get(moduleName);
    
    if (!state) {
      // Create new module if not exists
      this.modules.set(moduleName, {
        isActive: true,
        startTime: now,
        cumulativeRuntimeMs: 0,
        callCount: 1,
        lastActiveTime: now
      });
      return;
    }

    if (!state.isActive) {
      // Start inactive module
      state.isActive = true;
      state.startTime = now;
      state.lastActiveTime = now;
    }
    
    state.callCount++;
  }

  /**
   * Stop module activity tracking
   */
  stopModule(moduleName: string): void {
    let now = Date.now();
    let state = this.modules.get(moduleName);
    
    if (state && state.isActive) {
      // Add current session runtime
      state.cumulativeRuntimeMs += (now - state.startTime);
      state.isActive = false;
      state.startTime = 0;
      state.lastActiveTime = now;
    }
  }

  /**
   * Record module activity (for one-time operations)
   */
  recordActivity(moduleName: string): void {
    let now = Date.now();
    let state = this.modules.get(moduleName);
    
    if (!state) {
      // Create new module if not exists
      this.modules.set(moduleName, {
        isActive: false,
        startTime: 0,
        cumulativeRuntimeMs: 0,
        callCount: 1,
        lastActiveTime: now
      });
      return;
    }

    state.callCount++;
    state.lastActiveTime = now;
  }

  /**
   * Get statistics for all modules
   */
  getModuleStats(): ModuleStat[] {
    let now = Date.now();
    let stats: ModuleStat[] = [];
    
    let entries = Array.from(this.modules.entries());
    for (let i = 0; i < entries.length; i++) {
      let name = entries[i][0];
      let state = entries[i][1];
      let currentRuntime = state.cumulativeRuntimeMs;
      
      // Add current session runtime if active
      if (state.isActive && state.startTime > 0) {
        currentRuntime += (now - state.startTime);
      }
      
      stats.push({
        name: name,
        isActive: state.isActive,
        cumulativeRuntimeMs: currentRuntime,
        callCount: state.callCount,
        lastActiveTime: state.lastActiveTime
      });
    }
    
    // Sort by name for consistent display
    return stats.sort((a, b) => a.name.localeCompare(b.name));
  }

  /**
   * Get runtime formatted as human-readable string
   */
  formatRuntime(runtimeMs: number): string {
    if (runtimeMs < 1000) {
      return `${runtimeMs}ms`;
    }
    
    let seconds = Math.floor(runtimeMs / 1000);
    if (seconds < 60) {
      return `${seconds}s`;
    }
    
    let minutes = Math.floor(seconds / 60);
    let remainingSeconds = seconds % 60;
    if (minutes < 60) {
      return `${minutes}m ${remainingSeconds}s`;
    }
    
    let hours = Math.floor(minutes / 60);
    let remainingMinutes = minutes % 60;
    return `${hours}h ${remainingMinutes}m`;
  }

  /**
   * Get last active time formatted as human-readable string
   */
  formatLastActive(timestamp: number): string {
    if (timestamp === 0) {
      return 'Never';
    }
    
    let now = Date.now();
    let diffMs = now - timestamp;
    
    if (diffMs < 60000) { // < 1 minute
      return 'Just now';
    }
    
    let minutes = Math.floor(diffMs / 60000);
    if (minutes < 60) {
      return `${minutes}m ago`;
    }
    
    let hours = Math.floor(minutes / 60);
    if (hours < 24) {
      return `${hours}h ago`;
    }
    
    let days = Math.floor(hours / 24);
    return `${days}d ago`;
  }

  /**
   * Reset all statistics (for debugging/testing)
   */
  reset(): void {
    for (let state of this.modules.values()) {
      state.isActive = false;
      state.startTime = 0;
      state.cumulativeRuntimeMs = 0;
      state.callCount = 0;
      state.lastActiveTime = 0;
    }
  }
}

/** Convenience shortcut */
export const Monitor = ModuleMonitor.getInstance();