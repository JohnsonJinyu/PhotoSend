import { CustomContentDialog, promptAction } from "@kit.ArkUI"
import { pasteboard } from "@kit.BasicServicesKit"
import { TestType } from "@ohos/hypium";


const systemPasteboard: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();

@CustomDialog
export struct FeedbackDialog {
  controller: CustomDialogController
  private email: string = '1315130067@qq.com'

  /**
   * @throws
   */
  private copyEmail() {

    let data =pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN,this.email)

    systemPasteboard.setDataSync(data)

    this.getUIContext().getPromptAction().showToast({
      message:"邮箱地址已复制",
      duration:1000,
      showMode:promptAction.ToastShowMode.DEFAULT,
      bottom:80
    })
  }

  private sendEmail() {
    // 这里实现发送邮件的逻辑
  }

  build() {
    Column() {
      // 标题区域
      Text('意见反馈')
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .margin({ top: 24, bottom: 16 })
        .fontColor('#000000')

      // 邮箱地址显示
      Text(this.email)
        .fontSize(16)
        .fontColor('#666666')
        .backgroundColor('#F7F9FC')
        .padding(12)
        .borderRadius(8)
        .width('90%')
        .margin({ bottom: 20 })

      // 按钮区域
      Row() {
        Button('复制邮件', { type: ButtonType.Normal })
          .fontSize(16)
          .backgroundColor('#007DFF')
          .fontColor('#FFFFFF')
          .padding({ left: 20, right: 20 })
          .height(40)
          .borderRadius(20)
          .onClick(() => this.copyEmail())

        Blank().width(12)

        Button('发送邮件', { type: ButtonType.Capsule })
          .fontSize(16)
          .backgroundColor('#E6F3FF')
          .fontColor('#007DFF')
          .padding({ left: 20, right: 20 })
          .height(40)
          .borderRadius(20)
          .onClick(() => this.sendEmail())
      }
      .justifyContent(FlexAlign.Center)
      .margin({ bottom: 24 })
    }
    .width('85%')

    .alignItems(HorizontalAlign.Center)
  }
}
