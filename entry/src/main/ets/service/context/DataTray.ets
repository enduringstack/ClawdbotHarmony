/**
 * DataTray.ets — ArkTS wrapper for native data_tray C++ NAPI module
 *
 * 传感器数据托盘 - 高性能 C++ 实现
 */

import dataTrayNative from 'libdata_tray.so';
import { ContextSnapshot } from './ContextEngine';

/** 托盘槽位 */
export interface TraySlot {
  key: string;
  value: string;
  updatedAt: number;
  ttlMs: number;
  quality: number;
  source: string;
}

/** 读取结果 */
export interface TrayReadResult {
  value: string | null;
  quality: number;
  fresh: boolean;
  ageMs: number;
}

/** 调试状态 */
export interface TrayStatus {
  key: string;
  value: string;
  ageMs: number;
  ttlMs: number;
  fresh: boolean;
  effectiveQuality: number;
  source: string;
}

// 复用 ContextEngine 的 ContextSnapshot 类型
export { ContextSnapshot } from './ContextEngine';

/**
 * 数据托盘 - 单例模式
 * 直接调用 C++ 实现，无额外缓存
 */
export class DataTray {
  private static instance: DataTray | null = null;

  static getInstance(): DataTray {
    if (!DataTray.instance) {
      DataTray.instance = new DataTray();
    }
    return DataTray.instance;
  }

  /**
   * 写入数据
   */
  put(key: string, value: string, quality: number = 1.0, source: string = ''): void {
    dataTrayNative.put(key, value, quality, source.length > 0 ? source : key);
  }

  /**
   * 读取数据（含 TTL 衰减）
   */
  get(key: string): TrayReadResult {
    return dataTrayNative.get(key) as TrayReadResult;
  }

  /**
   * 获取上下文快照
   */
  getSnapshot(): ContextSnapshot {
    return dataTrayNative.getSnapshot() as ContextSnapshot;
  }

  /**
   * 设置 TTL
   */
  setTTL(key: string, ttlMs: number): void {
    dataTrayNative.setTTL(key, ttlMs);
  }

  /**
   * 获取调试状态
   */
  getStatus(): TrayStatus[] {
    return dataTrayNative.getStatus() as TrayStatus[];
  }

  /**
   * 清除所有数据
   */
  clear(): void {
    dataTrayNative.clear();
  }

  /**
   * 获取槽位数量
   */
  size(): number {
    return dataTrayNative.size() as number;
  }
}

// 默认导出单例
export default DataTray.getInstance();
