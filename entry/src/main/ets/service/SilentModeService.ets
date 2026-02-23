// Silent mode service: continuous background recording with VAD, speaker identification, and ASR
import { audio } from '@kit.AudioKit';
import { abilityAccessCtrl, common, wantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { preferences } from '@kit.ArkData';
import { fileIo } from '@kit.CoreFileKit';
import { util, buffer } from '@kit.ArkTS';
import { SilentConversationRecord, SilentConversationEntry, SilentConversationEntryEx, SettingsData, ActionItem } from '../model/Models';
import { CalendarCapability } from './gateway/CalendarCapability';
import { NodeRuntime } from './gateway/NodeRuntime';
import { GatewayChatEvent, ChatAttachment } from './gateway/GatewayModels';
import { Constants } from '../common/Constants';
import { LogService } from '../common/LogService';
import { VoiceprintService } from './VoiceprintService';
import { LocalAsrService } from './LocalAsrService';
import { AIService } from './AIService';
import { ConversationStore } from './ConversationStore';
import { VadService } from './VadService';
import { Monitor } from './ModuleMonitor';
import { SilentModeExtractor } from './SilentModeExtractor';
import { EmotionAnalyzer } from './EmotionAnalyzer';

type StateListener = (state: string) => void;

export class SilentModeService {
  private static instance: SilentModeService;
  private log: LogService = LogService.getInstance();
  private readonly TAG = 'SilentMode';

  // State: 'idle' | 'monitoring' | 'listening' | 'processing'
  private state: string = 'idle';
  private stateListeners: StateListener[] = [];

  // Three-tier power-saving state machine
  private frameSkipCounter: number = 0;
  private monitoringMode: boolean = true;         // Start in low-power monitoring
  private consecutiveEnergyFrames: number = 0;    // Consecutive high-energy frames
  private silentFrameCount: number = 0;           // Frames without speech in listening mode

  // Frame skip parameters
  private static readonly MONITOR_CHECK_INTERVAL = 4;       // Check RMS every 4 frames in monitoring mode
  private static readonly ENERGY_WAKEUP_THRESHOLD = 80;     // RMS threshold to wake up VAD (higher than VAD gate of 50)
  private static readonly ENERGY_WAKEUP_FRAMES = 2;         // Consecutive high-energy frames needed to wake up
  private static readonly SILENCE_RETURN_FRAMES = 500;      // ~30s silence returns to monitoring (~60ms/frame)

  // Audio capture
  private audioCapturer: audio.AudioCapturer | undefined;
  private reading: boolean = false;
  private stopping: boolean = false;  // Guard against start-during-stop race

  // Current recording
  private currentRecord: SilentConversationRecord | undefined;
  private unknownSpeakerCount: number = 0;  // Counter for unknown speakers
  private segmentBuffers: ArrayBuffer[] = [];
  private segmentStartTime: number = 0;
  private speechDetected: boolean = false;
  private silenceStartMs: number = 0;
  private lastSpeechMs: number = 0;

  // Ring buffer: keep max 5 minutes of audio (16kHz * 2 bytes * 300s = ~9.6MB)
  private static readonly MAX_RING_BYTES = 16000 * 2 * 300;
  private totalBufferBytes: number = 0;

  // Processing queue: serialize segment processing to avoid concurrent ASR on shared engine
  private processingQueue: ArrayBuffer[][] = [];
  private isProcessing: boolean = false;

  // Audio segment file paths for audio summary
  private audioSegmentPaths: string[] = [];

  // Smart conversation splitting: combine speech duration + speaker gap
  private cumulativeSpeechMs: number = 0;            // total speech time in current conversation
  private lastSegmentEndMs: number = 0;              // when last speech segment ended
  private lastSegmentSpeaker: string = '';            // speaker of last completed segment
  private static readonly SPLIT_MIN_SPEECH_MS = 180000;    // 3 min cumulative speech before considering split
  private static readonly SPLIT_SPEAKER_GAP_MS = 10000;    // 10s silence between speakers triggers split
  private static readonly SPLIT_HARD_CAP_MS = 600000;      // 10 min hard cap regardless

  // Context
  private context: common.UIAbilityContext | undefined;

  private constructor() {}

  static getInstance(): SilentModeService {
    if (!SilentModeService.instance) {
      SilentModeService.instance = new SilentModeService();
    }
    return SilentModeService.instance;
  }

  getState(): string {
    return this.state;
  }

  isActive(): boolean {
    return this.state !== 'idle';
  }

  addStateListener(listener: StateListener): void {
    this.stateListeners.push(listener);
  }

  removeStateListener(listener: StateListener): void {
    let idx = this.stateListeners.indexOf(listener);
    if (idx >= 0) this.stateListeners.splice(idx, 1);
  }

  private setState(newState: string): void {
    this.state = newState;
    for (let listener of this.stateListeners) {
      try { listener(newState); } catch { /* ignore */ }
    }
  }

  async start(context: common.UIAbilityContext): Promise<boolean> {
    if (this.state !== 'idle' || this.stopping) return false;

    this.context = context;

    // Request mic permission
    try {
      let atManager = abilityAccessCtrl.createAtManager();
      let permResult = await atManager.requestPermissionsFromUser(context, ['ohos.permission.MICROPHONE']);
      if (permResult.authResults[0] !== 0) {
        this.log.system(this.TAG, 'Mic permission denied');
        return false;
      }
    } catch (err) {
      this.log.error(this.TAG, `Permission error: ${(err as Error).message ?? ''}`);
      return false;
    }

    // Init store
    await ConversationStore.getInstance().init(context);

    // Init VoiceprintService
    try {
      await VoiceprintService.getInstance().init(context);
      // Log registered speakers
      let speakers = VoiceprintService.getInstance().listSpeakers();
      let names = speakers.map(s => s.name).join(', ');
      this.log.info(this.TAG, `VoiceprintService ready. Registered speakers: [${names}] (${speakers.length} total)`);
    } catch (err) {
      this.log.warn(this.TAG, `VoiceprintService init warning: ${err}`);
    }

    // Initialize Silero VAD
    let vadInitialized = await VadService.getInstance().init(context);
    if (!vadInitialized) {
      this.log.warn(this.TAG, 'Silero VAD init failed, will use RMS fallback');
    } else {
      this.log.info(this.TAG, 'Silero VAD initialized for speech detection');
    }

    // Create conversation record
    let recordId = `silent_${Date.now()}_${Math.floor(Math.random() * 100000)}`;
    this.unknownSpeakerCount = 0;  // Reset counter for new recording
    this.currentRecord = {
      id: recordId,
      startTime: Date.now(),
      endTime: 0,
      entries: [],
      summary: '',
      title: '',
      status: 'recording',
      participants: [],
      speakerAliases: {}
    };

    // Save initial record
    await ConversationStore.getInstance().saveRecord(this.currentRecord);

    // Start background task FIRST to keep running when app goes to background
    await this.startBackgroundTask(context);

    // Create audio capturer (same config as ChatPage)
    try {
      let capturerOptions: audio.AudioCapturerOptions = {
        streamInfo: {
          samplingRate: audio.AudioSamplingRate.SAMPLE_RATE_16000,
          channels: audio.AudioChannel.CHANNEL_1,
          sampleFormat: audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE,
          encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW
        },
        capturerInfo: {
          source: audio.SourceType.SOURCE_TYPE_MIC,  // Use MIC instead of VOICE_RECOGNITION for background
          capturerFlags: 0
        }
      };
      this.audioCapturer = await audio.createAudioCapturer(capturerOptions);
      await this.audioCapturer.start();
    } catch (err) {
      this.log.error(this.TAG, `AudioCapturer create failed: ${(err as Error).message ?? ''}`);
      await this.stopBackgroundTask(context);  // Clean up background task
      this.currentRecord = undefined;
      return false;
    }

    // Reset segment state
    this.segmentBuffers = [];
    this.segmentStartTime = 0;
    this.speechDetected = false;
    this.silenceStartMs = 0;
    this.lastSpeechMs = Date.now();
    this.totalBufferBytes = 0;
    this.processingQueue = [];
    this.isProcessing = false;
    this.audioSegmentPaths = [];

    // Initialize three-tier state machine in low-power monitoring mode
    this.monitoringMode = true;
    this.frameSkipCounter = 0;
    this.consecutiveEnergyFrames = 0;
    this.silentFrameCount = 0;

    // Initialize smart splitting counters
    this.cumulativeSpeechMs = 0;
    this.lastSegmentEndMs = 0;
    this.lastSegmentSpeaker = '';

    this.setState('monitoring');
    this.reading = true;
    this.audioReadLoop();

    this.log.info(this.TAG, `Started recording, record=${recordId}`);
    Monitor.startModule('SilentMode');
    return true;
  }

  private async startBackgroundTask(context: common.UIAbilityContext): Promise<void> {
    try {
      this.log.info(this.TAG, 'Starting background task...');
      this.log.info(this.TAG, `Bundle: ${context.abilityInfo.bundleName}, Ability: ${context.abilityInfo.name}`);
      
      // Create wantAgent for notification tap action
      let wantAgentInfo: wantAgent.WantAgentInfo = {
        wants: [
          {
            bundleName: context.abilityInfo.bundleName,
            abilityName: context.abilityInfo.name
          }
        ],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0,
        actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      };
      let agent = await wantAgent.getWantAgent(wantAgentInfo);
      this.log.info(this.TAG, 'WantAgent created successfully');

      // Start continuous task
      await backgroundTaskManager.startBackgroundRunning(context, backgroundTaskManager.BackgroundMode.AUDIO_RECORDING, agent);
      this.log.info(this.TAG, '✅ Background task started successfully - app can now record in background');
    } catch (err) {
      let error = err as Error;
      let code = (err as Record<string, number>).code ?? -1;
      this.log.error(this.TAG, `❌ Failed to start background task: code=${code} msg=${error.message ?? ''}`);
      // Common errors:
      // 9800001 - Permission denied (need KEEP_BACKGROUND_RUNNING)
      // 9800003 - Background mode not configured in module.json5
      if (code === 9800001) {
        this.log.system(this.TAG, 'Missing ohos.permission.KEEP_BACKGROUND_RUNNING permission');
      } else if (code === 9800003) {
        this.log.system(this.TAG, 'backgroundModes not configured in module.json5');
      }
    }
  }

  private async stopBackgroundTask(context: common.UIAbilityContext): Promise<void> {
    try {
      await backgroundTaskManager.stopBackgroundRunning(context);
      this.log.info(this.TAG, 'Background task stopped');
    } catch (err) {
      this.log.warn(this.TAG, `Failed to stop background task: ${(err as Error).message ?? ''}`);
    }
  }

  async stop(): Promise<void> {
    if (this.state === 'idle' || this.stopping) return;

    this.stopping = true;
    this.reading = false;
    this.log.info(this.TAG, 'Stopping...');

    // Set state to idle IMMEDIATELY so button responds instantly
    this.setState('idle');
    Monitor.stopModule('SilentMode');

    // Grab references then clear — so cleanup doesn't block UI
    let capturer = this.audioCapturer;
    this.audioCapturer = undefined;
    let ctx = this.context;

    this.log.info(this.TAG, 'Stopped (cleanup in background)');

    // All slow cleanup runs in background via setTimeout — stop() returns instantly
    setTimeout(async () => {
      try {
        // Stop background task (system API, can be slow)
        if (ctx) {
          try { await this.stopBackgroundTask(ctx); } catch { /* ignore */ }
        }

        // Release capturer (may block until pending read() returns)
        try {
          if (capturer) {
            await capturer.stop();
            await capturer.release();
          }
        } catch (err) {
          this.log.warn(this.TAG, `Capturer cleanup: ${(err as Error).message ?? ''}`);
        }

        // Process remaining segment and generate summary
        try {
          if (this.speechDetected && this.segmentBuffers.length > 0) {
            await this.processSegment();
          }
          await this.endConversation();
          this.log.info(this.TAG, 'Background processing complete');
        } catch (err) {
          this.log.error(this.TAG, `Background processing error: ${(err as Error).message ?? ''}`);
        }
      } finally {
        this.stopping = false;
      }
    }, 0);
  }

  private async audioReadLoop(): Promise<void> {
    if (!this.audioCapturer) return;

    let loopCount = 0;
    let lastLogTime = Date.now();
    let vadService = VadService.getInstance();
    let useVad = vadService.isInitialized();

    // Reset VAD state for new recording session
    if (useVad) {
      vadService.reset();
    }

    try {
      let bufSize = await this.audioCapturer.getBufferSize();
      this.log.info(this.TAG, `Audio read loop started, bufSize=${bufSize}, useVad=${useVad}, tier=monitoring`);

      while (this.reading && this.audioCapturer) {
        let buf: ArrayBuffer = await this.audioCapturer.read(bufSize, true);
        if (buf.byteLength === 0) continue;

        loopCount++;
        let now = Date.now();

        // ====== Tier 1: Low-power monitoring (frame skipping) ======
        if (this.monitoringMode) {
          this.frameSkipCounter++;
          if (this.frameSkipCounter < SilentModeService.MONITOR_CHECK_INTERVAL) {
            continue;  // Skip frame entirely — no RMS calculation
          }
          this.frameSkipCounter = 0;

          let rms = this.calculateRms(buf);

          // Log status every 10 seconds
          if (now - lastLogTime >= 10000) {
            this.log.debug(this.TAG, `[Tier1 monitoring] loops=${loopCount} rms=${Math.round(rms)}`);
            lastLogTime = now;
          }

          if (rms > SilentModeService.ENERGY_WAKEUP_THRESHOLD) {
            this.consecutiveEnergyFrames++;
            if (this.consecutiveEnergyFrames >= SilentModeService.ENERGY_WAKEUP_FRAMES) {
              // Wake up → enter listening mode
              this.monitoringMode = false;
              this.silentFrameCount = 0;
              // Ensure VAD is initialized
              if (!vadService.isInitialized()) {
                let ctx = this.context;
                if (ctx) {
                  useVad = await vadService.init(ctx);
                }
              } else {
                useVad = true;
              }
              this.setState('listening');
              this.log.info(this.TAG, `Tier1->Tier2: energy detected (rms=${Math.round(rms)}), activating VAD`);
            }
          } else {
            this.consecutiveEnergyFrames = 0;
          }

          // Check conversation split even in monitoring mode (silence timeout)
          if (this.currentRecord && this.currentRecord.entries.length > 0 &&
            now - this.lastSpeechMs >= Constants.SILENT_MODE_CONVERSATION_END_MS) {
            this.log.info(this.TAG, 'Conversation split in monitoring: silence timeout');
            await this.endConversation();
            await this.startNewRecord();
            this.cumulativeSpeechMs = 0;
            this.lastSegmentEndMs = 0;
            this.lastSegmentSpeaker = '';
            this.lastSpeechMs = now;
          }
          continue;
        }

        // ====== Tier 2: VAD active detection ======
        let rms = this.calculateRms(buf);

        // Log status every 10 seconds
        if (now - lastLogTime >= 10000) {
          this.log.debug(this.TAG, `[Tier2 listening] loops=${loopCount} entries=${this.currentRecord?.entries.length ?? 0} rms=${Math.round(rms)} silentFrames=${this.silentFrameCount}`);
          lastLogTime = now;
        }

        // Speech detection using Silero VAD or RMS fallback
        let isSpeech = false;
        if (useVad) {
          if (rms > 50 || this.speechDetected) {
            let float32Samples = VadService.pcmToFloat32(buf);
            vadService.acceptWaveform(float32Samples);
            isSpeech = vadService.isDetected();
          }
        } else {
          isSpeech = rms > Constants.SILENT_MODE_VAD_THRESHOLD;
        }

        if (isSpeech) {
          // ====== Tier 3: Speech collection + ASR ======
          this.silentFrameCount = 0;
          if (!this.speechDetected) {
            this.speechDetected = true;
            this.segmentStartTime = now;
            this.segmentBuffers = [];
            this.totalBufferBytes = 0;
          }
          this.silenceStartMs = 0;
          this.lastSpeechMs = now;
          this.addToSegmentBuffer(buf);
          // Auto-split: if segment exceeds 15s, force-end and process it
          if (now - this.segmentStartTime >= 15000) {
            this.log.info(this.TAG, `Auto-splitting segment at 15s (buffers=${this.segmentBuffers.length})`);
            let splitBuffers = this.segmentBuffers.slice();
            this.enqueueSegment(splitBuffers);
            this.segmentBuffers = [];
            this.totalBufferBytes = 0;
            this.segmentStartTime = now;
            if (useVad) { vadService.reset(); }
          }
        } else if (this.speechDetected) {
          // Silence after speech
          this.silentFrameCount = 0;  // Don't count during post-speech tail
          this.addToSegmentBuffer(buf);
          if (this.silenceStartMs === 0) {
            this.silenceStartMs = now;
          } else if (now - this.silenceStartMs >= Constants.SILENT_MODE_SILENCE_END_MS) {
            // End of speech segment — track cumulative duration
            let segmentDuration = now - this.segmentStartTime;
            this.cumulativeSpeechMs += segmentDuration;
            this.lastSegmentEndMs = now;
            if (segmentDuration >= Constants.SILENT_MODE_MIN_SEGMENT_MS) {
              let buffers = this.segmentBuffers.slice();
              this.enqueueSegment(buffers);
            }
            // Reset for next segment
            this.speechDetected = false;
            this.segmentBuffers = [];
            this.totalBufferBytes = 0;
            this.silenceStartMs = 0;
            if (useVad) {
              vadService.reset();
            }
          }
        } else {
          // No speech detected — count silence frames
          this.silentFrameCount++;
          if (this.silentFrameCount >= SilentModeService.SILENCE_RETURN_FRAMES) {
            // Prolonged silence → return to low-power monitoring
            this.monitoringMode = true;
            this.frameSkipCounter = 0;
            this.consecutiveEnergyFrames = 0;
            this.silentFrameCount = 0;
            if (useVad) {
              vadService.reset();
            }
            this.setState('monitoring');
            this.log.info(this.TAG, 'Tier2->Tier1: prolonged silence, entering monitoring mode');
          }

          // Smart conversation split: combine speech duration + speaker gap
          let shouldSplit = false;
          if (this.currentRecord && this.currentRecord.entries.length > 0) {
            let elapsedMs = now - this.currentRecord.startTime;
            // Hard cap: force split at 10 min regardless
            if (elapsedMs >= SilentModeService.SPLIT_HARD_CAP_MS) {
              shouldSplit = true;
              this.log.info(this.TAG, `Conversation split: hard cap ${Math.round(elapsedMs / 1000)}s`);
            }
            // Soft split: 3+ min of speech AND 10s+ silence gap
            else if (this.cumulativeSpeechMs >= SilentModeService.SPLIT_MIN_SPEECH_MS &&
              this.lastSegmentEndMs > 0 && now - this.lastSegmentEndMs >= SilentModeService.SPLIT_SPEAKER_GAP_MS) {
              shouldSplit = true;
              this.log.info(this.TAG, `Conversation split: ${Math.round(this.cumulativeSpeechMs / 1000)}s speech + ${Math.round((now - this.lastSegmentEndMs) / 1000)}s gap`);
            }
            // Original timeout: 60s silence after conversation
            else if (now - this.lastSpeechMs >= Constants.SILENT_MODE_CONVERSATION_END_MS) {
              shouldSplit = true;
              this.log.info(this.TAG, 'Conversation split: silence timeout');
            }
          }

          if (shouldSplit) {
            await this.endConversation();
            await this.startNewRecord();
            this.cumulativeSpeechMs = 0;
            this.lastSegmentEndMs = 0;
            this.lastSegmentSpeaker = '';
            this.lastSpeechMs = now;
          }
        }
      }
      this.log.info(this.TAG, `Audio read loop ended normally, total loops=${loopCount}`);
    } catch (err) {
      this.log.error(this.TAG, `Audio read loop error: ${(err as Error).message ?? ''}`);
    }
  }

  private addToSegmentBuffer(buf: ArrayBuffer): void {
    // Ring buffer: drop oldest if exceeding max
    while (this.totalBufferBytes + buf.byteLength > SilentModeService.MAX_RING_BYTES && this.segmentBuffers.length > 0) {
      let removed = this.segmentBuffers.shift();
      if (removed) this.totalBufferBytes -= removed.byteLength;
    }
    this.segmentBuffers.push(buf.slice(0));
    this.totalBufferBytes += buf.byteLength;
  }

  private calculateRms(buf: ArrayBuffer): number {
    let int16 = new Int16Array(buf);
    let sum = 0;
    for (let i = 0; i < int16.length; i++) {
      sum += int16[i] * int16[i];
    }
    return Math.sqrt(sum / int16.length);
  }

  /**
   * Find a matching unknown speaker from previous entries in the current conversation.
   * Uses cosine similarity to compare embeddings.
   */
  private findMatchingUnknownSpeaker(newEmbedding: number[]): string | null {
    if (!this.currentRecord || newEmbedding.length === 0) {
      return null;
    }

    const SIMILARITY_THRESHOLD = 0.75;  // Adjust as needed
    let bestMatch: string | null = null;
    let bestScore = 0;

    // Check against all previous entries with embeddings
    for (let entry of this.currentRecord.entries) {
      if (entry.embedding && entry.embedding.length > 0 && entry.speaker.startsWith('unknown_')) {
        let similarity = this.cosineSimilarity(newEmbedding, entry.embedding);
        if (similarity > SIMILARITY_THRESHOLD && similarity > bestScore) {
          bestScore = similarity;
          bestMatch = entry.speaker;
        }
      }
    }

    if (bestMatch) {
      this.log.info(this.TAG, `Matched existing speaker ${bestMatch} with score ${bestScore.toFixed(3)}`);
    }

    return bestMatch;
  }

  /**
   * Calculate cosine similarity between two embedding vectors.
   */
  private cosineSimilarity(a: number[], b: number[]): number {
    if (a.length !== b.length || a.length === 0) {
      return 0;
    }

    let dotProduct = 0;
    let normA = 0;
    let normB = 0;

    for (let i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }

    let denominator = Math.sqrt(normA) * Math.sqrt(normB);
    if (denominator === 0) {
      return 0;
    }

    return dotProduct / denominator;
  }

  /**
   * Merge user-edited speakerAliases from store into in-memory record, then save.
   * Prevents new ASR entries from overwriting user-assigned speaker names.
   */
  private async mergeAndSaveRecord(record: SilentConversationRecord): Promise<void> {
    try {
      let stored = await ConversationStore.getInstance().getRecord(record.id);
      if (stored && stored.speakerAliases) {
        let aliasKeys = Object.keys(stored.speakerAliases);
        for (let k of aliasKeys) {
          record.speakerAliases[k] = stored.speakerAliases[k];
        }
      }
    } catch { /* ignore */ }
    await ConversationStore.getInstance().saveRecord(record);
  }

  private chunksToFloat32(buffers: ArrayBuffer[]): Float32Array {
    // Calculate total Int16 samples
    let totalBytes = 0;
    for (let b of buffers) totalBytes += b.byteLength;
    let totalSamples = totalBytes / 2;

    // Merge into single Int16Array
    let merged = new Int16Array(totalSamples);
    let offset = 0;
    for (let b of buffers) {
      let chunk = new Int16Array(b);
      merged.set(chunk, offset);
      offset += chunk.length;
    }

    // Convert to Float32 normalized [-1.0, 1.0]
    let float32 = new Float32Array(totalSamples);
    for (let i = 0; i < totalSamples; i++) {
      float32[i] = merged[i] / 32768.0;
    }
    return float32;
  }

  /**
   * Enqueue a segment for serial processing.
   * Only one processSegment runs at a time to avoid concurrent ASR on shared engine.
   */
  private enqueueSegment(buffers: ArrayBuffer[]): void {
    this.processingQueue.push(buffers);
    this.log.debug(this.TAG, `Segment queued (queue size: ${this.processingQueue.length})`);
    if (!this.isProcessing) {
      this.processNextInQueue();
    }
  }

  private processNextInQueue(): void {
    if (this.processingQueue.length === 0) {
      this.isProcessing = false;
      return;
    }
    this.isProcessing = true;
    let buffers = this.processingQueue.shift()!;
    this.processSegment(buffers).then(() => {
      this.processNextInQueue();
    }).catch((err: Error) => {
      this.log.error(this.TAG, `Queue process error: ${err.message ?? ''}`);
      this.processNextInQueue();
    });
  }

  private async processSegment(buffers?: ArrayBuffer[]): Promise<void> {
    let bufs = buffers || this.segmentBuffers;
    if (bufs.length === 0) return;

    // Only update state if still actively recording (don't override 'idle' after stop)
    if (this.reading) {
      this.setState('processing');
    }

    // Save raw PCM segment to cache for later Qwen3-Omni audio summary
    if (this.context) {
      try {
        let segPath = `${this.context.cacheDir}/seg_${Date.now()}.pcm`;
        this.saveRawPcm(bufs, segPath);
        this.audioSegmentPaths.push(segPath);
        this.log.debug(this.TAG, `Saved PCM segment: ${segPath} (${this.audioSegmentPaths.length} total)`);
      } catch (err) {
        this.log.warn(this.TAG, `Failed to save PCM segment: ${(err as Error).message ?? ''}`);
      }
    }

    try {
      // Convert to Float32 for voiceprint
      let float32 = this.chunksToFloat32(bufs);
      let durationSec = float32.length / 16000;
      this.log.debug(this.TAG, `Processing segment: ${float32.length} samples (${durationSec.toFixed(2)}s)`);

      // Truncate audio for voiceprint to first 5 seconds (80000 samples) to avoid OOM on long segments
      let vpSamples = float32.length > 80000 ? float32.slice(0, 80000) : float32;

      // Speaker identification
      let speakerId = '';
      let confidence = 0;
      let embeddingArray: number[] = [];
      try {
        let vpService = VoiceprintService.getInstance();
        let registeredCount = vpService.getSpeakerCount();
        let registeredNames = vpService.getAllSpeakerNames();
        this.log.info(this.TAG, `Registered speakers: ${registeredCount} [${registeredNames.join(', ')}]`);

        // Extract embedding for storage (use truncated audio)
        let emb = vpService.extractEmbedding(vpSamples, 16000);
        if (emb) {
          embeddingArray = Array.from(emb);
          this.log.debug(this.TAG, `Extracted embedding: dim=${emb.length}`);
        } else {
          this.log.warn(this.TAG, 'Failed to extract embedding (audio too short or error)');
        }

        // Try to identify speaker using pre-computed embedding (avoids double extraction)
        let result = emb ? vpService.identifyFromEmbedding(emb) : vpService.identify(vpSamples, 16000);
        this.log.debug(this.TAG, `Identify result: speaker="${result.speaker}" score=${result.score.toFixed(3)} conf=${result.confidence}`);
        if (result.speaker && result.speaker !== 'unknown' && result.speaker !== '') {
          speakerId = result.speaker;
          confidence = result.score;
          this.log.info(this.TAG, `✅ Matched registered speaker: ${speakerId} (score=${confidence.toFixed(3)})`);
        } else if (registeredCount > 0) {
          this.log.info(this.TAG, `❌ No match found among ${registeredCount} registered speakers`);
        }
      } catch (err) {
        this.log.warn(this.TAG, `Speaker ID error: ${(err as Error).message ?? String(err)}`);
      }

      // Assign display name for unknown speakers
      let speaker = speakerId;
      if (!speakerId && this.currentRecord && embeddingArray.length > 0) {
        // Check if this voice matches a previous unknown speaker in this conversation
        let matchedSpeaker = this.findMatchingUnknownSpeaker(embeddingArray);
        if (matchedSpeaker) {
          speakerId = matchedSpeaker;
          speaker = speakerId;
        } else {
          // New unknown speaker
          this.unknownSpeakerCount++;
          speakerId = `unknown_${this.unknownSpeakerCount}`;
          let displayName = `说话人${this.unknownSpeakerCount}`;
          this.currentRecord.speakerAliases[speakerId] = displayName;
          speaker = speakerId;
        }
      } else if (!speakerId && this.currentRecord) {
        // No embedding available, create new speaker
        this.unknownSpeakerCount++;
        speakerId = `unknown_${this.unknownSpeakerCount}`;
        let displayName = `说话人${this.unknownSpeakerCount}`;
        this.currentRecord.speakerAliases[speakerId] = displayName;
        speaker = speakerId;
      }

      // Speech-to-text via LocalAsrService (if enabled)
      let text = '';
      let localAsrEnabled = true;
      if (this.context) {
        try {
          let prefStore = await preferences.getPreferences(this.context, Constants.PREFS_SETTINGS);
          localAsrEnabled = (await prefStore.get('silent_local_asr', false)) as boolean;
        } catch { /* default false */ localAsrEnabled = false; }
      }
      if (localAsrEnabled) {
        try {
          let asrService = LocalAsrService.getInstance();
          this.log.info(this.TAG, 'Starting local ASR recognition...');
          text = await asrService.recognizeFromPcm(bufs);
          if (text.trim().length > 0) {
            this.log.info(this.TAG, `ASR result: "${text.substring(0, 100)}"`);
          } else {
            this.log.info(this.TAG, 'ASR returned empty text');
          }
        } catch (err) {
          this.log.warn(this.TAG, `ASR error: ${(err as Error).message ?? String(err)}`);
        }
      } else {
        this.log.debug(this.TAG, 'Local ASR disabled, skipping (audio model will transcribe at summary)');
      }

      let record = this.currentRecord;
      // Create entry if we have text, or if local ASR is disabled (speaker tracking still needed)
      let hasText = text.trim().length > 0;
      if ((hasText || !localAsrEnabled) && record) {
        let extracted: import('../model/Models').ExtractedInfo | undefined;
        if (hasText) {
          let extractor = SilentModeExtractor.getInstance();
          extracted = extractor.extract(text.trim());
          let hasImportantInfo = extractor.hasImportantInfo(extracted);
          if (hasImportantInfo) {
            this.log.info(this.TAG, `Extracted: ${extractor.formatForDisplay(extracted)}`);
          } else {
            extracted = undefined;
          }
        }

        let emotion: import('../model/Models').EmotionAnalysis | undefined;
        try {
          let emotionAnalyzer = EmotionAnalyzer.getInstance();
          emotion = emotionAnalyzer.analyzeFromFloat32(float32);
          this.log.debug(this.TAG, `Emotion: ${emotionAnalyzer.getEmotionLabel(emotion.emotion)} (stress: ${emotionAnalyzer.getStressLabel(emotion.stressLevel)})`);
        } catch (err) {
          this.log.warn(this.TAG, `Emotion analysis error: ${err}`);
        }

        let entryText = hasText ? text.trim() : '[...]';
        let entry: SilentConversationEntryEx = {
          timestamp: Date.now(),
          speaker: speaker,
          text: entryText,
          confidence: confidence,
          embedding: embeddingArray.length > 0 ? embeddingArray : undefined,
          extracted: extracted,
          emotion: emotion
        };
        record.entries.push(entry);

        if (!record.participants.includes(speaker)) {
          record.participants.push(speaker);
        }

        // Track last speaker for smart splitting
        this.lastSegmentSpeaker = speaker;

        await this.mergeAndSaveRecord(record);
        this.log.info(this.TAG, `Entry: [${speaker}] ${entryText.substring(0, 50)}`);
      }
    } catch (err) {
      this.log.error(this.TAG, `processSegment error: ${(err as Error).message ?? ''}`);
    }

    if (this.reading) {
      this.setState('listening');
    }
  }

  private async endConversation(): Promise<void> {
    let record = this.currentRecord;
    if (!record) return;

    record.endTime = Date.now();

    // Check if there's any real speech content (not just "[...]" placeholders)
    let realEntries = record.entries.filter((e: SilentConversationEntry) => e.text.length > 0 && e.text !== '[...]');
    if (realEntries.length === 0) {
      // No real speech detected — skip summary and audio upload
      record.status = 'completed';
      this.log.info(this.TAG, `No real speech entries (${record.entries.length} total, 0 real), skipping summary`);
      this.cleanupAudioSegments();
      await this.mergeAndSaveRecord(record);
      return;
    }

    // Generate summary via AI
    record.status = 'summarizing';
    await this.mergeAndSaveRecord(record);

    try {
      let summary = await this.generateSummary(record);
      record.summary = summary;
      record.status = 'completed';
    } catch (err) {
      this.log.error(this.TAG, `Summary generation failed: ${err}`);
      record.status = record.entries.length > 0 ? 'completed' : 'error';
    }

    // Extract action items from summary and create calendar events
    if (record.summary.length > 0) {
      try {
        let actionItems = await this.extractActionItems(record);
        record.actionItems = actionItems;
        if (actionItems.length > 0) {
          this.log.info(this.TAG, `Extracted ${actionItems.length} action items, creating calendar events...`);
          await this.createCalendarEvents(actionItems);
          let createdCount = actionItems.filter((ai: ActionItem) => ai.created).length;
          this.log.info(this.TAG, `Calendar events created: ${createdCount}/${actionItems.length}`);
        }
      } catch (err) {
        this.log.warn(this.TAG, `Action item extraction failed: ${(err as Error).message ?? ''}`);
      }
    }

    // Generate title: "主题 | HH:MM-HH:MM | 人A、人B等"
    record.title = await this.buildSmartTitle(record);

    await this.mergeAndSaveRecord(record);

    // Clean up temporary PCM segment files
    this.cleanupAudioSegments();

    // Export markdown
    if (this.context) {
      await ConversationStore.getInstance().saveAsMarkdown(this.context, record);
    }
  }

  /**
   * Build a display title: "主题 | HH:MM-HH:MM | 人A、人B等"
   * Uses LLM to generate a short topic from the summary.
   */
  private async buildSmartTitle(record: SilentConversationRecord): Promise<string> {
    // Time range
    let startD = new Date(record.startTime);
    let endD = new Date(record.endTime > 0 ? record.endTime : Date.now());
    let startTime = `${String(startD.getHours()).padStart(2, '0')}:${String(startD.getMinutes()).padStart(2, '0')}`;
    let endTime = `${String(endD.getHours()).padStart(2, '0')}:${String(endD.getMinutes()).padStart(2, '0')}`;
    let timeRange = `${startTime}-${endTime}`;

    // Participants (max 2, then "等")
    let displayNames: string[] = [];
    for (let p of record.participants) {
      let alias = record.speakerAliases[p];
      displayNames.push(alias ? alias : p);
    }
    let participantStr = '';
    if (displayNames.length <= 2) {
      participantStr = displayNames.join('、');
    } else {
      participantStr = `${displayNames[0]}、${displayNames[1]}等`;
    }

    // Topic: use LLM to extract a short topic from summary
    let topic = '';
    if (record.summary.length > 0 && this.context) {
      try {
        topic = await this.generateTopicFromSummary(record.summary);
      } catch (err) {
        this.log.warn(this.TAG, `Topic generation failed: ${(err as Error).message ?? ''}`);
      }
    }
    // Fallback: extract first few chars from summary
    if (topic.length === 0 && record.summary.length > 0) {
      let lines = record.summary.split('\n').filter((l: string) => l.trim().length > 0);
      if (lines.length > 0) {
        let firstLine = lines[0].replace(/^[#\-*\u2022\s]+/, '').trim();
        if (firstLine.length > 10) {
          topic = firstLine.substring(0, 10) + '...';
        } else {
          topic = firstLine;
        }
      }
    }

    // Assemble title
    let parts: string[] = [];
    if (topic.length > 0) parts.push(topic);
    parts.push(timeRange);
    if (participantStr.length > 0) parts.push(participantStr);
    return parts.join(' | ');
  }

  /**
   * Use LLM to generate a short topic (2-8 Chinese chars) from the summary.
   */
  private async generateTopicFromSummary(summary: string): Promise<string> {
    if (!this.context) return '';

    let store = await preferences.getPreferences(this.context, Constants.PREFS_SETTINGS);
    let provider = (await store.get('provider', 'openrouter')) as string;
    let keyPref = 'key_' + provider;
    let modelPref = 'model_' + provider;
    let apiKey = (await store.get(keyPref, '')) as string;
    let baseUrl = (await store.get('url_' + provider, '')) as string;
    if (provider === 'openrouter' && baseUrl.length > 0 && !baseUrl.includes('openrouter')) {
      baseUrl = '';
    }
    let defaultModel = provider === 'openrouter' ? Constants.DEFAULT_MODEL_OPENROUTER
      : provider === 'anthropic' ? Constants.DEFAULT_MODEL_ANTHROPIC
        : provider === 'openai' ? Constants.DEFAULT_MODEL_OPENAI
          : provider === 'siliconflow' ? Constants.DEFAULT_MODEL_SILICONFLOW
            : '';
    let model = (await store.get(modelPref, defaultModel)) as string;
    if (model.length === 0) model = defaultModel;
    if (apiKey.length === 0 && provider === 'openrouter' && Constants.OPENROUTER_DEFAULT_KEY.length > 0) {
      apiKey = Constants.OPENROUTER_DEFAULT_KEY;
    }
    if (apiKey.length === 0 && (provider === 'openai' || provider === 'siliconflow') && Constants.SILICONFLOW_DEFAULT_KEY.length > 0) {
      apiKey = Constants.SILICONFLOW_DEFAULT_KEY;
    }

    let settings: SettingsData = {
      provider: provider,
      apiKey: apiKey,
      model: model,
      baseUrl: baseUrl,
      temperature: 0.1
    };

    let systemPrompt = '你是一个标题提取助手。从摘要中提取一个简短的主题词。只输出2-8个中文字的主题词，不要加标点符号，不要加任何解释。例如："项目进度讨论"、"机场接人安排"、"周末聚餐"。';
    let userMessage = `请从以下摘要中提取简短主题词：\n\n${summary}`;

    let aiService = AIService.getInstance();
    let result = await aiService.simpleChat(systemPrompt, userMessage, settings);
    let topic = result.trim().replace(/["""''。，！？、；：\s]/g, '');
    // Limit to 10 chars max
    if (topic.length > 10) {
      topic = topic.substring(0, 10);
    }
    this.log.info(this.TAG, `Generated topic: "${topic}"`);
    return topic;
  }

  private async generateSummary(record: SilentConversationRecord): Promise<string> {
    if (!this.context) return '';

    // Build transcript text
    let transcript = '';
    for (let entry of record.entries) {
      let t = new Date(entry.timestamp);
      let ts = `${String(t.getHours()).padStart(2, '0')}:${String(t.getMinutes()).padStart(2, '0')}`;
      transcript += `[${ts}] ${entry.speaker}: ${entry.text}\n`;
    }

    let systemPrompt = '你是一个对话摘要助手。请始终用简洁的中文总结以下对话的主要内容、关键决定和待办事项。即使对话是英文的，也请用中文总结。';
    let userMessage = `请总结以下对话：\n\n${transcript}`;

    // Load settings for AI call
    try {
      let store = await preferences.getPreferences(this.context, Constants.PREFS_SETTINGS);
      let provider = (await store.get('provider', 'openrouter')) as string;
      let keyPref = 'key_' + provider;
      let modelPref = 'model_' + provider;
      let apiKey = (await store.get(keyPref, '')) as string;
      let baseUrl = (await store.get('url_' + provider, '')) as string;
      if (provider === 'openrouter' && baseUrl.length > 0 && !baseUrl.includes('openrouter')) {
        baseUrl = '';
      }
      let defaultModel = provider === 'openrouter' ? Constants.DEFAULT_MODEL_OPENROUTER
        : provider === 'anthropic' ? Constants.DEFAULT_MODEL_ANTHROPIC
          : provider === 'openai' ? Constants.DEFAULT_MODEL_OPENAI
            : provider === 'siliconflow' ? Constants.DEFAULT_MODEL_SILICONFLOW
              : '';
      let model = (await store.get(modelPref, defaultModel)) as string;
      // Safety: if model is empty (stored as ''), use default
      if (model.length === 0) {
        model = defaultModel;
      }
      this.log.info(this.TAG, `Summary AI: provider=${provider} model=${model}`);
      if (apiKey.length === 0 && provider === 'openrouter' && Constants.OPENROUTER_DEFAULT_KEY.length > 0) {
        apiKey = Constants.OPENROUTER_DEFAULT_KEY;
      }
      if (apiKey.length === 0 && (provider === 'openai' || provider === 'siliconflow') && Constants.SILICONFLOW_DEFAULT_KEY.length > 0) {
        apiKey = Constants.SILICONFLOW_DEFAULT_KEY;
      }

      let settings: SettingsData = {
        provider: provider,
        apiKey: apiKey,
        model: model,
        baseUrl: baseUrl,
        temperature: 0.3
      };

      let aiService = AIService.getInstance();

      // Try audio summary if we have audio segments
      // Audio model setting: empty = use main provider model, non-empty = use specified model via AI Engine (SiliconFlow)
      let audioModelSetting = (await store.get('silent_audio_model', '')) as string;

      if (this.audioSegmentPaths.length > 0) {
        // Determine audio provider/key/model based on setting
        let audioProvider: string;
        let audioApiKey: string;
        let audioBaseUrl: string;
        let audioModel: string;

        if (audioModelSetting.length > 0) {
          // Explicit audio model configured → use AI Engine (SiliconFlow) key, same as ASR
          audioModel = audioModelSetting;
          audioApiKey = (await store.get('key_siliconflow', '')) as string;
          audioBaseUrl = (await store.get('url_siliconflow', '')) as string;
          audioProvider = 'siliconflow';
          // Fallback chain: siliconflow key → main provider key (if compatible) → default key
          if (audioApiKey.length === 0 && (provider === 'openai' || provider === 'openrouter')) {
            audioApiKey = apiKey;
            audioBaseUrl = baseUrl;
            audioProvider = provider;
          }
          if (audioApiKey.length === 0 && Constants.SILICONFLOW_DEFAULT_KEY.length > 0) {
            audioApiKey = Constants.SILICONFLOW_DEFAULT_KEY;
            audioProvider = 'siliconflow';
          }
        } else {
          // No audio model specified → use main provider's model (send audio to main LLM)
          audioModel = model;
          audioApiKey = apiKey;
          audioBaseUrl = baseUrl;
          audioProvider = provider;
        }

        if (audioApiKey.length > 0 && audioProvider !== 'anthropic') {
          try {
            let wavBase64 = this.encodeSegmentsAsWavBase64();
            if (wavBase64.length > 0) {
              let audioSettings: SettingsData = {
                provider: audioProvider,
                apiKey: audioApiKey,
                model: audioModel,
                baseUrl: audioBaseUrl,
                temperature: 0.3
              };
              let audioPrompt = '你是一个对话转录与摘要助手。请先准确转录音频中的对话内容，然后用简洁的中文总结主要内容、关键决定和待办事项。即使对话是英文的，也请用中文总结。';
              let audioUserMsg = '请转录并总结这段对话录音。';
              this.log.info(this.TAG, `Calling ${audioModel} for audio summary (provider=${audioProvider}, base64 len=${wavBase64.length})`);
              let audioResult = await aiService.simpleChatWithAudio(audioPrompt, audioUserMsg, wavBase64, audioSettings);
              if (audioResult.length > 0) {
                this.log.info(this.TAG, `Audio summary success (len=${audioResult.length})`);
                return audioResult;
              }
              this.log.warn(this.TAG, 'Audio model returned empty, falling back to text summary');
            }
          } catch (err) {
            this.log.warn(this.TAG, `Audio summary failed, falling back to text: ${(err as Error).message ?? ''}`);
          }
        } else if (audioProvider === 'anthropic' || audioApiKey.length === 0) {
          // No compatible API key — try gateway if connected
          let gateway = NodeRuntime.getInstance();
          if (gateway.isConnected) {
            try {
              let wavBase64 = this.encodeSegmentsAsWavBase64();
              if (wavBase64.length > 0) {
                let audioPrompt = '请转录以下音频中的对话内容，然后用简洁的中文总结主要内容、关键决定和待办事项。即使对话是英文的，也请用中文总结。';
                this.log.info(this.TAG, `Sending audio to gateway for summary (base64 len=${wavBase64.length})`);
                let gatewayResult = await this.chatViaGateway(audioPrompt, wavBase64);
                if (gatewayResult.length > 0) {
                  this.log.info(this.TAG, `Gateway audio summary success (len=${gatewayResult.length})`);
                  return gatewayResult;
                }
                this.log.warn(this.TAG, 'Gateway returned empty, falling back to text summary');
              }
            } catch (err) {
              this.log.warn(this.TAG, `Gateway audio summary failed: ${(err as Error).message ?? ''}`);
            }
          } else {
            this.log.warn(this.TAG, 'No API key and gateway not connected, cannot do audio summary');
          }
        }
      }

      // Fallback to text-only summary
      return await aiService.simpleChat(systemPrompt, userMessage, settings);
    } catch (err) {
      this.log.error(this.TAG, `Summary AI call failed: ${err}`);
      return '';
    }
  }

  private async startNewRecord(): Promise<void> {
    this.cleanupAudioSegments();
    let recordId = `silent_${Date.now()}_${Math.floor(Math.random() * 100000)}`;
    this.unknownSpeakerCount = 0;
    this.currentRecord = {
      id: recordId,
      startTime: Date.now(),
      endTime: 0,
      entries: [],
      summary: '',
      title: '',
      status: 'recording',
      participants: [],
      speakerAliases: {}
    };
    await ConversationStore.getInstance().saveRecord(this.currentRecord);
  }

  /**
   * Save raw PCM buffers to a file.
   */
  private saveRawPcm(buffers: ArrayBuffer[], filePath: string): void {
    let totalBytes = 0;
    for (let b of buffers) totalBytes += b.byteLength;
    let merged = new Uint8Array(totalBytes);
    let offset = 0;
    for (let b of buffers) {
      merged.set(new Uint8Array(b), offset);
      offset += b.byteLength;
    }
    let file = fileIo.openSync(filePath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    fileIo.writeSync(file.fd, merged.buffer as ArrayBuffer);
    fileIo.closeSync(file);
  }

  /**
   * Encode all saved PCM segments into a single WAV file as base64 string.
   * WAV format: 16kHz, 16-bit, mono. Max 3 minutes of audio (~5.76MB PCM).
   */
  private encodeSegmentsAsWavBase64(): string {
    if (this.audioSegmentPaths.length === 0) return '';

    this.log.info(this.TAG, `Encoding ${this.audioSegmentPaths.length} segments as WAV`);

    // Read and merge all PCM segments, up to 3 minutes (16000 * 2 * 180 = 5,760,000 bytes)
    let maxPcmBytes = 16000 * 2 * 180;
    let pcmChunks: Uint8Array[] = [];
    let totalPcmBytes = 0;

    for (let segPath of this.audioSegmentPaths) {
      try {
        let stat = fileIo.statSync(segPath);
        if (totalPcmBytes + stat.size > maxPcmBytes) {
          this.log.info(this.TAG, `Reached 3min audio limit, skipping remaining segments`);
          break;
        }
        let file = fileIo.openSync(segPath, fileIo.OpenMode.READ_ONLY);
        let buf = new ArrayBuffer(stat.size);
        fileIo.readSync(file.fd, buf);
        fileIo.closeSync(file);
        pcmChunks.push(new Uint8Array(buf));
        totalPcmBytes += stat.size;
      } catch (err) {
        this.log.warn(this.TAG, `Failed to read PCM segment ${segPath}: ${(err as Error).message ?? ''}`);
      }
    }

    if (totalPcmBytes === 0) return '';

    // Merge all PCM data
    let pcmData = new Uint8Array(totalPcmBytes);
    let offset = 0;
    for (let chunk of pcmChunks) {
      pcmData.set(chunk, offset);
      offset += chunk.length;
    }

    // Build 44-byte WAV header (16kHz, 16-bit, mono)
    let sampleRate = 16000;
    let bitsPerSample = 16;
    let numChannels = 1;
    let byteRate = sampleRate * numChannels * bitsPerSample / 8;
    let blockAlign = numChannels * bitsPerSample / 8;
    let dataSize = totalPcmBytes;
    let fileSize = 36 + dataSize;

    let wavHeader = new ArrayBuffer(44);
    let view = new DataView(wavHeader);
    // RIFF header
    view.setUint8(0, 0x52); // R
    view.setUint8(1, 0x49); // I
    view.setUint8(2, 0x46); // F
    view.setUint8(3, 0x46); // F
    view.setUint32(4, fileSize, true); // file size - 8
    view.setUint8(8, 0x57);  // W
    view.setUint8(9, 0x41);  // A
    view.setUint8(10, 0x56); // V
    view.setUint8(11, 0x45); // E
    // fmt sub-chunk
    view.setUint8(12, 0x66); // f
    view.setUint8(13, 0x6D); // m
    view.setUint8(14, 0x74); // t
    view.setUint8(15, 0x20); // (space)
    view.setUint32(16, 16, true);           // sub-chunk size (16 for PCM)
    view.setUint16(20, 1, true);            // audio format (1 = PCM)
    view.setUint16(22, numChannels, true);  // channels
    view.setUint32(24, sampleRate, true);   // sample rate
    view.setUint32(28, byteRate, true);     // byte rate
    view.setUint16(32, blockAlign, true);   // block align
    view.setUint16(34, bitsPerSample, true); // bits per sample
    // data sub-chunk
    view.setUint8(36, 0x64); // d
    view.setUint8(37, 0x61); // a
    view.setUint8(38, 0x74); // t
    view.setUint8(39, 0x61); // a
    view.setUint32(40, dataSize, true);     // data size

    // Combine header + PCM data
    let wavData = new Uint8Array(44 + totalPcmBytes);
    wavData.set(new Uint8Array(wavHeader), 0);
    wavData.set(pcmData, 44);

    // Convert to base64
    let base64Helper = new util.Base64Helper();
    let base64Str = base64Helper.encodeToStringSync(wavData);

    let durationSec = totalPcmBytes / (sampleRate * numChannels * bitsPerSample / 8);
    this.log.info(this.TAG, `WAV encoded: ${durationSec.toFixed(1)}s, ${totalPcmBytes} bytes PCM, base64 len=${base64Str.length}`);
    return base64Str;
  }

  /**
   * Clean up temporary PCM segment files from cache directory.
   */
  private cleanupAudioSegments(): void {
    for (let segPath of this.audioSegmentPaths) {
      try {
        fileIo.unlinkSync(segPath);
      } catch { /* ignore */ }
    }
    if (this.audioSegmentPaths.length > 0) {
      this.log.info(this.TAG, `Cleaned up ${this.audioSegmentPaths.length} PCM segment files`);
    }
    this.audioSegmentPaths = [];
  }

  /**
   * Send a message (with optional audio attachment) via gateway and wait for the final response.
   * Wraps the event-driven gateway chat into a Promise.
   */
  private chatViaGateway(text: string, audioBase64?: string): Promise<string> {
    return new Promise<string>((resolve, reject) => {
      let gateway = NodeRuntime.getInstance();
      let result = '';
      let done = false;
      let timeoutId = setTimeout(() => {
        if (!done) {
          done = true;
          gateway.removeChatListener(listener);
          reject(new Error('Gateway chat timeout (60s)'));
        }
      }, 60000);

      let runIdToMatch = '';

      let listener = (event: GatewayChatEvent): void => {
        if (done) return;
        // Match by runId once we know it
        if (runIdToMatch.length > 0 && event.runId !== runIdToMatch) return;

        if (event.state === 'delta' && event.message) {
          for (let block of event.message.content) {
            if (block.type === 'text' && block.text) {
              result += block.text;
            }
          }
        } else if (event.state === 'final') {
          if (event.message) {
            for (let block of event.message.content) {
              if (block.type === 'text' && block.text) {
                result += block.text;
              }
            }
          }
          done = true;
          clearTimeout(timeoutId);
          gateway.removeChatListener(listener);
          resolve(result);
        } else if (event.state === 'error' || event.state === 'aborted') {
          done = true;
          clearTimeout(timeoutId);
          gateway.removeChatListener(listener);
          reject(new Error(event.errorMessage ?? 'Gateway chat error'));
        }
      };

      gateway.addChatListener(listener);

      // Build attachments
      let attachments: ChatAttachment[] | undefined;
      if (audioBase64 && audioBase64.length > 0) {
        attachments = [{
          type: 'audio',
          mimeType: 'audio/wav',
          fileName: 'recording.wav',
          content: audioBase64
        }];
      }

      // Send and capture runId for matching
      gateway.sendChatMessage(text, undefined, attachments).then((runId: string) => {
        runIdToMatch = runId;
      }).catch((err: Error) => {
        if (!done) {
          done = true;
          clearTimeout(timeoutId);
          gateway.removeChatListener(listener);
          reject(err);
        }
      });
    });
  }

  /**
   * Extract action items from conversation summary using LLM.
   * Returns structured ActionItem[] with parsed timestamps.
   */
  private async extractActionItems(record: SilentConversationRecord): Promise<ActionItem[]> {
    if (!this.context || record.summary.length === 0) return [];

    let now = new Date();
    let year = now.getFullYear();
    let month = String(now.getMonth() + 1).padStart(2, '0');
    let day = String(now.getDate()).padStart(2, '0');
    let hours = String(now.getHours()).padStart(2, '0');
    let minutes = String(now.getMinutes()).padStart(2, '0');
    let weekDays: string[] = ['日', '一', '二', '三', '四', '五', '六'];
    let weekDay = weekDays[now.getDay()];
    let localTimeStr = `${year}年${month}月${day}日 星期${weekDay} ${hours}:${minutes}（本地时间）`;
    let tomorrowDate = new Date(now.getTime() + 24 * 3600 * 1000);
    let tomorrowStr = `${tomorrowDate.getFullYear()}-${String(tomorrowDate.getMonth() + 1).padStart(2, '0')}-${String(tomorrowDate.getDate()).padStart(2, '0')}`;

    let systemPrompt = `你是一个行动项提取助手。从对话摘要中提取需要添加到日历或提醒的行动项。

当前时间：${localTimeStr}
今天日期：${year}-${month}-${day}
明天日期：${tomorrowStr}

重要规则：
- "明天"指的是 ${tomorrowStr}，"今天"指的是 ${year}-${month}-${day}
- "下午"指的是 12:00-18:00，"上午"指的是 06:00-12:00，"晚上"指的是 18:00-24:00
- 所有时间必须使用本地时区，不要用 UTC
- 只提取有明确时间或截止期限的事项
- 不要编造时间——只提取对话中明确提到的时间

返回 JSON 数组，每项格式：
[{"title":"...", "startTime":"YYYY-MM-DDTHH:mm:ss", "endTime":"YYYY-MM-DDTHH:mm:ss", "location":"...", "reminder": 15}]

如果没有行动项，返回空数组 []。
只返回 JSON，不要包含任何其他文字。`;

    let userMessage = `请从以下对话摘要中提取行动项：\n\n${record.summary}`;

    try {
      let store = await preferences.getPreferences(this.context, Constants.PREFS_SETTINGS);
      let provider = (await store.get('provider', 'openrouter')) as string;
      let keyPref = 'key_' + provider;
      let modelPref = 'model_' + provider;
      let apiKey = (await store.get(keyPref, '')) as string;
      let baseUrl = (await store.get('url_' + provider, '')) as string;
      if (provider === 'openrouter' && baseUrl.length > 0 && !baseUrl.includes('openrouter')) {
        baseUrl = '';
      }
      let defaultModel = provider === 'openrouter' ? Constants.DEFAULT_MODEL_OPENROUTER
        : provider === 'anthropic' ? Constants.DEFAULT_MODEL_ANTHROPIC
          : provider === 'openai' ? Constants.DEFAULT_MODEL_OPENAI
            : provider === 'siliconflow' ? Constants.DEFAULT_MODEL_SILICONFLOW
              : '';
      let model = (await store.get(modelPref, defaultModel)) as string;
      if (model.length === 0) model = defaultModel;
      if (apiKey.length === 0 && provider === 'openrouter' && Constants.OPENROUTER_DEFAULT_KEY.length > 0) {
        apiKey = Constants.OPENROUTER_DEFAULT_KEY;
      }
      if (apiKey.length === 0 && (provider === 'openai' || provider === 'siliconflow') && Constants.SILICONFLOW_DEFAULT_KEY.length > 0) {
        apiKey = Constants.SILICONFLOW_DEFAULT_KEY;
      }

      let settings: SettingsData = {
        provider: provider,
        apiKey: apiKey,
        model: model,
        baseUrl: baseUrl,
        temperature: 0.1
      };

      this.log.info(this.TAG, 'Extracting action items from summary...');
      let aiService = AIService.getInstance();
      let response = await aiService.simpleChat(systemPrompt, userMessage, settings);

      // Parse JSON from response (may have markdown code block wrapper)
      let jsonStr = response.trim();
      let codeBlockMatch = jsonStr.match(/```(?:json)?\s*([\s\S]*?)```/);
      if (codeBlockMatch) {
        jsonStr = codeBlockMatch[1].trim();
      }

      let rawItems: object[] = JSON.parse(jsonStr) as object[];
      if (!Array.isArray(rawItems) || rawItems.length === 0) {
        this.log.info(this.TAG, 'No action items found in summary');
        return [];
      }

      let actionItems: ActionItem[] = [];
      for (let raw of rawItems) {
        let r = raw as Record<string, string | number>;
        let title = (r['title'] as string) ?? '';
        if (title.length === 0) continue;

        let startTimeStr = (r['startTime'] as string) ?? '';
        let endTimeStr = (r['endTime'] as string) ?? '';
        let location = (r['location'] as string) ?? '';
        let reminder = (r['reminder'] as number) ?? 15;

        // Parse ISO8601 to epoch ms
        let startMs = 0;
        let endMs = 0;
        if (startTimeStr.length > 0) {
          let parsed = new Date(startTimeStr);
          if (!isNaN(parsed.getTime())) {
            startMs = parsed.getTime();
          }
        }
        if (endTimeStr.length > 0) {
          let parsed = new Date(endTimeStr);
          if (!isNaN(parsed.getTime())) {
            endMs = parsed.getTime();
          }
        }

        // Default: endTime = startTime + 1h
        if (startMs > 0 && endMs === 0) {
          endMs = startMs + 3600000;
        }
        // Skip items without valid time
        if (startMs === 0) {
          this.log.warn(this.TAG, `Skipping action item "${title}" — no valid startTime`);
          continue;
        }

        actionItems.push({
          title: title,
          startTime: startMs,
          endTime: endMs,
          location: location,
          reminder: typeof reminder === 'number' ? reminder : 15,
          created: false,
          eventId: 0
        });
      }

      this.log.info(this.TAG, `Parsed ${actionItems.length} valid action items`);
      return actionItems;
    } catch (err) {
      this.log.warn(this.TAG, `extractActionItems error: ${(err as Error).message ?? ''}`);
      return [];
    }
  }

  /**
   * Create calendar events from extracted action items using CalendarCapability.
   */
  private async createCalendarEvents(items: ActionItem[]): Promise<void> {
    if (!this.context || items.length === 0) return;

    let calCap = new CalendarCapability();
    calCap.setContext(this.context);

    for (let item of items) {
      try {
        let params = JSON.stringify({
          title: item.title,
          startTime: item.startTime,
          endTime: item.endTime,
          location: item.location,
          reminderTime: [item.reminder]
        });
        let resultStr = await calCap.execute(params);
        let result = JSON.parse(resultStr) as Record<string, boolean | number>;
        if (result['ok'] as boolean) {
          item.created = true;
          item.eventId = (result['eventId'] as number) ?? 0;
          this.log.info(this.TAG, `Calendar event created: ${item.title} (id=${item.eventId})`);
        } else {
          this.log.warn(this.TAG, `Calendar event failed for "${item.title}": ${resultStr}`);
        }
      } catch (err) {
        this.log.warn(this.TAG, `Failed to create calendar event "${item.title}": ${(err as Error).message ?? ''}`);
      }
    }
  }

  getCurrentRecord(): SilentConversationRecord | undefined {
    return this.currentRecord;
  }
}
