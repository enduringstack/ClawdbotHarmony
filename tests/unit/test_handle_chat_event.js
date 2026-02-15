'use strict';
/**
 * Unit tests for chat event parsing logic.
 * Source: NodeRuntime.ets lines 1642-1701
 */

const { describe, it } = require('../lib/test-runner');
const { assertEqual, assertTrue, assertFalse, assertUndefined, assertDefined } = require('../lib/assert');

// Mirror of chat event parsing from NodeRuntime.ets
function parseChatEvent(payloadJson) {
  let raw = JSON.parse(payloadJson);
  let runId = raw.runId || '';
  let state = raw.state || '';
  let seq = raw.seq || 0;
  let sessionKey = raw.sessionKey || '';
  let errorMessage = raw.errorMessage || undefined;
  let stopReason = raw.stopReason || undefined;

  let message = undefined;
  let msgRaw = raw.message;
  if (msgRaw) {
    let blocks = [];
    let contentRaw = msgRaw.content;
    if (Array.isArray(contentRaw)) {
      for (let block of contentRaw) {
        let blockText = block.text || '';
        blocks.push({ type: block.type || 'text', text: blockText.length > 0 ? blockText : undefined });
      }
    } else if (typeof contentRaw === 'string') {
      blocks.push({ type: 'text', text: contentRaw });
    }
    message = { role: msgRaw.role || 'assistant', content: blocks, timestamp: msgRaw.timestamp || undefined };
  }

  return { runId, sessionKey, seq, state, message, errorMessage, stopReason };
}

function shouldSkipChatEvent(runId, seq, agentProcessedSeqs, agentActiveRunId) {
  let dedupKey = `${runId}:${seq}`;
  if (agentProcessedSeqs.has(dedupKey)) return true;
  if (agentActiveRunId.length > 0 && runId === agentActiveRunId) return true;
  return false;
}

describe('parseChatEvent', function () {
  it('basic chat event parsed correctly', function () {
    let result = parseChatEvent(JSON.stringify({
      runId: 'run-123',
      state: 'final',
      seq: 5,
      sessionKey: 'sess-abc'
    }));
    assertEqual(result.runId, 'run-123');
    assertEqual(result.state, 'final');
    assertEqual(result.seq, 5);
    assertEqual(result.sessionKey, 'sess-abc');
  });

  it('message with content blocks', function () {
    let result = parseChatEvent(JSON.stringify({
      runId: 'run-1',
      state: 'final',
      seq: 1,
      message: {
        role: 'assistant',
        content: [
          { type: 'text', text: 'Hello' },
          { type: 'text', text: ' World' }
        ],
        timestamp: 1700000000
      }
    }));
    assertDefined(result.message);
    assertEqual(result.message.role, 'assistant');
    assertEqual(result.message.content.length, 2);
    assertEqual(result.message.content[0].type, 'text');
    assertEqual(result.message.content[0].text, 'Hello');
    assertEqual(result.message.content[1].text, ' World');
    assertEqual(result.message.timestamp, 1700000000);
  });

  it('content as string creates single text block', function () {
    let result = parseChatEvent(JSON.stringify({
      runId: 'run-2',
      state: 'delta',
      seq: 2,
      message: {
        role: 'assistant',
        content: 'simple string content'
      }
    }));
    assertDefined(result.message);
    assertEqual(result.message.content.length, 1);
    assertEqual(result.message.content[0].type, 'text');
    assertEqual(result.message.content[0].text, 'simple string content');
  });
});

describe('shouldSkipChatEvent - dedup', function () {
  it('skip if runId:seq in agentProcessedSeqs', function () {
    let seqs = new Set();
    seqs.add('run-1:10');
    assertTrue(shouldSkipChatEvent('run-1', 10, seqs, ''));
  });

  it('skip if runId matches agentActiveRunId', function () {
    let seqs = new Set();
    assertTrue(shouldSkipChatEvent('active-run', 5, seqs, 'active-run'));
  });

  it('do not skip when no dedup match', function () {
    let seqs = new Set();
    assertFalse(shouldSkipChatEvent('run-new', 1, seqs, ''));
  });
});
