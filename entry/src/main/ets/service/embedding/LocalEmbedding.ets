import { common } from '@kit.AbilityKit';
import { LocalTokenizer } from './LocalTokenizer';
import { LocalTransformer } from './LocalTransformer';
import { LogService } from '../../common/LogService';
import { Constants } from '../../common/Constants';

export class LocalEmbedding {
  private static instance: LocalEmbedding | undefined = undefined;
  private tokenizer: LocalTokenizer | undefined = undefined;
  private transformer: LocalTransformer | undefined = undefined;
  private loaded: boolean = false;
  private loading: boolean = false;
  private log: LogService = LogService.getInstance();
  private readonly TAG = 'LocalEmbedding';

  static getInstance(): LocalEmbedding {
    if (!LocalEmbedding.instance) {
      LocalEmbedding.instance = new LocalEmbedding();
    }
    return LocalEmbedding.instance;
  }

  async init(context: common.Context): Promise<boolean> {
    if (this.loaded) return true;
    if (this.loading) return false;
    this.loading = true;
    try {
      let t0 = Date.now();
      this.tokenizer = new LocalTokenizer();
      await this.tokenizer.load(context);
      this.transformer = new LocalTransformer();
      await this.transformer.load(context);
      this.loaded = true;
      this.log.info(this.TAG, `Local embedding model loaded in ${Date.now() - t0}ms`);
      return true;
    } catch (e) {
      this.log.warn(this.TAG, `Failed to load model: ${(e as Error).message ?? String(e)}`);
      this.loaded = false;
      return false;
    } finally {
      this.loading = false;
    }
  }

  isReady(): boolean {
    return this.loaded;
  }

  async embed(text: string): Promise<number[]> {
    if (!this.loaded || !this.tokenizer || !this.transformer) return [];
    try {
      let t0 = Date.now();
      let encoded = this.tokenizer.encode(text);
      let vec = this.transformer.forward(encoded.inputIds, encoded.attentionMask, encoded.tokenTypeIds);
      let elapsed = Date.now() - t0;
      this.log.info(this.TAG, `embed: ${elapsed}ms, dim=${vec.length}, text="${text.substring(0, 40)}"`);
      return Array.from(vec);
    } catch (e) {
      this.log.warn(this.TAG, `embed failed: ${(e as Error).message ?? String(e)}`);
      return [];
    }
  }

  getDimension(): number {
    return Constants.LOCAL_EMBEDDING_DIM;
  }

  getModelName(): string {
    return Constants.LOCAL_EMBEDDING_MODEL;
  }
}
