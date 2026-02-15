'use strict';

const { describe, it, beforeEach } = require('../lib/test-runner');
const { assertEqual, assertTrue, assertFalse } = require('../lib/assert');

// Dedup tracker mirroring the agent/chat event dedup logic from NodeRuntime.ets
class DedupTracker {
  constructor() {
    this.agentProcessedSeqs = new Set();
    this.agentActiveRunId = '';
    this.dispatchedEvents = [];
  }

  processAgentEvent(runId, seq, state) {
    let dedupKey = `${runId}:${seq}`;
    this.agentProcessedSeqs.add(dedupKey);
    this.agentActiveRunId = runId;
    this.dispatchedEvents.push({ source: 'agent', runId, seq, state });

    // In real code, cleanup happens after 3s setTimeout for final/error/aborted
    // For testing, we provide a cleanup() method
  }

  processChatEvent(runId, seq, state) {
    let dedupKey = `${runId}:${seq}`;
    if (this.agentProcessedSeqs.has(dedupKey)) return false; // skipped
    if (this.agentActiveRunId.length > 0 && runId === this.agentActiveRunId) return false; // skipped
    this.dispatchedEvents.push({ source: 'chat', runId, seq, state });
    return true; // dispatched
  }

  cleanup() {
    this.agentProcessedSeqs.clear();
    this.agentActiveRunId = '';
  }
}

describe('agent event dedup - basic flow', function () {
  let tracker;

  beforeEach(function () {
    tracker = new DedupTracker();
  });

  it('agent event seq=1 is dispatched', function () {
    tracker.processAgentEvent('run-1', 1, 'delta');
    assertEqual(tracker.dispatchedEvents.length, 1);
    assertEqual(tracker.dispatchedEvents[0].source, 'agent');
    assertEqual(tracker.dispatchedEvents[0].seq, 1);
  });

  it('chat event same runId+seq is skipped (dedup by seq)', function () {
    tracker.processAgentEvent('run-1', 1, 'delta');
    let dispatched = tracker.processChatEvent('run-1', 1, 'delta');
    assertFalse(dispatched, 'chat event with same runId+seq should be skipped');
    assertEqual(tracker.dispatchedEvents.length, 1, 'only agent event dispatched');
  });

  it('chat event same runId, different seq is skipped (active run dedup)', function () {
    tracker.processAgentEvent('run-1', 1, 'delta');
    let dispatched = tracker.processChatEvent('run-1', 2, 'delta');
    assertFalse(dispatched, 'chat event with same runId should be skipped by active run');
    assertEqual(tracker.dispatchedEvents.length, 1);
  });

  it('chat event different runId is dispatched', function () {
    tracker.processAgentEvent('run-1', 1, 'delta');
    let dispatched = tracker.processChatEvent('run-2', 1, 'delta');
    assertTrue(dispatched, 'chat event with different runId should be dispatched');
    assertEqual(tracker.dispatchedEvents.length, 2);
    assertEqual(tracker.dispatchedEvents[1].source, 'chat');
    assertEqual(tracker.dispatchedEvents[1].runId, 'run-2');
  });

  it('after cleanup: chat event same runId is dispatched', function () {
    tracker.processAgentEvent('run-1', 1, 'delta');
    tracker.cleanup();
    let dispatched = tracker.processChatEvent('run-1', 1, 'delta');
    assertTrue(dispatched, 'after cleanup, same runId+seq should be dispatched');
    assertEqual(tracker.dispatchedEvents.length, 2);
    assertEqual(tracker.dispatchedEvents[1].source, 'chat');
  });
});

describe('agent event dedup - multi-seq accumulation', function () {
  let tracker;

  beforeEach(function () {
    tracker = new DedupTracker();
  });

  it('multiple agent events build up seq set, subsequent chat events all skipped', function () {
    tracker.processAgentEvent('run-1', 1, 'delta');
    tracker.processAgentEvent('run-1', 2, 'delta');
    tracker.processAgentEvent('run-1', 3, 'delta');

    assertFalse(tracker.processChatEvent('run-1', 1, 'delta'), 'seq=1 skipped');
    assertFalse(tracker.processChatEvent('run-1', 2, 'delta'), 'seq=2 skipped');
    assertFalse(tracker.processChatEvent('run-1', 3, 'delta'), 'seq=3 skipped');
    // seq=4 not in processed set, but still skipped by active run dedup
    assertFalse(tracker.processChatEvent('run-1', 4, 'delta'), 'seq=4 skipped by active run');

    assertEqual(tracker.dispatchedEvents.length, 3, 'only 3 agent events dispatched');
  });

  it('agent final event still dedup active until cleanup', function () {
    tracker.processAgentEvent('run-1', 1, 'delta');
    tracker.processAgentEvent('run-1', 2, 'final');

    // Final was dispatched as agent event
    assertEqual(tracker.dispatchedEvents.length, 2);
    assertEqual(tracker.dispatchedEvents[1].state, 'final');

    // Chat events still blocked because no cleanup yet
    assertFalse(tracker.processChatEvent('run-1', 1, 'delta'), 'still dedup before cleanup');
    assertFalse(tracker.processChatEvent('run-1', 2, 'final'), 'final also dedup');
    assertFalse(tracker.processChatEvent('run-1', 3, 'delta'), 'active run dedup');

    assertEqual(tracker.dispatchedEvents.length, 2, 'no new dispatches');
  });

  it('fresh tracker dispatches chat events normally', function () {
    let dispatched1 = tracker.processChatEvent('run-1', 1, 'delta');
    assertTrue(dispatched1, 'fresh tracker: chat event dispatched');

    let dispatched2 = tracker.processChatEvent('run-1', 2, 'delta');
    assertTrue(dispatched2, 'fresh tracker: second chat event dispatched');

    let dispatched3 = tracker.processChatEvent('run-2', 1, 'final');
    assertTrue(dispatched3, 'fresh tracker: different run chat event dispatched');

    assertEqual(tracker.dispatchedEvents.length, 3);
  });
});

describe('agent event dedup - error and aborted states', function () {
  let tracker;

  beforeEach(function () {
    tracker = new DedupTracker();
  });

  it('agent error event is dispatched and dedup remains active', function () {
    tracker.processAgentEvent('run-1', 1, 'error');
    assertEqual(tracker.dispatchedEvents.length, 1);
    assertEqual(tracker.dispatchedEvents[0].state, 'error');

    assertFalse(tracker.processChatEvent('run-1', 1, 'error'), 'error event dedup');
    assertFalse(tracker.processChatEvent('run-1', 2, 'delta'), 'active run dedup');
  });

  it('agent aborted event is dispatched and dedup remains active', function () {
    tracker.processAgentEvent('run-1', 1, 'aborted');
    assertEqual(tracker.dispatchedEvents.length, 1);
    assertEqual(tracker.dispatchedEvents[0].state, 'aborted');

    assertFalse(tracker.processChatEvent('run-1', 1, 'aborted'), 'aborted event dedup');
  });

  it('cleanup after error allows new events through', function () {
    tracker.processAgentEvent('run-1', 1, 'error');
    tracker.cleanup();

    assertTrue(tracker.processChatEvent('run-1', 1, 'delta'), 'after cleanup, events dispatch');
    assertTrue(tracker.processChatEvent('run-1', 2, 'delta'), 'after cleanup, new seq dispatches');
  });

  it('switching runs: new agent run replaces active run id', function () {
    tracker.processAgentEvent('run-1', 1, 'delta');
    tracker.processAgentEvent('run-2', 1, 'delta');

    // Active run is now run-2
    assertEqual(tracker.agentActiveRunId, 'run-2');

    // run-1 seq=1 still in processed seqs
    assertFalse(tracker.processChatEvent('run-1', 1, 'delta'), 'run-1 seq=1 in processed set');

    // run-1 seq=2 not in processed set AND run-1 is not active run -> dispatched
    assertTrue(tracker.processChatEvent('run-1', 2, 'delta'), 'run-1 seq=2 not blocked');

    // run-2 blocked by active run
    assertFalse(tracker.processChatEvent('run-2', 2, 'delta'), 'run-2 blocked by active run');
  });
});
