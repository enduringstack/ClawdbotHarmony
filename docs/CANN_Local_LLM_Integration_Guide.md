# ClawdBot 端侧 LLM 集成指南

本文档介绍如何为 ClawdBot 添加端侧大语言模型（LLM）推理功能。

## 目录

1. [概述](#概述)
2. [配置文件说明](#配置文件说明)
3. [部署步骤](#部署步骤)
4. [功能支持说明](#功能支持说明)
5. [故障排查](#故障排查)
6. [更换模型](#更换模型)

---

## 概述

ClawdBot 支持端侧 LLM 推理，使用 CANN (Compute Architecture for Neural Networks) 框架在 HarmonyOS 设备上运行大语言模型。

### 技术架构

```
┌─────────────────────────────────────────────────────────────┐
│                    ClawdBot Application                      │
├─────────────────────────────────────────────────────────────┤
│  TypeScript Layer                                            │
│  ┌──────────────────┐  ┌──────────────────┐                 │
│  │ CANNLocalService │  │   AIService      │                 │
│  └────────┬─────────┘  └──────────────────┘                 │
│           │                                                  │
│           ↓ N-API                                            │
├─────────────────────────────────────────────────────────────┤
│  C++ Layer                                                   │
│  ┌──────────────────┐  ┌──────────────────┐                 │
│  │  cann_wrapper    │  │   llm_core       │                 │
│  └────────┬─────────┘  └────────┬─────────┘                 │
│           │                     │                            │
│           ↓                     ↓                            │
│  ┌─────────────────────────────────────────┐                 │
│  │      libhiai_llm_engine.so              │                 │
│  │      (华为 NPU 推理引擎)                 │                 │
│  └─────────────────────────────────────────┘                 │
└─────────────────────────────────────────────────────────────┘
```

### 当前模型

- **Target 模型**: Pangu 7B (主模型，负责最终生成)
- **Draft 模型**: Pangu 220M (小模型，用于推测加速)
- **推理方式**: 推测推理 (Speculative Inference)
- **额外功能**: LoRA 动态加载

---

## 配置文件说明

### 1. 主要配置文件：Constants.ets

**位置**: `entry/src/main/ets/common/Constants.ets`

**所有端侧 LLM 配置集中在此文件**：

```typescript
// CANN Local LLM Configuration
static readonly CANN_TARGET_MODEL_NAME: string = 'chs_7b_target_model';
static readonly CANN_DRAFT_MODEL_NAME: string = 'chs_7b_draft_model';

// Model file names (relative to model directory)
static readonly CANN_TARGET_MODEL_FILE: string = 'chs_7b_target_model.omc';
static readonly CANN_DRAFT_MODEL_FILE: string = 'chs_7b_draft_model.omc';
static readonly CANN_TOKENIZER_FILE: string = 'tokenizer.model';
static readonly CANN_LORA_CONFIG_FILE: string = 'chs_7b_target_model.omc.loraconf';

// Inference parameters
static readonly CANN_MAX_GEN_TOKENS: number = 512;
static readonly CANN_TEMPERATURE: number = 0.7;
static readonly CANN_TOP_K: number = 16;
static readonly CANN_TOP_P: number = 0.8;
static readonly CANN_SPECULATIVE_GAMMA: number = 3;
```

### 2. 配置项详解

#### 模型路径配置

| 配置项 | 说明 | 示例值 |
|--------|------|--------|
| `CANN_TARGET_MODEL_NAME` | Target 模型目录名 | `chs_7b_target_model` |
| `CANN_DRAFT_MODEL_NAME` | Draft 模型目录名 | `chs_7b_draft_model` |
| `CANN_TARGET_MODEL_FILE` | Target 模型文件名 | `chs_7b_target_model.omc` |
| `CANN_DRAFT_MODEL_FILE` | Draft 模型文件名 | `chs_7b_draft_model.omc` |
| `CANN_TOKENIZER_FILE` | 分词器文件名 | `tokenizer.model` |
| `CANN_LORA_CONFIG_FILE` | LoRA 配置文件名 | `chs_7b_target_model.omc.loraconf` |

#### 推理参数配置

| 配置项 | 说明 | 默认值 | 取值范围 |
|--------|------|--------|---------|
| `CANN_MAX_GEN_TOKENS` | 最大生成长度 | 512 | 1-2048 |
| `CANN_TEMPERATURE` | 温度参数 | 0.7 | 0.0-2.0 |
| `CANN_TOP_K` | Top-K 采样 | 16 | 1-100 |
| `CANN_TOP_P` | Top-P 采样 | 0.8 | 0.0-1.0 |
| `CANN_SPECULATIVE_GAMMA` | 推测深度 | 3 | 1-8 |

### 3. 其他相关文件

#### lib64 目录

**位置**: `entry/src/main/cpp/lib64/`

需要放置以下文件：
- `libllm_core.so` - 核心 LLM 封装库
- `libhiai_llm_engine.so` - 华为 NPU 推理引擎

**获取方式**: 参考 `entry/src/main/cpp/lib64/README.md`

#### N-API 类型定义

**位置**: `entry/src/main/cpp/types/libcann_llm/index.d.ts`

TypeScript 接口定义，通常无需修改。

---

## 部署步骤

### 步骤 1: 获取 so 文件

**方式 1: 从源码编译（推荐）**

```bash
# 克隆源码仓库
git clone ssh://git@szv-y.codehub.huawei.com:2222/x00897182/cann_llm_deploy.git
cd cann_llm_deploy
git checkout external-release

# 在 DevEco Studio 中编译
# 生成的 so 文件位于：entry/build/default/intermediates/cmake/default/obj/arm64-v8a/

# 复制到本项目
cp entry/build/default/intermediates/cmake/default/obj/arm64-v8a/libllm_core.so \
   path/to/ClawdbotHarmony/entry/src/main/cpp/lib64/

cp path/to/libhiai_llm_engine.so \
   path/to/ClawdbotHarmony/entry/src/main/cpp/lib64/
```

**方式 2: 从预编译包获取**

联系项目维护者获取预编译 so 文件。

### 步骤 2: 编译项目

```bash
# 在 DevEco Studio 中打开项目
# Build -> Build Hap(s)/APP(s) -> Build Hap(s)
```

**编译日志验证**：
```
CANN LLM libraries found, enabling cann_llm module with full functionality
```

### 步骤 3: 获取模型文件

模型文件需要单独获取，包括：

**Target 模型 (chs_7b_target_model/)**:
```
chs_7b_target_model/
├── chs_7b_target_model.omc          # 模型结构文件 (~7MB)
├── chs_7b_target_model.json         # 模型配置
├── chs_7b_target_model.omc.loraconf # LoRA 配置 (~42KB)
├── chs_7b_target_model.omc.loradata # LoRA 数据 (~71MB)
├── chs_7b_target_model.omc.quantpara # 量化参数 (~7MB)
├── SubGraph_0.weight                # 模型权重 (~2.6GB)
├── chs_7b_32_1536.embedding_dequant_scale
├── chs_7b_32_1536.embedding_weights  # Embedding 权重 (~450MB)
└── tokenizer.model                  # 分词器 (~2.4MB)
```

**Draft 模型 (chs_7b_draft_model/)**:
```
chs_7b_draft_model/
├── chs_7b_draft_model.omc           # 模型结构文件 (~11MB)
├── chs_7b_draft_model.json          # 模型配置
├── SubGraph_0.weight                # 模型权重 (~50MB)
├── Pangu_7B_220M_TokenFreq.json     # Token 频率映射
├── chs_spec_model_32_4224.embedding_dequant_scale
├── chs_spec_model_32_4224.embedding_weights # Embedding 权重 (~75MB)
└── tokenizer.model                 # 分词器 (~2.4MB)
```

### 步骤 4: 部署模型到设备

**使用部署脚本**:

```bash
cd scripts
deploy_cann_model.bat
```

**手动部署**:

```bash
# 确定应用包名
PACKAGE_NAME="com.hongjieliu.clawdbot"

# 沙箱路径
SANDBOX_PATH="/data/app/el2/100/base/${PACKAGE_NAME}/haps/entry/files"

# 创建目录
hdc shell "mkdir -p ${SANDBOX_PATH}/chs_7b_target_model"
hdc shell "mkdir -p ${SANDBOX_PATH}/chs_7b_draft_model"

# 发送模型文件
hdc file send D:/path/to/chs_7b_target_model/* ${SANDBOX_PATH}/chs_7b_target_model/
hdc file send D:/path/to/chs_7b_draft_model/* ${SANDBOX_PATH}/chs_7b_draft_model/

# 验证
hdc shell "ls -la ${SANDBOX_PATH}/chs_7b_target_model/"
hdc shell "ls -la ${SANDBOX_PATH}/chs_7b_draft_model/"
```

### 步骤 5: 使用端侧模型

1. 打开 ClawdBot App
2. 进入 **设置**
3. 在 **AI Provider** 中选择 **CANN Local**
4. 开始对话

---

## 功能支持说明

### ✅ 支持的功能

| 功能 | 状态 | 说明 |
|------|------|------|
| **基础对话** | ✅ 完全支持 | 单轮/多轮对话 |
| **推测推理** | ✅ 完全支持 | 使用 Draft 模型加速 |
| **LoRA 动态加载** | ✅ 完全支持 | 运行时加载 LoRA 权重 |
| **流式输出** | ✅ 完全支持 | Token 级别的流式响应 |
| **对话历史** | ✅ 完全支持 | 多轮对话上下文 |
| **记忆系统** | ✅ 完全支持 | 跨会话持久记忆 |
| **System Prompt** | ✅ 完全支持 | 中文精简版系统提示 |
| **NPU 加速** | ✅ 完全支持 | 华为 NPU 硬件加速 |
| **离线推理** | ✅ 完全支持 | 无需网络连接 |

### ❌ 不支持的功能

| 功能 | 状态 | 原因 | 替代方案 |
|------|------|------|---------|
| **Tool Calling** | ❌ 不支持 | 模型未训练 function calling | 使用关键词匹配触发 |
| **多模态输入** | ❌ 不支持 | 仅文本模型 | - |
| **联网搜索** | ❌ 不支持 | 离线推理 | 使用云端模型 |
| **代码解释器** | ❌ 不支持 | 无执行环境 | - |
| **图片生成** | ❌ 不支持 | 仅文本生成 | - |
| **实时语音** | ❌ 不支持 | 需额外 ASR/TTS | - |
| **并发请求** | ❌ 不支持 | 单实例限制 | 一次一个请求 |
| **会话隔离** | ⚠️ 部分支持 | 共享 KV Cache | 建议一次只用一个会话 |

### ⚠️ 部分支持的功能

| 功能 | 状态 | 说明 |
|------|------|------|
| **自定义 System Prompt** | ⚠️ 部分支持 | 会转换为中文精简版 |
| **动态参数调整** | ⚠️ 部分支持 | 需修改 Constants.ets 重新编译 |
| **多模型切换** | ⚠️ 部分支持 | 需重新部署模型文件 |
| **会话隔离** | ⚠️ 部分支持 | 共享 KV Cache，建议一次只用一个会话 |

### ⚠️ 会话隔离限制说明

**问题描述**：

ClawdBot 支持并行会话（多个对话窗口同时运行），但端侧模型有特殊限制：

```
用户操作：同时打开会话 A 和会话 B

问题：
┌─────────────────────────────────────────────────────────────┐
│  会话 A                    │  会话 B                        │
│  "你好，我是小明"           │  "天气怎么样？"                │
│       ↓                    │       ↓                        │
│  KV Cache 包含会话 A 的上下文                               │
│       ↓                    │       ↓                        │
│  会话 B 的回复可能包含会话 A 的内容                          │
│  例如："小明，今天天气..."                                   │
└─────────────────────────────────────────────────────────────┘
```

**原因**：
- CANNLocalService 是单例模式（全局唯一实例）
- 模型只加载一次，所有会话共享
- KV Cache（推理缓存）在会话间共享

**解决方案**：

1. **推荐：一次只使用一个会话**
   - 切换会话前先关闭当前会话
   - 在设置中关闭"并行会话"功能

2. **替代方案：使用云端模型**
   - 需要并行会话时切换到云端模型
   - 云端模型完全支持会话隔离

3. **未来改进**（需要开发）：
   - 每个会话创建独立的模型实例
   - 实现会话级别的 KV Cache 隔离
   - 支持会话间快速切换

**最佳实践**：
```typescript
// 在 Constants.ets 中设置
static readonly DEFAULT_PARALLEL_SESSIONS: boolean = false;  // 关闭并行会话
```

### 功能对比表

| 功能 | 端侧模型 (CANN Local) | 云端模型 (OpenAI/Anthropic) |
|------|---------------------|---------------------------|
| **隐私保护** | ✅ 完全本地 | ❌ 数据上传云端 |
| **网络依赖** | ✅ 无需网络 | ❌ 必须联网 |
| **推理速度** | ⚠️ 较慢 (~3s) | ✅ 快速 (~1s) |
| **响应质量** | ⚠️ 中等 | ✅ 高 |
| **成本** | ✅ 免费 | ❌ 按量计费 |
| **Tool Calling** | ❌ 不支持 | ✅ 完全支持 |
| **多模态** | ❌ 仅文本 | ✅ 图片/音频 |
| **知识更新** | ❌ 固定训练数据 | ✅ 实时更新 |

---

## 故障排查

### 问题 1: 设置中没有 CANN Local 选项

**原因**: so 文件未找到

**解决方案**:
1. 检查 `entry/src/main/cpp/lib64/` 目录
2. 确认 `libllm_core.so` 和 `libhiai_llm_engine.so` 存在
3. 重新编译项目

### 问题 2: 模型初始化失败

**错误信息**: `Executor_Init failed: 1`

**可能原因**:
1. 模型文件未部署到设备
2. 模型文件损坏或不完整
3. 设备内存不足

**解决方案**:
```bash
# 检查模型文件
hdc shell "ls -la /data/app/el2/100/base/com.hongjieliu.clawdbot/haps/entry/files/"

# 检查文件完整性
hdc shell "md5sum /path/to/SubGraph_0.weight"

# 检查设备内存
hdc shell "cat /proc/meminfo | grep MemAvailable"
```

### 问题 3: 推理无响应

**可能原因**:
1. 模型未正确初始化
2. Prompt 格式错误
3. 内存不足

**调试步骤**:
```bash
# 查看日志
hdc shell "hilog -x" | grep -E "CANN_LLM|HIAI_DDK_MSG"

# 检查初始化状态
hdc shell "hilog -x" | grep "isAvailable"
```

### 问题 4: 输出质量差

**可能原因**:
1. Temperature 参数不合适
2. 模型不适合当前任务

**优化建议**:
```typescript
// 调整 Constants.ets 中的参数
static readonly CANN_TEMPERATURE: number = 0.5;  // 降低随机性
static readonly CANN_TOP_K: number = 40;         // 增加候选
static readonly CANN_TOP_P: number = 0.9;        // 提高阈值
```

### 问题 5: 内存不足

**症状**: 应用崩溃或系统卡顿

**解决方案**:
1. 减少 `CANN_MAX_GEN_TOKENS`
2. 关闭其他应用
3. 使用更小的模型

---

## 更换模型

### 更换步骤

**1. 修改配置文件**

编辑 `entry/src/main/ets/common/Constants.ets`:

```typescript
// 修改模型名称
static readonly CANN_TARGET_MODEL_NAME: string = 'new_target_model';
static readonly CANN_DRAFT_MODEL_NAME: string = 'new_draft_model';

// 修改文件名
static readonly CANN_TARGET_MODEL_FILE: string = 'new_target.omc';
static readonly CANN_DRAFT_MODEL_FILE: string = 'new_draft.omc';

// 修改推理参数（如需要）
static readonly CANN_MAX_GEN_TOKENS: number = 1024;
static readonly CANN_TEMPERATURE: number = 0.8;
```

**2. 准备新模型文件**

确保新模型文件格式符合要求：
- OMC 格式模型文件
- 兼容的权重文件
- 正确的 tokenizer

**3. 更新部署脚本**

修改 `scripts/deploy_cann_model.bat`:
```batch
set LOCAL_TARGET=D:/path/to/new_target_model
set LOCAL_DRAFT=D:/path/to/new_draft_model
```

**4. 重新部署**

```bash
# 重新编译
# 重新部署模型文件
# 重启应用
```

### 模型兼容性要求

**必须满足**:
- HarmonyOS 兼容的 OMC 格式
- 支持 NPU 推理
- 正确的量化配置

**推荐**:
- 推测推理支持（需要配套 Draft 模型）
- LoRA 支持（可选）

---

## 性能优化建议

### 1. 减少生成长度

```typescript
static readonly CANN_MAX_GEN_TOKENS: number = 256;  // 从 512 减到 256
```

### 2. 调整推测参数

```typescript
static readonly CANN_SPECULATIVE_GAMMA: number = 2;  // 从 3 减到 2
```

### 3. 优化采样策略

```typescript
static readonly CANN_TEMPERATURE: number = 0.5;  // 降低随机性
static readonly CANN_TOP_K: number = 10;         // 减少候选
```

---

## 附录

### A. 文件清单

```
ClawdbotHarmony/
├── entry/src/main/
│   ├── ets/
│   │   ├── common/
│   │   │   └── Constants.ets          ← 主要配置文件
│   │   └── service/
│   │       └── CANNLocalService.ets   ← 服务实现
│   └── cpp/
│       ├── CMakeLists.txt
│       ├── cann_llm/                  ← C++ 实现
│       │   ├── CMakeLists.txt
│       │   ├── cann_wrapper.cpp
│       │   └── llm_core.h
│       ├── cann_llm_stub/             ← Stub 实现
│       │   ├── CMakeLists.txt
│       │   └── cann_llm_stub.cpp
│       ├── types/libcann_llm/         ← TypeScript 类型
│       │   ├── index.d.ts
│       │   └── oh-package.json5
│       └── lib64/                     ← so 文件目录
│           ├── README.md
│           ├── libllm_core.so
│           └── libhiai_llm_engine.so
└── scripts/
    ├── deploy_cann_model.bat          ← 部署脚本
    └── deploy_cann_model.sh
```

### B. 相关文档

- [CANN_LLM_Engine_Integration_Guide.md](./CANN_LLM_Engine_Integration_Guide.md)
- [lib64/README.md](../entry/src/main/cpp/lib64/README.md)

### C. 常用命令

```bash
# 查看 CANN 日志
hdc shell "hilog -x" | grep "CANN_LLM"

# 检查模型文件
hdc shell "ls -la /data/app/el2/100/base/com.hongjieliu.clawdbot/haps/entry/files/"

# 检查 so 文件
ls -la entry/src/main/cpp/lib64/

# 部署模型
scripts/deploy_cann_model.bat
```

---

**文档版本**: 1.0  
**最后更新**: 2026-03-05  
**维护者**: ClawdBot Team
