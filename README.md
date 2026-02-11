# ClawdBot for HarmonyOS

<p align="center">
  <strong>HarmonyOS NEXT AI Assistant</strong><br>
  多模态个人 AI 助手 · Multi-modal Personal AI Assistant
</p>

---

## 中文

### 简介

ClawdBot 是一款运行在 HarmonyOS NEXT 上的个人 AI 助手应用，通过 OpenClaw Gateway 连接服务端，支持多 LLM 提供商、11 项设备能力、语音交互、记忆系统和可配置人格。

### 核心功能

**AI 对话**
- 多提供商支持：Anthropic (Claude)、OpenAI、OpenRouter、本地 Ollama
- 每个提供商独立保存 API Key、模型、Base URL
- Tool-use 循环（最多 8 轮），自动调用工具完成任务
- Soul 人格系统：可自定义 AI 行为风格和语气

**语音交互**
- 按住录音，松手自动识别（ASR）并发送
- TTS 自动朗读 AI 回复
- 语音消息气泡 UI，支持点击播放

**设备能力（11 项）**

| 能力 | 说明 |
|------|------|
| 定位 | GPS 定位，含缓存 |
| 相机 | 拍照/录像，自动压缩（1.7MB → 75KB）|
| 画布 | WebView 渲染（A2UI）|
| 截屏 | 截屏/录屏 |
| 通知 | 系统通知推送 |
| 短信 | 发送短信 |
| 麦克风 | 录音（M4A/WAV/MP3）|
| 音箱 | TTS 朗读 / 音频播放 |
| 邮件 | 调用系统邮件发送 |
| 日历 | 创建事件、设置提醒、查询日历 |
| 终端 | Shell 命令执行（NAPI C++）|

**记忆系统**
- 跨会话持久化：事实、偏好、指令
- 对话中自动提取记忆
- Gateway 模式下双向同步

**Gateway 节点模式**
- WebSocket RPC 协议连接 OpenClaw Gateway
- 双会话架构（operator + node）
- 指数退避自动重连

### 技术栈

- **平台**: HarmonyOS NEXT (API 12 ~ 22)
- **语言**: ArkTS + C++ (NAPI)
- **构建**: Hvigor
- **UI**: ArkUI 声明式
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
│   └── service/
│       ├── AIService.ets       # LLM 调用 + Tool-use 循环
│       ├── MemoryService.ets   # 记忆持久化
│       ├── SkillData.ets       # 技能 + 工具 Schema
│       └── gateway/            # 11 项 Capability 实现
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

ClawdBot is a personal AI assistant app for HarmonyOS NEXT. It connects to a backend via OpenClaw Gateway and supports multiple LLM providers, 11 device capabilities, voice interaction, a memory system, and configurable personality.

### Key Features

**AI Chat**
- Multi-provider: Anthropic (Claude), OpenAI, OpenRouter, local Ollama
- Per-provider API key, model, and base URL settings
- Tool-use loop (up to 8 rounds) for autonomous task execution
- Soul personality system: customizable AI behavior and tone

**Voice Interaction**
- Press-and-hold to record, auto-transcribe (ASR) and send
- TTS auto-read for AI responses
- Voice message bubbles with audio playback

**Device Capabilities (11)**

| Capability | Description |
|------------|-------------|
| Location | GPS with caching |
| Camera | Photo/video, auto-compression (1.7MB → 75KB) |
| Canvas | WebView rendering (A2UI) |
| Screen | Screenshot / screen recording |
| Notification | System push notifications |
| SMS | Send text messages |
| Microphone | Audio recording (M4A/WAV/MP3) |
| Speaker | TTS / audio playback |
| Email | System email client |
| Calendar | Create events, set reminders, list events |
| Exec | Shell command execution (NAPI C++) |

**Memory System**
- Persistent across sessions: facts, preferences, instructions
- Auto-extraction from conversations
- Bi-directional sync in Gateway mode

**Gateway Node Mode**
- WebSocket RPC protocol to OpenClaw Gateway
- Dual-session architecture (operator + node)
- Exponential backoff auto-reconnect

### Tech Stack

- **Platform**: HarmonyOS NEXT (API 12 ~ 22)
- **Language**: ArkTS + C++ (NAPI)
- **Build**: Hvigor
- **UI**: ArkUI declarative
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
│   └── service/
│       ├── AIService.ets       # LLM calls + tool-use loop
│       ├── MemoryService.ets   # Memory persistence
│       ├── SkillData.ets       # Skills + tool schemas
│       └── gateway/            # 11 capability implementations
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
