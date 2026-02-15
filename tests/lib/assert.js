'use strict';
/**
 * Lightweight assertion library for ClawdbotHarmony tests.
 * Zero external dependencies.
 */

class AssertionError extends Error {
  constructor(message) {
    super(message);
    this.name = 'AssertionError';
  }
}

function assertEqual(actual, expected, msg) {
  if (actual !== expected) {
    throw new AssertionError(
      `${msg || 'assertEqual'}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`
    );
  }
}

function assertNotEqual(actual, expected, msg) {
  if (actual === expected) {
    throw new AssertionError(
      `${msg || 'assertNotEqual'}: values should differ but both are ${JSON.stringify(actual)}`
    );
  }
}

function assertTrue(val, msg) {
  if (val !== true) {
    throw new AssertionError(`${msg || 'assertTrue'}: expected true, got ${JSON.stringify(val)}`);
  }
}

function assertFalse(val, msg) {
  if (val !== false) {
    throw new AssertionError(`${msg || 'assertFalse'}: expected false, got ${JSON.stringify(val)}`);
  }
}

function assertUndefined(val, msg) {
  if (val !== undefined) {
    throw new AssertionError(`${msg || 'assertUndefined'}: expected undefined, got ${JSON.stringify(val)}`);
  }
}

function assertDefined(val, msg) {
  if (val === undefined || val === null) {
    throw new AssertionError(`${msg || 'assertDefined'}: expected defined value, got ${val}`);
  }
}

function assertDeepEqual(actual, expected, msg) {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a !== e) {
    throw new AssertionError(`${msg || 'assertDeepEqual'}:\n  expected: ${e}\n  actual:   ${a}`);
  }
}

function assertIncludes(arr, item, msg) {
  if (!Array.isArray(arr) || !arr.includes(item)) {
    throw new AssertionError(
      `${msg || 'assertIncludes'}: ${JSON.stringify(item)} not found in ${JSON.stringify(arr)}`
    );
  }
}

function assertNotIncludes(arr, item, msg) {
  if (Array.isArray(arr) && arr.includes(item)) {
    throw new AssertionError(
      `${msg || 'assertNotIncludes'}: ${JSON.stringify(item)} should not be in ${JSON.stringify(arr)}`
    );
  }
}

function assertStartsWith(str, prefix, msg) {
  if (typeof str !== 'string' || !str.startsWith(prefix)) {
    throw new AssertionError(
      `${msg || 'assertStartsWith'}: ${JSON.stringify(str)} does not start with ${JSON.stringify(prefix)}`
    );
  }
}

function assertThrows(fn, msg) {
  try {
    fn();
  } catch (_e) {
    return;
  }
  throw new AssertionError(`${msg || 'assertThrows'}: expected function to throw`);
}

function assertGreaterThan(actual, expected, msg) {
  if (actual <= expected) {
    throw new AssertionError(
      `${msg || 'assertGreaterThan'}: expected ${actual} > ${expected}`
    );
  }
}

function assertLessThan(actual, expected, msg) {
  if (actual >= expected) {
    throw new AssertionError(
      `${msg || 'assertLessThan'}: expected ${actual} < ${expected}`
    );
  }
}

function assertMatch(str, regex, msg) {
  if (typeof str !== 'string' || !regex.test(str)) {
    throw new AssertionError(
      `${msg || 'assertMatch'}: ${JSON.stringify(str)} does not match ${regex}`
    );
  }
}

module.exports = {
  AssertionError,
  assertEqual,
  assertNotEqual,
  assertTrue,
  assertFalse,
  assertUndefined,
  assertDefined,
  assertDeepEqual,
  assertIncludes,
  assertNotIncludes,
  assertStartsWith,
  assertThrows,
  assertGreaterThan,
  assertLessThan,
  assertMatch,
};
