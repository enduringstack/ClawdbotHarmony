/**
 * VoiceprintService - Speaker identification using libvoiceprint NAPI.
 *
 * Provides:
 * - Speaker enrollment (register voice samples)
 * - Speaker identification (1:N search)
 * - Speaker verification (1:1 match)
 *
 * All processing is local, no network required.
 */
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import voiceprint from 'libvoiceprint.so';

const TAG = '[VoiceprintService]';
const PREFS_NAME = 'voiceprint_db';
const PROFILES_KEY = 'voiceprint_profiles';

// Model path (relative to rawfile)
const MODEL_DIR = 'voiceprint';

// Types for NAPI module
interface SpeakerMatch {
  name: string;
  score: number;
}

export interface VoiceprintProfile {
  name: string;
  enrolledAt: number;
  sampleCount: number;
  embedding: number[];
}

interface VoiceprintStore {
  speakers: VoiceprintProfile[];
  version: number;
}

export interface IdentifyResult {
  speaker: string;
  score: number;
  confidence: 'high' | 'medium' | 'low' | 'unknown';
}

interface VerifyResult {
  match: boolean;
  score: number;
}

// Typed wrapper for NAPI functions
function napiInitModel(dir: string): boolean {
  return voiceprint.initModel(dir) as boolean;
}

function napiGetEmbeddingDim(): number {
  return voiceprint.getEmbeddingDim() as number;
}

function napiIsModelLoaded(): boolean {
  return voiceprint.isModelLoaded() as boolean;
}

function napiExtractEmbedding(samples: Float32Array, rate: number): Float32Array {
  return voiceprint.extractEmbedding(samples, rate) as Float32Array;
}

function napiRegisterSpeaker(name: string, embeddings: Float32Array[]): boolean {
  return voiceprint.registerSpeaker(name, embeddings) as boolean;
}

function napiRemoveSpeaker(name: string): boolean {
  return voiceprint.removeSpeaker(name) as boolean;
}

function napiContainsSpeaker(name: string): boolean {
  return voiceprint.containsSpeaker(name) as boolean;
}

function napiGetAllSpeakers(): string[] {
  return voiceprint.getAllSpeakers() as string[];
}

function napiIdentifySpeaker(emb: Float32Array, threshold: number): SpeakerMatch {
  return voiceprint.identifySpeaker(emb, threshold) as SpeakerMatch;
}

function napiVerifySpeaker(name: string, emb: Float32Array, threshold: number): boolean {
  return voiceprint.verifySpeaker(name, emb, threshold) as boolean;
}

function napiComputeSimilarity(emb1: Float32Array, emb2: Float32Array): number {
  return voiceprint.computeSimilarity(emb1, emb2) as number;
}

function napiImportSpeakerEmbedding(name: string, emb: Float32Array): boolean {
  return voiceprint.importSpeakerEmbedding(name, emb) as boolean;
}

export class VoiceprintService {
  private static instance: VoiceprintService | null = null;
  private initialized: boolean = false;
  private store: preferences.Preferences | null = null;
  private profiles: VoiceprintProfile[] = [];

  // Thresholds
  private readonly IDENTIFY_THRESHOLD = 0.5;
  private readonly HIGH_CONFIDENCE = 0.75;
  private readonly MEDIUM_CONFIDENCE = 0.6;
  private readonly LOW_CONFIDENCE = 0.45;
  private readonly MIN_DURATION_SEC = 0.5;

  static getInstance(): VoiceprintService {
    if (!VoiceprintService.instance) {
      VoiceprintService.instance = new VoiceprintService();
    }
    return VoiceprintService.instance;
  }

  isInitialized(): boolean {
    return this.initialized;
  }

  async init(context: common.UIAbilityContext): Promise<boolean> {
    if (this.initialized) return true;

    try {
      this.store = await preferences.getPreferences(context, PREFS_NAME);

      // Initialize native model
      const ok: boolean = napiInitModel(MODEL_DIR);
      if (!ok) {
        console.error(TAG, 'Failed to init voiceprint model');
        return false;
      }

      const dim: number = napiGetEmbeddingDim();
      console.info(TAG, `Model loaded. Embedding dim: ${dim}`);

      // Restore persisted profiles
      await this.restoreProfiles();

      this.initialized = true;
      console.info(TAG, `Initialized. ${this.profiles.length} speaker(s) loaded.`);
      return true;
    } catch (error) {
      const e: BusinessError = error as BusinessError;
      console.error(TAG, `Init failed: ${e.message}`);
      return false;
    }
  }

  extractEmbedding(samples: Float32Array, sampleRate: number): Float32Array | null {
    if (!this.initialized || !napiIsModelLoaded()) {
      console.error(TAG, 'Service not initialized');
      return null;
    }

    const duration: number = samples.length / sampleRate;
    if (duration < this.MIN_DURATION_SEC) {
      console.warn(TAG, `Audio too short: ${duration.toFixed(2)}s`);
      return null;
    }

    try {
      const result: Float32Array = napiExtractEmbedding(samples, sampleRate);
      return result;
    } catch (error) {
      const e: BusinessError = error as BusinessError;
      console.error(TAG, `extractEmbedding error: ${e.message}`);
      return null;
    }
  }

  async enrollSpeaker(name: string, audioSamples: Float32Array[], sampleRate: number = 16000): Promise<boolean> {
    if (!this.initialized) return false;
    if (audioSamples.length === 0) return false;

    try {
      const embeddings: Float32Array[] = [];
      for (const samples of audioSamples) {
        const emb: Float32Array | null = this.extractEmbedding(samples, sampleRate);
        if (emb && emb.length > 0) {
          embeddings.push(emb);
        }
      }

      if (embeddings.length === 0) {
        console.error(TAG, 'No valid embeddings extracted');
        return false;
      }

      // Remove existing if any
      if (napiContainsSpeaker(name)) {
        napiRemoveSpeaker(name);
      }

      // Register with native
      const ok: boolean = napiRegisterSpeaker(name, embeddings);
      if (!ok) {
        console.error(TAG, `Failed to register speaker "${name}"`);
        return false;
      }

      // Compute average for persistence
      const avgEmbedding: Float32Array = this.averageEmbeddings(embeddings);

      const profile: VoiceprintProfile = {
        name: name,
        enrolledAt: Date.now(),
        sampleCount: embeddings.length,
        embedding: Array.from(avgEmbedding),
      };

      this.profiles = this.profiles.filter((p: VoiceprintProfile): boolean => p.name !== name);
      this.profiles.push(profile);
      await this.saveProfiles();

      console.info(TAG, `Enrolled speaker "${name}" with ${embeddings.length} sample(s)`);
      return true;
    } catch (error) {
      const e: BusinessError = error as BusinessError;
      console.error(TAG, `enrollSpeaker error: ${e.message}`);
      return false;
    }
  }

  identify(samples: Float32Array, sampleRate: number = 16000, threshold?: number): IdentifyResult {
    const unknown: IdentifyResult = { speaker: '', score: 0, confidence: 'unknown' };
    if (!this.initialized) return unknown;

    const actualThreshold: number = threshold ?? this.IDENTIFY_THRESHOLD;

    try {
      const embedding: Float32Array | null = this.extractEmbedding(samples, sampleRate);
      if (!embedding || embedding.length === 0) return unknown;

      const match: SpeakerMatch = napiIdentifySpeaker(embedding, actualThreshold);
      if (!match.name || match.name === '') return unknown;

      let confidence: 'high' | 'medium' | 'low' | 'unknown';
      if (match.score >= this.HIGH_CONFIDENCE) {
        confidence = 'high';
      } else if (match.score >= this.MEDIUM_CONFIDENCE) {
        confidence = 'medium';
      } else if (match.score >= this.LOW_CONFIDENCE) {
        confidence = 'low';
      } else {
        confidence = 'unknown';
      }

      return { speaker: match.name, score: match.score, confidence };
    } catch (error) {
      const e: BusinessError = error as BusinessError;
      console.error(TAG, `identify error: ${e.message}`);
      return unknown;
    }
  }

  verify(name: string, samples: Float32Array, sampleRate: number = 16000, threshold?: number): VerifyResult {
    const fail: VerifyResult = { match: false, score: 0 };
    if (!this.initialized) return fail;

    const actualThreshold: number = threshold ?? this.MEDIUM_CONFIDENCE;

    try {
      const embedding: Float32Array | null = this.extractEmbedding(samples, sampleRate);
      if (!embedding || embedding.length === 0) return fail;

      const match: boolean = napiVerifySpeaker(name, embedding, actualThreshold);
      const score: number = this.getSpeakerScore(name, embedding);

      return { match, score };
    } catch (error) {
      const e: BusinessError = error as BusinessError;
      console.error(TAG, `verify error: ${e.message}`);
      return fail;
    }
  }

  async removeSpeaker(name: string): Promise<boolean> {
    if (!this.initialized) return false;

    try {
      napiRemoveSpeaker(name);
      this.profiles = this.profiles.filter((p: VoiceprintProfile): boolean => p.name !== name);
      await this.saveProfiles();
      console.info(TAG, `Removed speaker "${name}"`);
      return true;
    } catch (error) {
      const e: BusinessError = error as BusinessError;
      console.error(TAG, `removeSpeaker error: ${e.message}`);
      return false;
    }
  }

  listSpeakers(): VoiceprintProfile[] {
    return this.profiles.slice();
  }

  getAllSpeakerNames(): string[] {
    return napiGetAllSpeakers();
  }

  getSpeakerCount(): number {
    return this.profiles.length;
  }

  containsSpeaker(name: string): boolean {
    return napiContainsSpeaker(name);
  }

  getEmbeddingDim(): number {
    return napiGetEmbeddingDim();
  }

  // ---- Private Methods ----

  private getSpeakerScore(name: string, embedding: Float32Array): number {
    const profile: VoiceprintProfile | undefined = this.profiles.find((p: VoiceprintProfile): boolean => p.name === name);
    if (!profile || !profile.embedding || profile.embedding.length === 0) return 0;

    const stored: Float32Array = new Float32Array(profile.embedding);
    return napiComputeSimilarity(embedding, stored);
  }

  private averageEmbeddings(embeddings: Float32Array[]): Float32Array {
    if (embeddings.length === 0) return new Float32Array(0);

    const dim: number = embeddings[0].length;
    const avg: Float32Array = new Float32Array(dim);

    for (const emb of embeddings) {
      for (let i = 0; i < dim; i++) {
        avg[i] += emb[i];
      }
    }

    for (let i = 0; i < dim; i++) {
      avg[i] /= embeddings.length;
    }

    return avg;
  }

  private async saveProfiles(): Promise<void> {
    if (!this.store) return;
    const data: VoiceprintStore = {
      speakers: this.profiles,
      version: 1,
    };
    await this.store.put(PROFILES_KEY, JSON.stringify(data));
    await this.store.flush();
  }

  private async restoreProfiles(): Promise<void> {
    if (!this.store) return;

    try {
      const raw: string = await this.store.get(PROFILES_KEY, '') as string;
      if (!raw || raw.length === 0) {
        this.profiles = [];
        return;
      }

      const data: VoiceprintStore = JSON.parse(raw) as VoiceprintStore;
      this.profiles = data.speakers || [];

      // Restore each speaker into native
      for (const profile of this.profiles) {
        if (profile.embedding && profile.embedding.length > 0) {
          const emb: Float32Array = new Float32Array(profile.embedding);
          napiImportSpeakerEmbedding(profile.name, emb);
        }
      }

      console.info(TAG, `Restored ${this.profiles.length} speaker profile(s)`);
    } catch (error) {
      const e: BusinessError = error as BusinessError;
      console.error(TAG, `restoreProfiles error: ${e.message}`);
      this.profiles = [];
    }
  }
}
