# ClawdBot 情景智能设计文档

## 架构概览

### C++ 核心逻辑 (高性能)
| 模块 | 文件 | 功能 |
|------|------|------|
| geo_utils | cpp/geo_utils/ | Haversine距离计算、围栏匹配 |
| dbscan_cluster | cpp/dbscan_cluster/ | DBSCAN聚类算法 |
| context_engine | cpp/context_engine/ | 规则引擎、LinUCB、MAB、决策树 |
| data_tray | cpp/data_tray/ | 传感器数据托盘、TTL管理 |
| location_fusion | cpp/location_fusion/ | 多源位置融合 |
| voiceprint | cpp/voiceprint/ | 声纹识别 |
| **motion_detector** | cpp/motion_detector/ | 运动状态检测 |
| **sampling_strategy** | cpp/motion_detector/ | 多级采集策略 |
| **place_learner** | cpp/place_learner/ | 地点信号学习 |
| **new_place_detector** | cpp/place_learner/ | 新地点检测 |
| **training_sync** | cpp/training_sync/ | 训练数据同步 |

### ArkTS 层 (UI + 平台API)
| 模块 | 功能 |
|------|------|
| ContextAwarenessService | 协调服务、调用平台API |
| GeofenceManager | 围栏管理、文件持久化 |
| DigitalWorldService | 数字世界插件管理 |
| 各Plugin | 传感器数据采集 |
| UI Pages | 用户界面 |

---
## 1. 多级采集策略 (功耗优化)

### 1.1 设计原则
- 根据运动状态动态调整传感器采集频率
- 静止时降低采集频率以节省功耗
- 运动时提高采集频率以保证精度
- **使用 CellID 代替 GPS 进行位置变化检测**

### 1.2 CellID 位置变化检测 (功耗优化)

**原理**：基站CellID变化说明用户可能移动了，CellID不变说明用户位置没变

**策略**：
```
1. 获取当前 CellID
2. 如果 CellID 与上次相同：
   - 不请求 GPS
   - 继续使用缓存的 GPS 位置
3. 如果 CellID 变化：
   - 可能移动了，请求一次 GPS
   - 更新缓存位置
```

**优势**：
- CellID 获取功耗极低（网络状态的一部分）
- 大幅减少 GPS 请求次数
- 在室内/静止场景下特别有效

**API**：`@ohos.telephony.radio` - `getSignalInformation()` 或监听网络状态变化

### 1.3 采集间隔配置

| 运动状态 | GPS间隔 | WiFi间隔 | 加速度计间隔 | 说明 |
|---------|---------|----------|-------------|------|
| stationary (静止) | 5分钟 | 5分钟 | 5秒 | 在家/办公室久坐 |
| walking (步行) | 30秒 | 2分钟 | 1秒 | 低速移动 |
| running (跑步) | 15秒 | 5分钟 | 500ms | 高频运动，不需要WiFi |
| driving (驾驶) | 5秒 | 关闭 | 2秒 | 高速移动，频繁更新GPS |
| unknown (未知) | 1分钟 | 2分钟 | 1秒 | 默认配置 |

### 1.3 运动状态检测
- **加速度传感器**：检测身体运动
- **GPS速度**：解决开车/高铁匀速问题
  - GPS速度 > 20m/s (72km/h) → 驾驶
  - GPS速度 > 5m/s (18km/h) → 驾驶/骑行
  - GPS速度 > 1.5m/s (5.4km/h) → 跑步/快走

### 1.4 拿起手机检测 (TODO)
**问题**：当前"拿起手机"会触发运动状态变化，导致不必要的GPS重采样

**解决方案**：
```
拿起手机特征：
- 加速度计：短暂脉冲 + 重力方向变化
- 陀螺仪：快速旋转
- 持续时间：< 3秒

运动特征：
- 加速度计：持续变化
- 步数增加
- GPS位移
- 持续时间：> 10秒
```

**实现要点**：
1. 区分"拿起看一眼" vs "开始移动"
2. 拿起手机不触发GPS频率调整
3. 只有真正运动才调整采集策略

---

## 2. 围栏特征学习

### 2.1 数据结构
```typescript
interface LearnedPlaceSignals {
  wifiSSIDs?: string[];            // 关联的WiFi SSID列表
  bluetoothDevices?: string[];     // 关联的蓝牙设备MAC/名称
  typicalTimes?: TimeRange[];      // 典型出现时间段
  lastSeen?: number;               // 最后一次学习时间戳
  visitCount?: number;             // 访问次数
}
```

### 2.2 学习触发
- 进入围栏时自动学习当前WiFi/蓝牙
- 首次学习到新特征时在聊天窗口提醒
- 数据持久化到 user_places.json

### 2.3 特征匹配
- WiFi连接时检查是否匹配已知围栏
- 即使GPS不精确，也能通过WiFi判断位置
- 支持多WiFi绑定同一围栏

---

## 3. App使用记录学习

### 3.1 权限
- `ohos.permission.LOOK_AT_SCREEN_DATA`

### 3.2 App分类
| 分类 | 示例App |
|------|---------|
| 社交 | 微信、QQ、WhatsApp、Telegram、Discord |
| 办公 | Email、WPS、Teams、Zoom、飞书、钉钉 |
| 娱乐 | 抖音、快手、B站、YouTube、Netflix |
| 导航 | 高德、百度地图、Google Maps |
| 购物 | 淘宝、京东、拼多多、Amazon |
| 资讯 | 今日头条、知乎、Twitter、Reddit |
| 健康 | 运动健康、Keep |
| 音乐 | 网易云、QQ音乐、Spotify |
| 阅读 | 微信读书、Kindle |
| 游戏 | 各种游戏 |

### 3.3 学习内容
- 当前前台App
- App使用时长
- 使用时段模式（用户习惯在什么时候用什么类型的App）
- 分类使用频率

### 3.4 推荐应用
- 根据用户习惯推荐相关App执行
- 例：用户习惯晚上刷抖音，推荐时可以提到

---

## 4. 静默模式增强

### 4.1 当前功能
- VAD语音检测
- 声纹识别说话人
- ASR转写
- AI摘要

### 4.2 待增强：关键信息提取
```typescript
interface ConversationKeyInfo {
  // 时间相关
  times: string[];           // "明天下午3点", "下周一"
  dates: string[];           // "3月15日", "这周末"
  
  // 地点相关
  locations: string[];       // "星巴克", "公司楼下"
  
  // 人物相关
  people: string[];          // "老王", "张总"
  
  // 事件相关
  events: string[];          // "开会", "吃饭", "看电影"
  
  // 计划相关
  plans: string[];           // "打算去买电脑", "准备出差"
  
  // 主题
  topics: string[];          // "讨论项目进度", "聊孩子教育"
}
```

### 4.3 待增强：情绪/心情检测
```typescript
interface EmotionAnalysis {
  mood: 'happy' | 'sad' | 'angry' | 'neutral' | 'excited' | 'tired';
  activity: 'talking' | 'singing' | 'arguing' | 'laughing' | 'whispering';
  energy: 'high' | 'medium' | 'low';
  stress: number;  // 0-100
}
```

**检测方法**：
- 语调分析（音高、语速、音量）
- 词汇情感分析
- 声音特征（笑声、叹气等）

### 4.4 唱歌检测
- 音高稳定性（唱歌 vs 说话）
- 节奏特征
- 旋律模式
- 背景音乐检测

---

## 5. 穿戴设备集成

### 5.1 问题
HarmonyOS `sensor.SensorId.HEART_RATE` 只能读取手机本身的传感器，**不能直接读取华为手表数据**。

### 5.2 解决方案
**方案A：使用健康数据API**
- 需要用户在华为健康App中开启数据共享
- 使用 `@ohos.healthDevice` 或 Health Kit

**方案B：华为健康数据同步**
- 华为健康App会将心率数据同步到系统
- 某些设备上 `sensor.SensorId.HEART_RATE` 可以获取同步后的数据
- 需要权限：`ohos.permission.READ_HEALTH_DATA`

### 5.3 待验证
- 检查 `sensor.on(SensorId.HEART_RATE)` 是否能获取手表同步数据
- 如果不能，需要研究 Health Kit API

---

## 6. 规则引擎与推荐

### 6.1 当前问题
- 规则定义了但匹配不到
- 可能是snapshot字段名与规则条件不匹配

### 6.2 规则条件字段
```json
{
  "timeOfDay": "morning|afternoon|evening|night",
  "isWeekend": "true|false",
  "motionState": "stationary|walking|running|driving",
  "geofence": "home|work|gym|...",
  "batteryLevel": "0-100",
  "isCharging": "true|false"
}
```

### 6.3 Snapshot生成
需要确保 `SensorDataTray.getSnapshot()` 返回的字段与规则条件匹配：
- `timeOfDay` - 需要根据当前时间计算
- `isWeekend` - 需要根据星期几计算
- `motionState` - 从数据托盘获取
- `geofence` - 从围栏管理器获取

---

## 7. 数据托盘规范

### 7.1 字段命名规范
- 统一使用小驼峰命名：`wifiSsid`, `gpsSpeed`, `heartRate`
- 避免重复字段
- TTL根据数据特性设置

### 7.2 当前字段
| Key | TTL | 来源 | 说明 |
|-----|-----|------|------|
| latitude | 2min | GPS | 纬度 |
| longitude | 2min | GPS | 经度 |
| wifiSsid | 2min | WiFi | 当前连接的WiFi |
| motionState | 30s | 加速度计 | 运动状态 |
| gpsSpeed | 2min | GPS | GPS速度 |
| heartRate | 30s | 穿戴设备 | 心率 |
| stepCount | 5min | 计步器 | 步数 |

---

## 8. 待办事项

### 高优先级

#### 1. C++ 模块 NAPI 绑定
以下 C++ 模块已设计但未完成 NAPI 绑定：

| 模块 | 文件 | 功能 | 状态 |
|------|------|------|------|
| motion_detector | cpp/motion_detector/ | 运动状态检测 | ✅ 已完成 |
| sampling_strategy | cpp/motion_detector/ | 多级采集策略 | ✅ 已完成 |
| place_signal_learner | cpp/place_learner/ | 地点信号学习 (WiFi/蓝牙/CellID) | ✅ 已完成 |
| sleep_pattern | cpp/sleep_pattern/ | 睡眠时间学习 | ✅ 已完成 |
| feedback_learner | cpp/feedback_learner/ | 用户反馈学习 | ✅ 已完成 |
| training_sync | cpp/training_sync/ | 训练数据同步 | ✅ 已完成 |

#### 2. 穿戴设备数据获取 ⏳
- [x] 添加 READ_HEALTH_DATA 权限申请
- [ ] 验证心率传感器是否能获取手表数据
- [ ] 如果不能，研究 Health Kit API

#### 3. ~~规则匹配问题~~ ✅ 已修复
- [x] 围栏推荐已生效
- [x] 睡前提醒已触发
- 规则引擎正常工作

#### 4. 反馈学习系统集成 ⏳
- [ ] 在 A2UI 卡片添加反馈按钮（有用/不准/调整）
- [ ] 记录反馈上下文（时间、地点、WiFi、场景）
- [ ] 支持用户输入调整值（如希望的提醒时间）
- [ ] 基于反馈调整规则参数

**示例场景**：
```
睡前提醒在 21:00 触发
用户反馈"不准"，并提供调整值 "22:00"
系统记录：规则=bedtime, 原始=21:00, 调整=22:00
下次推荐时间调整为 22:00
```

---

### 中优先级

#### 5. CellID 获取 (低功耗位置变化检测) ❓
**问题**: HarmonyOS `radio.getSignalInformation()` 只返回 `signalType`/`signalLevel`，不提供 CellID

**备选方案**:
- 研究 `telephony.radio.getNetworkState()`
- 研究 `telephony.call` 相关 API
- 或者放弃 CellID，完全依赖 WiFi + 加速度计

#### 6. App 使用记录学习 ❌
**问题**: `ohos.permission.LOOK_AT_SCREEN_DATA` 在当前 SDK 不存在

**备选方案**:
- 使用 `ForegroundAppPlugin` 的前台 App 检测（受限）
- 记录当前 App 使用时间
- 学习用户在不同地点/时间的 App 使用习惯

#### 7. 静默模式增强 ⏳
- [ ] 关键信息提取
  - 时间: "明天下午3点", "下周一"
  - 地点: "星巴克", "公司楼下"
  - 人物: "老王", "张总"
  - 事件: "开会", "吃饭"
  - 计划: "打算去买电脑"
- [ ] 情绪/心情检测
  - 语调分析
  - 唱歌检测
  - 压力水平

#### 8. 拿起手机检测 ⏳
**问题**: 当前"拿起手机"会触发运动状态变化，导致不必要的 GPS 请求

**需要实现**:
```
拿起手机特征：
- 加速度计：短暂脉冲 + 重力方向变化
- 陀螺仪：快速旋转
- 持续时间：< 3秒

运动特征：
- 加速度计：持续变化
- 步数增加
- GPS 位移
- 持续时间：> 10秒
```

---

### 低优先级

#### 9. 设计文档完善
- [ ] 添加架构图
- [ ] 添加数据流图
- [ ] 添加 API 文档

#### 10. 单元测试
- [ ] C++ 模块单元测试
- [ ] 规则引擎测试
- [ ] 睡眠模式学习测试

---

## 9. 训练数据同步系统设计 (C++)

### 9.1 架构概览

```
┌─────────────────────────────────────────────────────────┐
│                    ArkTS 层 (薄封装)                      │
│  TrainingDataSync.ets                                   │
│  - 初始化配置 (endpoint, deviceId)                       │
│  - 调用 NAPI 接口                                        │
│  - HTTP 上传 (HarmonyOS 网络 API)                        │
└─────────────────────┬───────────────────────────────────┘
                      │ NAPI
┌─────────────────────┴───────────────────────────────────┐
│                    C++ 核心层                             │
│  training_sync.cpp                                      │
│  - 训练数据收集与缓冲                                     │
│  - 数据序列化 (JSON)                                     │
│  - 批量管理、TTL清理                                     │
│  - 统计信息                                              │
└─────────────────────────────────────────────────────────┘
```

### 9.2 C++ 数据结构

```cpp
// 训练数据类型
enum class TrainingDataType {
    RULE_MATCH,          // 规则匹配记录
    USER_FEEDBACK,       // 用户反馈
    STATE_TRANSITION,    // 状态转换
    GEOFENCE_FEATURE     // 围栏特征
};

// 训练记录
struct TrainingRecord {
    std::string id;
    TrainingDataType type;
    int64_t timestamp;
    std::map<std::string, std::string> stringData;
    std::map<std::string, double> numericData;
    std::map<std::string, bool> boolData;
    bool synced;
};

// 规则匹配数据
struct RuleMatchData {
    std::string ruleId;
    std::string action;
    double confidence;
    std::string timeOfDay;
    int hour;
    std::string motionState;
    std::string prevMotionState;
    std::string prevActivityState;
    int64_t activityDuration;
    std::string geofence;
    std::string wifiSsid;
    int batteryLevel;
    bool isCharging;
};

// 用户反馈数据
struct UserFeedbackData {
    std::string ruleId;
    std::string feedbackType;  // accept/reject/adjust/dismiss
    std::string originalValue;
    std::string adjustedValue;
    std::string timeOfDay;
    int hour;
    std::string motionState;
    std::string geofence;
};

// 状态转换数据
struct StateTransitionData {
    std::string prevState;
    std::string newState;
    int64_t duration;
    std::string timeOfDay;
    int hour;
    std::string geofence;
    std::string wifiSsid;
};

// 同步统计
struct SyncStats {
    int pendingCount;
    int syncedCount;
    int64_t lastSyncTime;
    int64_t totalBytes;
};
```

### 9.3 C++ 类设计

```cpp
class TrainingDataSync {
public:
    static TrainingDataSync& getInstance();
    
    // 初始化
    void init(const std::string& deviceId);
    
    // 记录数据
    void recordRuleMatch(const RuleMatchData& data);
    void recordFeedback(const UserFeedbackData& data);
    void recordStateTransition(const StateTransitionData& data);
    
    // 批量操作
    std::string exportPendingAsJson();  // 导出待同步数据为JSON
    void markAsSynced(const std::vector<std::string>& ids);
    void cleanupSynced();
    
    // 统计
    SyncStats getStats() const;
    
    // 持久化 (供 NAPI 调用)
    std::string serialize() const;
    void deserialize(const std::string& json);
    
private:
    std::string deviceId_;
    std::vector<TrainingRecord> records_;
    int64_t lastSyncTime_;
    
    static constexpr int MAX_RECORDS = 200;
    static constexpr int SYNC_INTERVAL_MS = 3600000;  // 1小时
    
    std::string generateId(const std::string& prefix);
    void pruneIfNeeded();
};
```

### 9.4 NAPI 接口设计

```typescript
// training_sync_napi.cpp 导出接口
interface TrainingSyncNapi {
    // 初始化
    init(deviceId: string): void;
    
    // 记录数据
    recordRuleMatch(data: {
        ruleId: string;
        action: string;
        confidence: number;
        timeOfDay: string;
        hour: number;
        motionState: string;
        prevMotionState: string;
        prevActivityState: string;
        activityDuration: number;
        geofence: string;
        wifiSsid: string;
        batteryLevel: number;
        isCharging: boolean;
    }): void;
    
    recordFeedback(data: {
        ruleId: string;
        feedbackType: string;
        originalValue: string;
        adjustedValue: string;
        timeOfDay: string;
        hour: number;
        motionState: string;
        geofence: string;
    }): void;
    
    recordStateTransition(data: {
        prevState: string;
        newState: string;
        duration: number;
        timeOfDay: string;
        hour: number;
        geofence: string;
        wifiSsid: string;
    }): void;
    
    // 导出与标记
    exportPending(): string;  // 返回JSON字符串
    markSynced(ids: string[]): void;
    
    // 持久化
    serialize(): string;
    deserialize(json: string): void;
    
    // 统计
    getStats(): { pending: number; synced: number; lastSync: number };
}
```

### 9.5 数据流程

```
1. 数据产生
   ContextAwarenessService → C++ TrainingDataSync.recordRuleMatch()
                           → C++ TrainingDataSync.recordFeedback()
                           → C++ TrainingDataSync.recordStateTransition()

2. 持久化 (每次记录后)
   C++ → serialize() → ArkTS → preferences.put()

3. 同步触发 (定时/手动)
   ArkTS → C++ exportPending() → JSON
   ArkTS → HTTP POST to server
   ArkTS → C++ markSynced(ids)
   ArkTS → C++ serialize() → preferences.put()

4. 启动恢复
   ArkTS → preferences.get() → C++ deserialize()
```

### 9.6 服务端接口

**服务端位置**: `server/training-server.js`

与 OpenClaw Gateway 运行在同一台机器上：
- Gateway 端口: 18789
- 训练数据服务端口: 18790

**API 接口**:

```
POST /training/upload
Content-Type: application/json

{
    "deviceId": "device_xxx",
    "timestamp": 1708123456789,
    "records": [
        {
            "id": "rm_xxx",
            "type": "rule_match",
            "timestamp": 1708123456000,
            "data": {
                "ruleId": "bedtime_reminder",
                "action": "suggestion",
                "confidence": 0.85,
                ...
            }
        }
    ]
}

Response:
{
    "success": true,
    "receivedCount": 10,
    "serverTime": 1708123457000,
    "file": "device_xxx_2026-02-22.jsonl"
}

GET /training/stats  - 查看数据统计
GET /health          - 健康检查
```

**启动服务**:
```bash
node server/training-server.js
```

**数据存储**:
- 目录: `server/training-data/`
- 格式: JSONL (每行一条记录)
- 文件名: `{deviceId}_{date}.jsonl`

### 9.7 隐私与安全

1. **数据脱敏**: 敏感字段 (wifiSsid, geofence名) 可配置是否上传
2. **本地优先**: 默认只存本地，用户授权后才开启同步
3. **HTTPS**: 上传使用加密通道
4. **数据保留**: 服务端数据聚合后删除原始记录

### 9.8 文件结构

```
entry/src/main/cpp/training_sync/
├── training_sync.cpp          # 核心实现
├── training_sync.h            # 头文件
├── training_sync_napi.cpp     # NAPI 绑定
└── CMakeLists.txt             # 构建配置
```

---

## 10. 反馈学习系统设计

### 9.1 数据结构
```cpp
struct FeedbackRecord {
    std::string id;
    FeedbackType type;           // USEFUL/INACCURATE/DISMISS/ADJUST
    FeedbackContext context;     // 反馈时的上下文
    AdjustmentValue adjustment;  // 用户调整值
    int64_t timestamp;
};

struct FeedbackContext {
    std::string ruleId;
    std::string ruleName;
    int64_t feedbackTime;
    int hour;
    int minute;
    std::string timeOfDay;
    bool isWeekend;
    double latitude;
    double longitude;
    std::string geofence;
    std::string wifiSsid;
    std::string motionState;
};

struct AdjustmentValue {
    std::string key;             // "hour", "minute"
    double originalValue;
    double adjustedValue;
    std::string unit;
};
```

### 9.2 学习规则偏好
```cpp
struct RulePreference {
    std::string ruleId;
    double preferredHour;        // 用户偏好的小时
    double preferredMinute;      // 用户偏好的分钟
    double hourAdjustment;       // 小时调整量
    double confidence;           // 置信度
    int usefulCount;             // 有用次数
    int inaccurateCount;         // 不准次数
    int adjustCount;             // 调整次数
};
```

### 9.3 使用场景
1. **睡前提醒调整**: 用户反馈 21:00 太早，调整为 22:00
2. **久坐提醒频率**: 用户反馈太频繁，降低提醒频率
3. **通勤时间**: 用户反馈通勤时间不准确，调整触发时间

### 9.4 UI 交互
```
┌─────────────────────────────────┐
│ 💡 情景智能推荐                  │
│ 夜深了，早点休息 🌙              │
│ 规则: 睡前提醒 | 置信度: 65%     │
├─────────────────────────────────┤
│ [✅ 有用] [❌ 不准] [⏰ 调整时间] │
└─────────────────────────────────┘

点击"调整时间"后：
┌─────────────────────────────────┐
│ 调整提醒时间                     │
│ 当前: 21:00                     │
│ 调整为: [ 22 ] : [ 00 ]         │
│         [确认] [取消]           │
└─────────────────────────────────┘
```
