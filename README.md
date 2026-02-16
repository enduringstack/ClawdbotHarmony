# ClawdBot for HarmonyOS

<p align="center">
  <strong>HarmonyOS NEXT AI Assistant</strong><br>
  多模态个人 AI 助手 · Multi-modal Personal AI Assistant
</p>

---

## 中文

### 简介

ClawdBot 是一款运行在 HarmonyOS NEXT 上的全功能个人 AI 助手应用。支持双工作模式（单机模式 / 节点模式），集成 14 项设备能力、语音交互、持久记忆、定时任务、网页浏览等功能。

### 工作模式

| 模式 | 说明 |
|------|------|
| 单机模式 | 直接调用 LLM API（SiliconFlow、OpenAI、Anthropic、OpenRouter、Ollama），本地执行所有工具 |
| 节点模式 | 通过 WebSocket 连接 OpenClaw Gateway 服务端，双会话架构（operator + node），指数退避自动重连 |

### AI 能力

**多模型支持**
- 提供商：Anthropic (Claude)、OpenAI、OpenRouter、SiliconFlow、本地 Ollama 及任意 OpenAI 兼容 API
- 每个提供商独立保存 API Key、模型名、Base URL
- Tool-use 循环（最多 8 轮），自动调用工具完成复杂任务
- 弱模型自动分发：当模型不调用 tool 时，根据关键词自动触发正确的工具
- Soul 人格系统：可自定义 AI 行为风格和语气

**语音交互**
- 按住录音，松手自动识别并发送
- ASR 引擎：sherpa-onnx + SenseVoice-Small INT8（离线识别，支持中英日韩粤）
- TTS 自动朗读 AI 回复（HarmonyOS CoreSpeechKit，在线/离线双引擎）
- 对话模式（Talk Mode）：连续语音对话，自动检测静默
- 语音消息气泡 UI，WAV 录音保存，支持点击播放

### 设备能力（14 项）

| 能力 | 工具名 | 说明 |
|------|--------|------|
| 定位 | `get_location` | GPS 定位；天气查询时自动附加位置 |
| 相机 | `capture_photo` | 前/后摄拍照，自动压缩（1.7MB → 75KB），图片内联显示 |
| 截屏 | `screen_capture` | App 窗口截图（componentSnapshot），无需系统权限，图片内联显示 |
| 网页搜索 | `web_search` | 互联网搜索 |
| 网页浏览 | `open/navigate/eval/snapshot/close_webpage` | 全屏 WebView 浏览器，支持 JS 执行、表单填写、页面截图 |
| 网页抓取 | `web_fetch` | 抓取 URL 内容 |
| 日历 | `list_events`, `create_event`, `set_reminder` | 查询日历、创建事件、设置提醒 |
| 定时任务 | `create/list/cancel_scheduled_task` | 一次性或周期性定时任务（every 30m, daily 09:00 等） |
| 邮件 | `list/read/search_emails` | IMAP 读取邮箱（列表、详情、搜索） |
| 文件系统 | `read/write/list/search/pick_file` | 沙箱文件读写、目录列表、内容搜索、系统文件选择器 |
| 记忆 | `save/search_memory` | 持久化记忆存储与语义搜索 |
| 智能家居 | `list_devices`, `device_action` | 控制 HarmonyOS 分布式 IoT 设备 |
| 通知 | 系统通知推送 |
| 终端 | Shell 命令执行（NAPI C++ popen） |

### 使用示例

```
用户: 今天天气怎么样？
→ 自动获取 GPS 位置，搜索当地天气并回复

用户: 拍张照片
→ 调用后置摄像头拍照，照片内联显示在聊天中

用户: 截屏发给我
→ 截取当前 App 屏幕，图片内联显示，点击可全屏查看

用户: 打开百度
→ 在内置浏览器中打开 baidu.com

用户: 帮我搜一下华为最新手机
→ 调用网页搜索，返回搜索结果摘要

用户: 明天下午3点提醒我开会
→ 创建日历提醒事件

用户: 每30分钟提醒我喝水
→ 创建周期性定时任务

用户: 查一下我的邮件
→ 通过 IMAP 读取最近邮件列表

用户: 我在哪里？
→ 获取 GPS 坐标并返回位置信息

用户: 我叫小明，我喜欢喝咖啡
→ 自动保存到记忆：姓名（fact）+ 偏好（preference）

用户: 你有什么功能？
→ 列出所有可用能力

用户: 你现在是什么模式？用的什么模型？
→ 回答当前工作模式（单机/节点）和 AI 模型名称
```

### 智能功能

**记忆系统**
- 跨会话持久化：事实（fact）、偏好（preference）、指令（instruction）
- 对话中自动提取记忆，AI 主动保存用户信息
- 语义搜索匹配相关记忆
- Gateway 模式下双向同步

**上下文感知**
- 天气查询自动获取 GPS 位置
- 截屏/拍照结果自动内联显示，点击全屏预览
- 图片路径自动从文本中清除（不显示冗余路径）
- 对话历史浏览与管理（Markdown 格式保存）

**自动分发**
- 位置关键词 → 自动调用 `get_location`
- 截屏关键词 → 自动调用 `screen_capture`
- 天气关键词 → 自动附加 GPS 坐标
- 网页关键词 → 自动调用 `open_webpage`
- 邮件关键词 → 自动调用 `list_emails`

### 已知问题

**本地 Embedding 模型暂时禁用**

项目包含本地 MiniLM-L6 embedding 模型（6层 Transformer），用于离线语义搜索。但由于 HarmonyOS 的 ANR（应用无响应）阈值为 3 秒，单层 Transformer 计算在主线程上就可能超时导致崩溃。

尝试过的方案：
- ✅ 异步文件读取 - 解决了模型加载时的 ANR
- ❌ 每层后 yield 让出主线程 - 单层计算仍然太久
- ❌ Worker 线程 - ArkTS 严格类型检查导致实现复杂

当前状态：`LocalEmbedding.isReady()` 返回 `false`，强制使用云端 API。

TODO：实现基于 Worker 的后台计算方案。

### 技术栈

- **平台**: HarmonyOS NEXT (API 12 ~ 22)
- **语言**: ArkTS + C++ (NAPI)
- **构建**: Hvigor
- **UI**: ArkUI 声明式
- **ASR**: sherpa-onnx v1.12.24 + SenseVoice-Small INT8
- **TTS**: HarmonyOS CoreSpeechKit（在线 + 离线）
- **最低 SDK**: 5.0.0(12)
- **目标 SDK**: 6.0.2(22)

### 项目结构

```
entry/src/main/
├── ets/
│   ├── common/          # Constants, I18n, LogService
│   ├── components/      # MessageBubble, MarkdownText, SkillCard
│   ├── entryability/    # EntryAbility (应用入口)
│   ├── model/           # ChatMessage, MemoryItem 等数据模型
│   ├── pages/           # ChatPage, SettingsPage, SkillsPage, MemoryPage, LogPage
│   ├── workers/         # SenseVoiceAsrWorker (离线 ASR)
│   └── service/
│       ├── AIService.ets       # LLM 调用 + Tool-use 循环 + 自动分发
│       ├── MemoryService.ets   # 记忆持久化 + 语义搜索
│       ├── SkillData.ets       # 技能目录 + 工具 Schema 定义
│       └── gateway/            # 14 项 Capability 实现
│           ├── NodeRuntime.ets         # Gateway WebSocket 连接
│           ├── CameraCapability.ets    # 拍照 + 压缩
│           ├── ScreenCapability.ets    # App 窗口截图
│           ├── SpeakerCapability.ets   # TTS + 音频播放
│           ├── CalendarCapability.ets  # 日历事件 + 提醒
│           ├── CanvasCapability.ets    # WebView 浏览器
│           ├── ExecCapability.ets      # Shell 执行
│           └── ...
└── cpp/
    └── napi_exec.cpp    # Shell 执行（popen）
```

### 构建

```bash
# 需要安装 DevEco Studio
export DEVECO_SDK_HOME="/path/to/DevEco Studio/sdk"
hvigorw assembleHap --no-daemon
```

### 安装到设备

```bash
hdc install entry/build/default/outputs/default/entry-default-signed.hap
```

---

## English

### Introduction

ClawdBot is a full-featured personal AI assistant for HarmonyOS NEXT. It supports dual work modes (Standalone / Node), integrates 14 device capabilities, voice interaction, persistent memory, scheduled tasks, web browsing, and more.

### Work Modes

| Mode | Description |
|------|-------------|
| Standalone | Direct LLM API calls (SiliconFlow, OpenAI, Anthropic, OpenRouter, Ollama), all tools executed locally |
| Node | WebSocket connection to OpenClaw Gateway server, dual-session architecture (operator + node), exponential backoff auto-reconnect |

### AI Capabilities

**Multi-Model Support**
- Providers: Anthropic (Claude), OpenAI, OpenRouter, SiliconFlow, local Ollama, and any OpenAI-compatible API
- Per-provider API key, model name, and base URL settings
- Tool-use loop (up to 8 rounds) for autonomous complex task execution
- Weak model auto-dispatch: automatically triggers correct tools when model fails to call them
- Soul personality system: customizable AI behavior and tone

**Voice Interaction**
- Press-and-hold to record, auto-transcribe and send
- ASR engine: sherpa-onnx + SenseVoice-Small INT8 (offline, supports Chinese/English/Japanese/Korean/Cantonese)
- TTS auto-read for AI responses (HarmonyOS CoreSpeechKit, online/offline dual engine)
- Talk Mode: continuous voice conversation with automatic silence detection
- Voice message bubble UI, WAV recording saved, tap to play

### Device Capabilities (14)

| Capability | Tool Name | Description |
|------------|-----------|-------------|
| Location | `get_location` | GPS positioning; auto-appended for weather queries |
| Camera | `capture_photo` | Front/back camera, auto-compression (1.7MB → 75KB), inline image display |
| Screenshot | `screen_capture` | App window capture (componentSnapshot), no system permission required, inline display |
| Web Search | `web_search` | Internet search |
| Web Browser | `open/navigate/eval/snapshot/close_webpage` | Full-screen WebView browser with JS execution, form filling, page screenshot |
| Web Fetch | `web_fetch` | Fetch URL content |
| Calendar | `list_events`, `create_event`, `set_reminder` | List events, create events, set reminders |
| Scheduler | `create/list/cancel_scheduled_task` | One-shot or recurring tasks (every 30m, daily 09:00, etc.) |
| Email | `list/read/search_emails` | IMAP inbox reading (list, detail, search) |
| File System | `read/write/list/search/pick_file` | Sandbox file R/W, directory listing, content search, system file picker |
| Memory | `save/search_memory` | Persistent memory storage and semantic search |
| Smart Home | `list_devices`, `device_action` | Control HarmonyOS distributed IoT devices |
| Notification | System push notifications |
| Exec | Shell command execution (NAPI C++ popen) |

### Usage Examples

```
User: What's the weather today?
→ Auto-fetches GPS location, searches local weather and replies

User: Take a photo
→ Captures photo with rear camera, displays inline in chat

User: Take a screenshot
→ Captures current app screen, displays inline, tap for full-screen

User: Open Google
→ Opens google.com in built-in browser

User: Search for the latest iPhone
→ Calls web search, returns result summary

User: Remind me about the meeting tomorrow at 3pm
→ Creates a calendar reminder event

User: Remind me to drink water every 30 minutes
→ Creates a recurring scheduled task

User: Check my email
→ Reads recent emails via IMAP

User: Where am I?
→ Gets GPS coordinates and returns location info

User: My name is Alex, I like coffee
→ Auto-saves to memory: name (fact) + preference

User: What can you do?
→ Lists all available capabilities

User: What mode are you in? What model are you using?
→ Replies with current work mode (Standalone/Node) and AI model name
```

### Smart Features

**Memory System**
- Persistent across sessions: facts, preferences, instructions
- Auto-extraction from conversations, AI proactively saves user info
- Semantic search for related memories
- Bi-directional sync in Gateway mode

**Context Awareness**
- Weather queries auto-fetch GPS location
- Screenshot/photo results displayed inline, tap for full-screen preview
- Image paths auto-stripped from text (no redundant paths shown)
- Conversation history browsing and management (saved as Markdown)

**Auto-Dispatch**
- Location keywords → auto-call `get_location`
- Screenshot keywords → auto-call `screen_capture`
- Weather keywords → auto-append GPS coordinates
- Web keywords → auto-call `open_webpage`
- Email keywords → auto-call `list_emails`

### Known Issues

**Local Embedding Model Temporarily Disabled**

The project includes a local MiniLM-L6 embedding model (6-layer Transformer) for offline semantic search. However, due to HarmonyOS's 3-second ANR (Application Not Responding) threshold, even a single Transformer layer computation on the main thread can timeout and cause crashes.

Attempted solutions:
- ✅ Async file reading - Fixed ANR during model loading
- ❌ Yield after each layer - Single layer computation still too slow
- ❌ Worker thread - ArkTS strict typing made implementation complex

Current status: `LocalEmbedding.isReady()` returns `false`, forcing cloud API fallback.

TODO: Implement Worker-based background computation solution.

### Tech Stack

- **Platform**: HarmonyOS NEXT (API 12 ~ 22)
- **Language**: ArkTS + C++ (NAPI)
- **Build**: Hvigor
- **UI**: ArkUI declarative
- **ASR**: sherpa-onnx v1.12.24 + SenseVoice-Small INT8
- **TTS**: HarmonyOS CoreSpeechKit (online + offline)
- **Min SDK**: 5.0.0(12)
- **Target SDK**: 6.0.2(22)

### Project Structure

```
entry/src/main/
├── ets/
│   ├── common/          # Constants, I18n, LogService
│   ├── components/      # MessageBubble, MarkdownText, SkillCard
│   ├── entryability/    # EntryAbility (app entry)
│   ├── model/           # ChatMessage, MemoryItem and other data models
│   ├── pages/           # ChatPage, SettingsPage, SkillsPage, MemoryPage, LogPage
│   ├── workers/         # SenseVoiceAsrWorker (offline ASR)
│   └── service/
│       ├── AIService.ets       # LLM calls + tool-use loop + auto-dispatch
│       ├── MemoryService.ets   # Memory persistence + semantic search
│       ├── SkillData.ets       # Skill catalog + tool schema definitions
│       └── gateway/            # 14 capability implementations
│           ├── NodeRuntime.ets         # Gateway WebSocket connection
│           ├── CameraCapability.ets    # Photo capture + compression
│           ├── ScreenCapability.ets    # App window screenshot
│           ├── SpeakerCapability.ets   # TTS + audio playback
│           ├── CalendarCapability.ets  # Calendar events + reminders
│           ├── CanvasCapability.ets    # WebView browser
│           ├── ExecCapability.ets      # Shell execution
│           └── ...
└── cpp/
    └── napi_exec.cpp    # Shell execution (popen)
```

### Build

```bash
# Requires DevEco Studio
export DEVECO_SDK_HOME="/path/to/DevEco Studio/sdk"
hvigorw assembleHap --no-daemon
```

### Install to Device

```bash
hdc install entry/build/default/outputs/default/entry-default-signed.hap
```

---

## License

Apache-2.0
