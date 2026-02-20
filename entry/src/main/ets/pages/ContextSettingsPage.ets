/**
 * ContextSettingsPage — 情景智能管理页面
 * 功能：地理围栏管理 / 规则引擎状态 / MAB 统计
 */
import { router } from '@kit.ArkUI';
import { LogService } from '../common/LogService';
import { ContextAwarenessService } from '../service/context/ContextAwarenessService';
import { ContextEngineService } from '../service/context/ContextEngine';
import { Geofence, GeofenceCategory, FeedbackStats, FeedbackRuleStat } from '../service/context/ContextModels';

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

  private catIds: string[] = ['home', 'work', 'transit', 'shopping', 'restaurant', 'gym', 'custom'];
  private catLabels: string[] = ['🏠 家', '🏢 公司', '🚇 交通', '🛒 购物', '🍜 餐饮', '💪 健身', '📍 自定义'];

  aboutToAppear(): void {
    this.log.info('CtxSettings', 'Page opened');
    this.refresh();
  }

  private getCatLabel(cat: string): string {
    let idx = this.catIds.indexOf(cat);
    if (idx >= 0) return this.catLabels[idx];
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
    } catch (err) {
      this.log.warn('CtxSettings', 'refresh cas: ' + (err as Error).message);
      this.engineStatus = '情景智能未初始化';
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
      let cas = ContextAwarenessService.getInstance();
      let stats: FeedbackStats = cas.getFeedbackStats();
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
                  .onClick(() => { this.refreshFeedbackStats(); })
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

  private deleteGeofence(id: string): void {
    try {
      ContextAwarenessService.getInstance().removeGeofence(id);
    } catch (err) {
      this.log.error('CtxSettings', 'Del error: ' + (err as Error).message);
    }
    this.refresh();
  }
}
