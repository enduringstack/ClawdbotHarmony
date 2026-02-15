'use strict';

const { describe, it } = require('../lib/test-runner');
const { assertEqual } = require('../lib/assert');

// ConnectionState enum values from NodeRuntime.ets
const Connected = 'Connected';
const Connecting = 'Connecting\u2026';
const Reconnecting = 'Reconnecting\u2026';
const ErrorState = 'Error';
const Disconnected = 'Offline';

// Mirror of updateStatus logic from NodeRuntime.ets lines 1156-1195
function getStatusText(operatorState, nodeState, pairingScopeMissing) {
  let opConnected = operatorState === Connected;
  let nodeConnected = nodeState === Connected;

  if (opConnected && nodeConnected) return 'Connected';
  if (opConnected && !nodeConnected) return pairingScopeMissing ? 'Connected (node not paired)' : 'Connected (node offline)';
  if (!opConnected && nodeConnected) return 'Connected (operator offline)';
  if (operatorState === Connecting || nodeState === Connecting) return 'Connecting\u2026';
  if (operatorState === Reconnecting || nodeState === Reconnecting) return 'Reconnecting\u2026';
  if (operatorState === ErrorState || nodeState === ErrorState) return 'Error';
  return 'Offline';
}

describe('getStatusText', function () {
  it('both connected -> Connected', function () {
    assertEqual(getStatusText(Connected, Connected, false), 'Connected');
  });

  it('op connected, node disconnected -> Connected (node offline)', function () {
    assertEqual(getStatusText(Connected, Disconnected, false), 'Connected (node offline)');
  });

  it('op connected, node disconnected, pairingScopeMissing -> Connected (node not paired)', function () {
    assertEqual(getStatusText(Connected, Disconnected, true), 'Connected (node not paired)');
  });

  it('op disconnected, node connected -> Connected (operator offline)', function () {
    assertEqual(getStatusText(Disconnected, Connected, false), 'Connected (operator offline)');
  });

  it('op connecting, node disconnected -> Connecting...', function () {
    assertEqual(getStatusText(Connecting, Disconnected, false), 'Connecting\u2026');
  });

  it('op disconnected, node connecting -> Connecting...', function () {
    assertEqual(getStatusText(Disconnected, Connecting, false), 'Connecting\u2026');
  });

  it('op reconnecting, node disconnected -> Reconnecting...', function () {
    assertEqual(getStatusText(Reconnecting, Disconnected, false), 'Reconnecting\u2026');
  });

  it('op error, node disconnected -> Error', function () {
    assertEqual(getStatusText(ErrorState, Disconnected, false), 'Error');
  });

  it('both disconnected -> Offline', function () {
    assertEqual(getStatusText(Disconnected, Disconnected, false), 'Offline');
  });

  it('op connected, node error -> Connected (node offline)', function () {
    assertEqual(getStatusText(Connected, ErrorState, false), 'Connected (node offline)');
  });

  it('op connected, node error, pairingScopeMissing -> Connected (node not paired)', function () {
    assertEqual(getStatusText(Connected, ErrorState, true), 'Connected (node not paired)');
  });

  it('op connected, node connecting -> Connected (node offline)', function () {
    assertEqual(getStatusText(Connected, Connecting, false), 'Connected (node offline)');
  });

  it('op connected, node reconnecting -> Connected (node offline)', function () {
    assertEqual(getStatusText(Connected, Reconnecting, false), 'Connected (node offline)');
  });

  it('op error, node error -> Error', function () {
    assertEqual(getStatusText(ErrorState, ErrorState, false), 'Error');
  });

  it('op reconnecting, node error -> Reconnecting...', function () {
    assertEqual(getStatusText(Reconnecting, ErrorState, false), 'Reconnecting\u2026');
  });
});
