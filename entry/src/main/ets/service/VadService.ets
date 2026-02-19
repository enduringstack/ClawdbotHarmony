// VadService: Silero VAD-based voice activity detection
// Falls back to RMS if model not available, downloads/inits in background

import { Vad, VadConfig, SileroVadConfig, TenVadConfig } from 'sherpa_onnx';
import { common } from '@kit.AbilityKit';
import { LogService } from '../common/LogService';
import { fileIo } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';

const TAG = '[VadService]';
const VAD_MODEL = 'vad/silero_vad.onnx';
const VAD_MODEL_URL = 'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx';

export class VadService {
  private static instance: VadService | null = null;
  private log: LogService = LogService.getInstance();
  private vad: Vad | null = null;
  private initialized: boolean = false;
  private initFailed: boolean = false;
  private bgInitInProgress: boolean = false;

  private constructor() {}

  static getInstance(): VadService {
    if (!VadService.instance) {
      VadService.instance = new VadService();
    }
    return VadService.instance;
  }

  /**
   * Initialize VAD synchronously if model is already available in rawfile.
   * Returns true if ready immediately.
   */
  async init(context: common.UIAbilityContext): Promise<boolean> {
    if (this.initialized) return true;
    if (this.initFailed) return false;

    // Check rawfile first
    let hasRawfile = false;
    try {
      context.resourceManager.getRawFileContentSync(VAD_MODEL);
      hasRawfile = true;
    } catch { /* not in rawfile */ }

    if (hasRawfile) {
      return this.createVad(context);
    }

    // Check sandbox cache
    let sandboxPath = context.filesDir + '/vad/silero_vad.onnx';
    try {
      fileIo.statSync(sandboxPath);
      return this.createVadFromPath(sandboxPath, context);
    } catch { /* not cached */ }

    return false;
  }

  /**
   * Start background download + init. Non-blocking.
   * Call this early, then check isInitialized() later.
   */
  backgroundInit(context: common.UIAbilityContext): void {
    if (this.initialized || this.initFailed || this.bgInitInProgress) return;
    this.bgInitInProgress = true;
    this.log.info(TAG, 'Starting background VAD model download...');

    this.downloadAndInit(context).then((ok) => {
      this.bgInitInProgress = false;
      if (ok) {
        this.log.info(TAG, '✅ VAD ready (background init complete)');
      } else {
        this.log.warn(TAG, 'Background VAD init did not succeed');
      }
    }).catch((e: Error) => {
      this.bgInitInProgress = false;
      this.log.error(TAG, `Background VAD init error: ${e.message ?? ''}`);
    });
  }

  private async downloadAndInit(context: common.UIAbilityContext): Promise<boolean> {
    let vadDir = context.filesDir + '/vad';
    try { fileIo.mkdirSync(vadDir); } catch { /* exists */ }
    let destPath = vadDir + '/silero_vad.onnx';

    // Already downloaded?
    try {
      let stat = fileIo.statSync(destPath);
      if (stat.size > 100000) {
        this.log.info(TAG, `Model already cached (${stat.size} bytes), initializing...`);
        return this.createVadFromPath(destPath, context);
      }
    } catch { /* not cached */ }

    // Download
    this.log.info(TAG, `Downloading VAD model from ${VAD_MODEL_URL}...`);
    try {
      let httpRequest = http.createHttp();
      let response = await httpRequest.request(VAD_MODEL_URL, {
        method: http.RequestMethod.GET,
        connectTimeout: 15000,
        readTimeout: 60000,
        expectDataType: http.HttpDataType.ARRAY_BUFFER
      });
      httpRequest.destroy();

      if (response.responseCode === 200 && response.result instanceof ArrayBuffer) {
        let data = response.result as ArrayBuffer;
        this.log.info(TAG, `Downloaded ${data.byteLength} bytes`);

        let file = fileIo.openSync(destPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
        fileIo.writeSync(file.fd, data);
        fileIo.closeSync(file);

        this.log.info(TAG, 'Model saved, initializing VAD...');
        return this.createVadFromPath(destPath, context);
      } else {
        this.log.error(TAG, `Download failed: HTTP ${response.responseCode}`);
        return false;
      }
    } catch (e) {
      this.log.error(TAG, `Download error: ${(e as Error).message ?? ''}`);
      return false;
    }
  }

  /** Create VAD from rawfile model */
  private createVad(context: common.UIAbilityContext): boolean {
    try {
      const sileroConfig = new SileroVadConfig(
        VAD_MODEL, 0.5, 0.25, 0.5, 512, 20
      );
      const tenConfig = new TenVadConfig('', 0, 0, 0, 0, 0);
      const vadConfig = new VadConfig(sileroConfig, tenConfig, 16000, false, 2);

      this.vad = new Vad(vadConfig, 30, context.resourceManager);
      this.initialized = true;
      this.log.info(TAG, 'VAD initialized from rawfile');
      return true;
    } catch (e) {
      this.log.error(TAG, `VAD create failed (rawfile): ${(e as Error).message ?? ''}`);
      this.initFailed = true;
      return false;
    }
  }

  /** Create VAD from sandbox file path */
  private createVadFromPath(modelPath: string, context: common.UIAbilityContext): boolean {
    try {
      const sileroConfig = new SileroVadConfig(
        modelPath, 0.5, 0.25, 0.5, 512, 20
      );
      const tenConfig = new TenVadConfig('', 0, 0, 0, 0, 0);
      const vadConfig = new VadConfig(sileroConfig, tenConfig, 16000, false, 2);

      this.vad = new Vad(vadConfig, 30, context.resourceManager);
      this.initialized = true;
      this.log.info(TAG, `VAD initialized from sandbox: ${modelPath}`);
      return true;
    } catch (e) {
      this.log.error(TAG, `VAD create failed (sandbox): ${(e as Error).message ?? ''}`);
      this.initFailed = true;
      return false;
    }
  }

  /**
   * Release VAD model and free memory.
   * Call when Talk Mode exits to reduce heat/battery usage.
   */
  release(): void {
    if (this.vad) {
      try {
        this.vad.reset();
        this.vad.clear();
      } catch { /* ignore */ }
      this.vad = null;
      this.initialized = false;
      this.initFailed = false;
      this.log.info(TAG, 'VAD released');
    }
  }

  isInitialized(): boolean {
    return this.initialized;
  }

  isBackgroundLoading(): boolean {
    return this.bgInitInProgress;
  }

  acceptWaveform(samples: Float32Array): void {
    if (!this.vad) return;
    this.vad.acceptWaveform(samples);
  }

  isDetected(): boolean {
    return this.vad?.isDetected() ?? false;
  }

  isEmpty(): boolean {
    return this.vad?.isEmpty() ?? true;
  }

  reset(): void {
    this.vad?.reset();
  }

  clear(): void {
    this.vad?.clear();
  }

  flush(): void {
    this.vad?.flush();
  }

  static pcmToFloat32(pcmBuffer: ArrayBuffer): Float32Array {
    const int16 = new Int16Array(pcmBuffer);
    const float32 = new Float32Array(int16.length);
    for (let i = 0; i < int16.length; i++) {
      float32[i] = int16[i] / 32768.0;
    }
    return float32;
  }

  static pcmBuffersToFloat32(pcmBuffers: ArrayBuffer[]): Float32Array {
    let totalSamples = 0;
    for (const buf of pcmBuffers) {
      totalSamples += buf.byteLength / 2;
    }
    const float32 = new Float32Array(totalSamples);
    let offset = 0;
    for (const buf of pcmBuffers) {
      const int16 = new Int16Array(buf);
      for (let i = 0; i < int16.length; i++) {
        float32[offset++] = int16[i] / 32768.0;
      }
    }
    return float32;
  }
}
