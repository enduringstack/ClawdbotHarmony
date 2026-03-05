# CANN Local 端侧模型工具调用

## 概述

端侧模型 (CANN Local) 通过 Prompt Engineering 实现 Tool Calling 能力，与云端模型的原生 Tool Calling 有本质区别，但最终效果一致。

---

## 架构对比

### 云端模型

```
┌─────────────────────────────────────────────────────────────┐
│  API 请求                                                    │
│  {                                                           │
│    "model": "claude-sonnet-4",                               │
│    "messages": [...],                                        │
│    "tools": [                        ← API 参数传递          │
│      {                                                       │
│        "name": "capture_photo",                              │
│        "description": "Take a photo",                        │
│        "input_schema": {...}                                 │
│      }                                                       │
│    ]                                                         │
│  }                                                           │
└─────────────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────────┐
│  API 响应                                                    │
│  {                                                           │
│    "content": [                                              │
│      {                                                       │
│        "type": "tool_use",          ← 原生结构化输出          │
│        "name": "capture_photo",                              │
│        "input": {"camera": "back"}                           │
│      }                                                       │
│    ]                                                         │
│  }                                                           │
└─────────────────────────────────────────────────────────────┘
```

**特点**：
- 工具定义通过 API 参数传递
- 模型原生输出结构化对象
- 需要模型支持 Tool Calling 训练

---

### 端侧模型

```
┌─────────────────────────────────────────────────────────────┐
│  System Prompt (文本)                                        │
│                                                              │
│  ## 工具调用（重要）                                          │
│  你有权限调用设备功能。当用户请求时，输出 JSON 格式：          │
│                                                              │
│  {"name": "工具名", "arguments": {参数}}                     │
│                                                              │
│  ### 可用工具                                                │
│  **capture_photo** - 拍照                                    │
│  参数: camera ("front" 或 "back")                            │
│                                                              │
│  ### 示例                                                    │
│  用户: 拍照                                                   │
│  助手: {"name": "capture_photo", "arguments": {"camera": "back"}}│
└─────────────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────────┐
│  模型输出 (文本)                                             │
│  '{"name": "capture_photo", "arguments": {"camera": "back"}}'│
│                                                              │
│  ↓ extractToolCallsFromText() 解析                          │
│                                                              │
│  raw.toolCalls = [{                                         │
│    name: "capture_photo",                                   │
│    input: '{"camera": "back"}'                              │
│  }]                                                          │
└─────────────────────────────────────────────────────────────┘
```

**特点**：
- 工具定义嵌入 System Prompt
- 模型输出文本 JSON，需解析
- 无需特殊训练，依赖 Prompt Engineering

---

## 工作流程

```
┌─────────────────────────────────────────────────────────────┐
│  用户输入: "帮我截屏"                                         │
└─────────────────────┬───────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────────────────────┐
│  AIService.chat()                                           │
│  ├── provider === 'cann-local'                              │
│  │   └── callCANNLocal()                                    │
│  │       ├── buildCANNSystemPrompt() → 生成工具提示词         │
│  │       ├── modelinfer() → 模型推理                         │
│  │       └── extractToolCallsFromText() → 解析工具调用        │
│  │                                                           │
│  ├── response.toolCalls = [...]                             │
│  │                                                           │
│  └── for (tc of response.toolCalls) {                       │
│        executeTool(tc.name, tc.input, context)              │
│      }                                                       │
└─────────────────────┬───────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────────────────────┐
│  executeTool('screen_capture', '{}')                        │
│  ├── ScreenCapability.getInstance()                         │
│  ├── screenCap.setContext(context)                          │
│  └── screenCap.execute(Command.SCREEN_CAPTURE)              │
│      ├── componentSnapshot.get('appRoot')                   │
│      └── window.snapshot() fallback                         │
└─────────────────────┬───────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────────────────────┐
│  工具结果: {"note": "Screenshot saved", "path": "..."}       │
│                                                              │
│  → 添加到消息历史，再次调用模型进行总结                        │
│                                                              │
│  模型输出: "已为你截屏，保存在 ..."                           │
└─────────────────────────────────────────────────────────────┘
```

---

## 代码架构

### 配置层 (Constants.ets)

```typescript
// 添加工具名即可启用
static readonly CANN_ENABLED_TOOLS: string[] = [
  'capture_photo',
  'screen_capture',
  'get_location',
  'record_audio',
];
```

### 工具定义层 (SkillData.ets)

```typescript
// 云端和端侧共用
const TOOL_SCHEMAS: Map<string, ToolSchema[]> = new Map([
  ['skill_media', [
    { name: 'capture_photo', description: 'Take a photo', input_schema: {...} },
    { name: 'record_audio', description: 'Record audio', input_schema: {...} },
  ]],
  // ...
]);

// 根据工具名获取定义
export function getToolSchemaByName(name: string): ToolSchema | undefined;
```

### 提示词生成层 (CANNLocalService.ets)

```typescript
// 工具示例数据
const CANN_TOOL_EXTRAS_DATA: string[][] = [
  ['capture_photo', '拍照', 'camera', 'back'],
  ['capture_photo', '自拍', 'camera', 'front'],
  // ...
];

// 动态生成工具提示词
private buildToolsPrompt(): string {
  // 1. 从 TOOL_SCHEMAS 获取工具描述和参数
  // 2. 从 CANN_TOOL_EXTRAS_DATA 获取示例
  // 3. 拼接生成 System Prompt
}
```

### 工具执行层 (AIService.ets)

```typescript
// 云端和端侧共用
private async executeTool(name: string, input: string, context): Promise<string> {
  switch (name) {
    case 'capture_photo':
      // ...
    case 'screen_capture':
      // ...
    case 'get_location':
      // ...
    case 'record_audio':
      // ...
  }
}
```

---

## 当前支持的工具

### ✅ 已验证

| 工具 | 参数 | 说明 |
|------|------|------|
| `capture_photo` | `camera: "front" \| "back"` | 拍照 |
| `screen_capture` | 无 | 截屏 |
| `get_location` | 无 | 获取GPS位置 |
| `record_audio` | `seconds: number` | 录音 |

---

## 不支持的工具

### ❌ 需要网络连接

| 工具 | 原因 |
|------|------|
| `web_search` | 需要访问搜索引擎 API |
| `web_fetch` | 需要 HTTP 请求 |
| `open_webpage` | 需要打开 WebView |
| `close_webpage` | 依赖已打开的 WebView |
| `navigate_webpage` | 依赖已打开的 WebView |
| `eval_webpage` | 依赖 WebView JavaScript 环境 |
| `snapshot_webpage` | 依赖已打开的 WebView |

### ❌ 需要邮件协议

| 工具 | 原因 |
|------|------|
| `list_emails` | 需要 IMAP 连接 |
| `read_email` | 需要 IMAP 连接 |
| `search_emails` | 需要 IMAP 连接 |
| `send_email` | 需要 SMTP 连接 |

### ❌ 需要高级推理能力

| 工具 | 原因 |
|------|------|
| `search_memory` | 需要向量语义搜索，端侧无此能力 |
| `create_scheduled_task` | 复杂调度逻辑，需要时间解析和任务管理 |
| `create_skill` | 技能管理需要复杂逻辑 |
| `update_skill` | 同上 |
| `delete_skill` | 同上 |

### ❌ 需要外部服务

| 工具 | 原因 |
|------|------|
| `list_devices` | 需要智能家居 API 连接 |
| `device_action` | 需要智能家居设备通信 |

---

## 不建议支持的工具

### ⚠️ 时间解析复杂

| 工具 | 参数 | 风险 |
|------|------|------|
| `create_event` | title, start, end | 端侧模型可能无法准确解析时间格式 (ISO 8601) |
| `set_reminder` | message, time | 同上，时间解析可能不准确 |

**示例问题**：
```
用户: "明天下午三点开会"
模型输出: {"name": "create_event", "arguments": {"start": "???"}}  // 时间格式错误
```

### ⚠️ 可能涉及大量文件操作

| 工具 | 参数 | 风险 |
|------|------|------|
| `search_files` | path, pattern, content | 可能遍历大量文件，端侧性能有限 |

### ⚠️ 需要用户确认

| 工具 | 参数 | 风险 |
|------|------|------|
| `write_file` | path, content | 路径验证、权限检查复杂 |

---

## 推荐添加的工具

### ✅ 强烈推荐

| 工具 | 参数 | 理由 |
|------|------|------|
| `list_events` | days (可选) | 单参数，读取本地日历，离线操作 |
| `read_file` | path | 简单文件读取，无副作用 |
| `list_files` | path (可选) | 简单目录列表，无副作用 |
| `pick_file` | purpose | 调用系统文件选择器，用户可控 |

### ⚠️ 可考虑

| 工具 | 参数 | 注意事项 |
|------|------|---------|
| `save_memory` | mem_type, content | 简单，但需测试端侧能否正确分类记忆类型 |
| `write_file` | path, content | 需要用户确认路径，防止误操作 |

---

## 如何添加新工具

### 步骤 1: 在 Constants.ets 添加工具名

```typescript
static readonly CANN_ENABLED_TOOLS: string[] = [
  'capture_photo',
  'screen_capture',
  'get_location',
  'record_audio',
  'list_events',  // ← 添加新工具
];
```

### 步骤 2: 在 CANNLocalService.ets 添加示例

```typescript
const CANN_TOOL_EXTRAS_DATA: string[][] = [
  // ... 现有示例 ...
  
  // 添加新工具示例
  ['list_events', '查看日程', '', ''],
  ['list_events', '今天有什么安排', 'days', '1'],
  ['list_events', '未来一周的日程', 'days', '7'],
];
```

### 步骤 3: 工具描述自动生成

工具描述和参数定义会自动从 `TOOL_SCHEMAS` 获取，无需额外配置。

### 步骤 4: 验证工具执行

确保 `executeTool()` 中已实现该工具的逻辑。

---

## 性能考虑

### Prompt 长度

- 每个工具约增加 50-100 tokens
- 示例数据约增加 30-50 tokens/条
- 当前 4 个工具 + 示例 ≈ 500 tokens

### 建议

- 工具数量控制在 8 个以内
- 每个工具示例不超过 3 条
- 定期评估 Prompt 长度对推理速度的影响

---

## 调试技巧

### 查看生成的 System Prompt

```
hdc shell "hilog -x" | grep "buildCANNSystemPrompt: content="
```

### 查看工具调用解析

```
hdc shell "hilog -x" | grep "Extracted tool call"
```

### 查看工具执行结果

```
hdc shell "hilog -x" | grep "工具执行结果"
```

---

## 已知限制

1. **工具调用成功率**：依赖模型对 JSON 格式的理解，可能存在输出格式错误的情况
2. **时间解析**：端侧模型对 ISO 8601 时间格式理解有限
3. **复杂参数**：多参数工具的成功率低于单参数工具
4. **上下文影响**：历史对话中的失败记录可能影响后续工具调用

---

## 更新历史

| 日期 | 版本 | 更新内容 |
|------|------|---------|
| 2026-03-05 | v1.0 | 初始版本，支持 4 个工具 |
