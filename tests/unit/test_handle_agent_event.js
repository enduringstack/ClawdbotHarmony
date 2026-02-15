'use strict';
/**
 * Unit tests for agent event parsing logic (handleOperatorEvent).
 * Source: NodeRuntime.ets lines 1451-1637
 */

const { describe, it } = require('../lib/test-runner');
const { assertEqual } = require('../lib/assert');

// Mirror of agent event parsing from NodeRuntime.ets
function parseAgentEvent(payloadJson) {
  let raw = JSON.parse(payloadJson);
  let runId = raw.runId || '';
  let stream = raw.stream || '';
  let seq = raw.seq || 0;
  let sessionKey = raw.sessionKey || '';

  // Text extraction
  let fullText = '';
  let dataObj = raw.data;
  if (dataObj !== undefined && dataObj !== null) {
    if (typeof dataObj === 'string') {
      fullText = String(dataObj);
    } else if (dataObj.delta !== undefined && String(dataObj.delta).length > 0) {
      fullText = String(dataObj.delta);
    } else if (dataObj.text !== undefined) {
      fullText = String(dataObj.text);
    }
  }
  if (fullText.length === 0 && raw.text !== undefined) {
    fullText = String(raw.text);
  }
  if (fullText.length === 0 && raw.message) {
    let msgObj = raw.message;
    if (msgObj.content !== undefined) {
      if (Array.isArray(msgObj.content)) {
        for (let block of msgObj.content) {
          if (block.type === 'text' && block.text) fullText += block.text;
        }
      } else if (typeof msgObj.content === 'string') {
        fullText = msgObj.content;
      }
    }
  }
  if (fullText.length === 0 && raw.content !== undefined) {
    if (Array.isArray(raw.content)) {
      for (let block of raw.content) {
        if (block.type === 'text' && block.text) fullText += block.text;
      }
    } else if (typeof raw.content === 'string') {
      fullText = raw.content;
    }
  }

  // State detection
  let chatState = 'delta';
  let explicitState = raw.state !== undefined ? String(raw.state) : '';

  if (['final','done','complete','finished'].includes(explicitState)) chatState = 'final';
  else if (explicitState === 'error') chatState = 'error';
  else if (explicitState === 'aborted') chatState = 'aborted';

  if (chatState === 'delta' && raw.done !== undefined) {
    if (raw.done === true || String(raw.done) === 'true') chatState = 'final';
  }
  if (chatState === 'delta' && raw.delta !== undefined) {
    if (raw.delta === false || String(raw.delta) === 'false') chatState = 'final';
  }
  if (chatState === 'delta' && raw.type !== undefined) {
    let typeVal = String(raw.type);
    if (['done','final','complete'].includes(typeVal)) chatState = 'final';
    else if (typeVal === 'error') chatState = 'error';
  }

  let stopReason = '';
  if (raw.stopReason !== undefined) {
    stopReason = String(raw.stopReason);
    if (chatState === 'delta' && stopReason.length > 0) chatState = 'final';
  }

  if (chatState === 'delta' && stream === 'lifecycle' && dataObj && typeof dataObj === 'object') {
    if (dataObj.phase !== undefined && String(dataObj.phase) === 'end') chatState = 'final';
  }

  return { runId, sessionKey, seq, state: chatState, text: fullText, stopReason };
}

// --- Text extraction tests ---

describe('parseAgentEvent - text extraction', function () {
  it('data.delta preferred over data.text', function () {
    let result = parseAgentEvent(JSON.stringify({
      data: { delta: 'from delta', text: 'from text' }
    }));
    assertEqual(result.text, 'from delta');
  });

  it('data.text as fallback when no delta', function () {
    let result = parseAgentEvent(JSON.stringify({
      data: { text: 'fallback text' }
    }));
    assertEqual(result.text, 'fallback text');
  });

  it('data as direct string', function () {
    let result = parseAgentEvent(JSON.stringify({
      data: 'direct string data'
    }));
    assertEqual(result.text, 'direct string data');
  });

  it('top-level text field', function () {
    let result = parseAgentEvent(JSON.stringify({
      text: 'top level text'
    }));
    assertEqual(result.text, 'top level text');
  });

  it('message.content[].text array', function () {
    let result = parseAgentEvent(JSON.stringify({
      message: {
        content: [{ type: 'text', text: 'hello world' }]
      }
    }));
    assertEqual(result.text, 'hello world');
  });

  it('multiple content blocks concatenated', function () {
    let result = parseAgentEvent(JSON.stringify({
      message: {
        content: [
          { type: 'text', text: 'part one' },
          { type: 'text', text: ' part two' }
        ]
      }
    }));
    assertEqual(result.text, 'part one part two');
  });

  it('content as string', function () {
    let result = parseAgentEvent(JSON.stringify({
      content: 'string content'
    }));
    assertEqual(result.text, 'string content');
  });

  it('message.content as string', function () {
    let result = parseAgentEvent(JSON.stringify({
      message: { content: 'message content string' }
    }));
    assertEqual(result.text, 'message content string');
  });

  it('empty everywhere returns empty string', function () {
    let result = parseAgentEvent(JSON.stringify({}));
    assertEqual(result.text, '');
  });
});

// --- State detection tests ---

describe('parseAgentEvent - state detection', function () {
  it('state=final yields final', function () {
    let result = parseAgentEvent(JSON.stringify({ state: 'final' }));
    assertEqual(result.state, 'final');
  });

  it('state=done yields final', function () {
    let result = parseAgentEvent(JSON.stringify({ state: 'done' }));
    assertEqual(result.state, 'final');
  });

  it('state=complete yields final', function () {
    let result = parseAgentEvent(JSON.stringify({ state: 'complete' }));
    assertEqual(result.state, 'final');
  });

  it('state=finished yields final', function () {
    let result = parseAgentEvent(JSON.stringify({ state: 'finished' }));
    assertEqual(result.state, 'final');
  });

  it('state=error yields error', function () {
    let result = parseAgentEvent(JSON.stringify({ state: 'error' }));
    assertEqual(result.state, 'error');
  });

  it('state=aborted yields aborted', function () {
    let result = parseAgentEvent(JSON.stringify({ state: 'aborted' }));
    assertEqual(result.state, 'aborted');
  });

  it('done=true yields final', function () {
    let result = parseAgentEvent(JSON.stringify({ done: true }));
    assertEqual(result.state, 'final');
  });

  it('done="true" (string) yields final', function () {
    let result = parseAgentEvent(JSON.stringify({ done: 'true' }));
    assertEqual(result.state, 'final');
  });

  it('delta=false yields final', function () {
    let result = parseAgentEvent(JSON.stringify({ delta: false }));
    assertEqual(result.state, 'final');
  });

  it('type=done yields final', function () {
    let result = parseAgentEvent(JSON.stringify({ type: 'done' }));
    assertEqual(result.state, 'final');
  });

  it('type=error yields error', function () {
    let result = parseAgentEvent(JSON.stringify({ type: 'error' }));
    assertEqual(result.state, 'error');
  });

  it('stopReason=end_turn yields final', function () {
    let result = parseAgentEvent(JSON.stringify({ stopReason: 'end_turn' }));
    assertEqual(result.state, 'final');
    assertEqual(result.stopReason, 'end_turn');
  });

  it('lifecycle phase=end yields final', function () {
    let result = parseAgentEvent(JSON.stringify({
      stream: 'lifecycle',
      data: { phase: 'end' }
    }));
    assertEqual(result.state, 'final');
  });

  it('no signals yields delta', function () {
    let result = parseAgentEvent(JSON.stringify({
      data: { delta: 'some text' }
    }));
    assertEqual(result.state, 'delta');
  });
});
