'use strict';

const { describe, it } = require('../lib/test-runner');
const { assertEqual, assertUndefined } = require('../lib/assert');

// Mirror of buildMediaUrl logic from NodeRuntime.ets lines 537-551
function buildMediaUrl(endpoint, mediaPath) {
  if (!endpoint) return undefined;
  let path = mediaPath;
  if (path.startsWith('MEDIA:')) path = path.substring(6);
  if (path.startsWith('/')) path = path.substring(1);
  let scheme = endpoint.useTls ? 'https' : 'http';
  return `${scheme}://${endpoint.host}:${endpoint.port}/media/${path}`;
}

describe('buildMediaUrl', function () {
  it('returns undefined when endpoint is null/undefined', function () {
    assertUndefined(buildMediaUrl(null, 'MEDIA:/tmp/file.mp3'));
    assertUndefined(buildMediaUrl(undefined, 'MEDIA:/tmp/file.mp3'));
  });

  it('strips MEDIA: prefix and leading slash', function () {
    const ep = { host: 'gw.local', port: 9315, useTls: false };
    assertEqual(buildMediaUrl(ep, 'MEDIA:/tmp/file.mp3'), 'http://gw.local:9315/media/tmp/file.mp3');
  });

  it('strips leading slash when no MEDIA: prefix', function () {
    const ep = { host: 'gw.local', port: 9315, useTls: false };
    assertEqual(buildMediaUrl(ep, '/tmp/file.mp3'), 'http://gw.local:9315/media/tmp/file.mp3');
  });

  it('handles MEDIA: prefix without leading slash', function () {
    const ep = { host: 'gw.local', port: 9315, useTls: false };
    assertEqual(buildMediaUrl(ep, 'MEDIA:data/file.wav'), 'http://gw.local:9315/media/data/file.wav');
  });

  it('uses https when useTls is true', function () {
    const ep = { host: 'gw.local', port: 9315, useTls: true };
    const result = buildMediaUrl(ep, 'MEDIA:/tmp/file.mp3');
    assertEqual(result, 'https://gw.local:9315/media/tmp/file.mp3');
  });

  it('handles plain filename without prefix or slash', function () {
    const ep = { host: 'gw.local', port: 9315, useTls: false };
    assertEqual(buildMediaUrl(ep, 'voice.mp3'), 'http://gw.local:9315/media/voice.mp3');
  });

  it('handles nested paths with MEDIA: prefix', function () {
    const ep = { host: 'gw.local', port: 9315, useTls: false };
    assertEqual(buildMediaUrl(ep, 'MEDIA:/a/b/c/d.mp3'), 'http://gw.local:9315/media/a/b/c/d.mp3');
  });
});
