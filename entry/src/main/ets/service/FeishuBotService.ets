/**
 * Feishu (Lark) Bot Service — singleton.
 *
 * Connects to Feishu via WebSocket long-connection (protobuf binary frames).
 * Flow:
 *   1. POST tenant_access_token/internal → get token
 *   2. POST callback/ws/endpoint → get WSS URL
 *   3. webSocket.createWebSocket() → connect, ping/pong, receive events
 *
 * Protobuf codec is hand-rolled (minimal: Frame + Header only).
 */
import { webSocket } from '@kit.NetworkKit';
import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { fileIo } from '@kit.CoreFileKit';
import { Constants } from '../common/Constants';
import { LogService } from '../common/LogService';

const TAG = 'FeishuBot';

// ======================== Interfaces ========================

interface FeishuHeader {
  key: string;
  value: string;
}

interface FeishuFrame {
  seqId: number;
  logId: number;
  service: number;
  method: number;
  headers: FeishuHeader[];
  payloadEncoding: string;
  payloadType: string;
  payload: Uint8Array;
  logIdNew: string;
}

interface VarintResult {
  value: number;
  bytesRead: number;
}

interface LengthDelimitedResult {
  data: Uint8Array;
  bytesRead: number;
}

interface TokenResponse {
  code: number;
  msg: string;
  tenant_access_token: string;
  expire: number;
}

interface WsEndpointResponse {
  code: number;
  msg: string;
  data: WsEndpointData;
}

interface WsEndpointData {
  URL: string;
  ClientConfig: ClientConfig;
}

interface ClientConfig {
  ReconnectCount: number;
  ReconnectInterval: number;
  ReconnectNonce: number;
  PingInterval: number;
}

interface FeishuEventWrapper {
  schema: string;
  header: FeishuEventHeader;
  event: FeishuEventBody;
}

interface FeishuEventHeader {
  event_id: string;
  event_type: string;
  create_time: string;
  token: string;
  app_id: string;
  tenant_key: string;
}

interface FeishuEventBody {
  sender: FeishuSender;
  message: FeishuMessage;
}

interface FeishuSender {
  sender_id: FeishuSenderId;
  sender_type: string;
  tenant_key: string;
}

interface FeishuSenderId {
  union_id: string;
  user_id: string;
  open_id: string;
}

interface FeishuMessage {
  message_id: string;
  root_id: string;
  parent_id: string;
  create_time: string;
  chat_id: string;
  chat_type: string;
  message_type: string;
  content: string;
}

interface FeishuTextContent {
  text: string;
}

interface FeishuImageUploadResp {
  code: number;
  msg: string;
  data: FeishuImageData;
}

interface FeishuImageData {
  image_key: string;
}

// ======================== Protobuf Codec ========================

function readVarint(buf: Uint8Array, offset: number): VarintResult {
  // Supports up to 64-bit varint (10 bytes). We only keep the low 32 bits
  // but must consume all bytes to keep the decoder in sync.
  let value = 0;
  let shift = 0;
  let pos = offset;
  while (pos < buf.length) {
    let b = buf[pos];
    // Only apply bits that fit in 32-bit range (shift < 28 avoids JS bitwise overflow)
    if (shift < 28) {
      value |= (b & 0x7F) << shift;
    }
    pos++;
    if ((b & 0x80) === 0) {
      break;
    }
    shift += 7;
    if (shift >= 70) {
      break; // max 10 bytes for 64-bit varint
    }
  }
  return { value: value >>> 0, bytesRead: pos - offset };
}

function writeVarint(value: number): Uint8Array {
  let bytes: number[] = [];
  let v = value >>> 0; // ensure unsigned 32-bit
  while (v > 0x7F) {
    bytes.push((v & 0x7F) | 0x80);
    v = v >>> 7;
  }
  bytes.push(v & 0x7F);
  return new Uint8Array(bytes);
}

function readLengthDelimited(buf: Uint8Array, offset: number): LengthDelimitedResult {
  let lenResult = readVarint(buf, offset);
  let dataLen = lenResult.value;
  let dataStart = offset + lenResult.bytesRead;
  let data = buf.slice(dataStart, dataStart + dataLen);
  return { data: data, bytesRead: lenResult.bytesRead + dataLen };
}

function decodeHeader(buf: Uint8Array): FeishuHeader {
  let key = '';
  let value = '';
  let pos = 0;
  while (pos < buf.length) {
    let tagResult = readVarint(buf, pos);
    pos += tagResult.bytesRead;
    let fieldNumber = tagResult.value >>> 3;
    let wireType = tagResult.value & 0x07;
    if (wireType === 2) { // length-delimited
      let ldResult = readLengthDelimited(buf, pos);
      pos += ldResult.bytesRead;
      let str = uint8ArrayToString(ldResult.data);
      if (fieldNumber === 1) {
        key = str;
      } else if (fieldNumber === 2) {
        value = str;
      }
    } else if (wireType === 0) { // varint — skip
      let vr = readVarint(buf, pos);
      pos += vr.bytesRead;
    } else {
      break; // unknown wire type
    }
  }
  return { key: key, value: value };
}

function decodeFrame(buffer: ArrayBuffer): FeishuFrame {
  let buf = new Uint8Array(buffer);
  let frame: FeishuFrame = {
    seqId: 0,
    logId: 0,
    service: 0,
    method: 0,
    headers: [],
    payloadEncoding: '',
    payloadType: '',
    payload: new Uint8Array(0),
    logIdNew: '',
  };
  let pos = 0;
  while (pos < buf.length) {
    let tagResult = readVarint(buf, pos);
    if (tagResult.bytesRead === 0) break;
    pos += tagResult.bytesRead;
    let fieldNumber = tagResult.value >>> 3;
    let wireType = tagResult.value & 0x07;

    if (wireType === 0) { // varint
      let valResult = readVarint(buf, pos);
      pos += valResult.bytesRead;
      if (fieldNumber === 1) frame.seqId = valResult.value;
      else if (fieldNumber === 2) frame.logId = valResult.value;
      else if (fieldNumber === 3) frame.service = valResult.value;
      else if (fieldNumber === 4) frame.method = valResult.value;
    } else if (wireType === 2) { // length-delimited
      let ldResult = readLengthDelimited(buf, pos);
      pos += ldResult.bytesRead;
      if (fieldNumber === 5) {
        frame.headers.push(decodeHeader(ldResult.data));
      } else if (fieldNumber === 6) {
        frame.payloadEncoding = uint8ArrayToString(ldResult.data);
      } else if (fieldNumber === 7) {
        frame.payloadType = uint8ArrayToString(ldResult.data);
      } else if (fieldNumber === 8) {
        frame.payload = ldResult.data;
      } else if (fieldNumber === 9) {
        frame.logIdNew = uint8ArrayToString(ldResult.data);
      }
    } else {
      // Unknown wire type — skip (best effort)
      break;
    }
  }
  return frame;
}

function encodeFrame(frame: FeishuFrame): ArrayBuffer {
  let parts: Uint8Array[] = [];

  // field 1: seqId (varint)
  if (frame.seqId > 0) {
    parts.push(writeVarint((1 << 3) | 0));
    parts.push(writeVarint(frame.seqId));
  }
  // field 2: logId (varint)
  if (frame.logId > 0) {
    parts.push(writeVarint((2 << 3) | 0));
    parts.push(writeVarint(frame.logId));
  }
  // field 3: service (varint)
  if (frame.service > 0) {
    parts.push(writeVarint((3 << 3) | 0));
    parts.push(writeVarint(frame.service));
  }
  // field 4: method (varint)
  if (frame.method > 0) {
    parts.push(writeVarint((4 << 3) | 0));
    parts.push(writeVarint(frame.method));
  }
  // field 5: headers (repeated, length-delimited)
  for (let h of frame.headers) {
    let headerBytes = encodeHeaderMsg(h);
    parts.push(writeVarint((5 << 3) | 2));
    parts.push(writeVarint(headerBytes.length));
    parts.push(headerBytes);
  }
  // field 6: payloadEncoding (length-delimited)
  if (frame.payloadEncoding.length > 0) {
    let bytes = stringToUint8Array(frame.payloadEncoding);
    parts.push(writeVarint((6 << 3) | 2));
    parts.push(writeVarint(bytes.length));
    parts.push(bytes);
  }
  // field 7: payloadType (length-delimited)
  if (frame.payloadType.length > 0) {
    let bytes = stringToUint8Array(frame.payloadType);
    parts.push(writeVarint((7 << 3) | 2));
    parts.push(writeVarint(bytes.length));
    parts.push(bytes);
  }
  // field 8: payload (length-delimited)
  if (frame.payload.length > 0) {
    parts.push(writeVarint((8 << 3) | 2));
    parts.push(writeVarint(frame.payload.length));
    parts.push(frame.payload);
  }
  // field 9: logIdNew (length-delimited)
  if (frame.logIdNew.length > 0) {
    let bytes = stringToUint8Array(frame.logIdNew);
    parts.push(writeVarint((9 << 3) | 2));
    parts.push(writeVarint(bytes.length));
    parts.push(bytes);
  }

  // Concatenate all parts
  let totalLen = 0;
  for (let p of parts) totalLen += p.length;
  let result = new Uint8Array(totalLen);
  let offset = 0;
  for (let p of parts) {
    result.set(p, offset);
    offset += p.length;
  }
  return result.buffer as ArrayBuffer;
}

function encodeHeaderMsg(h: FeishuHeader): Uint8Array {
  let parts: Uint8Array[] = [];
  if (h.key.length > 0) {
    let keyBytes = stringToUint8Array(h.key);
    parts.push(writeVarint((1 << 3) | 2));
    parts.push(writeVarint(keyBytes.length));
    parts.push(keyBytes);
  }
  if (h.value.length > 0) {
    let valBytes = stringToUint8Array(h.value);
    parts.push(writeVarint((2 << 3) | 2));
    parts.push(writeVarint(valBytes.length));
    parts.push(valBytes);
  }
  let totalLen = 0;
  for (let p of parts) totalLen += p.length;
  let result = new Uint8Array(totalLen);
  let off = 0;
  for (let p of parts) {
    result.set(p, off);
    off += p.length;
  }
  return result;
}

function uint8ArrayToString(arr: Uint8Array): string {
  // Manual UTF-8 decoder — avoids HarmonyOS TextDecoder issues with sliced Uint8Array
  let result: string[] = [];
  let i = 0;
  while (i < arr.length) {
    let b0 = arr[i];
    if (b0 < 0x80) {
      result.push(String.fromCharCode(b0));
      i++;
    } else if ((b0 & 0xE0) === 0xC0 && i + 1 < arr.length) {
      let cp = ((b0 & 0x1F) << 6) | (arr[i + 1] & 0x3F);
      result.push(String.fromCharCode(cp));
      i += 2;
    } else if ((b0 & 0xF0) === 0xE0 && i + 2 < arr.length) {
      let cp = ((b0 & 0x0F) << 12) | ((arr[i + 1] & 0x3F) << 6) | (arr[i + 2] & 0x3F);
      result.push(String.fromCharCode(cp));
      i += 3;
    } else if ((b0 & 0xF8) === 0xF0 && i + 3 < arr.length) {
      // Supplementary plane → surrogate pair
      let cp = ((b0 & 0x07) << 18) | ((arr[i + 1] & 0x3F) << 12) | ((arr[i + 2] & 0x3F) << 6) | (arr[i + 3] & 0x3F);
      cp -= 0x10000;
      result.push(String.fromCharCode(0xD800 + (cp >> 10), 0xDC00 + (cp & 0x3FF)));
      i += 4;
    } else {
      result.push(String.fromCharCode(b0));
      i++;
    }
  }
  return result.join('');
}

function stringToUint8Array(str: string): Uint8Array {
  let encoder = new util.TextEncoder();
  return encoder.encodeInto(str);
}

// ======================== Service ========================

export class FeishuBotService {
  private static instance: FeishuBotService | undefined = undefined;

  private log: LogService = LogService.getInstance();
  private ws: webSocket.WebSocket | undefined = undefined;
  private wsGeneration: number = 0;
  private tenantToken: string = '';
  private tokenExpiresAt: number = 0;
  private appId: string = '';
  private appSecret: string = '';
  private pingInterval: number = 120;
  private pingTimer: number = -1;
  private reconnectCount: number = 3;
  private reconnectAttempt: number = 0;
  private shouldReconnect: boolean = false;
  private wssUrl: string = '';
  private serviceId: number = 0;
  private seqCounter: number = 0;
  private processedMsgIds: Set<string> = new Set<string>();

  onStateChanged: ((state: string) => void) | undefined = undefined;
  onMessageReceived: ((sender: string, text: string, messageId: string, chatId: string) => void) | undefined = undefined;

  private _connected: boolean = false;

  static getInstance(): FeishuBotService {
    if (!FeishuBotService.instance) {
      FeishuBotService.instance = new FeishuBotService();
    }
    return FeishuBotService.instance;
  }

  isConnected(): boolean {
    return this._connected;
  }

  async connect(appId: string, appSecret: string): Promise<void> {
    this.appId = appId;
    this.appSecret = appSecret;
    this.shouldReconnect = true;
    this.reconnectAttempt = 0;
    this.log.info(TAG, `connect() appId=${appId}`);
    this.notifyState('connecting');
    try {
      await this.refreshToken();
      await this.fetchWsEndpoint();
      this.connectWs();
    } catch (e) {
      let msg = (e as Error).message ?? String(e);
      this.log.error(TAG, `connect failed: ${msg}`);
      this.notifyState('error');
      this.scheduleReconnect();
    }
  }

  disconnect(): void {
    this.log.info(TAG, 'disconnect()');
    this.shouldReconnect = false;
    this.stopPing();
    this.closeSocket();
    this._connected = false;
    this.notifyState('disconnected');
  }

  async replyMessage(messageId: string, text: string): Promise<void> {
    await this.ensureToken();
    let url = `${Constants.FEISHU_MSG_API}/${messageId}/reply`;
    let bodyObj: Record<string, string> = {
      'msg_type': 'text',
      'content': JSON.stringify({ text: text }),
    };
    let bodyStr = JSON.stringify(bodyObj);
    this.log.info(TAG, `replyMessage: ${messageId} text=${text.substring(0, 50)}`);

    let req = http.createHttp();
    try {
      let resp = await req.request(url, {
        method: http.RequestMethod.POST,
        header: {
          'Authorization': `Bearer ${this.tenantToken}`,
          'Content-Type': 'application/json; charset=utf-8',
        } as Record<string, string>,
        extraData: bodyStr,
      });
      this.log.info(TAG, `reply response: ${resp.responseCode} ${String(resp.result).substring(0, 200)}`);
    } finally {
      req.destroy();
    }
  }

  /**
   * Upload image to Feishu and reply with image message.
   * @param messageId - the message to reply to
   * @param imagePath - local file path of the image (JPEG)
   * @param caption - optional text to send alongside
   */
  async replyWithImage(messageId: string, imagePath: string, caption?: string): Promise<void> {
    await this.ensureToken();

    // Step 1: Read the image file
    let file = fileIo.openSync(imagePath, fileIo.OpenMode.READ_ONLY);
    let stat = fileIo.statSync(imagePath);
    let buf = new ArrayBuffer(stat.size);
    fileIo.readSync(file.fd, buf);
    fileIo.closeSync(file);
    this.log.info(TAG, `replyWithImage: read ${stat.size} bytes from ${imagePath}`);

    // Step 2: Upload image to Feishu via multipart/form-data
    let boundary = '----FeishuBoundary' + Date.now().toString();
    let imageBytes = new Uint8Array(buf);

    // Build multipart body
    let headerPart = `--${boundary}\r\nContent-Disposition: form-data; name="image_type"\r\n\r\nmessage\r\n--${boundary}\r\nContent-Disposition: form-data; name="image"; filename="image.jpg"\r\nContent-Type: image/jpeg\r\n\r\n`;
    let footerPart = `\r\n--${boundary}--\r\n`;

    let encoder = new util.TextEncoder();
    let headerBytes = encoder.encodeInto(headerPart);
    let footerBytes = encoder.encodeInto(footerPart);

    // Combine into single ArrayBuffer
    let totalLen = headerBytes.length + imageBytes.length + footerBytes.length;
    let combined = new Uint8Array(totalLen);
    combined.set(headerBytes, 0);
    combined.set(imageBytes, headerBytes.length);
    combined.set(footerBytes, headerBytes.length + imageBytes.length);

    let uploadReq = http.createHttp();
    let imageKey = '';
    try {
      let uploadResp = await uploadReq.request('https://open.feishu.cn/open-apis/im/v1/images', {
        method: http.RequestMethod.POST,
        header: {
          'Authorization': `Bearer ${this.tenantToken}`,
          'Content-Type': `multipart/form-data; boundary=${boundary}`,
        } as Record<string, string>,
        extraData: combined.buffer,
      });
      this.log.info(TAG, `upload image resp: ${uploadResp.responseCode} ${String(uploadResp.result).substring(0, 300)}`);
      if (uploadResp.responseCode === 200) {
        let parsed = JSON.parse(String(uploadResp.result)) as FeishuImageUploadResp;
        if (parsed.code === 0 && parsed.data && parsed.data.image_key) {
          imageKey = parsed.data.image_key;
        }
      }
    } finally {
      uploadReq.destroy();
    }

    if (imageKey.length === 0) {
      this.log.error(TAG, 'Image upload failed, falling back to text reply');
      await this.replyMessage(messageId, caption ?? '图片上传失败');
      return;
    }
    this.log.info(TAG, `Image uploaded: image_key=${imageKey}`);

    // Step 3: Reply with image message
    let url = `${Constants.FEISHU_MSG_API}/${messageId}/reply`;
    let bodyObj: Record<string, string> = {
      'msg_type': 'image',
      'content': JSON.stringify({ image_key: imageKey }),
    };
    let replyReq = http.createHttp();
    try {
      let resp = await replyReq.request(url, {
        method: http.RequestMethod.POST,
        header: {
          'Authorization': `Bearer ${this.tenantToken}`,
          'Content-Type': 'application/json; charset=utf-8',
        } as Record<string, string>,
        extraData: JSON.stringify(bodyObj),
      });
      this.log.info(TAG, `image reply resp: ${resp.responseCode} ${String(resp.result).substring(0, 200)}`);
    } finally {
      replyReq.destroy();
    }

    // Step 4: Also send caption if present
    if (caption && caption.length > 0) {
      await this.replyMessage(messageId, caption);
    }
  }

  /** Test connection only (get token + WS endpoint) without establishing persistent WS. */
  async testConnection(appId: string, appSecret: string): Promise<string> {
    this.appId = appId;
    this.appSecret = appSecret;
    await this.refreshToken();
    await this.fetchWsEndpoint();
    return this.wssUrl;
  }

  // ==================== Token ====================

  private async refreshToken(): Promise<void> {
    this.log.info(TAG, 'Refreshing tenant_access_token...');
    let req = http.createHttp();
    try {
      let bodyObj: Record<string, string> = {
        'app_id': this.appId,
        'app_secret': this.appSecret,
      };
      let resp = await req.request(Constants.FEISHU_TOKEN_URL, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json; charset=utf-8',
        } as Record<string, string>,
        expectDataType: http.HttpDataType.STRING,
        extraData: JSON.stringify(bodyObj),
      });
      this.log.info(TAG, `Token resp code=${resp.responseCode} type=${typeof resp.result}`);
      let resultStr = typeof resp.result === 'string' ? resp.result : JSON.stringify(resp.result);
      this.log.info(TAG, `Token resp body: ${resultStr.substring(0, 300)}`);
      if (resp.responseCode !== 200) {
        throw new Error(`token HTTP error: ${resp.responseCode}`);
      }
      let result = JSON.parse(resultStr) as TokenResponse;
      if (result.code !== 0) {
        throw new Error(`token error: code=${result.code} msg=${result.msg}`);
      }
      this.tenantToken = result.tenant_access_token;
      this.tokenExpiresAt = Date.now() + (result.expire - 300) * 1000; // refresh 5 min early
      this.log.info(TAG, `Token obtained, expires in ${result.expire}s`);
    } finally {
      req.destroy();
    }
  }

  private async ensureToken(): Promise<void> {
    if (Date.now() >= this.tokenExpiresAt) {
      await this.refreshToken();
    }
  }

  // ==================== WS Endpoint ====================

  private async fetchWsEndpoint(): Promise<void> {
    this.log.info(TAG, 'Fetching WS endpoint...');
    let req = http.createHttp();
    try {
      let bodyObj: Record<string, string> = {
        'AppID': this.appId,
        'AppSecret': this.appSecret,
      };
      let resp = await req.request(Constants.FEISHU_WS_ENDPOINT_URL, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json; charset=utf-8',
          'locale': 'zh',
        } as Record<string, string>,
        expectDataType: http.HttpDataType.STRING,
        extraData: JSON.stringify(bodyObj),
      });
      this.log.info(TAG, `WS endpoint resp code=${resp.responseCode} type=${typeof resp.result}`);
      let resultStr = typeof resp.result === 'string' ? resp.result : JSON.stringify(resp.result);
      this.log.info(TAG, `WS endpoint resp body: ${resultStr.substring(0, 300)}`);
      if (resp.responseCode !== 200) {
        throw new Error(`ws endpoint HTTP error: ${resp.responseCode}`);
      }
      let result = JSON.parse(resultStr) as WsEndpointResponse;
      if (result.code !== 0) {
        throw new Error(`ws endpoint error: code=${result.code} msg=${result.msg}`);
      }
      this.wssUrl = result.data.URL;
      // Extract service_id from WSS URL query params
      let sidMatch = this.wssUrl.match(/service_id=(\d+)/);
      if (sidMatch) {
        this.serviceId = parseInt(sidMatch[1], 10);
      }
      let config = result.data.ClientConfig;
      if (config) {
        this.pingInterval = config.PingInterval > 0 ? config.PingInterval : 120;
        this.reconnectCount = config.ReconnectCount > 0 ? config.ReconnectCount : 3;
      }
      this.log.info(TAG, `WS URL: ${this.wssUrl.substring(0, 80)}... ping=${this.pingInterval}s serviceId=${this.serviceId}`);
    } finally {
      req.destroy();
    }
  }

  // ==================== WebSocket ====================

  private connectWs(): void {
    if (this.wssUrl.length === 0) {
      this.log.error(TAG, 'No WSS URL');
      return;
    }
    this.closeSocket();
    this.wsGeneration++;
    let gen = this.wsGeneration;

    let ws = webSocket.createWebSocket();
    this.ws = ws;

    ws.on('open', (_err, _value) => {
      if (gen !== this.wsGeneration) return;
      this.log.info(TAG, 'WebSocket OPEN');
      this._connected = true;
      this.reconnectAttempt = 0;
      this.notifyState('connected');
      this.startPing();
    });

    ws.on('message', (_err, value) => {
      if (gen !== this.wsGeneration) return;
      if (value instanceof ArrayBuffer) {
        this.handleBinaryFrame(value);
      } else if (typeof value === 'string') {
        this.log.debug(TAG, `WS text: ${(value as string).substring(0, 200)}`);
      }
    });

    ws.on('close', (_err, _value) => {
      if (gen !== this.wsGeneration) return;
      this.log.warn(TAG, 'WebSocket CLOSED');
      this._connected = false;
      this.notifyState('disconnected');
      this.stopPing();
      this.scheduleReconnect();
    });

    ws.on('error', (err) => {
      if (gen !== this.wsGeneration) return;
      let errDetail = '';
      try { errDetail = JSON.stringify(err); } catch { errDetail = String(err); }
      this.log.error(TAG, `WebSocket ERROR: msg=${err?.message ?? 'unknown'} detail=${errDetail}`);
      this._connected = false;
      this.notifyState('error');
      this.stopPing();
      this.scheduleReconnect();
    });

    this.log.info(TAG, `Connecting WS to ${this.wssUrl}`);;
    ws.connect(this.wssUrl, {
      header: {
        'User-Agent': 'ClawdBot/1.0',
      } as Record<string, string>,
    }, (err) => {
      if (gen !== this.wsGeneration) return;
      if (err) {
        let errDetail = '';
        try { errDetail = JSON.stringify(err); } catch { errDetail = String(err); }
        this.log.error(TAG, `ws.connect() callback error: msg=${err.message ?? ''} detail=${errDetail}`);
        this._connected = false;
        this.notifyState('error');
        this.scheduleReconnect();
      } else {
        this.log.info(TAG, 'ws.connect() callback: no error');
      }
    });
  }

  private closeSocket(): void {
    let ws = this.ws;
    this.ws = undefined;
    this.wsGeneration++;
    if (ws) {
      try { ws.close({ code: 1000, reason: 'bye' }, () => {}); } catch { /* ignore */ }
    }
  }

  // ==================== Ping ====================

  private startPing(): void {
    this.stopPing();
    let intervalMs = this.pingInterval * 1000;
    this.pingTimer = setInterval(() => {
      this.sendPing();
    }, intervalMs);
  }

  private stopPing(): void {
    if (this.pingTimer !== -1) {
      clearInterval(this.pingTimer);
      this.pingTimer = -1;
    }
  }

  private sendPing(): void {
    if (!this.ws) return;
    let frame: FeishuFrame = {
      seqId: 0,
      logId: 0,
      service: this.serviceId,
      method: 0, // control
      headers: [{ key: 'type', value: 'ping' }],
      payloadEncoding: '',
      payloadType: '',
      payload: new Uint8Array(0),
      logIdNew: '',
    };
    let data = encodeFrame(frame);
    this.ws.send(data, (err) => {
      if (err) {
        this.log.warn(TAG, `ping send failed: ${err.message ?? ''}`);
      } else {
        this.log.info(TAG, `Ping sent (service=${this.serviceId})`);
      }
    });
  }

  /** Respond to server ping with a pong frame */
  private sendPong(pingFrame: FeishuFrame): void {
    if (!this.ws) return;
    let frame: FeishuFrame = {
      seqId: 0,
      logId: pingFrame.logId,
      service: this.serviceId,
      method: 0,
      headers: [{ key: 'type', value: 'pong' }],
      payloadEncoding: '',
      payloadType: '',
      payload: new Uint8Array(0),
      logIdNew: pingFrame.logIdNew,
    };
    let data = encodeFrame(frame);
    this.ws.send(data, (err) => {
      if (err) {
        this.log.warn(TAG, `pong send failed: ${err.message ?? ''}`);
      } else {
        this.log.info(TAG, 'Pong sent to server');
      }
    });
  }

  // ==================== Reconnect ====================

  private scheduleReconnect(): void {
    if (!this.shouldReconnect) return;
    this.reconnectAttempt++;
    let delayMs = Math.min(
      Constants.GATEWAY_RECONNECT_MAX_MS,
      Constants.GATEWAY_RECONNECT_BASE_MS * Math.pow(Constants.GATEWAY_RECONNECT_MULTIPLIER, this.reconnectAttempt),
    );
    this.log.info(TAG, `Reconnect in ${Math.round(delayMs)}ms (attempt ${this.reconnectAttempt})`);
    this.notifyState('reconnecting');
    setTimeout(() => {
      if (!this.shouldReconnect) return;
      // Always re-fetch WS endpoint — the WSS URL contains one-time ticket/access_key
      this.fetchWsEndpoint().then(() => {
        this.connectWs();
      }).catch((e: Error) => {
        this.log.error(TAG, `Reconnect fetchWsEndpoint failed: ${e.message ?? ''}`);
        this.scheduleReconnect();
      });
    }, delayMs);
  }

  // ==================== Frame Handling ====================

  private handleBinaryFrame(buffer: ArrayBuffer): void {
    let frame: FeishuFrame;
    try {
      frame = decodeFrame(buffer);
    } catch (e) {
      this.log.error(TAG, `Frame decode error: ${(e as Error).message ?? ''}`);
      return;
    }

    // Read headers
    let headerType = '';
    for (let h of frame.headers) {
      if (h.key === 'type') headerType = h.value;
    }

    let allHeaders = frame.headers.map((h: FeishuHeader) => `${h.key}=${h.value}`).join(', ');
    this.log.info(TAG, `Frame: method=${frame.method} headers=[${allHeaders}] seqId=${frame.seqId} svc=${frame.service} payloadLen=${frame.payload.length}`);

    if (frame.method === 0) {
      // Control frame
      if (headerType === 'ping') {
        // Server ping — respond with pong immediately
        this.log.info(TAG, 'Server ping received, sending pong...');
        this.sendPong(frame);
      } else if (headerType === 'pong') {
        this.log.debug(TAG, 'Pong received from server');
      } else {
        this.log.info(TAG, `Control frame: type=${headerType}`);
      }
      return;
    }

    if (frame.method === 1) {
      if (headerType === 'event') {
        this.handleEventFrame(frame);
      } else {
        this.log.info(TAG, `Data frame type=${headerType} payloadLen=${frame.payload.length}`);
      }
    }
  }

  private handleEventFrame(frame: FeishuFrame): void {
    let t0 = Date.now();
    // Send ACK response frame immediately (within 3s)
    this.sendAckFrame(frame);

    if (frame.payload.length === 0) return;

    let payloadStr = uint8ArrayToString(frame.payload);
    this.log.info(TAG, `Event payload: ${payloadStr.substring(0, 300)}`);

    try {
      let event = JSON.parse(payloadStr) as FeishuEventWrapper;
      let eventType = event.header?.event_type ?? '';
      // Measure Feishu server → device latency
      let createTime = event.header?.create_time ?? '';
      if (createTime.length > 0) {
        let serverMs = parseInt(createTime, 10);
        if (serverMs < 1e12) serverMs *= 1000; // seconds → ms
        let latency = t0 - serverMs;
        this.log.info(TAG, `[TIMING] Feishu→device latency: ${latency}ms (server=${createTime}, local=${t0})`);
      }

      if (eventType === 'im.message.receive_v1') {
        this.handleImMessage(event);
      } else {
        this.log.info(TAG, `Unhandled event type: ${eventType}`);
      }
    } catch (e) {
      this.log.error(TAG, `Event parse error: ${(e as Error).message ?? ''}`);
    }
  }

  private handleImMessage(event: FeishuEventWrapper): void {
    let msg = event.event?.message;
    let sender = event.event?.sender;
    if (!msg || !sender) {
      this.log.warn(TAG, 'im.message.receive_v1: missing message or sender');
      return;
    }

    let messageId = msg.message_id ?? '';
    let chatId = msg.chat_id ?? '';
    let messageType = msg.message_type ?? '';
    let senderId = sender.sender_id?.open_id ?? sender.sender_id?.user_id ?? 'unknown';

    this.log.info(TAG, `IM message: from=${senderId} type=${messageType} id=${messageId} chat=${chatId}`);

    // Deduplicate: skip already-processed messages (Feishu may redeliver on reconnect)
    if (messageId.length > 0 && this.processedMsgIds.has(messageId)) {
      this.log.info(TAG, `Duplicate message ${messageId}, skipping`);
      return;
    }
    if (messageId.length > 0) {
      this.processedMsgIds.add(messageId);
      // Keep set bounded (max 200 entries)
      if (this.processedMsgIds.size > 200) {
        let iter = this.processedMsgIds.keys();
        let first: IteratorResult<string> = iter.next();
        if (!first.done) this.processedMsgIds.delete(first.value);
      }
    }

    // Only handle text messages for now
    if (messageType !== 'text') {
      this.log.info(TAG, `Skipping non-text message type: ${messageType}`);
      return;
    }

    let text = '';
    try {
      let content = JSON.parse(msg.content) as FeishuTextContent;
      text = content.text ?? '';
    } catch {
      text = msg.content ?? '';
    }

    if (text.length === 0) {
      this.log.info(TAG, 'Empty text message, skipping');
      return;
    }

    this.log.info(TAG, `Received text: "${text.substring(0, 100)}"`);

    if (this.onMessageReceived) {
      this.onMessageReceived(senderId, text, messageId, chatId);
    }
  }

  private sendAckFrame(originalFrame: FeishuFrame): void {
    if (!this.ws) return;
    this.seqCounter++;
    let ackFrame: FeishuFrame = {
      seqId: this.seqCounter,
      logId: originalFrame.logId,
      service: originalFrame.service,
      method: originalFrame.method,
      headers: [{ key: 'type', value: 'response' }],
      payloadEncoding: '',
      payloadType: '',
      payload: new Uint8Array(0),
      logIdNew: originalFrame.logIdNew,
    };
    let data = encodeFrame(ackFrame);
    this.ws.send(data, (err) => {
      if (err) {
        this.log.warn(TAG, `ACK send failed: ${err.message ?? ''}`);
      } else {
        this.log.debug(TAG, `ACK sent for seqId=${originalFrame.seqId}`);
      }
    });
  }

  // ==================== Helpers ====================

  private notifyState(state: string): void {
    if (this.onStateChanged) {
      try { this.onStateChanged(state); } catch { /* ignore */ }
    }
  }
}
