import { LogService } from '../common/LogService';
import { common } from '@kit.AbilityKit';
import { loadmodel, isInitialized, getLastError, answerget, modelinfer, deinitmodel, CANNConfig } from 'libcann_llm.so';

export { CANNConfig } from 'libcann_llm.so';

export class CANNLocalService {
  private static instance: CANNLocalService | undefined = undefined;
  private log: LogService = LogService.getInstance();
  private readonly TAG = 'CANNLocalService';
  private initialized: boolean = false;
  private initializing: boolean = false;
  private lastError: string = '';
  private tokenCallback: ((token: string) => void) | null = null;
  private doneCallback: (() => void) | null = null;
  private accumulatedText: string = '';

  static getInstance(): CANNLocalService {
    if (!CANNLocalService.instance) {
      CANNLocalService.instance = new CANNLocalService();
    }
    return CANNLocalService.instance;
  }

  isInitialized(): boolean {
    return this.initialized;
  }

  getLastError(): string {
    return this.lastError;
  }

  async init(config: CANNConfig): Promise<boolean> {
    if (this.initialized) {
      this.log.info(this.TAG, 'Already initialized');
      return true;
    }

    if (this.initializing) {
      this.log.warn(this.TAG, 'Initialization already in progress');
      return false;
    }

    this.initializing = true;
    this.log.info(this.TAG, `init: START with modelPath=${config.modelPath}`);
    this.log.info(this.TAG, `init: weightDir=${config.weightDir}`);
    this.log.info(this.TAG, `init: specModelPath=${config.specModelPath}`);

    try {
      this.log.info(this.TAG, 'init: calling loadmodel...');
      const result: string = loadmodel(config);
      this.log.info(this.TAG, `init: loadmodel result: ${result}`);

      this.initialized = isInitialized();
      this.log.info(this.TAG, `init: isInitialized=${this.initialized}`);
      
      if (!this.initialized) {
        this.lastError = getLastError() || result;
        this.log.error(this.TAG, `init: failed: ${this.lastError}`);
      } else {
        this.log.info(this.TAG, 'init: SUCCESS');
      }

      this.initializing = false;
      return this.initialized;
    } catch (e) {
      const err = e as Error;
      this.lastError = `Init error: ${err.message}`;
      this.log.error(this.TAG, `init: exception: ${this.lastError}`);
      this.initializing = false;
      return false;
    }
  }

  async infer(prompt: string, onToken?: (token: string) => void, onDone?: () => void): Promise<string> {
    if (!this.initialized) {
      this.log.error(this.TAG, 'infer: not initialized');
      throw new Error('CANN LLM not initialized');
    }

    this.log.info(this.TAG, `infer: START prompt="${prompt.substring(0, 100)}..."`);
    
    this.accumulatedText = '';
    this.tokenCallback = onToken || null;
    this.doneCallback = onDone || null;

    return new Promise((resolve, reject) => {
      try {
        this.log.info(this.TAG, 'infer: calling answerget...');
        answerget((token: string) => {
          this.accumulatedText += token;
          this.log.info(this.TAG, `infer: received token="${token}"`);
          if (this.tokenCallback) {
            this.tokenCallback(token);
          }
        });

        this.log.info(this.TAG, 'infer: calling modelinfer...');
        modelinfer(prompt);

        const checkDone = () => {
          setTimeout(() => {
            this.log.info(this.TAG, `infer: DONE, total length=${this.accumulatedText.length}`);
            if (this.doneCallback) {
              this.doneCallback();
            }
            resolve(this.accumulatedText);
          }, 500);
        };
        checkDone();

      } catch (e) {
        const err = e as Error;
        this.log.error(this.TAG, `infer: exception ${err.message}`);
        reject(e);
      }
    });
  }

  async inferSync(prompt: string): Promise<string> {
    if (!this.initialized) {
      throw new Error('CANN LLM not initialized');
    }

    this.log.info(this.TAG, `inferSync: prompt="${prompt.substring(0, 100)}..."`);

    return new Promise((resolve, reject) => {
      try {
        this.accumulatedText = '';

        answerget((token: string) => {
          this.accumulatedText += token;
        });

        modelinfer(prompt);

        setTimeout(() => {
          resolve(this.accumulatedText);
        }, 1000);

      } catch (e) {
        const err = e as Error;
        this.log.error(this.TAG, `inferSync error: ${err.message}`);
        reject(e);
      }
    });
  }

  deinit(): void {
    if (!this.initialized) {
      return;
    }

    this.log.info(this.TAG, 'Deinitializing CANN LLM');

    try {
      deinitmodel();
    } catch (e) {
      const err = e as Error;
      this.log.error(this.TAG, `deinit error: ${err.message}`);
    }

    this.initialized = false;
    this.accumulatedText = '';
    this.tokenCallback = null;
    this.doneCallback = null;
  }

  formatPrompt(userMessage: string): string {
    return `<s>[unused9]用户：${userMessage}[unused10][unused9]助手：`;
  }

  getDefaultConfig(context: common.UIAbilityContext): CANNConfig {
    const sandboxPath = context.filesDir;
    
    return {
      modelPath: `${sandboxPath}/chs_7b_target_model/chs_7b_target_model.omc`,
      weightDir: `${sandboxPath}/chs_7b_target_model`,
      tokenizerPath: `${sandboxPath}/chs_7b_target_model/tokenizer.model`,
      specModelPath: `${sandboxPath}/chs_7b_draft_model/chs_7b_draft_model.omc`,
      specWeightDir: `${sandboxPath}/chs_7b_draft_model`,
      loraCfgPath: `${sandboxPath}/chs_7b_target_model/chs_7b_target_model.omc.loraconf`,
      maxGenTokens: 512,
      temperature: 0.7
    };
  }
}
