'use strict';
/**
 * Unit tests for Constants values.
 * Source: Constants.ets
 */

const { describe, it } = require('../lib/test-runner');
const {
  assertEqual, assertTrue, assertStartsWith,
  assertGreaterThan, assertLessThan
} = require('../lib/assert');

// Mirror of relevant constants from Constants.ets
const Constants = {
  ANTHROPIC_URL: 'https://api.anthropic.com/v1/messages',
  OPENAI_URL: 'https://api.openai.com/v1/chat/completions',
  OPENROUTER_URL: 'https://openrouter.ai/api/v1/chat/completions',
  SILICONFLOW_URL: 'https://api.siliconflow.cn/v1/chat/completions',
  EMBEDDING_URL: 'https://api.siliconflow.cn/v1/embeddings',

  DEFAULT_GATEWAY_PORT: 9315,
  GATEWAY_RECONNECT_BASE_MS: 350,
  GATEWAY_RECONNECT_MULTIPLIER: 1.7,
  GATEWAY_RECONNECT_MAX_MS: 8000,

  MAX_TOKENS: 4096,
  MAX_HISTORY: 50,
  MAX_TOOL_LOOPS: 8,

  OPENROUTER_DEFAULT_KEY: '',
  SILICONFLOW_DEFAULT_KEY: '',

  EMBEDDING_DIM: 1024,
  VECTOR_SEARCH_TOP_K: 5,
};

describe('Constants - Gateway port', function () {
  it('DEFAULT_GATEWAY_PORT is 9315', function () {
    assertEqual(Constants.DEFAULT_GATEWAY_PORT, 9315);
  });
});

describe('Constants - API URLs', function () {
  it('ANTHROPIC_URL starts with https://', function () {
    assertStartsWith(Constants.ANTHROPIC_URL, 'https://');
  });

  it('OPENAI_URL starts with https://', function () {
    assertStartsWith(Constants.OPENAI_URL, 'https://');
  });

  it('OPENROUTER_URL starts with https://', function () {
    assertStartsWith(Constants.OPENROUTER_URL, 'https://');
  });

  it('SILICONFLOW_URL starts with https://', function () {
    assertStartsWith(Constants.SILICONFLOW_URL, 'https://');
  });

  it('EMBEDDING_URL starts with https://', function () {
    assertStartsWith(Constants.EMBEDDING_URL, 'https://');
  });
});

describe('Constants - Reconnect parameters', function () {
  it('GATEWAY_RECONNECT_BASE_MS is 350', function () {
    assertEqual(Constants.GATEWAY_RECONNECT_BASE_MS, 350);
  });

  it('GATEWAY_RECONNECT_MULTIPLIER is 1.7', function () {
    assertEqual(Constants.GATEWAY_RECONNECT_MULTIPLIER, 1.7);
  });

  it('GATEWAY_RECONNECT_MAX_MS is 8000', function () {
    assertEqual(Constants.GATEWAY_RECONNECT_MAX_MS, 8000);
  });

  it('GATEWAY_RECONNECT_BASE_MS < GATEWAY_RECONNECT_MAX_MS', function () {
    assertLessThan(Constants.GATEWAY_RECONNECT_BASE_MS, Constants.GATEWAY_RECONNECT_MAX_MS);
  });

  it('GATEWAY_RECONNECT_MULTIPLIER > 1', function () {
    assertGreaterThan(Constants.GATEWAY_RECONNECT_MULTIPLIER, 1);
  });
});

describe('Constants - Limits', function () {
  it('MAX_TOKENS is 4096', function () {
    assertEqual(Constants.MAX_TOKENS, 4096);
  });

  it('MAX_HISTORY is 50', function () {
    assertEqual(Constants.MAX_HISTORY, 50);
  });

  it('MAX_TOOL_LOOPS is 8', function () {
    assertEqual(Constants.MAX_TOOL_LOOPS, 8);
  });
});

describe('Constants - No hardcoded secrets', function () {
  it('OPENROUTER_DEFAULT_KEY is empty string', function () {
    assertEqual(Constants.OPENROUTER_DEFAULT_KEY, '');
  });

  it('SILICONFLOW_DEFAULT_KEY is empty string', function () {
    assertEqual(Constants.SILICONFLOW_DEFAULT_KEY, '');
  });
});

describe('Constants - Embedding', function () {
  it('EMBEDDING_DIM is 1024', function () {
    assertEqual(Constants.EMBEDDING_DIM, 1024);
  });

  it('VECTOR_SEARCH_TOP_K is 5', function () {
    assertEqual(Constants.VECTOR_SEARCH_TOP_K, 5);
  });
});
