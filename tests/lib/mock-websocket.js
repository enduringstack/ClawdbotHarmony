'use strict';
/**
 * Mock WebSocket server for scenario tests.
 * Uses Node.js built-in http and crypto modules. No external dependencies.
 *
 * Supports the OpenClaw gateway RPC protocol:
 *   Request:  {type:"req", id, method, params}
 *   Response: {type:"res", id, ok, payload}
 *   Event:    {type:"event", event, payload}
 */

const http = require('http');
const crypto = require('crypto');

// --- WebSocket frame helpers ---

const WS_GUID = '258EAFA5-E914-47DA-95CA-5AB9DC65C337';

function computeAcceptKey(key) {
  return crypto.createHash('sha1').update(key + WS_GUID).digest('base64');
}

/**
 * Encode a text string into a WebSocket frame (server-to-client, unmasked).
 * Supports payloads up to 65535 bytes.
 */
function encodeFrame(text) {
  const payload = Buffer.from(text, 'utf8');
  const len = payload.length;
  let header;

  if (len < 126) {
    header = Buffer.alloc(2);
    header[0] = 0x81; // FIN + text opcode
    header[1] = len;
  } else if (len <= 65535) {
    header = Buffer.alloc(4);
    header[0] = 0x81;
    header[1] = 126;
    header.writeUInt16BE(len, 2);
  } else {
    throw new Error('Frame payload exceeds 65535 bytes');
  }

  return Buffer.concat([header, payload]);
}

/**
 * Decode one WebSocket frame from a buffer (client-to-server, masked).
 * Returns { text, bytesConsumed } or null if the buffer is incomplete.
 */
function decodeFrame(buffer) {
  if (buffer.length < 2) return null;

  const firstByte = buffer[0];
  const opcode = firstByte & 0x0f;
  const secondByte = buffer[1];
  const masked = (secondByte & 0x80) !== 0;
  let payloadLen = secondByte & 0x7f;
  let offset = 2;

  if (payloadLen === 126) {
    if (buffer.length < 4) return null;
    payloadLen = buffer.readUInt16BE(2);
    offset = 4;
  } else if (payloadLen === 127) {
    if (buffer.length < 10) return null;
    // For simplicity, read lower 32 bits (sufficient for test frames)
    payloadLen = buffer.readUInt32BE(6);
    offset = 10;
  }

  const maskSize = masked ? 4 : 0;
  const totalNeeded = offset + maskSize + payloadLen;
  if (buffer.length < totalNeeded) return null;

  let maskKey = null;
  if (masked) {
    maskKey = buffer.slice(offset, offset + 4);
    offset += 4;
  }

  const payload = Buffer.alloc(payloadLen);
  for (let i = 0; i < payloadLen; i++) {
    payload[i] = masked
      ? buffer[offset + i] ^ maskKey[i % 4]
      : buffer[offset + i];
  }

  // Handle close frame (opcode 0x8)
  if (opcode === 0x8) {
    return { text: null, opcode: 0x8, bytesConsumed: totalNeeded };
  }

  // Handle ping (opcode 0x9) - respond with pong
  if (opcode === 0x9) {
    return { text: null, opcode: 0x9, bytesConsumed: totalNeeded, payload };
  }

  // Text frame (opcode 0x1)
  if (opcode === 0x1) {
    return { text: payload.toString('utf8'), opcode: 0x1, bytesConsumed: totalNeeded };
  }

  // For other opcodes, consume and skip
  return { text: null, opcode, bytesConsumed: totalNeeded };
}

/**
 * Encode a close frame (server-to-client, unmasked).
 */
function encodeCloseFrame(code) {
  const header = Buffer.alloc(4);
  header[0] = 0x88; // FIN + close opcode
  header[1] = 2;    // payload length = 2 (status code)
  header.writeUInt16BE(code || 1000, 2);
  return header;
}

/**
 * Encode a pong frame (server-to-client, unmasked).
 */
function encodePongFrame(payload) {
  const len = payload ? payload.length : 0;
  let header;
  if (len < 126) {
    header = Buffer.alloc(2);
    header[0] = 0x8a; // FIN + pong opcode
    header[1] = len;
  } else {
    header = Buffer.alloc(4);
    header[0] = 0x8a;
    header[1] = 126;
    header.writeUInt16BE(len, 2);
  }
  return payload ? Buffer.concat([header, payload]) : header;
}

// --- MockGateway ---

class MockGateway {
  constructor() {
    this.server = null;
    this.clients = [];
    this.handlers = {};
    this.receivedMessages = [];
    this.port = 0;
    this._nextReqId = 1;
  }

  /**
   * Register a handler for an RPC method.
   * handler: (params) => responsePayload
   * The handler return value becomes the `payload` in the response.
   * If the handler throws, an error response is sent.
   */
  onMethod(method, handler) {
    this.handlers[method] = handler;
  }

  /**
   * Start the mock server on a random available port.
   * Returns the port number.
   */
  async start() {
    return new Promise((resolve, reject) => {
      this.server = http.createServer((req, res) => {
        res.writeHead(404);
        res.end();
      });

      this.server.on('upgrade', (req, socket, head) => {
        const key = req.headers['sec-websocket-key'];
        if (!key) {
          socket.destroy();
          return;
        }

        const acceptKey = computeAcceptKey(key);
        const responseHeaders = [
          'HTTP/1.1 101 Switching Protocols',
          'Upgrade: websocket',
          'Connection: Upgrade',
          `Sec-WebSocket-Accept: ${acceptKey}`,
          '',
          ''
        ].join('\r\n');

        socket.write(responseHeaders);

        const clientIndex = this.clients.length;
        const clientInfo = { socket, buffer: Buffer.alloc(0), index: clientIndex };
        this.clients.push(clientInfo);

        socket.on('data', (data) => {
          clientInfo.buffer = Buffer.concat([clientInfo.buffer, data]);
          this._processBuffer(clientInfo);
        });

        socket.on('close', () => {
          clientInfo.socket = null;
        });

        socket.on('error', () => {
          clientInfo.socket = null;
        });
      });

      this.server.listen(0, '127.0.0.1', () => {
        this.port = this.server.address().port;
        resolve(this.port);
      });

      this.server.on('error', reject);
    });
  }

  /**
   * Process buffered data from a client, extracting complete frames.
   */
  _processBuffer(clientInfo) {
    while (clientInfo.buffer.length > 0) {
      const frame = decodeFrame(clientInfo.buffer);
      if (!frame) break;

      clientInfo.buffer = clientInfo.buffer.slice(frame.bytesConsumed);

      if (frame.opcode === 0x8) {
        // Close frame - respond with close and end
        if (clientInfo.socket) {
          clientInfo.socket.write(encodeCloseFrame(1000));
          clientInfo.socket.end();
        }
        continue;
      }

      if (frame.opcode === 0x9) {
        // Ping - respond with pong
        if (clientInfo.socket) {
          clientInfo.socket.write(encodePongFrame(frame.payload));
        }
        continue;
      }

      if (frame.text === null) continue;

      let msg;
      try {
        msg = JSON.parse(frame.text);
      } catch (_e) {
        continue;
      }

      this.receivedMessages.push({ clientIndex: clientInfo.index, message: msg });

      // Handle RPC requests
      if (msg.type === 'req' && msg.method) {
        const handler = this.handlers[msg.method];
        if (handler) {
          try {
            const payload = handler(msg.params);
            const res = { type: 'res', id: msg.id, ok: true, payload: payload || {} };
            this._sendToClient(clientInfo, JSON.stringify(res));
          } catch (err) {
            const res = {
              type: 'res', id: msg.id, ok: false,
              payload: { error: { code: err.code || 'HANDLER_ERROR', message: err.message } }
            };
            this._sendToClient(clientInfo, JSON.stringify(res));
          }
        }
      }
    }
  }

  /**
   * Send a raw text frame to a specific client.
   */
  _sendToClient(clientInfo, text) {
    if (clientInfo.socket && !clientInfo.socket.destroyed) {
      clientInfo.socket.write(encodeFrame(text));
    }
  }

  /**
   * Send an event to all connected clients.
   */
  sendEvent(event, payload) {
    const msg = JSON.stringify({ type: 'event', event, payload: payload || {} });
    for (const client of this.clients) {
      this._sendToClient(client, msg);
    }
  }

  /**
   * Send an event to a specific client by index.
   */
  sendEventTo(clientIndex, event, payload) {
    const client = this.clients[clientIndex];
    if (client) {
      const msg = JSON.stringify({ type: 'event', event, payload: payload || {} });
      this._sendToClient(client, msg);
    }
  }

  /**
   * Get messages received from a specific client.
   */
  getMessagesFrom(clientIndex) {
    return this.receivedMessages
      .filter(m => m.clientIndex === clientIndex)
      .map(m => m.message);
  }

  /**
   * Get all received messages with a specific RPC method.
   */
  getMethodCalls(method) {
    return this.receivedMessages
      .filter(m => m.message.type === 'req' && m.message.method === method)
      .map(m => m.message);
  }

  /**
   * Close the server and all client connections.
   */
  async close() {
    for (const client of this.clients) {
      if (client.socket && !client.socket.destroyed) {
        try {
          client.socket.write(encodeCloseFrame(1000));
          client.socket.end();
        } catch (_e) {
          // ignore
        }
      }
    }
    this.clients = [];

    return new Promise((resolve) => {
      if (this.server) {
        this.server.close(() => resolve());
      } else {
        resolve();
      }
    });
  }
}

module.exports = {
  MockGateway,
  encodeFrame,
  decodeFrame,
  encodeCloseFrame,
  encodePongFrame,
  computeAcceptKey,
  WS_GUID,
};
