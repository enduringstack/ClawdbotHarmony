/**
 * RecommendationFeedbackCard — 推荐卡片 + 反馈按钮
 *
 * 显示情景引擎推荐内容，底部右侧有 👍/👎 按钮。
 * 点击按钮后按钮隐藏并显示 "感谢反馈" toast。
 * 点击卡片主区域触发 onActionTap（隐式正反馈 +0.8）。
 * 支持滑动关闭（dismiss 反馈 -0.1 延迟 5min）。
 */

@Component
export struct RecommendationFeedbackCard {
  /** 规则 ID */
  @Prop ruleId: string = '';
  /** 推荐文本 / 原因 */
  @Prop reason: string = '';
  /** 动作类型标签 */
  @Prop actionLabel: string = '';
  /** 置信度 0-1 */
  @Prop confidence: number = 0;

  /** 回调 */
  onThumbsUp: (ruleId: string) => void = () => {};
  onThumbsDown: (ruleId: string) => void = () => {};
  onActionTap: (ruleId: string) => void = () => {};
  onDismiss: (ruleId: string) => void = () => {};

  /** 内部状态 */
  @State feedbackGiven: boolean = false;
  @State toastText: string = '';
  @State showToast: boolean = false;
  @State offsetX: number = 0;

  build() {
    Column() {
      // 主卡片
      Stack({ alignContent: Alignment.BottomEnd }) {
        // 卡片内容区 — 可点击执行推荐动作
        Column() {
          // 顶部：动作类型标签 + 置信度
          Row() {
            Text(this.actionIcon())
              .fontSize(14)
            Text(this.actionLabel.length > 0 ? this.actionLabel : this.defaultActionLabel())
              .fontSize(12)
              .fontColor('#007AFF')
              .fontWeight(FontWeight.Medium)
              .margin({ left: 4 })
            Blank()
            if (this.confidence > 0) {
              Text(Math.round(this.confidence * 100).toString() + '%')
                .fontSize(11)
                .fontColor('#999999')
            }
          }
          .width('100%')

          // 推荐内容
          Text(this.reason)
            .fontSize(15)
            .fontColor('#1A1A1A')
            .lineHeight(22)
            .width('100%')
            .margin({ top: 8 })

          // 底部：提示 + 反馈按钮
          Row() {
            Text('轻触执行')
              .fontSize(11)
              .fontColor('#CCCCCC')
              .layoutWeight(1)

            if (!this.feedbackGiven) {
              // 👍 按钮
              Text('\uD83D\uDC4D')
                .fontSize(20)
                .width(36)
                .height(36)
                .textAlign(TextAlign.Center)
                .borderRadius(18)
                .backgroundColor('#F0F8F0')
                .onClick(() => {
                  this.handleThumbsUp();
                })

              // 👎 按钮
              Text('\uD83D\uDC4E')
                .fontSize(20)
                .width(36)
                .height(36)
                .textAlign(TextAlign.Center)
                .borderRadius(18)
                .backgroundColor('#FFF0F0')
                .margin({ left: 8 })
                .onClick(() => {
                  this.handleThumbsDown();
                })
            }
          }
          .width('100%')
          .margin({ top: 12 })
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')
        .padding(16)
        .onClick(() => {
          this.handleActionTap();
        })

        // 感谢反馈 toast
        if (this.showToast) {
          Text(this.toastText)
            .fontSize(12)
            .fontColor(Color.White)
            .backgroundColor('#4CAF50')
            .borderRadius(12)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .margin({ bottom: 50, right: 8 })
        }
      }
      .width('100%')
      .backgroundColor(Color.White)
      .borderRadius(12)
      .shadow({ radius: 4, color: '#0000000D', offsetX: 0, offsetY: 2 })
    }
    .width('100%')
    .offset({ x: this.offsetX })
    .gesture(
      PanGesture({ direction: PanDirection.Horizontal })
        .onActionUpdate((event: GestureEvent) => {
          this.offsetX = event.offsetX;
        })
        .onActionEnd((event: GestureEvent) => {
          if (Math.abs(event.offsetX) > 120) {
            // 滑走 → dismiss
            this.offsetX = event.offsetX > 0 ? 400 : -400;
            this.onDismiss(this.ruleId);
          } else {
            this.offsetX = 0;
          }
        })
    )
    .animation({ duration: 200, curve: Curve.EaseOut })
  }

  private handleThumbsUp(): void {
    this.feedbackGiven = true;
    this.toastText = '感谢反馈';
    this.showToast = true;
    this.onThumbsUp(this.ruleId);
    this.hideToastLater();
  }

  private handleThumbsDown(): void {
    this.feedbackGiven = true;
    this.toastText = '感谢反馈';
    this.showToast = true;
    this.onThumbsDown(this.ruleId);
    this.hideToastLater();
  }

  private handleActionTap(): void {
    if (this.feedbackGiven) return;
    this.feedbackGiven = true;
    this.toastText = '已执行';
    this.showToast = true;
    this.onActionTap(this.ruleId);
    this.hideToastLater();
  }

  private hideToastLater(): void {
    setTimeout(() => {
      this.showToast = false;
    }, 1500);
  }

  private actionIcon(): string {
    let label = this.actionLabel;
    if (label === 'suggestion') return '\uD83D\uDCA1';
    if (label === 'notification') return '\uD83D\uDD14';
    if (label === 'automation') return '\u2699\uFE0F';
    return '\uD83D\uDCA1';
  }

  private defaultActionLabel(): string {
    let label = this.actionLabel;
    if (label === 'suggestion') return '智能建议';
    if (label === 'notification') return '提醒';
    if (label === 'automation') return '自动化';
    return '推荐';
  }
}
