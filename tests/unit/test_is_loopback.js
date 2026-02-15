'use strict';
/**
 * Unit tests for isLoopback logic.
 * Source: GatewaySession.ets lines 787-793
 */

const { describe, it } = require('../lib/test-runner');
const { assertTrue, assertFalse } = require('../lib/assert');

// Mirror of isLoopback logic from GatewaySession.ets
function isLoopback(host) {
  let h = host.trim().toLowerCase();
  if (h === 'localhost' || h === '::1' || h === '0.0.0.0' || h === '::') return true;
  return h.startsWith('127.');
}

describe('isLoopback', function () {
  it('returns true for localhost', function () {
    assertTrue(isLoopback('localhost'));
  });

  it('returns true for LOCALHOST (case-insensitive)', function () {
    assertTrue(isLoopback('LOCALHOST'));
  });

  it('returns true for localhost with surrounding spaces', function () {
    assertTrue(isLoopback(' localhost '));
  });

  it('returns true for 127.0.0.1', function () {
    assertTrue(isLoopback('127.0.0.1'));
  });

  it('returns true for 127.255.255.255', function () {
    assertTrue(isLoopback('127.255.255.255'));
  });

  it('returns true for ::1', function () {
    assertTrue(isLoopback('::1'));
  });

  it('returns true for 0.0.0.0', function () {
    assertTrue(isLoopback('0.0.0.0'));
  });

  it('returns true for ::', function () {
    assertTrue(isLoopback('::'));
  });

  it('returns false for 192.168.1.1', function () {
    assertFalse(isLoopback('192.168.1.1'));
  });

  it('returns false for gateway.local', function () {
    assertFalse(isLoopback('gateway.local'));
  });

  it('returns false for empty string', function () {
    assertFalse(isLoopback(''));
  });

  it('returns false for 128.0.0.1', function () {
    assertFalse(isLoopback('128.0.0.1'));
  });
});
