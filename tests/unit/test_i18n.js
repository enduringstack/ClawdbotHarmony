'use strict';
/**
 * Unit tests for I18n class logic.
 * Source: I18n.ets lines 620-669
 */

const { describe, it, beforeEach } = require('../lib/test-runner');
const { assertEqual, assertTrue, assertFalse } = require('../lib/assert');

// Build simplified zh/en maps with a representative subset of keys
const zhMap = new Map();
zhMap.set('tab.chat', '聊天');
zhMap.set('tab.skills', '技能');
zhMap.set('chat.title', 'ClawdBot');
zhMap.set('chat.thinking', '思考中...');
zhMap.set('settings.title', '设置');
zhMap.set('zh.only.key', '仅中文');

const enMap = new Map();
enMap.set('tab.chat', 'Chat');
enMap.set('tab.skills', 'Skills');
enMap.set('chat.title', 'ClawdBot');
enMap.set('chat.thinking', 'Thinking...');
enMap.set('settings.title', 'Settings');
enMap.set('en.only.key', 'English only');

class I18n {
  static currentLang = 'zh';
  static listeners = [];

  static init(lang) { I18n.currentLang = lang; }
  static get lang() { return I18n.currentLang; }
  static setLang(lang) {
    I18n.currentLang = lang;
    for (let listener of I18n.listeners) { try { listener(); } catch {} }
  }
  static addListener(fn) { I18n.listeners.push(fn); }
  static removeListener(fn) {
    let idx = I18n.listeners.indexOf(fn);
    if (idx >= 0) I18n.listeners.splice(idx, 1);
  }
  static t(key) {
    let map = I18n.currentLang === 'zh' ? zhMap : enMap;
    let val = map.get(key);
    if (val !== undefined) return val;
    let enVal = enMap.get(key);
    if (enVal !== undefined) return enVal;
    return key;
  }
}

describe('I18n', function () {
  beforeEach(function () {
    I18n.currentLang = 'zh';
    I18n.listeners = [];
  });

  it('t() returns zh value when lang=zh', function () {
    I18n.init('zh');
    assertEqual(I18n.t('tab.chat'), '聊天');
  });

  it('t() returns en value when lang=en', function () {
    I18n.init('en');
    assertEqual(I18n.t('tab.chat'), 'Chat');
  });

  it('t() falls back to en when key missing in zh', function () {
    I18n.init('zh');
    assertEqual(I18n.t('en.only.key'), 'English only');
  });

  it('t() returns key itself when missing everywhere', function () {
    assertEqual(I18n.t('nonexistent.key'), 'nonexistent.key');
  });

  it('setLang() changes language and t() reflects it', function () {
    I18n.init('zh');
    assertEqual(I18n.t('tab.skills'), '技能');
    I18n.setLang('en');
    assertEqual(I18n.t('tab.skills'), 'Skills');
  });

  it('listener called on setLang()', function () {
    let called = false;
    I18n.addListener(function () { called = true; });
    I18n.setLang('en');
    assertTrue(called);
  });

  it('removeListener works', function () {
    let called = false;
    let fn = function () { called = true; };
    I18n.addListener(fn);
    I18n.removeListener(fn);
    I18n.setLang('en');
    assertFalse(called);
  });

  it('same key value across languages', function () {
    I18n.init('zh');
    let zhVal = I18n.t('chat.title');
    I18n.init('en');
    let enVal = I18n.t('chat.title');
    assertEqual(zhVal, 'ClawdBot');
    assertEqual(enVal, 'ClawdBot');
  });
});
