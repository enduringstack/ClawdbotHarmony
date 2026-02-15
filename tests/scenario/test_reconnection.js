'use strict';
/**
 * Scenario test: Exponential backoff reconnection logic.
 *
 * Mirrors the reconnection delay calculation from GatewaySession.ets
 * using constants from Constants.ets:
 *   GATEWAY_RECONNECT_BASE_MS   = 350
 *   GATEWAY_RECONNECT_MULTIPLIER = 1.7
 *   GATEWAY_RECONNECT_MAX_MS    = 8000
 *
 * Formula: delay = min(MAX, BASE * MULTIPLIER^attempt)
 *
 * Validates specific attempt values, cap behavior, monotonicity,
 * and reset-on-success semantics.
 */

const { describe, it } = require('../lib/test-runner');
const {
  assertEqual, assertTrue, assertGreaterThan, assertLessThan,
} = require('../lib/assert');

// --- Mirror of reconnection constants from Constants.ets lines 69-71 ---

const BASE = 350;
const MULTIPLIER = 1.7;
const MAX = 8000;

/**
 * Calculate reconnection delay for a given attempt number.
 * Mirrors GatewaySession.ets reconnection logic.
 */
function calculateReconnectDelay(attempt) {
  return Math.min(MAX, BASE * Math.pow(MULTIPLIER, attempt));
}

/**
 * Simulate a reconnection state machine.
 * Returns the sequence of delays for the given number of attempts.
 */
function simulateReconnectionSequence(numAttempts) {
  const delays = [];
  let attempt = 0;
  for (let i = 0; i < numAttempts; i++) {
    delays.push(calculateReconnectDelay(attempt));
    attempt++;
  }
  return delays;
}

/**
 * Simulate reconnection with a successful reconnect at a given attempt.
 * After success, the attempt counter resets to 0.
 */
function simulateWithSuccessAt(successAtAttempt, totalAttempts) {
  const delays = [];
  let attempt = 0;
  for (let i = 0; i < totalAttempts; i++) {
    delays.push(calculateReconnectDelay(attempt));
    if (i === successAtAttempt) {
      // Successful reconnect resets the counter
      attempt = 0;
    } else {
      attempt++;
    }
  }
  return delays;
}

// --- Tests ---

describe('Reconnection delay - specific attempts', function () {
  it('attempt 0: 350 * 1.7^0 = 350ms', function () {
    const delay = calculateReconnectDelay(0);
    assertEqual(delay, 350);
  });

  it('attempt 1: 350 * 1.7^1 = 595ms', function () {
    const delay = calculateReconnectDelay(1);
    assertEqual(delay, 350 * 1.7);
    assertEqual(delay, 595);
  });

  it('attempt 2: 350 * 1.7^2 = ~1011.5ms', function () {
    const delay = calculateReconnectDelay(2);
    const expected = 350 * Math.pow(1.7, 2);
    assertEqual(delay, expected);
    // Verify approximate value
    assertGreaterThan(delay, 1011);
    assertLessThan(delay, 1012);
  });

  it('attempt 3: 350 * 1.7^3 = ~1719.6ms', function () {
    const delay = calculateReconnectDelay(3);
    const expected = 350 * Math.pow(1.7, 3);
    assertEqual(delay, expected);
    assertGreaterThan(delay, 1719);
    assertLessThan(delay, 1720);
  });

  it('attempt 5: 350 * 1.7^5 = ~4969.5ms', function () {
    const delay = calculateReconnectDelay(5);
    const expected = 350 * Math.pow(1.7, 5);
    assertEqual(delay, expected);
    assertGreaterThan(delay, 4969);
    assertLessThan(delay, 4970);
  });
});

describe('Reconnection delay - cap behavior', function () {
  it('attempt 10: capped at 8000ms', function () {
    const delay = calculateReconnectDelay(10);
    assertEqual(delay, MAX);
  });

  it('attempt 20: still capped at 8000ms', function () {
    const delay = calculateReconnectDelay(20);
    assertEqual(delay, MAX);
  });

  it('attempt 50: still capped at 8000ms', function () {
    const delay = calculateReconnectDelay(50);
    assertEqual(delay, MAX);
  });

  it('attempt 100: still capped at 8000ms', function () {
    const delay = calculateReconnectDelay(100);
    assertEqual(delay, MAX);
  });

  it('uncapped value at attempt 7 exceeds MAX', function () {
    const uncapped = BASE * Math.pow(MULTIPLIER, 7);
    assertGreaterThan(uncapped, MAX, 'raw value at attempt 7 should exceed MAX');
    assertEqual(calculateReconnectDelay(7), MAX, 'capped value should equal MAX');
  });
});

describe('Reconnection delay - monotonicity', function () {
  it('delays are monotonically non-decreasing for attempts 0-20', function () {
    let prevDelay = 0;
    for (let attempt = 0; attempt <= 20; attempt++) {
      const delay = calculateReconnectDelay(attempt);
      assertTrue(
        delay >= prevDelay,
        'delay at attempt ' + attempt + ' (' + delay + ') should be >= previous (' + prevDelay + ')'
      );
      prevDelay = delay;
    }
  });

  it('delays are strictly increasing before hitting the cap', function () {
    let prevDelay = 0;
    for (let attempt = 0; attempt < 7; attempt++) {
      const delay = calculateReconnectDelay(attempt);
      assertGreaterThan(
        delay, prevDelay,
        'delay at attempt ' + attempt + ' should be > previous'
      );
      prevDelay = delay;
    }
  });
});

describe('Reconnection delay - bounds', function () {
  it('all delays are >= BASE (350ms)', function () {
    for (let attempt = 0; attempt <= 30; attempt++) {
      const delay = calculateReconnectDelay(attempt);
      assertTrue(
        delay >= BASE,
        'delay at attempt ' + attempt + ' (' + delay + ') should be >= BASE (' + BASE + ')'
      );
    }
  });

  it('all delays are <= MAX (8000ms)', function () {
    for (let attempt = 0; attempt <= 100; attempt++) {
      const delay = calculateReconnectDelay(attempt);
      assertTrue(
        delay <= MAX,
        'delay at attempt ' + attempt + ' (' + delay + ') should be <= MAX (' + MAX + ')'
      );
    }
  });
});

describe('Reconnection delay - reset on success', function () {
  it('successful reconnect resets attempt to 0', function () {
    // Attempts: 0, 1, 2, then success at attempt 2, so next is attempt 0 again
    const delays = simulateWithSuccessAt(2, 5);
    // delays[0] = attempt 0 = 350
    // delays[1] = attempt 1 = 595
    // delays[2] = attempt 2 = 1011.5  (success here, reset)
    // delays[3] = attempt 0 = 350     (reset!)
    // delays[4] = attempt 1 = 595
    assertEqual(delays[0], 350);
    assertEqual(delays[1], 595);
    assertEqual(delays[3], 350, 'after success, delay resets to BASE');
    assertEqual(delays[4], 595, 'after reset, exponential resumes');
  });

  it('multiple resets produce repeating pattern', function () {
    // Success at attempt 1 each time
    const delays = simulateWithSuccessAt(1, 4);
    // delays[0] = attempt 0 = 350
    // delays[1] = attempt 1 = 595 (success, reset)
    // delays[2] = attempt 0 = 350 (reset)
    // delays[3] = attempt 1 = 595
    assertEqual(delays[0], delays[2], 'first delay after reset matches initial');
    assertEqual(delays[1], delays[3], 'second delay after reset matches');
  });
});

describe('Reconnection delay - sequence simulation', function () {
  it('first 6 delays form expected sequence', function () {
    const delays = simulateReconnectionSequence(6);
    assertEqual(delays.length, 6);
    assertEqual(delays[0], 350);
    assertEqual(delays[1], 595);
    // Remaining delays are strictly increasing
    for (let i = 1; i < delays.length; i++) {
      assertGreaterThan(delays[i], delays[i - 1]);
    }
  });

  it('sequence eventually plateaus at MAX', function () {
    const delays = simulateReconnectionSequence(15);
    // Last several delays should all be MAX
    for (let i = 10; i < 15; i++) {
      assertEqual(delays[i], MAX, 'delay at index ' + i + ' should be MAX');
    }
  });
});
