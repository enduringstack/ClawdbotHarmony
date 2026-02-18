// Experience page - view and manage experiences (skills + memory)
import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { ExperienceStorage } from '../service/ExperienceStorage';
import { Experience, Skill, Memory } from '../model/ExperiencePack';

@Entry
@Component
struct ExperienceRoutePage {
  @State experiences: Experience[] = [];
  @State selectedExp: Experience | null = null;
  @State isLoading: boolean = true;
  @State lastSync: string = '从未';
  private storage: ExperienceStorage = ExperienceStorage.getInstance();

  aboutToAppear(): void {
    this.loadExperiences();
  }

  private async loadExperiences(): Promise<void> {
    try {
      let ctx = getContext(this) as common.UIAbilityContext;
      let pack = await this.storage.load(ctx);
      if (pack) {
        this.experiences = pack.experiences;
        this.lastSync = this.storage.getLastSyncTime();
      }
    } catch (e) {
      console.error('Load experiences failed:', (e as Error).message);
    }
    this.isLoading = false;
  }

  build() {
    Navigation() {
      if (this.isLoading) {
        Column() {
          LoadingProgress()
            .width(48)
            .height(48)
          Text('加载中...')
            .fontSize(14)
            .fontColor('#999999')
            .margin({ top: 16 })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else if (this.selectedExp) {
        // 详情视图
        this.ExperienceDetail(this.selectedExp)
      } else {
        // 列表视图
        this.ExperienceList()
      }
    }
    .title(this.selectedExp ? this.selectedExp.name : '经验')
    .titleMode(NavigationTitleMode.Mini)
    .menus(this.selectedExp ? [
      { value: '返回', action: () => { this.selectedExp = null; } }
    ] : [])
    .navBarPosition(NavBarPosition.Start)
    .mode(NavigationMode.Stack)
    .backButtonIcon($r('sys.media.ohos_ic_public_arrow_left'))
    .onNavBarStateChange((isVisible: boolean) => {
      if (!isVisible && this.selectedExp) {
        this.selectedExp = null;
      }
    })
  }

  @Builder
  ExperienceList() {
    Column() {
      // 统计
      Row() {
        Column() {
          Text(`${this.experiences.length}`)
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1A1A1A')
          Text('条经验')
            .fontSize(12)
            .fontColor('#999999')
        }
        .layoutWeight(1)

        Column() {
          Text(`${this.storage.getTotalSkillsCount()}`)
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1A1A1A')
          Text('个技能')
            .fontSize(12)
            .fontColor('#999999')
        }
        .layoutWeight(1)

        Column() {
          Text(`${this.storage.getTotalMemoryCount()}`)
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1A1A1A')
          Text('条记忆')
            .fontSize(12)
            .fontColor('#999999')
        }
        .layoutWeight(1)
      }
      .width('100%')
      .padding(16)
      .backgroundColor('#F8F8F8')
      .borderRadius(12)
      .margin({ left: 16, right: 16, top: 16 })

      // 同步时间
      Text(`上次同步: ${this.lastSync}`)
        .fontSize(12)
        .fontColor('#999999')
        .margin({ top: 8, bottom: 16 })

      // 经验列表
      if (this.experiences.length === 0) {
        Column() {
          Text('📚')
            .fontSize(48)
          Text('暂无经验')
            .fontSize(16)
            .fontColor('#999999')
            .margin({ top: 12 })
          Text('经验会在与 AI 交互过程中自动学习')
            .fontSize(12)
            .fontColor('#CCCCCC')
            .margin({ top: 4 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List() {
          ForEach(this.experiences, (exp: Experience) => {
            ListItem() {
              this.ExperienceCard(exp)
            }
          })
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 16, right: 16 })
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  ExperienceCard(exp: Experience) {
    Column() {
      Row() {
        Text(exp.name)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor('#1A1A1A')
          .layoutWeight(1)
        Text('>')
          .fontSize(14)
          .fontColor('#CCCCCC')
      }
      .width('100%')

      if (exp.description.length > 0) {
        Text(exp.description)
          .fontSize(13)
          .fontColor('#666666')
          .margin({ top: 4 })
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }

      Row() {
        Text(`${exp.skills.length} 技能`)
          .fontSize(12)
          .fontColor('#999999')
        Text('·')
          .fontSize(12)
          .fontColor('#CCCCCC')
          .margin({ left: 8, right: 8 })
        Text(`${exp.memory.length} 记忆`)
          .fontSize(12)
          .fontColor('#999999')
        Blank()
        Text(this.formatTime(exp.updatedAt))
          .fontSize(11)
          .fontColor('#CCCCCC')
      }
      .width('100%')
      .margin({ top: 8 })
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#FFFFFF')
    .borderRadius(12)
    .margin({ bottom: 12 })
    .shadow({ radius: 4, color: '#0000000A', offsetY: 2 })
    .onClick(() => {
      this.selectedExp = exp;
    })
  }

  @Builder
  ExperienceDetail(exp: Experience) {
    Scroll() {
      Column() {
        // 描述
        if (exp.description.length > 0) {
          Text(exp.description)
            .fontSize(14)
            .fontColor('#666666')
            .width('100%')
            .padding(16)
        }

        // Skills 部分
        this.SectionTitle('技能', exp.skills.length)
        if (exp.skills.length === 0) {
          Text('暂无技能')
            .fontSize(13)
            .fontColor('#999999')
            .padding(16)
        } else {
          ForEach(exp.skills, (skill: Skill) => {
            this.SkillCard(skill)
          })
        }

        // Memory 部分
        this.SectionTitle('记忆', exp.memory.length)
        if (exp.memory.length === 0) {
          Text('暂无记忆')
            .fontSize(13)
            .fontColor('#999999')
            .padding(16)
        } else {
          Column() {
            ForEach(exp.memory, (mem: Memory) => {
              this.MemoryRow(mem)
            })
          }
          .width('100%')
          .padding({ left: 16, right: 16 })
          .backgroundColor('#FFFFFF')
          .borderRadius(12)
          .margin({ left: 16, right: 16 })
        }

        // 时间信息
        Column() {
          Text(`创建时间: ${this.formatTime(exp.createdAt)}`)
            .fontSize(12)
            .fontColor('#999999')
          Text(`更新时间: ${this.formatTime(exp.updatedAt)}`)
            .fontSize(12)
            .fontColor('#999999')
            .margin({ top: 4 })
        }
        .width('100%')
        .padding(16)
        .margin({ top: 16 })
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  SectionTitle(title: string, count: number) {
    Row() {
      Text(title)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor('#1A1A1A')
      Text(` (${count})`)
        .fontSize(14)
        .fontColor('#999999')
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 16, bottom: 8 })
  }

  @Builder
  SkillCard(skill: Skill) {
    Column() {
      Text(skill.name)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor('#1A1A1A')
        .width('100%')

      if (skill.description.length > 0) {
        Text(skill.description)
          .fontSize(12)
          .fontColor('#666666')
          .margin({ top: 4 })
          .width('100%')
      }

      if (skill.instructions.length > 0) {
        Text(skill.instructions)
          .fontSize(12)
          .fontColor('#888888')
          .fontFamily('monospace')
          .margin({ top: 8 })
          .padding(8)
          .backgroundColor('#F5F5F5')
          .borderRadius(6)
          .width('100%')
          .maxLines(10)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor('#FFFFFF')
    .borderRadius(10)
    .margin({ left: 16, right: 16, bottom: 8 })
  }

  @Builder
  MemoryRow(mem: Memory) {
    Row() {
      Text(mem.key)
        .fontSize(13)
        .fontColor('#666666')
        .width(100)
      Text(mem.value)
        .fontSize(13)
        .fontColor('#1A1A1A')
        .layoutWeight(1)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding({ top: 10, bottom: 10 })
    .border({ width: { bottom: 1 }, color: '#F0F0F0' })
  }

  private formatTime(ts: number): string {
    if (ts === 0) return '-';
    let d = new Date(ts);
    return `${d.getMonth() + 1}/${d.getDate()} ${d.getHours()}:${d.getMinutes().toString().padStart(2, '0')}`;
  }
}
