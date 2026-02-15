'use strict';
/**
 * Unit tests for buildClientInfo logic.
 * Source: NodeRuntime.ets lines 1708-1720
 */

const { describe, it } = require('../lib/test-runner');
const { assertEqual, assertTrue, assertFalse } = require('../lib/assert');

const APP_VERSION = '2.10.9';

// Mirror of buildClientInfo from NodeRuntime.ets
function buildClientInfo(clientId, clientMode, displayName) {
  let info = {
    id: clientId,
    version: APP_VERSION,
    platform: 'HarmonyOS',
    mode: clientMode,
    deviceFamily: 'HarmonyOS',
  };
  if (displayName && displayName.length > 0) {
    info.displayName = displayName;
  }
  return info;
}

describe('buildClientInfo', function () {
  it('returns correct basic fields without displayName', function () {
    const info = buildClientInfo('test-client', 'node');
    assertEqual(info.id, 'test-client');
    assertEqual(info.version, APP_VERSION);
    assertEqual(info.platform, 'HarmonyOS');
    assertEqual(info.mode, 'node');
    assertEqual(info.deviceFamily, 'HarmonyOS');
  });

  it('does not include displayName when not provided', function () {
    const info = buildClientInfo('test-client', 'node');
    assertFalse(info.hasOwnProperty('displayName'),
      'displayName should not be present');
  });

  it('includes displayName when provided', function () {
    const info = buildClientInfo('test-client', 'ui', 'Test');
    assertTrue(info.hasOwnProperty('displayName'),
      'displayName should be present');
    assertEqual(info.displayName, 'Test');
  });

  it('does not include displayName when empty string', function () {
    const info = buildClientInfo('test-client', 'node', '');
    assertFalse(info.hasOwnProperty('displayName'),
      'displayName should not be present for empty string');
  });
});
