'use strict';
/**
 * Scenario test: Chat message send and streaming delta flow.
 *
 * Simulates the full chat lifecycle:
 *   1. Client sends chat.send RPC
 *   2. Server responds with runId
 *   3. Server streams agent delta events
 *   4. Final event signals end of response
 *
 * Validates message structure, delta accumulation, sequencing,
 * idempotency keys, and state transitions.
 */

const { describe, it, beforeEach } = require('../lib/test-runner');
const {
  assertEqual, assertTrue, assertDefined, assertNotEqual,
  assertStartsWith, assertGreaterThan, assertMatch,
} = require('../lib/assert');

// --- Protocol simulation helpers ---

let idCounter = 0;

function buildChatSendRequest(id, opts) {
  opts = opts || {};
  idCounter++;
  return {
    type: 'req',
    id: id,
    method: 'chat.send',
    params: {
      sessionKey: opts.sessionKey || 'agent:main:main',
      message: opts.message || 'Hello',
      idempotencyKey: opts.idempotencyKey || ('harmony-' + Date.now() + '-' + idCounter),
    }
  };
}

function buildChatSendResponse(id, runId) {
  return {
    type: 'res',
    id: id,
    ok: true,
    payload: { runId: runId }
  };
}

function buildAgentDeltaEvent(runId, seq, delta, opts) {
  opts = opts || {};
  let payload = {
    runId: runId,
    seq: seq,
    stream: opts.stream || 'assistant',
    data: { delta: delta },
  };
  if (opts.state) payload.state = opts.state;
  if (opts.stopReason) payload.stopReason = opts.stopReason;
  return {
    type: 'event',
    event: 'agent',
    payload: payload
  };
}

/**
 * Simulate a full chat flow: send request, get runId, receive streaming deltas.
 */
function simulateChatFlow(userMessage, deltas) {
  const reqId = '1';
  const runId = 'run-' + Math.random().toString(36).slice(2, 10);

  const sendReq = buildChatSendRequest(reqId, { message: userMessage });
  const sendRes = buildChatSendResponse(reqId, runId);

  const events = [];
  for (let i = 0; i < deltas.length; i++) {
    const isLast = i === deltas.length - 1;
    events.push(buildAgentDeltaEvent(runId, i, deltas[i], {
      state: isLast ? 'final' : undefined,
      stopReason: isLast ? 'end_turn' : undefined,
    }));
  }

  return { sendReq, sendRes, events, runId };
}

/**
 * Accumulate text from a sequence of agent delta events.
 */
function accumulateDeltas(events) {
  let text = '';
  for (const evt of events) {
    if (evt.payload && evt.payload.data && evt.payload.data.delta) {
      text += evt.payload.data.delta;
    }
  }
  return text;
}

// --- Tests ---

describe('Chat message flow - request structure', function () {
  it('chat.send request has correct method', function () {
    const req = buildChatSendRequest('1', { message: 'Hi' });
    assertEqual(req.type, 'req');
    assertEqual(req.method, 'chat.send');
  });

  it('chat.send request has correct sessionKey format', function () {
    const req = buildChatSendRequest('1', { sessionKey: 'agent:main:main' });
    assertEqual(req.params.sessionKey, 'agent:main:main');
    // sessionKey should contain colons separating parts
    const parts = req.params.sessionKey.split(':');
    assertEqual(parts.length, 3, 'sessionKey has 3 colon-separated parts');
    assertEqual(parts[0], 'agent');
  });

  it('chat.send request includes message text', function () {
    const req = buildChatSendRequest('1', { message: 'What is the weather?' });
    assertEqual(req.params.message, 'What is the weather?');
  });

  it('chat.send request includes idempotencyKey', function () {
    const req = buildChatSendRequest('1');
    assertDefined(req.params.idempotencyKey, 'idempotencyKey should be defined');
    assertStartsWith(req.params.idempotencyKey, 'harmony-');
  });
});

describe('Chat message flow - response handling', function () {
  it('chat.send response extracts runId', function () {
    const res = buildChatSendResponse('1', 'run-abc123');
    assertTrue(res.ok, 'response should be ok');
    assertEqual(res.payload.runId, 'run-abc123');
  });

  it('response id matches request id', function () {
    const req = buildChatSendRequest('42', { message: 'test' });
    const res = buildChatSendResponse('42', 'run-xyz');
    assertEqual(req.id, res.id);
  });
});

describe('Chat message flow - delta accumulation', function () {
  it('deltas accumulate to full text: Hello world!', function () {
    const { events } = simulateChatFlow('Hi', ['Hello', ' world', '!']);
    const text = accumulateDeltas(events);
    assertEqual(text, 'Hello world!');
  });

  it('single delta produces single token', function () {
    const { events } = simulateChatFlow('Hi', ['Complete response.']);
    const text = accumulateDeltas(events);
    assertEqual(text, 'Complete response.');
  });

  it('empty deltas produce empty text', function () {
    const { events } = simulateChatFlow('Hi', ['']);
    // Empty delta string
    const text = accumulateDeltas(events);
    assertEqual(text, '');
  });

  it('many small deltas accumulate correctly', function () {
    const chars = 'The quick brown fox jumps over the lazy dog'.split('');
    const { events } = simulateChatFlow('test', chars);
    const text = accumulateDeltas(events);
    assertEqual(text, 'The quick brown fox jumps over the lazy dog');
  });
});

describe('Chat message flow - event sequencing', function () {
  it('final event has state=final', function () {
    const { events } = simulateChatFlow('Hi', ['Hello', ' there']);
    const lastEvent = events[events.length - 1];
    assertEqual(lastEvent.payload.state, 'final');
  });

  it('non-final events do not have state=final', function () {
    const { events } = simulateChatFlow('Hi', ['a', 'b', 'c']);
    for (let i = 0; i < events.length - 1; i++) {
      assertTrue(
        events[i].payload.state === undefined,
        'non-final event ' + i + ' should not have state'
      );
    }
  });

  it('all events share the same runId', function () {
    const { events, runId } = simulateChatFlow('test', ['x', 'y', 'z']);
    for (const evt of events) {
      assertEqual(evt.payload.runId, runId, 'runId should match');
    }
  });

  it('sequences are monotonically increasing', function () {
    const { events } = simulateChatFlow('test', ['a', 'b', 'c', 'd']);
    for (let i = 1; i < events.length; i++) {
      assertGreaterThan(
        events[i].payload.seq,
        events[i - 1].payload.seq,
        'seq[' + i + '] > seq[' + (i - 1) + ']'
      );
    }
  });

  it('sequences start at 0', function () {
    const { events } = simulateChatFlow('test', ['a', 'b']);
    assertEqual(events[0].payload.seq, 0, 'first seq is 0');
    assertEqual(events[1].payload.seq, 1, 'second seq is 1');
  });

  it('final event includes stopReason', function () {
    const { events } = simulateChatFlow('Hi', ['done']);
    const lastEvent = events[events.length - 1];
    assertEqual(lastEvent.payload.stopReason, 'end_turn');
  });
});

describe('Chat message flow - idempotency', function () {
  it('idempotencyKey is unique per request', function () {
    const req1 = buildChatSendRequest('1', { message: 'a' });
    const req2 = buildChatSendRequest('2', { message: 'b' });
    assertNotEqual(
      req1.params.idempotencyKey,
      req2.params.idempotencyKey,
      'idempotency keys should differ'
    );
  });

  it('idempotencyKey matches expected format', function () {
    const req = buildChatSendRequest('1');
    assertMatch(req.params.idempotencyKey, /^harmony-\d+-\d+$/);
  });
});
