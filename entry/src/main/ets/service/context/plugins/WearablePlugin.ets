/**
 * WearablePlugin — Collect wearable device sensor data
 *
 * Uses HarmonyOS sensor API to read heart rate data.
 * On Huawei devices with Huawei Health app, heart rate data from
 * connected wearables (watch/band) is synced and available via sensor API.
 *
 * Reads heart rate sensor data to detect physiological state:
 * - Resting (< 80 bpm)
 * - Active (80-120 bpm)
 * - Exercise (> 120 bpm)
 * - Stressed (elevated but not exercising)
 *
 * Combined with StepCounterPlugin data, provides rich activity context.
 *
 * Provides: heart_rate, heart_rate_status, wearing_state, device_connected
 *
 * Permission: ohos.permission.READ_HEALTH_DATA
 * API: @kit.SensorServiceKit — sensor.SensorId.HEART_RATE
 */
import { sensor } from '@kit.SensorServiceKit';
import { common, abilityAccessCtrl } from '@kit.AbilityKit';
import { LogService } from '../../../common/LogService';
import { DigitalPlugin, DigitalSnapshot } from './DigitalPluginInterface';

const TAG = 'WearablePlugin';

export class WearablePlugin implements DigitalPlugin {
  name: string = 'wearable';
  private log: LogService = LogService.getInstance();
  private heartRate: number = 0;
  private lastHeartRateTime: number = 0;
  private heartRateSensorRegistered: boolean = false;
  private wearableDeviceConnected: boolean = false;
  private deviceName: string = '';
  private initError: string = '';
  private context: common.UIAbilityContext | undefined;

  async init(context: common.UIAbilityContext): Promise<void> {
    this.context = context;
    this.log.info(TAG, 'Init: requesting health data permission...');
    
    // 先请求权限
    let granted = await this.requestHealthPermission();
    if (granted) {
      this.subscribeHeartRate();
    } else {
      this.initError = 'Health data permission denied';
      this.log.warn(TAG, 'Health data permission not granted');
    }
    
    this.log.info(TAG, `Init complete: sensorRegistered=${this.heartRateSensorRegistered}`);
  }

  getSnapshot(): DigitalSnapshot {
    let status = this.getHeartRateStatus();
    let wearing = this.isWearing();

    let data: Record<string, string> = {
      'heart_rate': this.heartRate.toString(),
      'heart_rate_status': status,
      'wearing_state': wearing ? 'on_wrist' : 'off_wrist',
      'heart_rate_age_sec': this.getHeartRateAgeSec().toString(),
      'device_connected': this.wearableDeviceConnected ? 'true' : 'false',
      'device_name': this.deviceName,
      'sensor_registered': this.heartRateSensorRegistered ? 'true' : 'false',
      'init_error': this.initError
    };

    return {
      pluginName: this.name,
      timestamp: Date.now(),
      data: data
    };
  }

  destroy(): void {
    this.unsubscribeAll();
    this.log.info(TAG, 'Destroyed');
  }

  private getHeartRateStatus(): string {
    if (this.heartRate <= 0) {
      return 'unknown';
    }
    if (this.heartRate < 60) {
      return 'low';
    }
    if (this.heartRate < 80) {
      return 'resting';
    }
    if (this.heartRate < 120) {
      return 'active';
    }
    return 'exercise';
  }

  private isWearing(): boolean {
    if (this.heartRate <= 0) {
      return false;
    }
    let ageSec = this.getHeartRateAgeSec();
    return ageSec < 120;
  }

  private getHeartRateAgeSec(): number {
    if (this.lastHeartRateTime <= 0) {
      return 9999;
    }
    return Math.floor((Date.now() - this.lastHeartRateTime) / 1000);
  }

  private async requestHealthPermission(): Promise<boolean> {
    if (!this.context) {
      this.log.warn(TAG, 'No context available for permission request');
      return false;
    }
    
    try {
      let atManager = abilityAccessCtrl.createAtManager();
      let result = await atManager.requestPermissionsFromUser(this.context, ['ohos.permission.READ_HEALTH_DATA']);
      let granted = result.authResults[0] === 0;
      this.log.info(TAG, `READ_HEALTH_DATA permission: ${granted ? 'granted' : 'denied'}`);
      return granted;
    } catch (err) {
      this.log.error(TAG, `Permission request error: ${(err as Error).message}`);
      return false;
    }
  }

  private subscribeHeartRate(): void {
    try {
      sensor.on(sensor.SensorId.HEART_RATE, (data: sensor.HeartRateResponse) => {
        if (data && data.heartRate > 0) {
          this.heartRate = data.heartRate;
          this.lastHeartRateTime = Date.now();
          if (!this.wearableDeviceConnected) {
            this.wearableDeviceConnected = true;
            this.deviceName = 'watch_or_band';
            this.log.info(TAG, `Heart rate received: ${this.heartRate} bpm, wearable detected`);
          }
        }
      }, { interval: 10000000000 });
      this.heartRateSensorRegistered = true;
      this.log.info(TAG, 'Heart rate sensor subscribed successfully');
    } catch (err) {
      let errMsg = (err as Error).message;
      this.log.warn(TAG, `Heart rate sensor subscription failed: ${errMsg}`);
      this.initError = errMsg;
      this.heartRateSensorRegistered = false;
    }
  }

  private unsubscribeAll(): void {
    if (this.heartRateSensorRegistered) {
      try {
        sensor.off(sensor.SensorId.HEART_RATE);
        this.heartRateSensorRegistered = false;
      } catch {
        // ignore
      }
    }
  }
}
