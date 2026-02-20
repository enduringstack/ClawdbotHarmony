/**
 * ContextSettingsPage — 情景智能管理页面（最小化版本排查闪退）
 */
import { router } from '@kit.ArkUI';

@Entry
@Component
struct ContextSettingsPage {
  @State status: string = '页面已加载';

  aboutToAppear(): void {
    this.status = '情景智能设置页面 - 正常运行';
  }

  build() {
    Column() {
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

      Column() {
        Text(this.status)
          .fontSize(16)
          .fontColor('#333333')
          .padding(20)

        Text('如果你能看到这个页面，说明基础路由正常。')
          .fontSize(14)
          .fontColor('#999999')
          .padding({ left: 20, right: 20 })
      }
      .width('100%')
      .layoutWeight(1)
      .backgroundColor('#F2F2F7')
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .height('100%')
  }
}
