'use strict';
/**
 * Lightweight test runner for ClawdbotHarmony tests.
 * Provides describe/it/beforeEach with colored output.
 * Zero external dependencies.
 */

const RED = '\x1b[31m';
const GREEN = '\x1b[32m';
const YELLOW = '\x1b[33m';
const CYAN = '\x1b[36m';
const DIM = '\x1b[2m';
const NC = '\x1b[0m';

let suites = [];
let currentSuite = null;

function describe(name, fn) {
  let suite = { name, tests: [], beforeEachFn: null };
  let prev = currentSuite;
  currentSuite = suite;
  fn();
  currentSuite = prev;
  suites.push(suite);
}

function it(name, fn) {
  if (!currentSuite) throw new Error('it() must be called inside describe()');
  currentSuite.tests.push({ name, fn });
}

function beforeEach(fn) {
  if (!currentSuite) throw new Error('beforeEach() must be called inside describe()');
  currentSuite.beforeEachFn = fn;
}

async function runAll() {
  let totalPass = 0;
  let totalFail = 0;
  let failures = [];

  for (const suite of suites) {
    console.log(`\n${CYAN}  ${suite.name}${NC}`);
    for (const test of suite.tests) {
      try {
        if (suite.beforeEachFn) suite.beforeEachFn();
        const result = test.fn();
        if (result && typeof result.then === 'function') {
          await result;
        }
        console.log(`    ${GREEN}\u2713${NC} ${DIM}${test.name}${NC}`);
        totalPass++;
      } catch (err) {
        console.log(`    ${RED}\u2717 ${test.name}${NC}`);
        console.log(`      ${RED}${err.message}${NC}`);
        totalFail++;
        failures.push({ suite: suite.name, test: test.name, error: err.message });
      }
    }
  }

  console.log('');
  if (totalFail === 0) {
    console.log(`${GREEN}  ${totalPass} passing${NC}`);
  } else {
    console.log(`${GREEN}  ${totalPass} passing${NC}`);
    console.log(`${RED}  ${totalFail} failing${NC}`);
    console.log('');
    failures.forEach((f, i) => {
      console.log(`  ${RED}${i + 1}) ${f.suite} > ${f.test}${NC}`);
      console.log(`     ${RED}${f.error}${NC}`);
    });
  }
  console.log('');

  process.exit(totalFail > 0 ? 1 : 0);
}

// Auto-run after all describe() calls are registered
process.nextTick(() => {
  if (suites.length > 0) {
    runAll().catch(err => {
      console.error(`${RED}Runner error: ${err.message}${NC}`);
      process.exit(1);
    });
  }
});

module.exports = { describe, it, beforeEach };
