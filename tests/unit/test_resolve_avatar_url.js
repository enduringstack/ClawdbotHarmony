'use strict';

const { describe, it } = require('../lib/test-runner');
const { assertEqual, assertUndefined } = require('../lib/assert');

// Mirror of resolveAgentAvatarUrl logic from NodeRuntime.ets lines 554-573
function resolveAgentAvatarUrl(cachedAvatarPath, agentIdentity, endpoint) {
  if (cachedAvatarPath && cachedAvatarPath.length > 0) return cachedAvatarPath;
  if (!agentIdentity || agentIdentity.avatar.length === 0) return undefined;
  let av = agentIdentity.avatar;
  if (av.startsWith('data:')) return av;
  if (av.startsWith('http://') || av.startsWith('https://')) return av;
  if (!endpoint) return undefined;
  let path = av.startsWith('/') ? av.substring(1) : av;
  let scheme = endpoint.useTls ? 'https' : 'http';
  return `${scheme}://${endpoint.host}:${endpoint.port}/media/${path}`;
}

describe('resolveAgentAvatarUrl', function () {
  const ep = { host: 'gw.local', port: 9315, useTls: false };

  it('returns cached path when available', function () {
    assertEqual(
      resolveAgentAvatarUrl('/cached/avatar.png', { avatar: 'other.png' }, ep),
      '/cached/avatar.png'
    );
  });

  it('returns undefined when no identity provided', function () {
    assertUndefined(resolveAgentAvatarUrl('', null, ep));
    assertUndefined(resolveAgentAvatarUrl('', undefined, ep));
  });

  it('returns undefined when avatar is empty string', function () {
    assertUndefined(resolveAgentAvatarUrl('', { avatar: '' }, ep));
  });

  it('returns data: URI directly', function () {
    const dataUri = 'data:image/png;base64,iVBORw0KGgo=';
    assertEqual(resolveAgentAvatarUrl('', { avatar: dataUri }, ep), dataUri);
  });

  it('returns http:// URL directly', function () {
    const url = 'http://example.com/avatar.png';
    assertEqual(resolveAgentAvatarUrl('', { avatar: url }, ep), url);
  });

  it('returns https:// URL directly', function () {
    const url = 'https://example.com/avatar.png';
    assertEqual(resolveAgentAvatarUrl('', { avatar: url }, ep), url);
  });

  it('builds URL from relative path with endpoint', function () {
    assertEqual(
      resolveAgentAvatarUrl('', { avatar: 'avatars/bot.png' }, ep),
      'http://gw.local:9315/media/avatars/bot.png'
    );
  });

  it('strips leading slash from relative path', function () {
    assertEqual(
      resolveAgentAvatarUrl('', { avatar: '/avatars/bot.png' }, ep),
      'http://gw.local:9315/media/avatars/bot.png'
    );
  });

  it('returns undefined for relative path when no endpoint', function () {
    assertUndefined(resolveAgentAvatarUrl('', { avatar: 'avatars/bot.png' }, null));
  });
});
