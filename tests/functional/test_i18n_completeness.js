'use strict';

const fs = require('fs');
const path = require('path');
const { describe, it } = require('../lib/test-runner');
const { assertEqual, assertTrue, assertGreaterThan } = require('../lib/assert');

// Read the actual I18n.ets source file
const i18nPath = path.resolve(__dirname, '../../entry/src/main/ets/common/I18n.ets');
const source = fs.readFileSync(i18nPath, 'utf8');

// Extract all m.set('key', 'value') calls from buildZh() and buildEn() functions
function extractKeys(src, funcName) {
  // Find the function body
  let regex = new RegExp(`function ${funcName}\\(\\)[\\s\\S]*?return m;`, 'm');
  let match = src.match(regex);
  if (!match) return [];
  let body = match[0];
  // Extract all m.set('key', ...) calls
  let keys = [];
  let setRegex = /m\.set\('([^']+)'/g;
  let m;
  while ((m = setRegex.exec(body)) !== null) {
    keys.push(m[1]);
  }
  return keys;
}

const zhKeys = extractKeys(source, 'buildZh');
const enKeys = extractKeys(source, 'buildEn');

const zhSet = new Set(zhKeys);
const enSet = new Set(enKeys);

// --- Symmetry tests ---

describe('i18n completeness - key symmetry', function () {
  it('zh and en have the same number of keys', function () {
    assertEqual(zhSet.size, enSet.size,
      `zh has ${zhSet.size} unique keys, en has ${enSet.size} unique keys`);
  });

  it('every zh key exists in en', function () {
    let missingInEn = [];
    for (const key of zhKeys) {
      if (!enSet.has(key)) missingInEn.push(key);
    }
    assertEqual(missingInEn.length, 0,
      `keys in zh but missing from en: ${missingInEn.join(', ')}`);
  });

  it('every en key exists in zh', function () {
    let missingInZh = [];
    for (const key of enKeys) {
      if (!zhSet.has(key)) missingInZh.push(key);
    }
    assertEqual(missingInZh.length, 0,
      `keys in en but missing from zh: ${missingInZh.join(', ')}`);
  });
});

// --- Duplicate tests ---

describe('i18n completeness - no duplicates', function () {
  it('no duplicate keys within zh', function () {
    let seen = new Set();
    let dupes = [];
    for (const key of zhKeys) {
      if (seen.has(key)) dupes.push(key);
      seen.add(key);
    }
    assertEqual(dupes.length, 0,
      `duplicate zh keys: ${dupes.join(', ')}`);
  });

  it('no duplicate keys within en', function () {
    let seen = new Set();
    let dupes = [];
    for (const key of enKeys) {
      if (seen.has(key)) dupes.push(key);
      seen.add(key);
    }
    assertEqual(dupes.length, 0,
      `duplicate en keys: ${dupes.join(', ')}`);
  });
});

// --- Sanity check ---

describe('i18n completeness - sanity checks', function () {
  it('zh has more than 100 keys', function () {
    assertGreaterThan(zhKeys.length, 100,
      `expected > 100 zh keys, got ${zhKeys.length}`);
  });

  it('en has more than 100 keys', function () {
    assertGreaterThan(enKeys.length, 100,
      `expected > 100 en keys, got ${enKeys.length}`);
  });
});

// --- Key format tests ---

describe('i18n completeness - key format', function () {
  it('all zh keys use dot notation (contain at least one dot)', function () {
    let noDot = zhKeys.filter(k => !k.includes('.'));
    assertEqual(noDot.length, 0,
      `zh keys without dot: ${noDot.join(', ')}`);
  });

  it('all en keys use dot notation (contain at least one dot)', function () {
    let noDot = enKeys.filter(k => !k.includes('.'));
    assertEqual(noDot.length, 0,
      `en keys without dot: ${noDot.join(', ')}`);
  });
});

// --- Namespace coverage ---

describe('i18n completeness - namespace coverage', function () {
  const requiredNamespaces = ['tab', 'chat', 'skills', 'memory', 'settings', 'log', 'cron', 'session', 'state'];

  for (const ns of requiredNamespaces) {
    it(`zh contains keys with "${ns}." namespace`, function () {
      let count = zhKeys.filter(k => k.startsWith(ns + '.')).length;
      assertGreaterThan(count, 0, `no zh keys with namespace "${ns}."`);
    });
  }

  for (const ns of requiredNamespaces) {
    it(`en contains keys with "${ns}." namespace`, function () {
      let count = enKeys.filter(k => k.startsWith(ns + '.')).length;
      assertGreaterThan(count, 0, `no en keys with namespace "${ns}."`);
    });
  }
});
