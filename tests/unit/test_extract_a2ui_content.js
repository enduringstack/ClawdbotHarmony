'use strict';

const { describe, it } = require('../lib/test-runner');
const { assertEqual } = require('../lib/assert');

// Mirror of extractA2UIContent logic from NodeRuntime.ets lines 1409-1420
function extractA2UIContent(paramsJson) {
  if (!paramsJson || paramsJson.length === 0) return '';
  try {
    let p = JSON.parse(paramsJson);
    if (p['lines'] !== undefined) return p['lines'];
    if (p['content'] !== undefined) return p['content'];
    if (p['jsonl'] !== undefined) return p['jsonl'];
    return paramsJson;
  } catch {
    return paramsJson;
  }
}

describe('extractA2UIContent', function () {
  it('returns empty string for undefined input', function () {
    assertEqual(extractA2UIContent(undefined), '');
  });

  it('returns empty string for empty string input', function () {
    assertEqual(extractA2UIContent(''), '');
  });

  it('extracts lines field', function () {
    assertEqual(extractA2UIContent('{"lines":"line1\\nline2"}'), 'line1\nline2');
  });

  it('extracts content field', function () {
    assertEqual(extractA2UIContent('{"content":"hello"}'), 'hello');
  });

  it('extracts jsonl field', function () {
    assertEqual(extractA2UIContent('{"jsonl":"data"}'), 'data');
  });

  it('gives priority to lines over content', function () {
    assertEqual(extractA2UIContent('{"lines":"a","content":"b"}'), 'a');
  });

  it('returns raw JSON when no recognized field', function () {
    assertEqual(extractA2UIContent('{"foo":"bar"}'), '{"foo":"bar"}');
  });

  it('returns raw string when JSON is invalid', function () {
    assertEqual(extractA2UIContent('not json'), 'not json');
  });
});
