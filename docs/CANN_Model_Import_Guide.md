# CANN 端侧模型导入指南

## 概述

端侧模型文件约 5.5GB，由于体积较大，不打包在应用内。用户需要手动将模型文件导入到设备。

---

## 方式一：USB 传输（推荐）

### 步骤 1：准备模型文件

从内部渠道获取以下模型文件：

**目标模型 (Target Model) - 约 5.4GB**
```
chs_7b_target_model/
├── SubGraph_0.weight              (2.6GB)
├── chs_7b_target_model.json
├── chs_7b_target_model.omc
├── chs_7b_target_model.omc.loraconf
├── chs_7b_target_model.omc.loradata
├── chs_7b_target_model.omc.quantpara
├── chs_7b_32_1536.embedding_dequant_scale
├── chs_7b_32_1536.embedding_weights  (450MB)
└── tokenizer.model
```

**Draft 模型 (Draft Model) - 约 140MB**
```
chs_7b_draft_model/
├── SubGraph_0.weight              (50MB)
├── chs_7b_draft_model.json
├── chs_7b_draft_model.omc
├── chs_7b_draft_model.omc.loraconf
├── chs_7b_draft_model.omc.loradata
├── chs_7b_draft_model.omc.quantpara
└── tokenizer.model
```

### 步骤 2：连接设备

1. 使用 USB 线连接设备和电脑
2. 在设备上选择"文件传输"模式（MTP）
3. 在电脑上打开"此电脑"，找到设备

### 步骤 3：复制模型文件

**Windows 路径**：
```
此电脑\设备名\内部存储\Data\com.hongjieliu.clawdbot\files\
```

**或**：
```
此电脑\设备名\内部存储\Android\data\com.hongjieliu.clawdbot\files\
```

创建以下目录结构：
```
files/
├── chs_7b_target_model/
│   ├── SubGraph_0.weight
│   ├── chs_7b_target_model.json
│   ├── chs_7b_target_model.omc
│   ├── ...
└── chs_7b_draft_model/
    ├── SubGraph_0.weight
    ├── chs_7b_draft_model.json
    ├── ...
```

### 步骤 4：验证

1. 打开 ClawdBot 应用
2. 进入设置页面
3. 检查是否出现"CANN Local"选项
4. 选择"CANN Local"作为 AI 提供者
5. 发送测试消息验证功能

---

## 方式二：应用内导入

### 步骤 1：复制模型到设备存储

将模型文件复制到设备的任意可访问目录，例如：
- 内部存储/Download/chs_7b_target_model/
- 内部存储/Download/chs_7b_draft_model/

### 步骤 2：使用应用导入

1. 打开 ClawdBot 应用
2. 进入设置 → AI 模型
3. 点击"导入模型"按钮
4. 选择模型目录
5. 等待导入完成

---

## 常见问题

### Q: 找不到应用目录？

A: 确保应用已启动过一次。HarmonyOS 应用目录在首次启动后才会创建。

### Q: 复制速度很慢？

A: USB 2.0 传输 5.5GB 约需 15-20 分钟。建议使用 USB 3.0 接口。

### Q: 提示"模型文件不存在"？

A: 检查目录名称是否正确：
- 目标模型目录名：`chs_7b_target_model`
- Draft 模型目录名：`chs_7b_draft_model`

### Q: 应用崩溃或闪退？

A: 可能原因：
1. 模型文件损坏 → 重新复制
2. 设备内存不足 → 关闭其他应用
3. 模型文件不完整 → 检查文件大小

---

## 模型文件校验

### 目标模型主要文件大小参考

| 文件名 | 大小 |
|--------|------|
| SubGraph_0.weight | ~2.6 GB |
| chs_7b_32_1536.embedding_weights | ~450 MB |
| chs_7b_target_model.omc | ~1.5 GB |

### Draft 模型主要文件大小参考

| 文件名 | 大小 |
|--------|------|
| SubGraph_0.weight | ~50 MB |
| chs_7b_draft_model.omc | ~50 MB |

---

## 技术细节

### 应用沙盒路径

```
/data/app/el2/100/base/com.hongjieliu.clawdbot/haps/entry/files/
```

### 模型初始化流程

1. 应用启动时检查 `isCANNAvailable()`
2. 如果 so 文件存在，尝试加载模型
3. 模型路径从 `context.filesDir` 获取
4. 加载成功后显示"CANN Local"选项

---

## 支持

如有问题，请联系内部技术支持团队。
