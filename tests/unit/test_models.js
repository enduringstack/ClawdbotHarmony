'use strict';
/**
 * Unit tests for ChatMessage, MemoryItem, ChatSession constructors.
 * Source: Models.ets (without @Observed decorator)
 */

const { describe, it } = require('../lib/test-runner');
const {
  assertEqual, assertNotEqual, assertTrue, assertFalse,
  assertStartsWith, assertDeepEqual, assertGreaterThan
} = require('../lib/assert');

// Mirror of ChatMessage from Models.ets
class ChatMessage {
  constructor(role, content) {
    this.id = `m_${Date.now()}_${Math.floor(Math.random() * 100000)}`;
    this.role = role;
    this.content = content;
    this.timestamp = Date.now();
    this.isToolCall = false;
    this.toolName = '';
    this.toolInput = '';
    this.toolOutput = '';
    this.imagePath = '';
    this.audioPath = '';
    this.userImagePath = '';
    this.userImagePaths = [];
    this.feedback = '';
    this.videoPath = '';
    this.buttons = [];
    this.attachmentName = '';
    this.a2uiContent = '';
    this.canvasUrl = '';
    this.replyToId = '';
    this.replyToContent = '';
    this.replyToRole = '';
  }
}

// Mirror of MemoryItem from Models.ets
class MemoryItem {
  constructor(memType, content, importance) {
    this.id = `mem_${Date.now()}_${Math.floor(Math.random() * 100000)}`;
    this.memType = memType;
    this.content = content;
    this.importance = importance !== undefined ? importance : 0.5;
    this.createdAt = Date.now();
  }
}

// Mirror of ChatSession from Models.ets
class ChatSession {
  constructor(title) {
    this.id = `session_${Date.now()}_${Math.floor(Math.random() * 100000)}`;
    this.title = title || '\u65b0\u5bf9\u8bdd';
    this.createdAt = Date.now();
    this.updatedAt = Date.now();
    this.messageCount = 0;
    this.lastMessage = '';
    this.isPinned = false;
  }
}

describe('ChatMessage', function () {
  it('constructor sets id starting with m_, role, and content', function () {
    const msg = new ChatMessage('user', 'hello');
    assertStartsWith(msg.id, 'm_');
    assertEqual(msg.role, 'user');
    assertEqual(msg.content, 'hello');
  });

  it('timestamp is approximately Date.now()', function () {
    const before = Date.now();
    const msg = new ChatMessage('user', 'hello');
    const after = Date.now();
    assertTrue(msg.timestamp >= before && msg.timestamp <= after,
      'timestamp should be close to Date.now()');
  });

  it('all string fields default to empty string', function () {
    const msg = new ChatMessage('user', 'hello');
    assertEqual(msg.toolName, '');
    assertEqual(msg.toolInput, '');
    assertEqual(msg.toolOutput, '');
    assertEqual(msg.imagePath, '');
    assertEqual(msg.audioPath, '');
    assertEqual(msg.userImagePath, '');
    assertEqual(msg.feedback, '');
    assertEqual(msg.videoPath, '');
    assertEqual(msg.attachmentName, '');
    assertEqual(msg.a2uiContent, '');
    assertEqual(msg.canvasUrl, '');
    assertEqual(msg.replyToId, '');
    assertEqual(msg.replyToContent, '');
    assertEqual(msg.replyToRole, '');
  });

  it('all array fields default to empty arrays', function () {
    const msg = new ChatMessage('user', 'hello');
    assertDeepEqual(msg.userImagePaths, []);
    assertDeepEqual(msg.buttons, []);
  });

  it('isToolCall defaults to false', function () {
    const msg = new ChatMessage('user', 'hello');
    assertFalse(msg.isToolCall);
  });

  it('two ChatMessage instances have different IDs', function () {
    const msg1 = new ChatMessage('user', 'a');
    const msg2 = new ChatMessage('user', 'b');
    assertNotEqual(msg1.id, msg2.id, 'IDs should be unique');
  });
});

describe('MemoryItem', function () {
  it('constructor sets id starting with mem_, memType, content, importance', function () {
    const item = new MemoryItem('fact', 'test', 0.8);
    assertStartsWith(item.id, 'mem_');
    assertEqual(item.memType, 'fact');
    assertEqual(item.content, 'test');
    assertEqual(item.importance, 0.8);
  });

  it('default importance is 0.5 when not provided', function () {
    const item = new MemoryItem('fact', 'test');
    assertEqual(item.importance, 0.5);
  });

  it('createdAt is set to approximately Date.now()', function () {
    const before = Date.now();
    const item = new MemoryItem('fact', 'test', 0.8);
    const after = Date.now();
    assertTrue(item.createdAt >= before && item.createdAt <= after,
      'createdAt should be close to Date.now()');
  });
});

describe('ChatSession', function () {
  it('constructor with title sets id starting with session_ and correct title', function () {
    const s = new ChatSession('test');
    assertStartsWith(s.id, 'session_');
    assertEqual(s.title, 'test');
  });

  it('constructor without title defaults to new dialog title', function () {
    const s = new ChatSession();
    assertEqual(s.title, '\u65b0\u5bf9\u8bdd');
  });

  it('default fields: messageCount=0, lastMessage empty, isPinned=false', function () {
    const s = new ChatSession('test');
    assertEqual(s.messageCount, 0);
    assertEqual(s.lastMessage, '');
    assertFalse(s.isPinned);
  });

  it('createdAt and updatedAt are set', function () {
    const before = Date.now();
    const s = new ChatSession('test');
    const after = Date.now();
    assertTrue(s.createdAt >= before && s.createdAt <= after,
      'createdAt should be close to Date.now()');
    assertTrue(s.updatedAt >= before && s.updatedAt <= after,
      'updatedAt should be close to Date.now()');
  });
});
