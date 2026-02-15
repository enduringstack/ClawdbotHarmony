'use strict';
/**
 * Scenario test: Deduplication of interleaved agent and chat events.
 *
 * The gateway may send both "agent" events (preferred, real-time deltas)
 * and "chat" events (fallback, cumulative messages) for the same run.
 * The client must deduplicate: if an agent event was already processed
 * for a given runId:seq, the corresponding chat event should be skipped.
 *
 * Validates that:
 *   - Agent events are always dispatched
 *   - Duplicate chat events are skipped
 *   - After dedup state cleanup, new events are dispatched
 *   - Mixed run IDs are handled independently
 */

const { describe, it, beforeEach } = require('../lib/test-runner');
const {
  assertEqual, assertTrue, assertFalse,
} = require('../lib/assert');

// --- DedupTracker: mirrors dedup logic from NodeRuntime.ets ---

class DedupTracker {
  constructor() {
    /** Set of "runId:seq" keys already processed via agent events */
    this.agentProcessedSeqs = new Set();
    /** The currently active agent runId (agent events are streaming) */
    this.agentActiveRunId = '';
    /** Dispatch log for test verification */
    this.dispatched = [];
    this.skipped = [];
  }

  /**
   * Process an agent event. Always dispatched; records the key for dedup.
   */
  processAgentEvent(runId, seq, data) {
    const dedupKey = runId + ':' + seq;
    this.agentProcessedSeqs.add(dedupKey);
    this.agentActiveRunId = runId;
    this.dispatched.push({ source: 'agent', runId, seq, data });
  }

  /**
   * Process a chat event. Skipped if already handled by an agent event.
   */
  processChatEvent(runId, seq, data) {
    const dedupKey = runId + ':' + seq;

    // Skip if this exact runId:seq was already processed via agent
    if (this.agentProcessedSeqs.has(dedupKey)) {
      this.skipped.push({ source: 'chat', runId, seq, reason: 'seq-dedup' });
      return false;
    }

    // Skip if the agent is actively streaming for this runId
    if (this.agentActiveRunId.length > 0 && runId === this.agentActiveRunId) {
      this.skipped.push({ source: 'chat', runId, seq, reason: 'active-run' });
      return false;
    }

    // No dedup match - dispatch
    this.dispatched.push({ source: 'chat', runId, seq, data });
    return true;
  }

  /**
   * Clear dedup state (e.g., when a run completes or on reconnect).
   */
  clearDedup() {
    this.agentProcessedSeqs.clear();
    this.agentActiveRunId = '';
  }

  getDispatchedCount(source) {
    return this.dispatched.filter(d => d.source === source).length;
  }

  getSkippedCount(source) {
    return this.skipped.filter(s => s.source === source).length;
  }
}

// --- Event simulation helpers ---

function buildAgentEvent(runId, seq, delta) {
  return {
    source: 'agent',
    payload: { runId, seq, stream: 'assistant', data: { delta } }
  };
}

function buildChatEvent(runId, seq, state, cumulativeText) {
  return {
    source: 'chat',
    payload: {
      runId, seq, state,
      message: { role: 'assistant', content: [{ type: 'text', text: cumulativeText }] }
    }
  };
}

/**
 * Build the standard interleaved event sequence from the spec.
 */
function buildInterleavedEvents() {
  return [
    buildAgentEvent('R1', 0, 'Hi'),
    buildChatEvent('R1', 0, 'delta', 'Hi'),
    buildAgentEvent('R1', 1, ' there'),
    buildChatEvent('R1', 1, 'delta', 'Hi there'),
    buildAgentEvent('R1', 2, '!'),
    buildChatEvent('R1', 2, 'final', 'Hi there!'),
  ];
}

/**
 * Process an event through the dedup tracker.
 */
function processEvent(tracker, event) {
  const p = event.payload;
  if (event.source === 'agent') {
    tracker.processAgentEvent(p.runId, p.seq, p.data);
  } else {
    tracker.processChatEvent(p.runId, p.seq, p);
  }
}

// --- Tests ---

describe('Dedup agent vs chat - interleaved events', function () {
  let tracker;

  beforeEach(function () {
    tracker = new DedupTracker();
  });

  it('only agent events dispatched from interleaved sequence (3 total)', function () {
    const events = buildInterleavedEvents();
    for (const evt of events) {
      processEvent(tracker, evt);
    }
    assertEqual(tracker.getDispatchedCount('agent'), 3, 'should dispatch 3 agent events');
  });

  it('all chat events skipped from interleaved sequence (3 total)', function () {
    const events = buildInterleavedEvents();
    for (const evt of events) {
      processEvent(tracker, evt);
    }
    assertEqual(tracker.getSkippedCount('chat'), 3, 'should skip 3 chat events');
  });

  it('no chat events dispatched during active agent run', function () {
    const events = buildInterleavedEvents();
    for (const evt of events) {
      processEvent(tracker, evt);
    }
    assertEqual(tracker.getDispatchedCount('chat'), 0, 'should dispatch 0 chat events');
  });

  it('total dispatched events = 3 (all agent)', function () {
    const events = buildInterleavedEvents();
    for (const evt of events) {
      processEvent(tracker, evt);
    }
    assertEqual(tracker.dispatched.length, 3);
  });

  it('dispatched agent events have correct sequence order', function () {
    const events = buildInterleavedEvents();
    for (const evt of events) {
      processEvent(tracker, evt);
    }
    assertEqual(tracker.dispatched[0].seq, 0);
    assertEqual(tracker.dispatched[1].seq, 1);
    assertEqual(tracker.dispatched[2].seq, 2);
  });

  it('dispatched agent deltas reconstruct full text', function () {
    const events = buildInterleavedEvents();
    for (const evt of events) {
      processEvent(tracker, evt);
    }
    const fullText = tracker.dispatched
      .filter(d => d.source === 'agent')
      .map(d => d.data.delta)
      .join('');
    assertEqual(fullText, 'Hi there!');
  });
});

describe('Dedup agent vs chat - after cleanup', function () {
  let tracker;

  beforeEach(function () {
    tracker = new DedupTracker();
  });

  it('after cleanup: new chat event for different runId is dispatched', function () {
    // Process interleaved events for R1
    const events = buildInterleavedEvents();
    for (const evt of events) {
      processEvent(tracker, evt);
    }

    // Clear dedup state
    tracker.clearDedup();

    // New chat event for a different runId
    const newChat = buildChatEvent('R2', 0, 'delta', 'New message');
    processEvent(tracker, newChat);

    assertEqual(tracker.getDispatchedCount('chat'), 1, 'new chat for R2 should be dispatched');
  });

  it('after cleanup: new chat event for same runId R1 is dispatched', function () {
    const events = buildInterleavedEvents();
    for (const evt of events) {
      processEvent(tracker, evt);
    }

    tracker.clearDedup();

    // Same runId R1 but dedup was cleared
    const replayChat = buildChatEvent('R1', 0, 'delta', 'Replayed');
    processEvent(tracker, replayChat);

    assertEqual(tracker.getDispatchedCount('chat'), 1, 'R1 chat after cleanup should dispatch');
  });

  it('total dispatched after cleanup = 3 agent + post-cleanup chat', function () {
    const events = buildInterleavedEvents();
    for (const evt of events) {
      processEvent(tracker, evt);
    }

    tracker.clearDedup();

    processEvent(tracker, buildChatEvent('R2', 0, 'delta', 'Post-cleanup 1'));
    processEvent(tracker, buildChatEvent('R3', 0, 'final', 'Post-cleanup 2'));

    assertEqual(tracker.getDispatchedCount('agent'), 3, 'agent count unchanged');
    assertEqual(tracker.getDispatchedCount('chat'), 2, 'two post-cleanup chat events');
    assertEqual(tracker.dispatched.length, 5, 'total dispatched = 3 + 2');
  });

  it('clearDedup resets agentActiveRunId', function () {
    const tracker2 = new DedupTracker();
    tracker2.processAgentEvent('R1', 0, { delta: 'hi' });
    assertEqual(tracker2.agentActiveRunId, 'R1');
    tracker2.clearDedup();
    assertEqual(tracker2.agentActiveRunId, '', 'activeRunId should be empty after clear');
  });

  it('clearDedup resets agentProcessedSeqs', function () {
    const tracker2 = new DedupTracker();
    tracker2.processAgentEvent('R1', 0, { delta: 'hi' });
    assertTrue(tracker2.agentProcessedSeqs.has('R1:0'));
    tracker2.clearDedup();
    assertFalse(tracker2.agentProcessedSeqs.has('R1:0'), 'seq should be cleared');
    assertEqual(tracker2.agentProcessedSeqs.size, 0);
  });
});

describe('Dedup agent vs chat - mixed run IDs', function () {
  let tracker;

  beforeEach(function () {
    tracker = new DedupTracker();
  });

  it('chat event for different runId during active agent run is dispatched', function () {
    // Agent starts run R1
    tracker.processAgentEvent('R1', 0, { delta: 'Hello' });

    // Chat event arrives for a *different* run R-other
    const dispatched = tracker.processChatEvent('R-other', 0, { text: 'unrelated' });
    assertTrue(dispatched, 'chat for different runId should be dispatched');
  });

  it('chat event for same runId during active agent run is skipped', function () {
    tracker.processAgentEvent('R1', 0, { delta: 'Hello' });

    // Chat for same runId but different seq (not in processed set, but active run matches)
    const dispatched = tracker.processChatEvent('R1', 99, { text: 'dup' });
    assertFalse(dispatched, 'chat for active runId should be skipped');
  });

  it('agent events for different runs update activeRunId', function () {
    tracker.processAgentEvent('R1', 0, { delta: 'a' });
    assertEqual(tracker.agentActiveRunId, 'R1');

    tracker.processAgentEvent('R2', 0, { delta: 'b' });
    assertEqual(tracker.agentActiveRunId, 'R2');

    // Chat for R1 is now dispatched because activeRunId is R2
    // But R1:0 is still in processedSeqs, so it's still deduped by seq
    const dispatched = tracker.processChatEvent('R1', 0, {});
    assertFalse(dispatched, 'R1:0 still in processedSeqs');

    // Chat for R1 with a new seq (not in processed set, and activeRunId is R2)
    const dispatched2 = tracker.processChatEvent('R1', 5, {});
    assertTrue(dispatched2, 'R1:5 not in processedSeqs and activeRunId is R2');
  });
});

describe('Dedup agent vs chat - edge cases', function () {
  let tracker;

  beforeEach(function () {
    tracker = new DedupTracker();
  });

  it('chat-only flow (no agent events) dispatches all chat events', function () {
    tracker.processChatEvent('R1', 0, { text: 'a' });
    tracker.processChatEvent('R1', 1, { text: 'b' });
    tracker.processChatEvent('R1', 2, { text: 'c' });

    assertEqual(tracker.getDispatchedCount('chat'), 3);
    assertEqual(tracker.getSkippedCount('chat'), 0);
  });

  it('agent-only flow (no chat events) dispatches all agent events', function () {
    tracker.processAgentEvent('R1', 0, { delta: 'x' });
    tracker.processAgentEvent('R1', 1, { delta: 'y' });

    assertEqual(tracker.getDispatchedCount('agent'), 2);
    assertEqual(tracker.getSkippedCount('chat'), 0);
  });

  it('duplicate agent events are still dispatched (agent never skipped)', function () {
    tracker.processAgentEvent('R1', 0, { delta: 'a' });
    tracker.processAgentEvent('R1', 0, { delta: 'a' });

    assertEqual(tracker.getDispatchedCount('agent'), 2, 'both agent events dispatched');
  });
});
