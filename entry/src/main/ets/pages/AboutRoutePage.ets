// About page with system status
import { router } from '@kit.ArkUI';
import { I18n, t } from '../common/I18n';
import { NodeRuntime } from '../service/gateway/NodeRuntime';

@Entry
@Component
struct AboutRoutePage {
  @State lang: string = 'zh';
  @State memoryUsage: string = '-';
  @State activeSessions: number = 0;
  @State tokenUsage: string = '-';
  @State gatewayStatus: string = '-';
  private refreshTimer: number = -1;

  aboutToAppear(): void {
    this.refreshStatus();
    // Refresh every 3 seconds
    this.refreshTimer = setInterval(() => {
      this.refreshStatus();
    }, 3000);
  }

  aboutToDisappear(): void {
    if (this.refreshTimer >= 0) {
      clearInterval(this.refreshTimer);
      this.refreshTimer = -1;
    }
  }

  private refreshStatus(): void {
    // Gateway status
    let runtime = NodeRuntime.getInstance();
    if (runtime.isConnected) {
      this.gatewayStatus = t('chat.online');
      this.activeSessions = 1;
    } else {
      this.gatewayStatus = t('chat.offline');
      this.activeSessions = 0;
    }
  }

  @Builder
  InfoRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(14)
        .fontColor('#666666')
      Blank()
      Text(value)
        .fontSize(14)
        .fontColor('#333333')
    }
    .width('100%')
    .padding({ top: 12, bottom: 12 })
  }

  @Builder
  SectionTitle(title: string) {
    Text(title)
      .fontSize(12)
      .fontWeight(FontWeight.Medium)
      .fontColor('#999999')
      .letterSpacing(1)
      .padding({ left: 4, top: 20, bottom: 8 })
      .width('100%')
  }

  build() {
    Column() {
      // Header
      Row() {
        Text('←')
          .fontSize(24)
          .fontColor('#333333')
          .onClick(() => {
            router.back();
          })

        Text(t('settings.about'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#333333')
          .margin({ left: 16 })

        Blank()
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .backgroundColor('#FFFFFF')

      Scroll() {
        Column() {
          // ========== About Section ==========
          this.SectionTitle(t('settings.about'))
          Column() {
            this.InfoRow(t('settings.app'), 'ClawdBot')
            Divider().color('#F0F0F0')
            this.InfoRow(t('settings.version'), '2.18.15')
            Divider().color('#F0F0F0')
            this.InfoRow(t('settings.basedOn'), 'OpenClaw')
            Divider().color('#F0F0F0')
            this.InfoRow(t('settings.platform'), 'HarmonyOS NEXT')
          }
          .padding(16)
          .backgroundColor(Color.White)
          .borderRadius(12)

          // ========== System Status Section ==========
          this.SectionTitle(t('settings.systemStatus'))
          Column() {
            this.InfoRow(t('settings.gatewayStatus'), this.gatewayStatus)
            Divider().color('#F0F0F0')
            this.InfoRow(t('settings.activeSessions'), `${this.activeSessions}`)
            Divider().color('#F0F0F0')
            this.InfoRow(t('settings.memoryUsage'), this.memoryUsage)
            Divider().color('#F0F0F0')
            this.InfoRow(t('settings.tokenUsage'), this.tokenUsage)
          }
          .padding(16)
          .backgroundColor(Color.White)
          .borderRadius(12)

          // Footer
          Text('© 2026 OpenClaw')
            .fontSize(12)
            .fontColor('#CCCCCC')
            .margin({ top: 32, bottom: 32 })
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
      }
      .layoutWeight(1)
      .backgroundColor('#F5F5F5')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
  }
}
