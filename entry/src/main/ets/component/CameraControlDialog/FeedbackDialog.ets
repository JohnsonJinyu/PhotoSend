import { CustomContentDialog, promptAction } from "@kit.ArkUI"
import { pasteboard } from "@kit.BasicServicesKit"
import { TestType } from "@ohos/hypium";
import { common, wantConstant } from "@kit.AbilityKit";


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
    let context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    let wantParam: Record<string, Object> = {
      'sceneType': 1,
      'email': [encodeURI('xxx@example.com'), encodeURI(this.email)], // 收件人邮箱地址，多值以逗号分隔，对数组内容使用encodeURI()方法进行url编码
      //'cc': [encodeURI('xxx@example.com'), encodeURI('xxx@example.com')], // 抄收人邮箱地址，多值以逗号分隔，对数组内容使用encodeURI()方法进行url编码
      //'bcc': [encodeURI('xxx@example.com'), encodeURI('xxx@example.com')], // 密送人邮箱地址，多值以逗号分隔，对数组内容使用encodeURI()方法进行url编码
      'subject': encodeURI('PhotoSend应用意见反馈'), // 邮件主题，对内容使用encodeURI()方法进行url编码
      'body': encodeURI('请提交你的反馈意见······'), // 邮件正文，对内容使用encodeURI()方法进行url编码
      'ability.params.stream': [encodeURI('附件uri1'), encodeURI('附件uri2')], // 附件uri，多值以逗号分隔，对数组内容使用encodeURI()方法进行url编码
      'ability.want.params.uriPermissionFlag': wantConstant.Flags.FLAG_AUTH_READ_URI_PERMISSION
    };
    let abilityStartCallback: common.AbilityStartCallback = {
      onError: (code: number, name: string, message: string) => {
        console.error(`onError code ${code} name: ${name} message: ${message}`);
      },
      onResult: (result) => {
        console.info(`onResult result: ${JSON.stringify(result)}`);
      }
    }

    context.startAbilityByType("mail", wantParam, abilityStartCallback,
      (err) => {
        if (err) {
          console.error(`startAbilityByType fail, err: ${JSON.stringify(err)}`);
        } else {
          console.info(`success`);
        }
      });
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
        .align(Alignment.Center)
        .borderRadius(8)
        .height(30)
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
