'use strict';

const { describe, it } = require('../lib/test-runner');
const { assertEqual, assertDeepEqual, assertIncludes, assertTrue, assertGreaterThan } = require('../lib/assert');

// Mirror of capability toggle -> caps/commands mapping from NodeRuntime.ets
function buildNodeOptions(f) {
  let caps = [], commands = [];
  if (f.location) { caps.push('location'); commands.push('location.get'); }
  if (f.camera) { caps.push('camera'); commands.push('camera.snap', 'camera.clip'); }
  if (f.canvas) {
    caps.push('canvas');
    commands.push('canvas.present', 'canvas.hide', 'canvas.navigate', 'canvas.eval', 'canvas.snapshot', 'canvas.a2ui.push', 'canvas.a2ui.pushJSONL', 'canvas.a2ui.reset');
  }
  if (f.screen) { caps.push('screen'); commands.push('screen.capture', 'screen.record'); }
  if (f.notification) { caps.push('notification'); commands.push('notification.show', 'system.notify'); }
  if (f.sms) { caps.push('sms'); commands.push('sms.send'); }
  if (f.microphone) { caps.push('microphone'); commands.push('mic.record'); }
  if (f.speaker) { caps.push('speaker'); commands.push('speaker.speak', 'speaker.play', 'speaker.stop'); }
  if (f.email) { caps.push('email'); commands.push('email.send'); }
  if (f.calendar) { caps.push('calendar'); commands.push('calendar.add'); }
  if (f.exec) { caps.push('exec'); commands.push('exec.run'); }
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

// --- Individual capability tests ---

describe('capability mapping - individual capabilities', function () {
  it('location: caps=[location], commands=[location.get]', function () {
    const r = buildNodeOptions(onlyFlag('location'));
    assertDeepEqual(r.caps, ['location']);
    assertDeepEqual(r.commands, ['location.get']);
  });

  it('camera: caps=[camera], commands=[camera.snap, camera.clip]', function () {
    const r = buildNodeOptions(onlyFlag('camera'));
    assertDeepEqual(r.caps, ['camera']);
    assertDeepEqual(r.commands, ['camera.snap', 'camera.clip']);
  });

  it('canvas: caps=[canvas], 8 commands', function () {
    const r = buildNodeOptions(onlyFlag('canvas'));
    assertDeepEqual(r.caps, ['canvas']);
    assertEqual(r.commands.length, 8, 'canvas commands count');
    assertDeepEqual(r.commands, [
      'canvas.present', 'canvas.hide', 'canvas.navigate', 'canvas.eval',
      'canvas.snapshot', 'canvas.a2ui.push', 'canvas.a2ui.pushJSONL', 'canvas.a2ui.reset'
    ]);
  });

  it('screen: caps=[screen], commands=[screen.capture, screen.record]', function () {
    const r = buildNodeOptions(onlyFlag('screen'));
    assertDeepEqual(r.caps, ['screen']);
    assertDeepEqual(r.commands, ['screen.capture', 'screen.record']);
  });

  it('notification: caps=[notification], commands=[notification.show, system.notify]', function () {
    const r = buildNodeOptions(onlyFlag('notification'));
    assertDeepEqual(r.caps, ['notification']);
    assertDeepEqual(r.commands, ['notification.show', 'system.notify']);
  });

  it('sms: caps=[sms], commands=[sms.send]', function () {
    const r = buildNodeOptions(onlyFlag('sms'));
    assertDeepEqual(r.caps, ['sms']);
    assertDeepEqual(r.commands, ['sms.send']);
  });

  it('microphone: caps=[microphone], commands=[mic.record]', function () {
    const r = buildNodeOptions(onlyFlag('microphone'));
    assertDeepEqual(r.caps, ['microphone']);
    assertDeepEqual(r.commands, ['mic.record']);
  });

  it('speaker: caps=[speaker], commands=[speaker.speak, speaker.play, speaker.stop]', function () {
    const r = buildNodeOptions(onlyFlag('speaker'));
    assertDeepEqual(r.caps, ['speaker']);
    assertDeepEqual(r.commands, ['speaker.speak', 'speaker.play', 'speaker.stop']);
  });

  it('email: caps=[email], commands=[email.send]', function () {
    const r = buildNodeOptions(onlyFlag('email'));
    assertDeepEqual(r.caps, ['email']);
    assertDeepEqual(r.commands, ['email.send']);
  });

  it('calendar: caps=[calendar], commands=[calendar.add]', function () {
    const r = buildNodeOptions(onlyFlag('calendar'));
    assertDeepEqual(r.caps, ['calendar']);
    assertDeepEqual(r.commands, ['calendar.add']);
  });

  it('exec: caps=[exec], commands=[exec.run]', function () {
    const r = buildNodeOptions(onlyFlag('exec'));
    assertDeepEqual(r.caps, ['exec']);
    assertDeepEqual(r.commands, ['exec.run']);
  });
});

// --- Aggregate and combination tests ---

describe('capability mapping - aggregates and combinations', function () {
  it('all enabled: 11 caps, 23 commands', function () {
    const r = buildNodeOptions(allEnabled());
    assertEqual(r.caps.length, 11, 'caps count');
    assertEqual(r.commands.length, 23, 'commands count');
  });

  it('all disabled: empty arrays', function () {
    const r = buildNodeOptions(allDisabled());
    assertDeepEqual(r.caps, []);
    assertDeepEqual(r.commands, []);
  });

  it('each capability commands match their capability namespace', function () {
    const capNames = ['location', 'camera', 'canvas', 'screen', 'sms', 'microphone', 'speaker', 'email', 'calendar', 'exec'];
    const namespaceMap = {
      location: 'location.', camera: 'camera.', canvas: 'canvas.',
      screen: 'screen.', sms: 'sms.', microphone: 'mic.',
      speaker: 'speaker.', email: 'email.', calendar: 'calendar.', exec: 'exec.'
    };
    for (const cap of capNames) {
      const r = buildNodeOptions(onlyFlag(cap));
      const prefix = namespaceMap[cap];
      for (const cmd of r.commands) {
        assertTrue(cmd.startsWith(prefix), `command "${cmd}" should start with "${prefix}"`);
      }
    }
  });

  it('notification commands use notification. or system. namespace', function () {
    const r = buildNodeOptions(onlyFlag('notification'));
    for (const cmd of r.commands) {
      assertTrue(
        cmd.startsWith('notification.') || cmd.startsWith('system.'),
        `notification command "${cmd}" should start with notification. or system.`
      );
    }
  });

  it('no duplicate commands across all capabilities', function () {
    const r = buildNodeOptions(allEnabled());
    const seen = new Set();
    for (const cmd of r.commands) {
      assertTrue(!seen.has(cmd), `duplicate command: ${cmd}`);
      seen.add(cmd);
    }
  });

  it('no duplicate caps across all capabilities', function () {
    const r = buildNodeOptions(allEnabled());
    const seen = new Set();
    for (const cap of r.caps) {
      assertTrue(!seen.has(cap), `duplicate cap: ${cap}`);
      seen.add(cap);
    }
  });

  it('every command string contains a dot', function () {
    const r = buildNodeOptions(allEnabled());
    for (const cmd of r.commands) {
      assertTrue(cmd.includes('.'), `command "${cmd}" should contain a dot`);
    }
  });

  it('combo: {location, speaker, exec}', function () {
    let f = allDisabled();
    f.location = true;
    f.speaker = true;
    f.exec = true;
    const r = buildNodeOptions(f);
    assertDeepEqual(r.caps, ['location', 'speaker', 'exec']);
    assertEqual(r.commands.length, 5, 'commands count for location+speaker+exec');
    assertIncludes(r.commands, 'location.get');
    assertIncludes(r.commands, 'speaker.speak');
    assertIncludes(r.commands, 'speaker.play');
    assertIncludes(r.commands, 'speaker.stop');
    assertIncludes(r.commands, 'exec.run');
  });

  it('combo: {camera, canvas, notification}', function () {
    let f = allDisabled();
    f.camera = true;
    f.canvas = true;
    f.notification = true;
    const r = buildNodeOptions(f);
    assertDeepEqual(r.caps, ['camera', 'canvas', 'notification']);
    assertEqual(r.commands.length, 12, 'commands count for camera+canvas+notification');
    assertIncludes(r.commands, 'camera.snap');
    assertIncludes(r.commands, 'camera.clip');
    assertIncludes(r.commands, 'canvas.present');
    assertIncludes(r.commands, 'notification.show');
    assertIncludes(r.commands, 'system.notify');
  });
});
