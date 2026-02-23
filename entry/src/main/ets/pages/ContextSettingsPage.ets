/**
 * ContextSettingsPage — 情景智能管理页面
 * 功能：地理围栏管理 / 规则引擎状态 / MAB 统计
 */
import { router, promptAction } from '@kit.ArkUI';
import { LogService } from '../common/LogService';
import { I18n } from '../common/I18n';
import { ContextAwarenessService } from '../service/context/ContextAwarenessService';
import { ContextEngineService } from '../service/context/ContextEngine';
import { FeedbackService } from '../service/context/FeedbackService';
import { Geofence, GeofenceCategory, FeedbackStats, FeedbackRuleStat } from '../service/context/ContextModels';
import { LocationDiscoveryService, GeofenceSuggestion } from '../service/context/LocationDiscoveryService';
import { LearnedSignalsSummary } from '../service/context/LocationFusionService';
import { GeofenceSuggestionCard } from '../components/GeofenceSuggestionCard';
import { TrayStatus } from '../service/context/DataTray';

@Entry
@Component
struct ContextSettingsPage {
  private log: LogService = LogService.getInstance();

  @State geofenceNames: string[] = [];
  @State geofenceDetails: string[] = [];
  @State geofenceIds: string[] = [];
  @State ruleCount: number = 0;
  @State mabStats: string = '';
  @State engineStatus: string = '';
  @State suggestions: GeofenceSuggestion[] = [];
  @State discoveryStats: string = '';
  @State showAddDialog: boolean = false;
  @State newName: string = '';
  @State newLat: string = '';
  @State newLon: string = '';
  @State newRadius: string = '100';
  @State selectedCat: number = 6;

  // 反馈统计
  @State fbTotal: number = 0;
  @State fbPositive: number = 0;
  @State fbNegative: number = 0;
  @State fbRatioText: string = '--';
  @State fbTopRuleNames: string[] = [];
  @State fbTopRuleScores: string[] = [];

  // 积极探索模式
  @State exploreMode: boolean = false;
  @State exploreFpCount: number = 0;
  // 已学习的位置信号
  @State learnedSignals: LearnedSignalsSummary[] = [];
  // 数据托盘 — 物理世界
  @State physKeys: string[] = [];
  @State physLabels: string[] = [];
  @State physValues: string[] = [];
  @State physAges: string[] = [];
  @State physIndicators: string[] = [];
  @State physQualities: string[] = [];
  // 数据托盘 — 数字世界
  @State digiKeys: string[] = [];
  @State digiLabels: string[] = [];
  @State digiValues: string[] = [];
  @State digiAges: string[] = [];
  @State digiIndicators: string[] = [];
  @State digiQualities: string[] = [];
  private trayTimer: number = -1;
  // 当前状态概览
  @State statusTime: string = '';
  @State statusLocation: string = '';
  @State statusMotion: string = '';
  @State statusBattery: string = '';
  @State statusWifi: string = '';

  // key → 中文标签映射
  private static readonly KEY_LABELS: Record<string, string> = {
    // ---- 物理世界（传感器 + 环境） ----
    'hour': '小时',
    'timeOfDay': '时段',
    'dayOfWeek': '星期',
    'isWeekend': '周末',
    'batteryLevel': '电量',
    'isCharging': '充电中',
    'networkType': '网络类型',
    'wifiSsid': 'WiFi名称',
    'wifiLost': 'WiFi丢失',
    'wifiLostCategory': 'WiFi丢失分类',
    'wifiLostWork': '离开公司WiFi',
    'latitude': '纬度',
    'longitude': '经度',
    'geofence': '围栏',
    'stepCount': '步数(累计)',
    'step_count_today': '今日步数',
    'motionState': '运动状态',
    'isPickup': '拿起手机',
    'gpsSpeed': 'GPS速度',
    'locationAccuracy': '定位精度(m)',
    'cellId': '基站ID',
    // 蓝牙
    'bt_enabled': '蓝牙开启',
    'bt_connected_count': '蓝牙连接数',
    'bt_audio_connected': '蓝牙音频',
    'bt_device_names': '蓝牙设备',
    // 穿戴设备
    'heart_rate': '心率',
    'heart_rate_status': '心率状态',
    'heart_rate_age_sec': '心率数据龄(秒)',
    'wearing_state': '佩戴状态',
    // 音频环境
    'audio_scene': '音频场景',
    'audio_device': '音频设备',
    'audio_inCall': '通话中',
    'audio_ringing': '响铃中',
    'audio_headphones': '耳机连接',
    'noise_level': '噪音等级',
    'sound_scene': '声音场景',
    'has_voice': '检测到人声',
    'volume_db': '音量(dB)',
    // 姿态
    'phone_posture': '手机姿态',
    'ambient_brightness': '环境亮度(lux)',
    'proximity': '近距离感应',
    // ---- 数字世界（应用 / 信息） ----
    // 日历
    'cal_eventCount': '日历事件数',
    'cal_hasUpcoming': '有待办事件',
    'cal_nextTitle': '下个日程',
    'cal_nextMinutes': '下个日程(分钟)',
    'cal_nextLocation': '日程地点',
    'cal_inMeeting': '会议中',
    'cal_currentTitle': '当前会议',
    'cal_todayCount': '今日日程数',
    // 应用使用
    'app_isForeground': '应用在前台',
    'app_sessionMinutes': '本次使用(分钟)',
    'app_sessionsToday': '今日使用次数',
    'app_canReadOthers': '可读取其他应用',
    // 前台应用
    'foreground_app': '前台应用',
    'app_category': '应用类别',
    'app_usage_min': '应用使用(分钟)',
    // 通知
    'notif_enabled': '通知已开启',
    'notif_selfCount': '本应用通知数',
    'notif_canReadOthers': '可读取其他通知',
    'notif_lastSentMinutes': '上次通知(分钟)',
  };

  private catIds: string[] = ['home', 'work', 'transit', 'shopping', 'restaurant', 'gym', 'custom'];
  @State catLabels: string[] = ['🏠 家', '🏢 公司', '🚇 交通', '🛒 购物', '🍜 餐饮', '💪 健身', '📍 自定义'];

  aboutToAppear(): void {
    this.log.info('CtxSettings', 'Page opened');
    // 用 I18n 初始化分类标签
    let labels: string[] = [];
    for (let i = 0; i < this.catIds.length; i++) {
      labels.push(this.getCatIcon(this.catIds[i]) + ' ' + I18n.t('place.category.' + this.catIds[i]));
    }
    this.catLabels = labels;
    this.refresh();
    this.refreshTrayStatus();
    // Auto-refresh tray every 5 seconds
    this.trayTimer = setInterval(() => {
      this.refreshTrayStatus();
    }, 5000);
  }

  aboutToDisappear(): void {
    if (this.trayTimer !== -1) {
      clearInterval(this.trayTimer);
      this.trayTimer = -1;
    }
  }

  private getCatLabel(cat: string): string {
    let icon = this.getCatIcon(cat);
    let label = I18n.t('place.category.' + cat);
    return icon + ' ' + label;
  }

  private getCatIcon(cat: string): string {
    if (cat === 'home') return '🏠';
    if (cat === 'work') return '🏢';
    if (cat === 'transit') return '🚇';
    if (cat === 'gym') return '💪';
    if (cat === 'restaurant') return '🍜';
    if (cat === 'shopping') return '🛒';
    return '📍';
  }

  private refresh(): void {
    try {
      let cas = ContextAwarenessService.getInstance();
      let gfs = cas.getAllGeofences();
      let names: string[] = [];
      let details: string[] = [];
      let ids: string[] = [];
      for (let i = 0; i < gfs.length; i++) {
        let gf = gfs[i];
        names.push(this.getCatLabel(gf.category) + ' ' + gf.name);
        details.push(gf.latitude.toFixed(4) + ', ' + gf.longitude.toFixed(4) + '  r=' + gf.radiusMeters.toString() + 'm');
        ids.push(gf.id);
      }
      this.geofenceNames = names;
      this.geofenceDetails = details;
      this.geofenceIds = ids;
      this.engineStatus = cas.getStatus();
      this.exploreMode = cas.isExploreMode();
      this.learnedSignals = cas.getLearnedSignalsSummaries();
      this.suggestions = cas.getLocationSuggestions();
      this.suggestions = cas.getFilteredSuggestions();
      let stats = cas.getLocationDiscoveryStats();
      this.discoveryStats = `历史点: ${stats.historyCount} | 聚类: ${stats.clusterCount} | 上次发现: ${stats.lastDiscovery}`;
    } catch (err) {
      this.log.warn('CtxSettings', 'refresh cas: ' + (err as Error).message);
      this.engineStatus = '情景智能未初始化';
      this.discoveryStats = '';
      this.suggestions = [];
    }
    try {
      this.ruleCount = ContextEngineService.getInstance().getRuleCount();
    } catch (err) {
      this.ruleCount = 0;
    }
    this.refreshFeedbackStats();
  }

  private refreshFeedbackStats(): void {
    try {
      // Use FeedbackService directly to get latest stats (including A2UI button feedback)
      let stats: FeedbackStats = FeedbackService.getInstance().getStats();
      this.fbTotal = stats.totalCount;
      this.fbPositive = stats.positiveCount;
      this.fbNegative = stats.negativeCount;
      if (stats.positiveCount + stats.negativeCount > 0) {
        this.fbRatioText = Math.round(stats.positiveRatio * 100).toString() + '%';
      } else {
        this.fbRatioText = '--';
      }
      let names: string[] = [];
      let scores: string[] = [];
      for (let i = 0; i < stats.topRules.length; i++) {
        let tr: FeedbackRuleStat = stats.topRules[i];
        names.push(tr.ruleName);
        scores.push(tr.avgReward.toFixed(2) + ' (' + tr.feedbackCount.toString() + ' fb)');
      }
      this.fbTopRuleNames = names;
      this.fbTopRuleScores = scores;
    } catch (err) {
      this.fbTotal = 0;
      this.fbRatioText = '--';
    }
  }

  build() {
    Stack() {
      Column() {
        // Header
        Row() {
          Text('←')
            .fontSize(22)
            .fontColor('#1A1A1A')
            .padding(8)
            .onClick(() => { router.back(); })
          Text('情景智能设置')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1A1A1A')
            .layoutWeight(1)
        }
        .width('100%')
        .height(48)
        .padding({ left: 8, right: 16 })
        .backgroundColor(Color.White)

        Scroll() {
          Column({ space: 16 }) {
            // ===== 当前状态概览 =====
            Column({ space: 6 }) {
              Text('当前状态')
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor(Color.White)
                .margin({ bottom: 4 })
              Row({ space: 12 }) {
                Text(this.statusTime)
                  .fontSize(13)
                  .fontColor('#E0E0E0')
                Text(this.statusMotion)
                  .fontSize(13)
                  .fontColor('#E0E0E0')
                Text(this.statusBattery)
                  .fontSize(13)
                  .fontColor('#E0E0E0')
              }
              .width('100%')
              if (this.statusLocation.length > 0) {
                Text(this.statusLocation)
                  .fontSize(13)
                  .fontColor('#E0E0E0')
                  .width('100%')
                  .margin({ top: 2 })
              }
              if (this.statusWifi.length > 0) {
                Text(this.statusWifi)
                  .fontSize(13)
                  .fontColor('#E0E0E0')
                  .width('100%')
              }
            }
            .width('100%')
            .padding(16)
            .linearGradient({
              direction: GradientDirection.Right,
              colors: [['#2196F3', 0.0], ['#1976D2', 1.0]]
            })
            .borderRadius(12)

            // ===== 引擎状态 =====
            Column() {
              Text('引擎状态')
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor('#1A1A1A')
                .margin({ bottom: 8 })
              Text(this.engineStatus)
                .fontSize(13)
                .fontColor('#666666')
                .width('100%')
              Text('C++ 规则数: ' + this.ruleCount.toString())
                .fontSize(13)
                .fontColor('#666666')
                .margin({ top: 4 })
              Text('管理规则 \u2192')
                .fontSize(14)
                .fontColor('#007AFF')
                .margin({ top: 10 })
                .onClick(() => {
                  router.pushUrl({ url: 'pages/RuleManagementPage' });
                })
            }
            .width('100%')
            .padding(16)
            .backgroundColor(Color.White)
            .borderRadius(12)

            // ===== 积极探索模式 =====
            Column() {
              Row() {
                Column() {
                  Text(I18n.t('context.explore.title'))
                    .fontSize(15)
                    .fontWeight(FontWeight.Medium)
                    .fontColor('#1A1A1A')
                  Text(I18n.t('context.explore.desc'))
                    .fontSize(12)
                    .fontColor('#999999')
                    .margin({ top: 2 })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)

                Toggle({ type: ToggleType.Switch, isOn: this.exploreMode })
                  .selectedColor('#007AFF')
                  .onChange((isOn: boolean) => {
                    this.exploreMode = isOn;
                    ContextAwarenessService.getInstance().setExploreMode(isOn);
                  })
              }
              .width('100%')
            }
            .width('100%')
            .padding(16)
            .backgroundColor(Color.White)
            .borderRadius(12)

            // ===== 数据托盘 =====
            Column() {
              Row() {
                Text('\u{1F4E1} 数据托盘 (' + (this.physKeys.length + this.digiKeys.length).toString() + ')')
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#1A1A1A')
                  .layoutWeight(1)
                Text('刷新')
                  .fontSize(14)
                  .fontColor('#007AFF')
                  .onClick(() => { this.refreshTrayStatus(); })
              }
              .width('100%')
              .margin({ bottom: 4 })

              Text('每 5 秒自动刷新')
                .fontSize(11)
                .fontColor('#BBBBBB')
                .width('100%')
                .margin({ bottom: 8 })

              if (this.physKeys.length === 0 && this.digiKeys.length === 0) {
                Text('托盘为空（传感器未开始写入）')
                  .fontSize(13)
                  .fontColor('#999999')
                  .width('100%')
                  .textAlign(TextAlign.Center)
                  .padding(16)
              } else {
                // ── 物理世界 ──
                Text('\u{1F30D} 物理世界 (' + this.physKeys.length.toString() + ')')
                  .fontSize(13)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#2E7D32')
                  .width('100%')
                  .margin({ bottom: 4, top: 4 })

                Row() {
                  Text('名称').fontSize(11).fontColor('#999999').fontWeight(FontWeight.Medium).width(90)
                  Text('数值').fontSize(11).fontColor('#999999').fontWeight(FontWeight.Medium).layoutWeight(1)
                  Text('龄').fontSize(11).fontColor('#999999').fontWeight(FontWeight.Medium).width(40)
                  Text('质').fontSize(11).fontColor('#999999').fontWeight(FontWeight.Medium).width(32)
                  Text('').width(18)
                }.width('100%').padding({ bottom: 2 })

                ForEach(this.physKeys, (key: string, idx: number) => {
                  Row() {
                    Text(idx < this.physLabels.length ? this.physLabels[idx] : key)
                      .fontSize(12).fontColor('#1A1A1A').width(90).maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(idx < this.physValues.length ? this.physValues[idx] : '')
                      .fontSize(12).fontColor('#666666').layoutWeight(1).maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(idx < this.physAges.length ? this.physAges[idx] : '')
                      .fontSize(11).fontColor('#999999').width(40)
                    Text(idx < this.physQualities.length ? this.physQualities[idx] : '')
                      .fontSize(11).fontColor('#999999').width(32)
                    Text(idx < this.physIndicators.length ? this.physIndicators[idx] : '')
                      .fontSize(12).width(18)
                  }.width('100%').padding({ top: 2, bottom: 2 })
                }, (key: string, idx: number) => 'p_' + key + '_' + idx.toString())

                // ── 数字世界 ──
                Text('\u{1F4F1} 数字世界 (' + this.digiKeys.length.toString() + ')')
                  .fontSize(13)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#1565C0')
                  .width('100%')
                  .margin({ bottom: 4, top: 12 })

                if (this.digiKeys.length === 0) {
                  Text('暂无插件数据')
                    .fontSize(12).fontColor('#999999').width('100%')
                    .textAlign(TextAlign.Center).padding(8)
                } else {
                  Row() {
                    Text('名称').fontSize(11).fontColor('#999999').fontWeight(FontWeight.Medium).width(90)
                    Text('数值').fontSize(11).fontColor('#999999').fontWeight(FontWeight.Medium).layoutWeight(1)
                    Text('龄').fontSize(11).fontColor('#999999').fontWeight(FontWeight.Medium).width(40)
                    Text('质').fontSize(11).fontColor('#999999').fontWeight(FontWeight.Medium).width(32)
                    Text('').width(18)
                  }.width('100%').padding({ bottom: 2 })

                  ForEach(this.digiKeys, (key: string, idx: number) => {
                    Row() {
                      Text(idx < this.digiLabels.length ? this.digiLabels[idx] : key)
                        .fontSize(12).fontColor('#1A1A1A').width(90).maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                      Text(idx < this.digiValues.length ? this.digiValues[idx] : '')
                        .fontSize(12).fontColor('#666666').layoutWeight(1).maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                      Text(idx < this.digiAges.length ? this.digiAges[idx] : '')
                        .fontSize(11).fontColor('#999999').width(40)
                      Text(idx < this.digiQualities.length ? this.digiQualities[idx] : '')
                        .fontSize(11).fontColor('#999999').width(32)
                      Text(idx < this.digiIndicators.length ? this.digiIndicators[idx] : '')
                        .fontSize(12).width(18)
                    }.width('100%').padding({ top: 2, bottom: 2 })
                  }, (key: string, idx: number) => 'd_' + key + '_' + idx.toString())
                }
              }
            }
            .width('100%')
            .padding(16)
            .backgroundColor(Color.White)
            .borderRadius(12)

            // ===== 地理围栏 =====
            Column() {
              Row() {
                Text('地理围栏 (' + this.geofenceNames.length.toString() + ')')
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#1A1A1A')
                  .layoutWeight(1)
                Text('＋ 添加')
                  .fontSize(14)
                  .fontColor('#007AFF')
                  .onClick(() => { this.showAddDialog = true; })
              }
              .width('100%')
              .margin({ bottom: 12 })

              if (this.geofenceNames.length === 0) {
                Text('暂无围栏，点击右上角添加')
                  .fontSize(14)
                  .fontColor('#999999')
                  .width('100%')
                  .textAlign(TextAlign.Center)
                  .padding(20)
              } else {
                ForEach(this.geofenceIds, (gfId: string, index: number) => {
                  Column() {
                    Row() {
                      Column({ space: 2 }) {
                        Text(this.geofenceNames[index])
                          .fontSize(14)
                          .fontColor('#1A1A1A')
                        Text(this.geofenceDetails[index])
                          .fontSize(11)
                          .fontColor('#999999')
                      }
                      .layoutWeight(1)
                      .alignItems(HorizontalAlign.Start)

                      Text('删除')
                        .fontSize(13)
                        .fontColor('#FF3B30')
                        .padding(4)
                        .onClick(() => { this.deleteGeofence(gfId); })
                    }
                    .width('100%')
                    .padding({ top: 8, bottom: 8 })
                    Divider().color('#F0F0F0')
                  }
                }, (gfId: string) => gfId)
              }
            }
            .width('100%')
            .padding(16)
            .backgroundColor(Color.White)
            .borderRadius(12)

            // ===== 已学习的位置信号 =====
            Column() {
              Row() {
                Text('位置信号学习')
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#1A1A1A')
                  .layoutWeight(1)
                Text('清除全部')
                  .fontSize(13)
                  .fontColor('#FF3B30')
                  .onClick(() => { this.clearAllSignals(); })
              }
              .width('100%')
              .margin({ bottom: 8 })

              Text('GPS 高精度时自动学习 WiFi/蓝牙信号，用于室内定位增强')
                .fontSize(12)
                .fontColor('#999999')
                .width('100%')
                .margin({ bottom: 8 })

              if (this.learnedSignals.length === 0) {
                Text('暂无已学习信号，进入围栏区域后会自动学习')
                  .fontSize(13)
                  .fontColor('#999999')
                  .width('100%')
                  .textAlign(TextAlign.Center)
                  .padding(16)
              } else {
                ForEach(this.learnedSignals, (sig: LearnedSignalsSummary) => {
                  Column() {
                    Row() {
                      Column({ space: 2 }) {
                        Text(sig.geofenceName)
                          .fontSize(14)
                          .fontWeight(FontWeight.Medium)
                          .fontColor('#1A1A1A')
                        if (sig.wifiSsids.length > 0) {
                          Text('WiFi: ' + sig.wifiSsids.join(', '))
                            .fontSize(12)
                            .fontColor('#007AFF')
                        }
                        if (sig.btDevices.length > 0) {
                          Text('BT: ' + sig.btDevices.join(', '))
                            .fontSize(12)
                            .fontColor('#5856D6')
                        }
                        Text('观测 ' + sig.totalObservations.toString() + ' 次')
                          .fontSize(11)
                          .fontColor('#999999')
                      }
                      .layoutWeight(1)
                      .alignItems(HorizontalAlign.Start)

                      Text('清除')
                        .fontSize(13)
                        .fontColor('#FF3B30')
                        .padding(4)
                        .onClick(() => { this.clearSignalsForGeofence(sig.geofenceId); })
                    }
                    .width('100%')
                    .padding({ top: 8, bottom: 8 })
                    Divider().color('#F0F0F0')
                  }
                }, (sig: LearnedSignalsSummary) => sig.geofenceId)
              }
            }
            .width('100%')
            .padding(16)
            .backgroundColor(Color.White)
            .borderRadius(12)

            // ===== 反馈统计 =====
            Column() {
              Row() {
                Text('反馈统计')
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#1A1A1A')
                  .layoutWeight(1)
                Text('刷新')
                  .fontSize(14)
                  .fontColor('#007AFF')
                  .onClick(() => {
                    this.refreshFeedbackStats();
                    try { promptAction.showToast({ message: '反馈统计已刷新', duration: 1500 }); } catch {}
                  })
              }
              .width('100%')
              .margin({ bottom: 12 })

              // 数字统计行
              Row() {
                Column() {
                  Text(this.fbTotal.toString())
                    .fontSize(22)
                    .fontWeight(FontWeight.Bold)
                    .fontColor('#1A1A1A')
                  Text('总反馈')
                    .fontSize(11)
                    .fontColor('#999999')
                    .margin({ top: 2 })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Center)

                Column() {
                  Text(this.fbRatioText)
                    .fontSize(22)
                    .fontWeight(FontWeight.Bold)
                    .fontColor('#4CAF50')
                  Text('好评率')
                    .fontSize(11)
                    .fontColor('#999999')
                    .margin({ top: 2 })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Center)

                Column() {
                  Text(this.fbPositive.toString() + ' / ' + this.fbNegative.toString())
                    .fontSize(16)
                    .fontWeight(FontWeight.Medium)
                    .fontColor('#1A1A1A')
                  Text('\uD83D\uDC4D / \uD83D\uDC4E')
                    .fontSize(11)
                    .fontColor('#999999')
                    .margin({ top: 2 })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Center)
              }
              .width('100%')
              .padding({ top: 4, bottom: 8 })

              // Top 规则
              if (this.fbTopRuleNames.length > 0) {
                Divider().color('#F0F0F0').margin({ top: 8, bottom: 8 })
                Text('最有效规则 Top ' + this.fbTopRuleNames.length.toString())
                  .fontSize(13)
                  .fontWeight(FontWeight.Medium)
                  .fontColor('#666666')
                  .width('100%')
                  .margin({ bottom: 6 })
                ForEach(this.fbTopRuleNames, (name: string, idx: number) => {
                  Row() {
                    Text((idx + 1).toString() + '.')
                      .fontSize(13)
                      .fontColor('#007AFF')
                      .fontWeight(FontWeight.Bold)
                      .width(20)
                    Text(name)
                      .fontSize(13)
                      .fontColor('#1A1A1A')
                      .layoutWeight(1)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(idx < this.fbTopRuleScores.length ? this.fbTopRuleScores[idx] : '')
                      .fontSize(12)
                      .fontColor('#999999')
                  }
                  .width('100%')
                  .padding({ top: 3, bottom: 3 })
                }, (name: string, idx: number) => name + '_' + idx.toString())
              }
            }
            .width('100%')
            .padding(16)
            .backgroundColor(Color.White)
            .borderRadius(12)

            // ===== MAB =====
            Column() {
              Row() {
                Text('MAB 学习统计')
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#1A1A1A')
                  .layoutWeight(1)
                Text('刷新')
                  .fontSize(14)
                  .fontColor('#007AFF')
                  .onClick(() => {
                    try { this.mabStats = ContextEngineService.getInstance().getStats(); } catch (e) {}
                  })
              }
              .width('100%')
              .margin({ bottom: 8 })
              Text(this.mabStats.length > 2 ? this.mabStats : '暂无数据')
                .fontSize(12)
                .fontColor('#999999')
                .width('100%')
            }
            .width('100%')
            .padding(16)
            .backgroundColor(Color.White)
            .borderRadius(12)

            // ===== 位置自动发现 =====
            Column() {
              Row() {
                Text('📍 位置自动发现')
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#1A1A1A')
                  .layoutWeight(1)
                Text('立即发现')
                  .fontSize(14)
                  .fontColor('#007AFF')
                  .onClick(() => { this.triggerDiscovery(); })
              }
              .width('100%')
              .margin({ bottom: 8 })

              Text(this.discoveryStats.length > 0 ? this.discoveryStats : '未启动')
                .fontSize(12)
                .fontColor('#999999')
                .width('100%')
                .margin({ bottom: 8 })

              if (this.suggestions.length === 0) {
                Text('暂无发现，GPS 历史积累后会自动发现常去地点')
                  .fontSize(13)
                  .fontColor('#999999')
                  .width('100%')
                  .textAlign(TextAlign.Center)
                  .padding(16)
              } else {
                ForEach(this.suggestions, (s: GeofenceSuggestion) => {
                  GeofenceSuggestionCard({
                    suggestionId: s.id,
                    name: s.name,
                    category: s.category,
                    reason: s.reason,
                    confidence: s.confidence,
                    latitude: s.latitude,
                    longitude: s.longitude,
                    radiusMeters: s.radiusMeters,
                    onAccept: (id: string, name: string, category: string) => {
                      this.handleAcceptSuggestion(id, name, category);
                    },
                    onIgnore: (id: string) => {
                      this.handleIgnoreSuggestion(id);
                    },
                    onDefer: (id: string) => {
                      this.handleDeferSuggestion(id);
                    },
                  })
                    .margin({ bottom: 8 })
                }, (s: GeofenceSuggestion) => s.id)
              }
            }
            .width('100%')
            .padding(16)
            .backgroundColor(Color.White)
            .borderRadius(12)
          }
          .padding({ left: 16, right: 16, top: 12, bottom: 40 })
        }
        .layoutWeight(1)
        .backgroundColor('#F2F2F7')
      }
      .width('100%')
      .height('100%')

      // ===== 添加围栏弹窗 =====
      if (this.showAddDialog) {
        Column() {
          Column({ space: 12 }) {
            Text('添加地理围栏')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor('#1A1A1A')

            TextInput({ placeholder: '名称（如：家、公司）' })
              .onChange((val: string) => { this.newName = val; })
              .width('100%')
              .height(44)

            Row({ space: 8 }) {
              TextInput({ placeholder: '纬度' })
                .onChange((val: string) => { this.newLat = val; })
                .layoutWeight(1)
                .height(44)
              TextInput({ placeholder: '经度' })
                .onChange((val: string) => { this.newLon = val; })
                .layoutWeight(1)
                .height(44)
            }
            .width('100%')

            TextInput({ placeholder: '半径（米），默认100' })
              .onChange((val: string) => { this.newRadius = val; })
              .width('100%')
              .height(44)

            Text('类别')
              .fontSize(14)
              .fontColor('#666666')

            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.catLabels, (label: string) => {
                Text(label)
                  .fontSize(13)
                  .fontColor(this.selectedCat === this.catLabels.indexOf(label) ? Color.White : '#1A1A1A')
                  .backgroundColor(this.selectedCat === this.catLabels.indexOf(label) ? '#007AFF' : '#F0F0F0')
                  .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                  .borderRadius(16)
                  .margin(4)
                  .onClick(() => { this.selectedCat = this.catLabels.indexOf(label); })
              }, (label: string) => label)
            }
            .width('100%')

            Row({ space: 12 }) {
              Button('取消')
                .fontSize(14)
                .backgroundColor('#F0F0F0')
                .fontColor('#1A1A1A')
                .layoutWeight(1)
                .onClick(() => { this.showAddDialog = false; })
              Button('添加')
                .fontSize(14)
                .backgroundColor('#007AFF')
                .fontColor(Color.White)
                .layoutWeight(1)
                .onClick(() => { this.doAddGeofence(); })
            }
            .width('100%')
            .margin({ top: 8 })
          }
          .width('85%')
          .padding(20)
          .backgroundColor(Color.White)
          .borderRadius(16)
          .shadow({ radius: 20, color: '#40000000' })
          .onClick(() => {})
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#80000000')
        .justifyContent(FlexAlign.Center)
        .onClick(() => { this.showAddDialog = false; })
      }
    }
    .width('100%')
    .height('100%')
  }

  private doAddGeofence(): void {
    this.log.info('CtxSettings', 'Add: ' + this.newName + ' ' + this.newLat + ',' + this.newLon);
    if (this.newName.length === 0 || this.newLat.length === 0 || this.newLon.length === 0) return;
    let lat = parseFloat(this.newLat);
    let lon = parseFloat(this.newLon);
    let radius = this.newRadius.length > 0 ? parseFloat(this.newRadius) : 100;
    if (isNaN(lat) || isNaN(lon) || isNaN(radius)) return;
    try {
      let cas = ContextAwarenessService.getInstance();
      let gf: Geofence = {
        id: 'user_' + Date.now().toString(),
        name: this.newName,
        latitude: lat,
        longitude: lon,
        radiusMeters: radius,
        category: this.catIds[this.selectedCat] as GeofenceCategory,
      };
      cas.addGeofence(gf);
    } catch (err) {
      this.log.error('CtxSettings', 'Add error: ' + (err as Error).message);
    }
    this.showAddDialog = false;
    this.newName = '';
    this.newLat = '';
    this.newLon = '';
    this.newRadius = '100';
    this.selectedCat = 6;
    this.refresh();
  }

  private triggerDiscovery(): void {
    try {
      let cas = ContextAwarenessService.getInstance();
      let discovery = LocationDiscoveryService.getInstance();
      let stats = cas.getLocationDiscoveryStats();
      
      if (stats.historyCount < 10) {
        promptAction.showToast({
          message: I18n.t('context.discovery.notEnoughData'),
          duration: 2000
        });
        return;
      }
      
      promptAction.showToast({
        message: I18n.t('context.discovery.running'),
        duration: 1500
      });
      
      discovery.runDiscovery().then((suggestions: GeofenceSuggestion[]) => {
        this.suggestions = cas.getFilteredSuggestions();
        let newStats = cas.getLocationDiscoveryStats();
        this.discoveryStats = `历史点: ${newStats.historyCount} | 聚类: ${newStats.clusterCount} | 上次发现: ${newStats.lastDiscovery}`;
        
        if (this.suggestions.length > 0) {
          promptAction.showToast({
            message: I18n.t('context.discovery.found').replace('{0}', this.suggestions.length.toString()),
            duration: 2000
          });
        } else {
          promptAction.showToast({
            message: I18n.t('context.discovery.noResult'),
            duration: 2000
          });
        }
      });
    } catch (err) {
      this.log.error('CtxSettings', 'Discovery error: ' + (err as Error).message);
    }
  }

  private handleAcceptSuggestion(clusterId: string, name: string, category: string): void {
    try {
      let cas = ContextAwarenessService.getInstance();
      let raw = this.locationDiscovery().getSuggestions();
      let match: GeofenceSuggestion | undefined = undefined;
      for (let i = 0; i < raw.length; i++) {
        if (raw[i].id === clusterId) {
          match = raw[i];
          break;
        }
      }
      if (match) {
        cas.acceptSuggestion(match, name, category);
      }
      this.refresh();
    } catch (err) {
      this.log.error('CtxSettings', 'Accept suggestion error: ' + (err as Error).message);
    }
  }

  private handleIgnoreSuggestion(clusterId: string): void {
    try {
      ContextAwarenessService.getInstance().ignoreSuggestion(clusterId);
      this.refresh();
    } catch (err) {
      this.log.error('CtxSettings', 'Ignore suggestion error: ' + (err as Error).message);
    }
  }

  private handleDeferSuggestion(clusterId: string): void {
    try {
      ContextAwarenessService.getInstance().deferSuggestion(clusterId);
      this.refresh();
    } catch (err) {
      this.log.error('CtxSettings', 'Defer suggestion error: ' + (err as Error).message);
    }
  }

  private locationDiscovery(): LocationDiscoveryService {
    return LocationDiscoveryService.getInstance();
  }

  private refreshTrayStatus(): void {
    try {
      let cas = ContextAwarenessService.getInstance();
      let statuses: TrayStatus[] = cas.getTrayStatus();

      let pK: string[] = [], pL: string[] = [], pV: string[] = [], pA: string[] = [], pI: string[] = [], pQ: string[] = [];
      let dK: string[] = [], dL: string[] = [], dV: string[] = [], dA: string[] = [], dI: string[] = [], dQ: string[] = [];

      for (let i = 0; i < statuses.length; i++) {
        let s: TrayStatus = statuses[i];
        let label = ContextSettingsPage.KEY_LABELS[s.key] ?? s.key;
        let val = s.value.length > 20 ? s.value.substring(0, 20) + '...' : s.value;
        let age = this.formatAge(s.ageMs);
        let ind = s.fresh ? '\u{1F7E2}' : (s.effectiveQuality > 0 ? '\u{1F7E1}' : '\u{1F534}');
        let qual = (s.effectiveQuality * 100).toFixed(0) + '%';

        if (s.source === 'digital') {
          dK.push(s.key); dL.push(label); dV.push(val); dA.push(age); dI.push(ind); dQ.push(qual);
        } else {
          pK.push(s.key); pL.push(label); pV.push(val); pA.push(age); pI.push(ind); pQ.push(qual);
        }
      }
      this.physKeys = pK; this.physLabels = pL; this.physValues = pV;
      this.physAges = pA; this.physIndicators = pI; this.physQualities = pQ;
      this.digiKeys = dK; this.digiLabels = dL; this.digiValues = dV;
      this.digiAges = dA; this.digiIndicators = dI; this.digiQualities = dQ;

      // 更新顶部状态概览
      this.updateStatusHeader(statuses);
    } catch (err) {
      this.physKeys = [];
      this.digiKeys = [];
    }
  }

  private formatAge(ms: number): string {
    if (ms < 1000) return ms.toString() + 'ms';
    if (ms < 60000) return (ms / 1000).toFixed(0) + 's';
    if (ms < 3600000) return (ms / 60000).toFixed(1) + 'm';
    return (ms / 3600000).toFixed(1) + 'h';
  }

  private updateStatusHeader(statuses: TrayStatus[]): void {
    let trayMap: Record<string, string> = {};
    for (let i = 0; i < statuses.length; i++) {
      trayMap[statuses[i].key] = statuses[i].value;
    }
    // 时间
    let now = new Date();
    let h = now.getHours().toString().padStart(2, '0');
    let m = now.getMinutes().toString().padStart(2, '0');
    let tod = trayMap['timeOfDay'] ?? '';
    let todCn: Record<string, string> = { 'morning': '上午', 'afternoon': '下午', 'evening': '傍晚', 'night': '晚上' };
    this.statusTime = h + ':' + m + ' ' + (todCn[tod] ?? tod);

    // 运动状态
    let motion = trayMap['motionState'] ?? '';
    let motionCn: Record<string, string> = {
      'stationary': '静止', 'walking': '步行', 'running': '跑步',
      'cycling': '骑行', 'driving': '驾车', 'transit': '交通',
      'pickup': '拿起手机', 'putdown': '放下手机', 'unknown': '未知'
    };
    this.statusMotion = motionCn[motion] ?? motion;

    // 电量
    let bat = trayMap['batteryLevel'] ?? '';
    let charging = trayMap['isCharging'] === 'true' ? ' \u26A1' : '';
    this.statusBattery = bat.length > 0 ? bat + '%' + charging : '';

    // 位置：根据围栏 ID 查找实际围栏，显示分类标签 + 名称
    let geofenceId = trayMap['geofence'] ?? '';
    if (geofenceId.length > 0) {
      try {
        let gfs = ContextAwarenessService.getInstance().getAllGeofences();
        let matched = false;
        for (let i = 0; i < gfs.length; i++) {
          if (gfs[i].id === geofenceId) {
            let catLabel = I18n.t('place.category.' + gfs[i].category);
            this.statusLocation = this.getCatIcon(gfs[i].category) + ' ' + catLabel + ' ' + gfs[i].name;
            matched = true;
            break;
          }
        }
        if (!matched) {
          this.statusLocation = geofenceId;
        }
      } catch (_e) {
        this.statusLocation = geofenceId;
      }
    } else {
      this.statusLocation = '';
    }

    // WiFi
    let wifi = trayMap['wifiSsid'] ?? '';
    this.statusWifi = wifi.length > 0 ? 'WiFi: ' + wifi : '';
  }

  private deleteGeofence(id: string): void {
    try {
      ContextAwarenessService.getInstance().removeGeofence(id);
    } catch (err) {
      this.log.error('CtxSettings', 'Del error: ' + (err as Error).message);
    }
    this.refresh();
  }

  private clearSignalsForGeofence(geofenceId: string): void {
    try {
      ContextAwarenessService.getInstance().clearLearnedSignals(geofenceId).then(() => {
        this.refresh();
      });
    } catch (err) {
      this.log.error('CtxSettings', 'Clear signals error: ' + (err as Error).message);
    }
  }

  private clearAllSignals(): void {
    try {
      ContextAwarenessService.getInstance().clearAllLearnedSignals().then(() => {
        this.refresh();
      });
    } catch (err) {
      this.log.error('CtxSettings', 'Clear all signals error: ' + (err as Error).message);
    }
  }
}
