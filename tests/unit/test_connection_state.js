'use strict';

const { describe, it } = require('../lib/test-runner');
const { assertEqual } = require('../lib/assert');

// ConnectionState enum values from NodeRuntime.ets lines 144-166
const Connected = 'Connected';
const Connecting = 'Connecting\u2026';
const Reconnecting = 'Reconnecting\u2026';
const ErrorState = 'Error';
const Disconnected = 'Offline';

// Mirror of connectionState getter logic
function getConnectionState(operatorState, nodeState) {
  if (operatorState === Connected && nodeState === Connected) return Connected;
  if (operatorState === Connected || nodeState === Connected) return Connected;
  if (operatorState === Connecting || nodeState === Connecting) return Connecting;
  if (operatorState === Reconnecting || nodeState === Reconnecting) return Reconnecting;
  if (operatorState === ErrorState || nodeState === ErrorState) return ErrorState;
  return Disconnected;
}

describe('getConnectionState', function () {
  // Both connected
  it('both connected -> Connected', function () {
    assertEqual(getConnectionState(Connected, Connected), Connected);
  });

  // One connected, other in various states
  it('operator connected, node disconnected -> Connected', function () {
    assertEqual(getConnectionState(Connected, Disconnected), Connected);
  });

  it('operator connected, node connecting -> Connected', function () {
    assertEqual(getConnectionState(Connected, Connecting), Connected);
  });

  it('operator connected, node reconnecting -> Connected', function () {
    assertEqual(getConnectionState(Connected, Reconnecting), Connected);
  });

  it('operator connected, node error -> Connected', function () {
    assertEqual(getConnectionState(Connected, ErrorState), Connected);
  });

  it('operator disconnected, node connected -> Connected', function () {
    assertEqual(getConnectionState(Disconnected, Connected), Connected);
  });

  it('operator connecting, node connected -> Connected', function () {
    assertEqual(getConnectionState(Connecting, Connected), Connected);
  });

  it('operator error, node connected -> Connected', function () {
    assertEqual(getConnectionState(ErrorState, Connected), Connected);
  });

  // Both connecting
  it('both connecting -> Connecting', function () {
    assertEqual(getConnectionState(Connecting, Connecting), Connecting);
  });

  // One connecting, other disconnected
  it('operator connecting, node disconnected -> Connecting', function () {
    assertEqual(getConnectionState(Connecting, Disconnected), Connecting);
  });

  it('operator disconnected, node connecting -> Connecting', function () {
    assertEqual(getConnectionState(Disconnected, Connecting), Connecting);
  });

  // Reconnecting states
  it('both reconnecting -> Reconnecting', function () {
    assertEqual(getConnectionState(Reconnecting, Reconnecting), Reconnecting);
  });

  it('operator reconnecting, node disconnected -> Reconnecting', function () {
    assertEqual(getConnectionState(Reconnecting, Disconnected), Reconnecting);
  });

  it('operator disconnected, node reconnecting -> Reconnecting', function () {
    assertEqual(getConnectionState(Disconnected, Reconnecting), Reconnecting);
  });

  // Error states
  it('operator error, node disconnected -> Error', function () {
    assertEqual(getConnectionState(ErrorState, Disconnected), ErrorState);
  });

  it('operator disconnected, node error -> Error', function () {
    assertEqual(getConnectionState(Disconnected, ErrorState), ErrorState);
  });

  it('both error -> Error', function () {
    assertEqual(getConnectionState(ErrorState, ErrorState), ErrorState);
  });

  // Both disconnected
  it('both disconnected -> Offline', function () {
    assertEqual(getConnectionState(Disconnected, Disconnected), Disconnected);
  });

  // Mixed non-connected states (priority checks)
  it('operator connecting, node reconnecting -> Connecting (connecting takes priority)', function () {
    assertEqual(getConnectionState(Connecting, Reconnecting), Connecting);
  });

  it('operator reconnecting, node connecting -> Connecting (connecting takes priority)', function () {
    assertEqual(getConnectionState(Reconnecting, Connecting), Connecting);
  });

  it('operator connecting, node error -> Connecting (connecting takes priority)', function () {
    assertEqual(getConnectionState(Connecting, ErrorState), Connecting);
  });

  it('operator error, node reconnecting -> Reconnecting (reconnecting takes priority over error)', function () {
    assertEqual(getConnectionState(ErrorState, Reconnecting), Reconnecting);
  });

  it('operator reconnecting, node error -> Reconnecting (reconnecting takes priority over error)', function () {
    assertEqual(getConnectionState(Reconnecting, ErrorState), Reconnecting);
  });
});
