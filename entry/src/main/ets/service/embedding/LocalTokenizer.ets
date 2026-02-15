import { common } from '@kit.AbilityKit';
import { LogService } from '../../common/LogService';

export interface TokenizerOutput {
  inputIds: Int32Array;
  attentionMask: Int32Array;
  tokenTypeIds: Int32Array;
}

interface TokenizerConfig {
  cls_token_id: number;
  sep_token_id: number;
  pad_token_id: number;
  unk_token_id: number;
  max_length: number;
  do_lower_case: boolean;
}

export class LocalTokenizer {
  private vocab: Map<string, number> = new Map();
  private config: TokenizerConfig = {
    cls_token_id: 101,
    sep_token_id: 102,
    pad_token_id: 0,
    unk_token_id: 100,
    max_length: 128,
    do_lower_case: true,
  };
  private loaded: boolean = false;
  private log: LogService = LogService.getInstance();
  private readonly TAG = 'LocalTokenizer';

  async load(context: common.Context): Promise<void> {
    let rm = (context as common.UIAbilityContext).resourceManager;

    // Load vocabulary
    let vocabRaw = rm.getRawFileContentSync('model/vocab.json');
    let vocabStr = String.fromCharCode(...new Uint8Array(vocabRaw.buffer));
    let vocabObj = JSON.parse(vocabStr) as Record<string, number>;
    this.vocab = new Map<string, number>();
    let keys = Object.keys(vocabObj);
    for (let key of keys) {
      this.vocab.set(key, vocabObj[key]);
    }

    // Load tokenizer config
    let tokRaw = rm.getRawFileContentSync('model/tokenizer.json');
    let tokStr = String.fromCharCode(...new Uint8Array(tokRaw.buffer));
    this.config = JSON.parse(tokStr) as TokenizerConfig;

    this.loaded = true;
    this.log.info(this.TAG, `Loaded vocab: ${this.vocab.size} tokens, maxLen=${this.config.max_length}`);
  }

  encode(text: string): TokenizerOutput {
    let maxLen = this.config.max_length;

    // 1. Normalize & basic tokenize
    let tokens = this.basicTokenize(text);

    // 2. WordPiece sub-tokenization
    let wpTokens: string[] = [];
    for (let token of tokens) {
      let subTokens = this.wordPieceTokenize(token);
      for (let st of subTokens) {
        wpTokens.push(st);
      }
    }

    // 3. Truncate to max_length - 2 (for [CLS] and [SEP])
    if (wpTokens.length > maxLen - 2) {
      wpTokens = wpTokens.slice(0, maxLen - 2);
    }

    // 4. Convert to IDs: [CLS] + tokens + [SEP] + padding
    let seqLen = wpTokens.length + 2;
    let inputIds = new Int32Array(maxLen);
    let attentionMask = new Int32Array(maxLen);
    let tokenTypeIds = new Int32Array(maxLen);

    inputIds[0] = this.config.cls_token_id;
    attentionMask[0] = 1;
    for (let i = 0; i < wpTokens.length; i++) {
      let id = this.vocab.get(wpTokens[i]);
      inputIds[i + 1] = id !== undefined ? id : this.config.unk_token_id;
      attentionMask[i + 1] = 1;
    }
    inputIds[seqLen - 1] = this.config.sep_token_id;
    attentionMask[seqLen - 1] = 1;
    // Remaining positions stay 0 (pad_token_id=0, mask=0, type=0)

    return { inputIds, attentionMask, tokenTypeIds };
  }

  private basicTokenize(text: string): string[] {
    if (this.config.do_lower_case) {
      text = text.toLowerCase();
    }

    // Strip accents
    text = this.stripAccents(text);

    // Insert spaces around CJK characters and punctuation
    let output = '';
    for (let i = 0; i < text.length; i++) {
      let cp = text.charCodeAt(i);
      if (this.isCJK(cp)) {
        output += ' ' + text[i] + ' ';
      } else if (this.isPunctuation(cp)) {
        output += ' ' + text[i] + ' ';
      } else if (this.isWhitespace(cp)) {
        output += ' ';
      } else if (cp === 0 || cp === 0xFFFD || this.isControl(cp)) {
        // Skip control chars
      } else {
        output += text[i];
      }
    }

    // Split on whitespace and filter empties
    let tokens: string[] = [];
    let parts = output.split(' ');
    for (let part of parts) {
      if (part.length > 0) {
        tokens.push(part);
      }
    }
    return tokens;
  }

  private wordPieceTokenize(word: string): string[] {
    if (word.length === 0) return [];

    let tokens: string[] = [];
    let start = 0;

    while (start < word.length) {
      let end = word.length;
      let found = false;

      while (start < end) {
        let substr = word.substring(start, end);
        if (start > 0) {
          substr = '##' + substr;
        }
        if (this.vocab.has(substr)) {
          tokens.push(substr);
          found = true;
          break;
        }
        end--;
      }

      if (!found) {
        tokens.push('[UNK]');
        break;
      }
      start = end;
    }

    return tokens;
  }

  private stripAccents(text: string): string {
    // Use NFKD normalization to decompose accented characters
    let normalized = text.normalize('NFKD');
    let result = '';
    for (let i = 0; i < normalized.length; i++) {
      let cp = normalized.charCodeAt(i);
      // Unicode category Mn (Mark, Nonspacing) - combining diacritical marks
      if (cp >= 0x0300 && cp <= 0x036F) continue;
      if (cp >= 0x1AB0 && cp <= 0x1AFF) continue;
      if (cp >= 0x1DC0 && cp <= 0x1DFF) continue;
      if (cp >= 0x20D0 && cp <= 0x20FF) continue;
      if (cp >= 0xFE20 && cp <= 0xFE2F) continue;
      result += normalized[i];
    }
    return result;
  }

  private isCJK(cp: number): boolean {
    return (cp >= 0x4E00 && cp <= 0x9FFF) ||
      (cp >= 0x3400 && cp <= 0x4DBF) ||
      (cp >= 0x20000 && cp <= 0x2A6DF) ||
      (cp >= 0x2A700 && cp <= 0x2B73F) ||
      (cp >= 0x2B740 && cp <= 0x2B81F) ||
      (cp >= 0x2B820 && cp <= 0x2CEAF) ||
      (cp >= 0xF900 && cp <= 0xFAFF) ||
      (cp >= 0x2F800 && cp <= 0x2FA1F);
  }

  private isPunctuation(cp: number): boolean {
    if ((cp >= 33 && cp <= 47) || (cp >= 58 && cp <= 64) ||
      (cp >= 91 && cp <= 96) || (cp >= 123 && cp <= 126)) {
      return true;
    }
    // CJK punctuation ranges
    if (cp >= 0x3000 && cp <= 0x303F) return true;
    if (cp >= 0xFF00 && cp <= 0xFFEF) return true;
    return false;
  }

  private isWhitespace(cp: number): boolean {
    return cp === 32 || cp === 9 || cp === 10 || cp === 13 || cp === 0xA0;
  }

  private isControl(cp: number): boolean {
    if (cp === 9 || cp === 10 || cp === 13) return false;
    return (cp >= 0 && cp <= 31) || (cp >= 127 && cp <= 159);
  }
}
