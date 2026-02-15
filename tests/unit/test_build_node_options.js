'use strict';

const { describe, it } = require('../lib/test-runner');
const { assertEqual, assertDeepEqual, assertIncludes } = require('../lib/assert');

// Mirror of capability toggle -> caps/commands mapping from NodeRuntime.ets lines 1734-1804
function buildNodeOptions(caps_flags) {
  let caps = [];
  let commands = [];

  if (caps_flags.location) { caps.push('location'); commands.push('location.get'); }
  if (caps_flags.camera) { caps.push('camera'); commands.push('camera.snap'); commands.push('camera.clip'); }
  if (caps_flags.canvas) {
    caps.push('canvas');
    commands.push('canvas.present', 'canvas.hide', 'canvas.navigate', 'canvas.eval', 'canvas.snapshot', 'canvas.a2ui.push', 'canvas.a2ui.pushJSONL', 'canvas.a2ui.reset');
  }
  if (caps_flags.screen) { caps.push('screen'); commands.push('screen.capture', 'screen.record'); }
  if (caps_flags.notification) { caps.push('notification'); commands.push('notification.show', 'system.notify'); }
  if (caps_flags.sms) { caps.push('sms'); commands.push('sms.send'); }
  if (caps_flags.microphone) { caps.push('microphone'); commands.push('mic.record'); }
  if (caps_flags.speaker) { caps.push('speaker'); commands.push('speaker.speak', 'speaker.play', 'speaker.stop'); }
  if (caps_flags.email) { caps.push('email'); commands.push('email.send'); }
  if (caps_flags.calendar) { caps.push('calendar'); commands.push('calendar.add'); }
  if (caps_flags.exec) { caps.push('exec'); commands.push('exec.run'); }

  return { caps, commands };
}

function allEnabled() {
  return {
    location: true, camera: true, canvas: true, screen: true,
    notification: true, sms: true, microphone: true, speaker: true,
    email: true, calendar: true, exec: true
  };
}

function allDisabled() {
  return {
    location: false, camera: false, canvas: false, screen: false,
    notification: false, sms: false, microphone: false, speaker: false,
    email: false, calendar: false, exec: false
  };
}

function onlyFlag(flag) {
  let f = allDisabled();
  f[flag] = true;
  return f;
}

describe('buildNodeOptions', function () {
  it('all enabled -> 11 caps, 23 commands', function () {
    const result = buildNodeOptions(allEnabled());
    assertEqual(result.caps.length, 11, 'caps count');
    assertEqual(result.commands.length, 23, 'commands count');
  });

  it('all disabled -> empty arrays', function () {
    const result = buildNodeOptions(allDisabled());
    assertDeepEqual(result.caps, []);
    assertDeepEqual(result.commands, []);
  });

  it('only location -> caps=[location], commands=[location.get]', function () {
    const result = buildNodeOptions(onlyFlag('location'));
    assertDeepEqual(result.caps, ['location']);
    assertDeepEqual(result.commands, ['location.get']);
  });

  it('only camera -> caps=[camera], commands=[camera.snap, camera.clip]', function () {
    const result = buildNodeOptions(onlyFlag('camera'));
    assertDeepEqual(result.caps, ['camera']);
    assertDeepEqual(result.commands, ['camera.snap', 'camera.clip']);
  });

  it('only canvas -> caps=[canvas], 8 commands', function () {
    const result = buildNodeOptions(onlyFlag('canvas'));
    assertDeepEqual(result.caps, ['canvas']);
    assertEqual(result.commands.length, 8, 'canvas commands count');
    assertIncludes(result.commands, 'canvas.present');
    assertIncludes(result.commands, 'canvas.hide');
    assertIncludes(result.commands, 'canvas.navigate');
    assertIncludes(result.commands, 'canvas.eval');
    assertIncludes(result.commands, 'canvas.snapshot');
    assertIncludes(result.commands, 'canvas.a2ui.push');
    assertIncludes(result.commands, 'canvas.a2ui.pushJSONL');
    assertIncludes(result.commands, 'canvas.a2ui.reset');
  });

  it('only speaker -> caps=[speaker], 3 commands', function () {
    const result = buildNodeOptions(onlyFlag('speaker'));
    assertDeepEqual(result.caps, ['speaker']);
    assertDeepEqual(result.commands, ['speaker.speak', 'speaker.play', 'speaker.stop']);
  });

  it('notification includes both notification.show and system.notify', function () {
    const result = buildNodeOptions(onlyFlag('notification'));
    assertDeepEqual(result.caps, ['notification']);
    assertIncludes(result.commands, 'notification.show');
    assertIncludes(result.commands, 'system.notify');
    assertEqual(result.commands.length, 2, 'notification commands count');
  });

  it('email + calendar -> caps=[email,calendar], commands=[email.send,calendar.add]', function () {
    let flags = allDisabled();
    flags.email = true;
    flags.calendar = true;
    const result = buildNodeOptions(flags);
    assertDeepEqual(result.caps, ['email', 'calendar']);
    assertDeepEqual(result.commands, ['email.send', 'calendar.add']);
  });

  it('exec only -> caps=[exec], commands=[exec.run]', function () {
    const result = buildNodeOptions(onlyFlag('exec'));
    assertDeepEqual(result.caps, ['exec']);
    assertDeepEqual(result.commands, ['exec.run']);
  });
});
