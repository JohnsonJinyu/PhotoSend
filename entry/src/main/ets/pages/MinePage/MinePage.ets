@Component
export struct MinePage {
  @Builder
  menuItem(icon: Resource, title: string, onClick: () => void) {
    Row() {
      Image(icon)
        .width(24)
        .height(24)
        .margin({ right: 16 })
      Text(title)
        .fontSize(16)

      Blank()

      Image($r('app.media.ic_arrow_right'))
        .width(16)
        .height(16)
    }
    .width('100%')
    .height(56)
    .padding({ left: 24, right: 16 })
    .onClick(onClick)
  }

  build() {
    Column() {
      List() {
        ListItem() {
          this.menuItem($r('app.media.ic_settings'), '设置', () => {
            // 跳转设置页逻辑
          })
        }
        .border({ width: { bottom: 1 }, color: '#F1F3F5' })


        ListItem() {
          this.menuItem($r('app.media.ic_about'), '关于', () => {
            // 跳转关于页逻辑
          })
        }
        .border({ width: { bottom: 1 }, color: '#F1F3F5' })


        ListItem() {
          this.menuItem($r('app.media.ic_feedback'), '意见反馈', () => {
            // 跳转反馈页逻辑
          })
        }
      }
      .width('100%')
      .height('auto')
      .divider({ strokeWidth: 1, color: '#F1F3F5' })
      .margin({ top: 12 })
    }
    .width('100%')
    .height('100%')
  }
}