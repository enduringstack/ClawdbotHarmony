'use strict';
/**
 * Unit tests for GatewayProtocol, Capability, and Command constants.
 * Source: GatewayProtocol.ets
 */

const { describe, it } = require('../lib/test-runner');
const { assertEqual, assertTrue, assertIncludes } = require('../lib/assert');

// Mirror of GatewayProtocol constants
const GatewayProtocol = { VERSION: 3 };

const Capability = {
  Canvas: 'canvas',
  Camera: 'camera',
  Screen: 'screen',
  Sms: 'sms',
  VoiceWake: 'voiceWake',
  Location: 'location',
  Notification: 'notification',
  Microphone: 'microphone',
  Speaker: 'speaker',
  Email: 'email',
  Calendar: 'calendar',
  Exec: 'exec',
};

const Command = {
  CANVAS_PRESENT: 'canvas.present',
  CANVAS_HIDE: 'canvas.hide',
  CANVAS_NAVIGATE: 'canvas.navigate',
  CANVAS_EVAL: 'canvas.eval',
  CANVAS_SNAPSHOT: 'canvas.snapshot',
  CANVAS_A2UI_PUSH: 'canvas.a2ui.push',
  CANVAS_A2UI_PUSH_JSONL: 'canvas.a2ui.pushJSONL',
  CANVAS_A2UI_RESET: 'canvas.a2ui.reset',
  CAMERA_SNAP: 'camera.snap',
  CAMERA_CLIP: 'camera.clip',
  SCREEN_CAPTURE: 'screen.capture',
  SCREEN_RECORD: 'screen.record',
  SMS_SEND: 'sms.send',
  LOCATION_GET: 'location.get',
  NOTIFICATION_SHOW: 'notification.show',
  SYSTEM_NOTIFY: 'system.notify',
  MIC_RECORD: 'mic.record',
  SPEAKER_SPEAK: 'speaker.speak',
  SPEAKER_PLAY: 'speaker.play',
  SPEAKER_STOP: 'speaker.stop',
  EMAIL_SEND: 'email.send',
  CALENDAR_ADD: 'calendar.add',
  EXEC_RUN: 'exec.run',
};

describe('GatewayProtocol', function () {
  it('VERSION is 3', function () {
    assertEqual(GatewayProtocol.VERSION, 3);
  });
});

describe('Capability constants', function () {
  it('has exactly 12 capabilities', function () {
    const vals = Object.values(Capability);
    assertEqual(vals.length, 12, 'should have 12 capabilities');
  });

  it('all capability values are unique', function () {
    const vals = Object.values(Capability);
    const unique = new Set(vals);
    assertEqual(unique.size, vals.length, 'all capability values should be unique');
  });

  it('contains expected capability values', function () {
    const vals = Object.values(Capability);
    const expected = [
      'canvas', 'camera', 'screen', 'sms', 'voiceWake', 'location',
      'notification', 'microphone', 'speaker', 'email', 'calendar', 'exec'
    ];
    for (const cap of expected) {
      assertIncludes(vals, cap, `should include capability '${cap}'`);
    }
  });
});

describe('Command constants', function () {
  it('has exactly 23 commands', function () {
    const vals = Object.values(Command);
    assertEqual(vals.length, 23, 'should have 23 commands');
  });

  it('all command values are unique', function () {
    const vals = Object.values(Command);
    const unique = new Set(vals);
    assertEqual(unique.size, vals.length, 'all command values should be unique');
  });

  it('all command values contain a dot', function () {
    const vals = Object.values(Command);
    for (const cmd of vals) {
      assertTrue(cmd.includes('.'), `command '${cmd}' should contain a dot`);
    }
  });

  it('contains all expected command values', function () {
    const vals = Object.values(Command);
    const expected = [
      'canvas.present', 'canvas.hide', 'canvas.navigate', 'canvas.eval',
      'canvas.snapshot', 'canvas.a2ui.push', 'canvas.a2ui.pushJSONL',
      'canvas.a2ui.reset', 'camera.snap', 'camera.clip', 'screen.capture',
      'screen.record', 'sms.send', 'location.get', 'notification.show',
      'system.notify', 'mic.record', 'speaker.speak', 'speaker.play',
      'speaker.stop', 'email.send', 'calendar.add', 'exec.run'
    ];
    for (const cmd of expected) {
      assertIncludes(vals, cmd, `should include command '${cmd}'`);
    }
  });
});
