'use strict';
/**
 * Unit tests for InvokeResult.
 * Source: GatewayModels.ets lines 78-98
 */

const { describe, it } = require('../lib/test-runner');
const { assertTrue, assertFalse, assertEqual, assertUndefined } = require('../lib/assert');

// Mirror of InvokeResult from GatewayModels.ets
class InvokeResult {
  constructor() {
    this.ok = true;
    this.payloadJson = undefined;
    this.errorCode = undefined;
    this.errorMessage = undefined;
  }

  static success(payloadJson) {
    let r = new InvokeResult();
    r.ok = true;
    r.payloadJson = payloadJson;
    return r;
  }

  static error(code, message) {
    let r = new InvokeResult();
    r.ok = false;
    r.errorCode = code;
    r.errorMessage = message;
    return r;
  }
}

describe('InvokeResult', function () {
  it('success() with no payload returns ok=true, payloadJson=undefined', function () {
    const r = InvokeResult.success();
    assertTrue(r.ok, 'ok should be true');
    assertUndefined(r.payloadJson, 'payloadJson should be undefined');
  });

  it('success(payload) returns ok=true with correct payloadJson', function () {
    const r = InvokeResult.success('{"data":1}');
    assertTrue(r.ok, 'ok should be true');
    assertEqual(r.payloadJson, '{"data":1}');
  });

  it('error(code, message) returns ok=false with correct error fields', function () {
    const r = InvokeResult.error('INVALID', 'bad');
    assertFalse(r.ok, 'ok should be false');
    assertEqual(r.errorCode, 'INVALID');
    assertEqual(r.errorMessage, 'bad');
  });
});
