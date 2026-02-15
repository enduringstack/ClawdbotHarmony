'use strict';
/**
 * Scenario test: Device capability invoke flow.
 *
 * Simulates the server requesting a device capability (e.g., location.get)
 * and the client responding with a result or error.
 *
 * Flow:
 *   1. Server sends node.invoke.request event
 *   2. Client processes the command
 *   3. Client sends node.invoke.result RPC
 *
 * Validates request parsing, success/error result formatting,
 * ID matching, and unsupported command handling.
 */

const { describe, it } = require('../lib/test-runner');
const {
  assertEqual, assertTrue, assertFalse, assertDefined,
  assertDeepEqual, assertGreaterThan,
} = require('../lib/assert');

// --- Protocol simulation helpers ---

function buildInvokeRequest(opts) {
  opts = opts || {};
  return {
    type: 'event',
    event: 'node.invoke.request',
    payload: {
      id: opts.id || 'inv-001',
      nodeId: opts.nodeId || 'harmony-device',
      command: opts.command || 'location.get',
      paramsJSON: opts.paramsJSON || '{}',
      timeoutMs: opts.timeoutMs || 30000,
    }
  };
}

function buildInvokeSuccessResult(reqId, invokeId, nodeId, payload) {
  return {
    type: 'req',
    id: reqId,
    method: 'node.invoke.result',
    params: {
      id: invokeId,
      nodeId: nodeId,
      ok: true,
      payload: payload,
    }
  };
}

function buildInvokeErrorResult(reqId, invokeId, nodeId, code, message) {
  return {
    type: 'req',
    id: reqId,
    method: 'node.invoke.result',
    params: {
      id: invokeId,
      nodeId: nodeId,
      ok: false,
      error: { code: code, message: message },
    }
  };
}

/**
 * Parse an invoke request event payload, extracting command and params.
 * Mirrors logic from NodeRuntime.ets invoke handling.
 */
function parseInvokeRequest(event) {
  const p = event.payload;
  let params = {};
  if (p.paramsJSON && p.paramsJSON.length > 0) {
    try {
      params = JSON.parse(p.paramsJSON);
    } catch (_e) {
      params = {};
    }
  }
  return {
    id: p.id,
    nodeId: p.nodeId,
    command: p.command,
    params: params,
    timeoutMs: p.timeoutMs,
  };
}

/**
 * Supported commands lookup.
 */
const SUPPORTED_COMMANDS = new Set([
  'location.get', 'camera.snap', 'camera.clip', 'screen.capture',
  'notification.show', 'system.notify', 'sms.send', 'mic.record',
  'speaker.speak', 'speaker.play', 'speaker.stop', 'email.send',
  'calendar.add', 'exec.run',
  'canvas.present', 'canvas.hide', 'canvas.navigate', 'canvas.eval',
  'canvas.snapshot', 'canvas.a2ui.push', 'canvas.a2ui.pushJSONL', 'canvas.a2ui.reset',
  'screen.record',
]);

/**
 * Simulate processing an invoke request and generating a result.
 */
function processInvoke(event) {
  const parsed = parseInvokeRequest(event);

  if (!SUPPORTED_COMMANDS.has(parsed.command)) {
    return buildInvokeErrorResult(
      '1', parsed.id, parsed.nodeId,
      'INVALID_REQUEST', 'Unsupported command: ' + parsed.command
    );
  }

  // Simulate success for location.get
  if (parsed.command === 'location.get') {
    return buildInvokeSuccessResult('1', parsed.id, parsed.nodeId, {
      latitude: 39.9042,
      longitude: 116.4074,
      accuracy: parsed.params.accuracy === 'high' ? 10 : 100,
    });
  }

  // Default success with empty payload
  return buildInvokeSuccessResult('1', parsed.id, parsed.nodeId, {});
}

function simulateInvokeFlow(command, paramsJSON) {
  const invokeReq = buildInvokeRequest({
    id: 'inv-' + Math.random().toString(36).slice(2, 8),
    command: command,
    paramsJSON: paramsJSON || '{}',
  });

  const invokeResult = processInvoke(invokeReq);
  return { invokeReq, invokeResult };
}

// --- Tests ---

describe('Invoke flow - request parsing', function () {
  it('invoke request parsed correctly with all fields', function () {
    const req = buildInvokeRequest({
      id: 'inv-42',
      nodeId: 'node-harmony',
      command: 'location.get',
      paramsJSON: '{"accuracy":"high"}',
      timeoutMs: 15000,
    });
    const parsed = parseInvokeRequest(req);
    assertEqual(parsed.id, 'inv-42');
    assertEqual(parsed.nodeId, 'node-harmony');
    assertEqual(parsed.command, 'location.get');
    assertDeepEqual(parsed.params, { accuracy: 'high' });
    assertEqual(parsed.timeoutMs, 15000);
  });

  it('invoke request with empty paramsJSON yields empty params', function () {
    const req = buildInvokeRequest({ paramsJSON: '{}' });
    const parsed = parseInvokeRequest(req);
    assertDeepEqual(parsed.params, {});
  });

  it('invoke request with invalid paramsJSON yields empty params', function () {
    const req = buildInvokeRequest({ paramsJSON: 'not-json' });
    const parsed = parseInvokeRequest(req);
    assertDeepEqual(parsed.params, {});
  });

  it('invoke request event has correct event name', function () {
    const req = buildInvokeRequest();
    assertEqual(req.type, 'event');
    assertEqual(req.event, 'node.invoke.request');
  });
});

describe('Invoke flow - success result', function () {
  it('success result has ok=true and payload', function () {
    const { invokeResult } = simulateInvokeFlow('location.get', '{"accuracy":"high"}');
    assertTrue(invokeResult.params.ok, 'result should be ok');
    assertDefined(invokeResult.params.payload, 'payload should be defined');
  });

  it('location.get result contains coordinates', function () {
    const { invokeResult } = simulateInvokeFlow('location.get', '{"accuracy":"high"}');
    const p = invokeResult.params.payload;
    assertEqual(p.latitude, 39.9042);
    assertEqual(p.longitude, 116.4074);
    assertEqual(p.accuracy, 10);
  });

  it('location.get with low accuracy returns coarse accuracy', function () {
    const { invokeResult } = simulateInvokeFlow('location.get', '{"accuracy":"low"}');
    assertEqual(invokeResult.params.payload.accuracy, 100);
  });

  it('success result method is node.invoke.result', function () {
    const { invokeResult } = simulateInvokeFlow('location.get');
    assertEqual(invokeResult.type, 'req');
    assertEqual(invokeResult.method, 'node.invoke.result');
  });
});

describe('Invoke flow - error result', function () {
  it('error result has ok=false and error code/message', function () {
    const result = buildInvokeErrorResult('1', 'inv-1', 'node-1', 'TIMEOUT', 'timed out');
    assertFalse(result.params.ok, 'result should not be ok');
    assertEqual(result.params.error.code, 'TIMEOUT');
    assertEqual(result.params.error.message, 'timed out');
  });

  it('unsupported command produces INVALID_REQUEST error', function () {
    const { invokeResult } = simulateInvokeFlow('bogus.command');
    assertFalse(invokeResult.params.ok, 'result should not be ok');
    assertEqual(invokeResult.params.error.code, 'INVALID_REQUEST');
    assertTrue(
      invokeResult.params.error.message.indexOf('bogus.command') >= 0,
      'error message should mention the unsupported command'
    );
  });
});

describe('Invoke flow - ID matching', function () {
  it('result invoke ID matches request invoke ID', function () {
    const req = buildInvokeRequest({ id: 'inv-match-test' });
    const result = processInvoke(req);
    assertEqual(result.params.id, 'inv-match-test');
  });

  it('result nodeId matches request nodeId', function () {
    const req = buildInvokeRequest({ nodeId: 'my-harmony-node' });
    const result = processInvoke(req);
    assertEqual(result.params.nodeId, 'my-harmony-node');
  });

  it('different invoke IDs produce different result IDs', function () {
    const req1 = buildInvokeRequest({ id: 'inv-aaa' });
    const req2 = buildInvokeRequest({ id: 'inv-bbb' });
    const res1 = processInvoke(req1);
    const res2 = processInvoke(req2);
    assertEqual(res1.params.id, 'inv-aaa');
    assertEqual(res2.params.id, 'inv-bbb');
  });
});
