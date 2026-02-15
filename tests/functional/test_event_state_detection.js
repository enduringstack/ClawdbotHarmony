'use strict';

const { describe, it } = require('../lib/test-runner');
const { assertEqual } = require('../lib/assert');

// Mirror of state detection logic from NodeRuntime.ets
function detectState(raw) {
  let chatState = 'delta';
  let stream = raw.stream || '';
  let explicitState = raw.state !== undefined ? String(raw.state) : '';

  if (['final', 'done', 'complete', 'finished'].includes(explicitState)) chatState = 'final';
  else if (explicitState === 'error') chatState = 'error';
  else if (explicitState === 'aborted') chatState = 'aborted';

  if (chatState === 'delta' && raw.done !== undefined) {
    if (raw.done === true || String(raw.done) === 'true') chatState = 'final';
  }
  if (chatState === 'delta' && raw.delta !== undefined) {
    if (raw.delta === false || String(raw.delta) === 'false') chatState = 'final';
  }
  if (chatState === 'delta' && raw.type !== undefined) {
    let t = String(raw.type);
    if (['done', 'final', 'complete'].includes(t)) chatState = 'final';
    else if (t === 'error') chatState = 'error';
  }
  let stopReason = '';
  if (raw.stopReason !== undefined) {
    stopReason = String(raw.stopReason);
    if (chatState === 'delta' && stopReason.length > 0) chatState = 'final';
  }
  if (chatState === 'delta' && stream === 'lifecycle' && raw.data && typeof raw.data === 'object') {
    if (raw.data.phase !== undefined && String(raw.data.phase) === 'end') chatState = 'final';
  }
  return chatState;
}

// --- Explicit state field ---

describe('detectState - explicit state field', function () {
  it('state="final" -> final', function () {
    assertEqual(detectState({ state: 'final' }), 'final');
  });

  it('state="done" -> final', function () {
    assertEqual(detectState({ state: 'done' }), 'final');
  });

  it('state="complete" -> final', function () {
    assertEqual(detectState({ state: 'complete' }), 'final');
  });

  it('state="finished" -> final', function () {
    assertEqual(detectState({ state: 'finished' }), 'final');
  });

  it('state="error" -> error', function () {
    assertEqual(detectState({ state: 'error' }), 'error');
  });

  it('state="aborted" -> aborted', function () {
    assertEqual(detectState({ state: 'aborted' }), 'aborted');
  });

  it('state="streaming" (unknown) -> delta', function () {
    assertEqual(detectState({ state: 'streaming' }), 'delta');
  });
});

// --- done field ---

describe('detectState - done field', function () {
  it('done=true -> final', function () {
    assertEqual(detectState({ done: true }), 'final');
  });

  it('done="true" (string) -> final', function () {
    assertEqual(detectState({ done: 'true' }), 'final');
  });

  it('done=false -> delta (not falsy trigger)', function () {
    assertEqual(detectState({ done: false }), 'delta');
  });

  it('done=0 -> delta (falsy, String(0) !== "true")', function () {
    assertEqual(detectState({ done: 0 }), 'delta');
  });

  it('done=null -> delta', function () {
    assertEqual(detectState({ done: null }), 'delta');
  });
});

// --- delta field ---

describe('detectState - delta field (inverted)', function () {
  it('delta=false -> final', function () {
    assertEqual(detectState({ delta: false }), 'final');
  });

  it('delta="false" (string) -> final', function () {
    assertEqual(detectState({ delta: 'false' }), 'final');
  });

  it('delta=true -> delta (delta=true does not trigger final)', function () {
    assertEqual(detectState({ delta: true }), 'delta');
  });

  it('delta="some text" -> delta (non-false string)', function () {
    assertEqual(detectState({ delta: 'some text' }), 'delta');
  });
});

// --- type field ---

describe('detectState - type field', function () {
  it('type="done" -> final', function () {
    assertEqual(detectState({ type: 'done' }), 'final');
  });

  it('type="final" -> final', function () {
    assertEqual(detectState({ type: 'final' }), 'final');
  });

  it('type="complete" -> final', function () {
    assertEqual(detectState({ type: 'complete' }), 'final');
  });

  it('type="error" -> error', function () {
    assertEqual(detectState({ type: 'error' }), 'error');
  });

  it('type="streaming" -> delta (unknown type)', function () {
    assertEqual(detectState({ type: 'streaming' }), 'delta');
  });

  it('type="content_block_delta" -> delta (unknown type)', function () {
    assertEqual(detectState({ type: 'content_block_delta' }), 'delta');
  });
});

// --- stopReason field ---

describe('detectState - stopReason field', function () {
  it('stopReason="end_turn" -> final', function () {
    assertEqual(detectState({ stopReason: 'end_turn' }), 'final');
  });

  it('stopReason="max_tokens" -> final', function () {
    assertEqual(detectState({ stopReason: 'max_tokens' }), 'final');
  });

  it('stopReason="" (empty) -> delta (empty stopReason does not trigger)', function () {
    assertEqual(detectState({ stopReason: '' }), 'delta');
  });
});

// --- lifecycle phase ---

describe('detectState - lifecycle phase', function () {
  it('stream="lifecycle", data.phase="end" -> final', function () {
    assertEqual(detectState({ stream: 'lifecycle', data: { phase: 'end' } }), 'final');
  });

  it('stream="lifecycle", data.phase="start" -> delta (only end triggers)', function () {
    assertEqual(detectState({ stream: 'lifecycle', data: { phase: 'start' } }), 'delta');
  });

  it('stream="lifecycle", no data -> delta', function () {
    assertEqual(detectState({ stream: 'lifecycle' }), 'delta');
  });

  it('stream="chat", data.phase="end" -> delta (wrong stream)', function () {
    assertEqual(detectState({ stream: 'chat', data: { phase: 'end' } }), 'delta');
  });
});

// --- Priority / multiple signal tests ---

describe('detectState - signal priority', function () {
  it('state="error" + done=true -> error (explicit state wins)', function () {
    assertEqual(detectState({ state: 'error', done: true }), 'error');
  });

  it('state="aborted" + done=true -> aborted (explicit state wins)', function () {
    assertEqual(detectState({ state: 'aborted', done: true }), 'aborted');
  });

  it('state="final" + type="error" -> final (explicit state checked first)', function () {
    assertEqual(detectState({ state: 'final', type: 'error' }), 'final');
  });

  it('state="error" + delta=false -> error (state overrides delta)', function () {
    assertEqual(detectState({ state: 'error', delta: false }), 'error');
  });

  it('done=true + stopReason="end_turn" -> final (done checked first, both final)', function () {
    assertEqual(detectState({ done: true, stopReason: 'end_turn' }), 'final');
  });

  it('no signals at all -> delta', function () {
    assertEqual(detectState({}), 'delta');
  });

  it('empty object with unrelated fields -> delta', function () {
    assertEqual(detectState({ runId: 'r1', seq: 1, text: 'hello' }), 'delta');
  });
});
