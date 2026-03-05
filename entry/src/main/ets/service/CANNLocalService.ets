import { LogService } from '../common/LogService';
import { common } from '@kit.AbilityKit';
import { loadmodel, isInitialized, getLastError, answerget, modelinfer, deinitmodel, CANNConfig } from 'libcann_llm.so';

export { CANNConfig } from 'libcann_llm.so';

export interface CANNMessage {
  role: 'user' | 'assistant';
  content: string;
}

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

    this.log.info(this.TAG, `infer: START prompt length=${prompt.length}`);
    
    this.accumulatedText = '';
    this.tokenCallback = onToken || null;
    this.doneCallback = onDone || null;

    return new Promise((resolve, reject) => {
      try {
        this.log.info(this.TAG, 'infer: calling answerget...');
        answerget((token: string) => {
          this.accumulatedText += token;
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

  buildCANNSystemPrompt(originalSystemPrompt: string): string {
    const d = new Date();
    const tz = -(d.getTimezoneOffset() / 60);
    const tzStr = `UTC${tz >= 0 ? '+' : ''}${tz}`;
    const now = `${d.getFullYear()}-${(d.getMonth()+1).toString().padStart(2,'0')}-${d.getDate().toString().padStart(2,'0')} ${d.getHours().toString().padStart(2,'0')}:${d.getMinutes().toString().padStart(2,'0')} ${tzStr}`;

    let soulText = this.extractSoulText(originalSystemPrompt);

    let base = `你是 ClawdBot，运行在 HarmonyOS 上的个人 AI 助手。

## 角色设定
${soulText}

## 回复风格
- 极简回复，1-2句话
- 直接给答案，不说废话
- 不要用 markdown 格式，用纯文本回复

## 当前信息
时间：${now}
平台：HarmonyOS
模式：本地推理

## 记忆系统
你有持久记忆能力，可以跨对话保存信息。

### 何时保存记忆：
- 用户分享个人信息：名字、生日、工作、爱好、住址
- 用户表达偏好：语言、沟通风格、喜好
- 用户给出指令："以后都要..."、"永远不要..."

### 何时回忆记忆：
- 回答可能与过去信息相关的问题时
- 用户提到以前说过的事情时
- 需要用户偏好或事实时

### 记忆规则：
- 主动保存：用户说"我叫小明"时自动保存
- 不保存临时信息：天气查询、一次性计算
- 保存时在回复中说明：[已记住: ...]
`;

    let memoryBlock = this.extractMemoryBlock(originalSystemPrompt);
    if (memoryBlock.length > 0) {
      base += `\n## 已保存的记忆\n${memoryBlock}\n`;
    }

    let relevantMemories = this.extractRelevantMemories(originalSystemPrompt);
    if (relevantMemories.length > 0) {
      base += `\n## 当前相关记忆\n${relevantMemories}\n`;
    }

    return base;
  }

  private extractSoulText(systemPrompt: string): string {
    const soulMatch = systemPrompt.match(/## Soul\s*\n([\s\S]*?)(?=\n##|$)/);
    return soulMatch ? soulMatch[1].trim() : '我是一个乐于助人的 AI 助手。';
  }

  private extractMemoryBlock(systemPrompt: string): string {
    const memMatch = systemPrompt.match(/<memory>([\s\S]*?)<\/memory>/);
    return memMatch ? memMatch[1].trim() : '';
  }

  private extractRelevantMemories(systemPrompt: string): string {
    const relMatch = systemPrompt.match(/<relevant-memories>([\s\S]*?)<\/relevant-memories>/);
    return relMatch ? relMatch[1].trim() : '';
  }

  formatMultiTurnPrompt(messages: CANNMessage[], systemPrompt: string): string {
    let prompt = systemPrompt + '\n\n';
    
    prompt += '<s>';
    
    for (const msg of messages) {
      if (msg.role === 'user') {
        prompt += `[unused9]用户：${msg.content}[unused10]`;
      } else if (msg.role === 'assistant') {
        prompt += `[unused9]助手：${msg.content}`;
      }
    }
    
    prompt += '[unused9]助手：';
    
    return prompt;
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
