'use strict';

const { describe, it } = require('../lib/test-runner');
const { assertEqual } = require('../lib/assert');

// State constants
const C = 'Connected';
const Ci = 'Connecting\u2026';
const R = 'Reconnecting\u2026';
const E = 'Error';
const D = 'Offline';

const ALL_STATES = [C, Ci, R, E, D];

// Mirror of connection state logic from NodeRuntime.ets
function getConnectionState(opState, nodeState) {
  if (opState === C && nodeState === C) return C;
  if (opState === C || nodeState === C) return C;
  if (opState === Ci || nodeState === Ci) return Ci;
  if (opState === R || nodeState === R) return R;
  if (opState === E || nodeState === E) return E;
  return D;
}

function getStatusText(opState, nodeState, pairingScopeMissing) {
  let opC = opState === C, nodeC = nodeState === C;
  if (opC && nodeC) return 'Connected';
  if (opC && !nodeC) return pairingScopeMissing ? 'Connected (node not paired)' : 'Connected (node offline)';
  if (!opC && nodeC) return 'Connected (operator offline)';
  if (opState === Ci || nodeState === Ci) return 'Connecting\u2026';
  if (opState === R || nodeState === R) return 'Reconnecting\u2026';
  if (opState === E || nodeState === E) return 'Error';
  return 'Offline';
}

// Expected results for ALL 25 combinations of getConnectionState
// Priority: Connected > Connecting > Reconnecting > Error > Offline
function expectedState(op, node) {
  if (op === C || node === C) return C;
  if (op === Ci || node === Ci) return Ci;
  if (op === R || node === R) return R;
  if (op === E || node === E) return E;
  return D;
}

// --- Test ALL 25 combinations of getConnectionState ---

describe('getConnectionState - all 25 combinations', function () {
  for (const op of ALL_STATES) {
    for (const node of ALL_STATES) {
      const expected = expectedState(op, node);
      it(`op=${op}, node=${node} -> ${expected}`, function () {
        assertEqual(getConnectionState(op, node), expected);
      });
    }
  }
});

// --- getStatusText tests ---

describe('getStatusText - both connected', function () {
  it('both connected -> "Connected"', function () {
    assertEqual(getStatusText(C, C, false), 'Connected');
  });

  it('both connected, pairingScopeMissing irrelevant -> "Connected"', function () {
    assertEqual(getStatusText(C, C, true), 'Connected');
  });
});

describe('getStatusText - operator connected, node not', function () {
  it('op=Connected, node=Offline, pairing=false -> "Connected (node offline)"', function () {
    assertEqual(getStatusText(C, D, false), 'Connected (node offline)');
  });

  it('op=Connected, node=Offline, pairing=true -> "Connected (node not paired)"', function () {
    assertEqual(getStatusText(C, D, true), 'Connected (node not paired)');
  });

  it('op=Connected, node=Connecting, pairing=false -> "Connected (node offline)"', function () {
    assertEqual(getStatusText(C, Ci, false), 'Connected (node offline)');
  });

  it('op=Connected, node=Reconnecting, pairing=true -> "Connected (node not paired)"', function () {
    assertEqual(getStatusText(C, R, true), 'Connected (node not paired)');
  });

  it('op=Connected, node=Error, pairing=false -> "Connected (node offline)"', function () {
    assertEqual(getStatusText(C, E, false), 'Connected (node offline)');
  });
});

describe('getStatusText - node connected, operator not', function () {
  it('op=Offline, node=Connected -> "Connected (operator offline)"', function () {
    assertEqual(getStatusText(D, C, false), 'Connected (operator offline)');
  });

  it('op=Connecting, node=Connected -> "Connected (operator offline)"', function () {
    assertEqual(getStatusText(Ci, C, false), 'Connected (operator offline)');
  });

  it('op=Reconnecting, node=Connected -> "Connected (operator offline)"', function () {
    assertEqual(getStatusText(R, C, false), 'Connected (operator offline)');
  });

  it('op=Error, node=Connected -> "Connected (operator offline)"', function () {
    assertEqual(getStatusText(E, C, false), 'Connected (operator offline)');
  });

  it('pairingScopeMissing does not affect operator offline text', function () {
    assertEqual(getStatusText(D, C, true), 'Connected (operator offline)');
  });
});

describe('getStatusText - neither connected', function () {
  it('both Connecting -> "Connecting..."', function () {
    assertEqual(getStatusText(Ci, Ci, false), 'Connecting\u2026');
  });

  it('op=Connecting, node=Offline -> "Connecting..."', function () {
    assertEqual(getStatusText(Ci, D, false), 'Connecting\u2026');
  });

  it('op=Offline, node=Connecting -> "Connecting..."', function () {
    assertEqual(getStatusText(D, Ci, false), 'Connecting\u2026');
  });

  it('op=Connecting, node=Error -> "Connecting..."', function () {
    assertEqual(getStatusText(Ci, E, false), 'Connecting\u2026');
  });

  it('both Reconnecting -> "Reconnecting..."', function () {
    assertEqual(getStatusText(R, R, false), 'Reconnecting\u2026');
  });

  it('op=Reconnecting, node=Offline -> "Reconnecting..."', function () {
    assertEqual(getStatusText(R, D, false), 'Reconnecting\u2026');
  });

  it('op=Reconnecting, node=Error -> "Reconnecting..."', function () {
    assertEqual(getStatusText(R, E, false), 'Reconnecting\u2026');
  });

  it('both Error -> "Error"', function () {
    assertEqual(getStatusText(E, E, false), 'Error');
  });

  it('op=Error, node=Offline -> "Error"', function () {
    assertEqual(getStatusText(E, D, false), 'Error');
  });

  it('op=Offline, node=Error -> "Error"', function () {
    assertEqual(getStatusText(D, E, false), 'Error');
  });

  it('both Offline -> "Offline"', function () {
    assertEqual(getStatusText(D, D, false), 'Offline');
  });

  it('both Offline, pairingScopeMissing irrelevant -> "Offline"', function () {
    assertEqual(getStatusText(D, D, true), 'Offline');
  });
});
