'use strict';
/**
 * Scenario test: Gateway connect handshake flow.
 *
 * Simulates the full connect sequence at the protocol level:
 *   1. Server sends connect.challenge event with nonce
 *   2. Client sends connect RPC request
 *   3. Server responds with agent identity and auth tokens
 *
 * Validates frame structure, protocol version, identity extraction,
 * device token handling, and error cases.
 */

const { describe, it } = require('../lib/test-runner');
const {
  assertEqual, assertTrue, assertDefined, assertUndefined,
  assertDeepEqual, assertStartsWith, assertGreaterThan,
} = require('../lib/assert');

// --- Protocol simulation helpers ---

function buildChallengeEvent(nonce) {
  return {
    type: 'event',
    event: 'connect.challenge',
    payload: { nonce: nonce }
  };
}

function buildConnectRequest(id, opts) {
  opts = opts || {};
  return {
    type: 'req',
    id: id,
    method: 'connect',
    params: {
      minProtocol: opts.minProtocol || 3,
      maxProtocol: opts.maxProtocol || 3,
      client: {
        id: opts.clientId || 'openclaw-control-ui',
        version: opts.version || '2.10.9',
        platform: opts.platform || 'HarmonyOS',
        mode: opts.mode || 'ui',
      },
      role: opts.role || 'operator',
      scopes: opts.scopes || ['operator.read', 'operator.write'],
      auth: opts.auth || { token: 'test-token' },
      device: opts.device || {
        id: 'dev-harmony-001',
        publicKey: 'pk-test-abc',
        signature: 'sig-test-xyz',
        signedAt: Date.now(),
        nonce: opts.nonce || undefined,
      },
    }
  };
}

function buildConnectResponse(id, opts) {
  opts = opts || {};
  let payload = {};
  if (opts.agent !== undefined) {
    payload.agent = opts.agent;
  } else {
    payload.agent = {
      identity: {
        name: opts.botName || 'TestBot',
        emoji: opts.botEmoji || '',
        avatar: opts.botAvatar || '/avatars/bot.png',
      }
    };
  }
  if (opts.deviceToken !== undefined) {
    payload.auth = { deviceToken: opts.deviceToken };
  } else {
    payload.auth = { deviceToken: 'dt-session-abc123' };
  }
  return {
    type: 'res',
    id: id,
    ok: opts.ok !== undefined ? opts.ok : true,
    payload: payload
  };
}

/**
 * Extract bot identity from a connect response payload.
 * Mirrors logic from NodeRuntime.ets connect response handling.
 */
function extractBotIdentity(connectRes) {
  if (!connectRes.ok) return null;
  let agent = connectRes.payload && connectRes.payload.agent;
  if (!agent || !agent.identity) return null;
  return {
    name: agent.identity.name || '',
    emoji: agent.identity.emoji || '',
    avatar: agent.identity.avatar || '',
  };
}

/**
 * Extract device token from a connect response payload.
 */
function extractDeviceToken(connectRes) {
  if (!connectRes.ok) return null;
  let auth = connectRes.payload && connectRes.payload.auth;
  if (!auth) return null;
  return auth.deviceToken || null;
}

/**
 * Simulate the full connect flow and return all protocol frames.
 */
function simulateConnectFlow(opts) {
  opts = opts || {};
  const nonce = opts.nonce || 'challenge-nonce-' + Math.random().toString(36).slice(2, 10);
  const reqId = opts.reqId || '1';

  // Step 1: Server challenge
  const challenge = buildChallengeEvent(nonce);

  // Step 2: Client connect request (includes nonce from challenge)
  const connectReq = buildConnectRequest(reqId, {
    ...opts,
    nonce: nonce,
  });

  // Step 3: Server response
  const connectRes = buildConnectResponse(reqId, opts);

  return { challenge, connectReq, connectRes };
}

// --- Tests ---

describe('Gateway connect flow - frame structure', function () {
  it('challenge event has correct RPC shape', function () {
    const { challenge } = simulateConnectFlow();
    assertEqual(challenge.type, 'event', 'challenge type');
    assertEqual(challenge.event, 'connect.challenge', 'challenge event name');
    assertDefined(challenge.payload, 'challenge payload');
    assertDefined(challenge.payload.nonce, 'challenge nonce');
  });

  it('connect request is a valid RPC req frame', function () {
    const { connectReq } = simulateConnectFlow();
    assertEqual(connectReq.type, 'req', 'request type');
    assertDefined(connectReq.id, 'request id');
    assertEqual(connectReq.method, 'connect', 'request method');
    assertDefined(connectReq.params, 'request params');
  });

  it('connect response is a valid RPC res frame', function () {
    const { connectRes } = simulateConnectFlow();
    assertEqual(connectRes.type, 'res', 'response type');
    assertDefined(connectRes.id, 'response id');
    assertTrue(connectRes.ok, 'response ok');
    assertDefined(connectRes.payload, 'response payload');
  });

  it('request and response IDs match', function () {
    const { connectReq, connectRes } = simulateConnectFlow({ reqId: '42' });
    assertEqual(connectReq.id, connectRes.id, 'IDs should match');
    assertEqual(connectReq.id, '42');
  });

  it('all frames can be serialized to valid JSON', function () {
    const { challenge, connectReq, connectRes } = simulateConnectFlow();
    // Serialize and re-parse to verify valid JSON
    const frames = [challenge, connectReq, connectRes];
    for (const frame of frames) {
      const json = JSON.stringify(frame);
      const parsed = JSON.parse(json);
      assertEqual(parsed.type, frame.type, 'round-trip preserves type');
    }
  });
});

describe('Gateway connect flow - protocol version', function () {
  it('connect request includes protocol version 3', function () {
    const { connectReq } = simulateConnectFlow();
    assertEqual(connectReq.params.minProtocol, 3, 'minProtocol');
    assertEqual(connectReq.params.maxProtocol, 3, 'maxProtocol');
  });

  it('client info includes HarmonyOS platform', function () {
    const { connectReq } = simulateConnectFlow();
    assertEqual(connectReq.params.client.platform, 'HarmonyOS');
  });

  it('client info includes version string', function () {
    const { connectReq } = simulateConnectFlow({ version: '2.10.9' });
    assertEqual(connectReq.params.client.version, '2.10.9');
  });

  it('client id is openclaw-control-ui', function () {
    const { connectReq } = simulateConnectFlow();
    assertEqual(connectReq.params.client.id, 'openclaw-control-ui');
  });
});

describe('Gateway connect flow - identity extraction', function () {
  it('extract identity from successful connect response', function () {
    const { connectRes } = simulateConnectFlow({
      botName: 'ClawBot', botEmoji: '', botAvatar: '/img/claw.png'
    });
    const identity = extractBotIdentity(connectRes);
    assertDefined(identity, 'identity should be defined');
    assertEqual(identity.name, 'ClawBot');
    assertEqual(identity.avatar, '/img/claw.png');
  });

  it('identity not available when agent block is missing', function () {
    const res = buildConnectResponse('1', { agent: {} });
    const identity = extractBotIdentity(res);
    // agent exists but no identity sub-object
    assertEqual(identity, null, 'identity should be null when agent.identity is missing');
  });

  it('identity not available when ok is false', function () {
    const res = {
      type: 'res', id: '1', ok: false,
      payload: { error: { code: 'AUTH_FAILED', message: 'bad token' } }
    };
    const identity = extractBotIdentity(res);
    assertEqual(identity, null, 'identity should be null on error response');
  });

  it('identity fields default to empty string when missing', function () {
    const res = buildConnectResponse('1', { agent: { identity: {} } });
    const identity = extractBotIdentity(res);
    assertDefined(identity);
    assertEqual(identity.name, '');
    assertEqual(identity.emoji, '');
    assertEqual(identity.avatar, '');
  });
});

describe('Gateway connect flow - auth token handling', function () {
  it('device token extracted from connect response', function () {
    const { connectRes } = simulateConnectFlow({ deviceToken: 'dt-harmony-999' });
    const token = extractDeviceToken(connectRes);
    assertEqual(token, 'dt-harmony-999');
  });

  it('device token is null on error response', function () {
    const res = { type: 'res', id: '1', ok: false, payload: {} };
    const token = extractDeviceToken(res);
    assertEqual(token, null);
  });

  it('device token is null when auth block is missing', function () {
    const res = { type: 'res', id: '1', ok: true, payload: { agent: {} } };
    const token = extractDeviceToken(res);
    assertEqual(token, null);
  });
});

describe('Gateway connect flow - nonce handling', function () {
  it('nonce from challenge is included in device block', function () {
    const { challenge, connectReq } = simulateConnectFlow({ nonce: 'server-nonce-42' });
    assertEqual(challenge.payload.nonce, 'server-nonce-42');
    assertEqual(connectReq.params.device.nonce, 'server-nonce-42');
  });

  it('device block includes required fields', function () {
    const { connectReq } = simulateConnectFlow();
    const device = connectReq.params.device;
    assertDefined(device.id, 'device id');
    assertDefined(device.publicKey, 'device publicKey');
    assertDefined(device.signature, 'device signature');
    assertDefined(device.signedAt, 'device signedAt');
    assertGreaterThan(device.signedAt, 0, 'signedAt should be positive');
  });

  it('scopes are present in connect request', function () {
    const { connectReq } = simulateConnectFlow();
    assertTrue(Array.isArray(connectReq.params.scopes), 'scopes is an array');
    assertGreaterThan(connectReq.params.scopes.length, 0, 'at least one scope');
  });
});
