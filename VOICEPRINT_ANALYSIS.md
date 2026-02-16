# 声纹识别 (Voice Print / Speaker Identification) 可行性分析

## 1. 目标

在 ClawdBotHarmony 中实现声纹识别功能：
- **说话人识别 (Speaker Identification)**: 识别"谁在说话"
- **声纹注册**: 支持注册多个用户的声纹
- **与现有 ASR 集成**: 在语音识别的同时识别说话人身份

## 2. 现有代码分析

### 2.1 音频采集
- **MicrophoneCapability.ets**: 使用 `AVRecorder` 录制音频 (M4A/AAC格式, 44.1kHz)
- **ChatPage.ets**: 使用 `AudioCapturer` 实时采集 PCM 音频 (16kHz/16bit/mono)

### 2.2 语音识别
- **LocalAsrService.ets**: 使用 HarmonyOS `@kit.CoreSpeechKit.speechRecognizer` 进行本地语音识别
- 支持离线识别，无需网络
- 输入格式: PCM 16kHz/16bit/mono

### 2.3 关键发现
- 音频采集基础设施已完善
- PCM 音频流可直接用于声纹识别
- 无需额外的录音实现

---

## 3. 声纹识别方案对比

### 方案 A: sherpa-onnx (推荐 ⭐⭐⭐⭐⭐)

**简介**: 开源的端侧语音处理框架，支持说话人识别、语音识别、语音合成等。

**优点**:
- ✅ **完全离线**: 所有处理在设备上完成，无隐私泄露风险
- ✅ **开源免费**: Apache 2.0 许可，无 API 调用费用
- ✅ **多平台支持**: 支持 Android、iOS、Linux、Windows、HarmonyOS (通过 NDK)
- ✅ **轻量模型**: 3D-Speaker 模型仅 ~25MB，适合移动设备
- ✅ **高准确率**: 3D-Speaker 在 VoxCeleb 测试集 EER ~1%

**缺点**:
- ⚠️ 需要 C++ NAPI 集成
- ⚠️ 需要编译 ONNX Runtime for HarmonyOS

**集成方式**:
1. 使用现有的 `napi_exec.cpp` 框架
2. 添加 sherpa-onnx C++ 库
3. ArkTS 调用 NAPI 接口提取声纹特征

**资源**:
- GitHub: https://github.com/k2-fsa/sherpa-onnx
- 模型: https://github.com/k2-fsa/sherpa-onnx/releases (3dspeaker*.onnx)

---

### 方案 B: HarmonyOS 原生 API (不推荐 ⭐⭐)

**现状**:
- HarmonyOS 目前**没有原生的声纹识别 API**
- `@kit.CoreSpeechKit` 仅支持语音识别 (ASR)，不支持说话人识别
- `@kit.Security` 没有声纹相关能力

**结论**: HarmonyOS 原生方案暂不可行。

---

### 方案 C: 云服务 (备选 ⭐⭐⭐)

| 服务商 | 准确率 | 价格 | 延迟 | 备注 |
|--------|--------|------|------|------|
| **讯飞 (iFlytek)** | 高 | 0.01元/次 | ~500ms | 国内首选，文档完善 |
| **阿里云** | 高 | 0.005元/次 | ~300ms | 批量便宜 |
| **百度云** | 中高 | 0.006元/次 | ~400ms | 免费额度大 |
| **腾讯云** | 中 | 0.004元/次 | ~350ms | 性价比高 |

**优点**:
- ✅ 集成简单，只需 HTTP 调用
- ✅ 高准确率，持续优化
- ✅ 无需本地模型

**缺点**:
- ❌ 需要网络连接
- ❌ 有隐私顾虑 (音频上传到服务器)
- ❌ 持续产生 API 费用
- ❌ 依赖第三方服务稳定性

---

## 4. 推荐方案: sherpa-onnx

### 4.1 架构设计

```
┌─────────────────────────────────────────────────────────┐
│                    ChatPage.ets                          │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐  │
│  │ AudioCapturer│──▶│ PCM Buffer │──▶│ VoiceprintService│  │
│  └─────────────┘  └─────────────┘  └────────┬────────┘  │
└──────────────────────────────────────────────┼──────────┘
                                               │
                                               ▼
┌─────────────────────────────────────────────────────────┐
│                   voiceprint_napi.cpp                   │
│  ┌─────────────────────────────────────────────────┐   │
│  │ sherpa-onnx SpeakerEmbeddingExtractor          │   │
│  │ - extractEmbedding(pcm) → float[192]           │   │
│  │ - cosineSimilarity(emb1, emb2) → float         │   │
│  └─────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
                                               │
                                               ▼
┌─────────────────────────────────────────────────────────┐
│                VoiceprintStore.ets                      │
│  ┌─────────────────────────────────────────────────┐   │
│  │ users: Map<userId, embedding[]>                 │   │
│  │ - register(userId, embedding)                   │   │
│  │ - identify(embedding) → userId | null           │   │
│  │ - verify(userId, embedding) → boolean           │   │
│  └─────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

### 4.2 核心组件

1. **VoiceprintService.ets** - ArkTS 服务层
   - 管理录音和特征提取流程
   - 提供注册/识别/验证 API

2. **voiceprint_napi.cpp** - NAPI 桥接
   - 加载 sherpa-onnx 模型
   - 提取 192 维声纹特征向量
   - 计算余弦相似度

3. **VoiceprintStore.ets** - 声纹存储
   - 持久化存储用户声纹
   - 支持多声纹平均 (提高准确率)
   - 使用 Preferences/文件存储

### 4.3 工作流程

**注册流程**:
```
1. 用户说话 → AudioCapturer 采集 PCM
2. PCM → NAPI → sherpa-onnx 提取 embedding (192维向量)
3. 存储 {userId: embedding} 到 VoiceprintStore
4. 建议录制 3-5 段，取平均提高准确率
```

**识别流程**:
```
1. 用户说话 → AudioCapturer 采集 PCM
2. PCM → NAPI → sherpa-onnx 提取 embedding
3. 与所有已注册用户计算余弦相似度
4. 返回相似度最高且超过阈值 (0.5-0.7) 的用户
```

---

## 5. 实现计划

### Phase 1: 环境准备 (1-2 天)
- [ ] 下载 sherpa-onnx 源码
- [ ] 配置 HarmonyOS NDK 编译环境
- [ ] 编译 ONNX Runtime for arm64-v8a
- [ ] 下载 3D-Speaker 模型 (~25MB)

### Phase 2: NAPI 模块 (2-3 天)
- [ ] 创建 `voiceprint_napi.cpp`
- [ ] 实现 `extractEmbedding(pcmBuffer) → Float32Array`
- [ ] 实现 `computeSimilarity(emb1, emb2) → number`
- [ ] 更新 CMakeLists.txt 链接 sherpa-onnx

### Phase 3: ArkTS 服务层 (1-2 天)
- [ ] 创建 `VoiceprintService.ets`
- [ ] 创建 `VoiceprintStore.ets` (Preferences 存储)
- [ ] 实现 `register(userId, audioBuffer)`
- [ ] 实现 `identify(audioBuffer) → userId | null`

### Phase 4: UI 集成 (1-2 天)
- [ ] 设置页添加"声纹管理"入口
- [ ] 创建 VoiceprintPage.ets (注册/删除用户)
- [ ] ChatPage 集成 - 显示当前说话人

### Phase 5: 测试优化 (1-2 天)
- [ ] 多用户识别测试
- [ ] 阈值调优 (EER 最优点)
- [ ] 性能测试 (特征提取 <200ms)

**总预估**: 6-11 天

---

## 6. 技术细节

### 6.1 音频格式要求
- **采样率**: 16kHz (与现有 ASR 兼容)
- **位深**: 16bit signed int
- **声道**: mono
- **最小时长**: 1-2 秒
- **推荐时长**: 3-5 秒 (注册时)

### 6.2 声纹特征
- **维度**: 192 (3D-Speaker 默认)
- **归一化**: L2 归一化后存储
- **相似度**: 余弦相似度 (cosine similarity)
- **阈值**: 0.5-0.7 (需实测调优)

### 6.3 存储格式
```json
{
  "users": {
    "user1": {
      "name": "张三",
      "embeddings": [[0.12, -0.34, ...], [...], ...],
      "centroid": [0.11, -0.33, ...],
      "createdAt": 1708012345
    }
  }
}
```

---

## 7. 风险与挑战

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| ONNX Runtime 编译失败 | 阻塞 | 使用预编译库或简化版 ONNX |
| 模型文件过大 | APK 体积增加 | 模型量化或首次运行下载 |
| 识别准确率不足 | 用户体验差 | 多模型集成，增加注册样本 |
| 特征提取延迟高 | 卡顿 | 异步处理，使用 Worker |

---

## 8. 结论

**推荐方案**: sherpa-onnx 本地方案

**理由**:
1. **隐私优先**: 音频不上传，完全本地处理
2. **零成本**: 开源免费，无 API 费用
3. **离线可用**: 无网络也能工作
4. **高准确率**: 3D-Speaker 模型效果优秀
5. **可扩展**: 同一框架可支持 ASR、TTS、VAD 等

**下一步**: 确认后开始 Phase 1 环境准备。

---

*分析时间: 2026-02-16*
*分析人: Linda (AI Assistant)*
