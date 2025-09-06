import { promptAction } from "@kit.ArkUI"

@Component
export struct CameraPage {
  // status control
  @State isConnected: boolean = false
  @State showConnectionSheet: boolean = false
  @State cameraImage: Resource = $r('app.media.camera_pre_zf')
  // 连接模式选项列表
  private connectionOptions: string[] = [
    '添加照相机',
    '切换照相机',
    '忽略照相机',
    'WiFi AP模式连接',
    'WiFi STA模式连接',
    '下载位置数据'
  ]

  build() {
    Column() {
      // 顶部相机图片展示区域
      Column() {
        Image(this.cameraImage)
          .width('100%')
          .height(250)
          .objectFit(ImageFit.Cover)


        // 连接状态提示
        Row() {
          Text(this.isConnected ? '已连接相机' : '未连接相机')
            .fontSize(14)
            .fontColor(this.isConnected ? '#00C853' : '#F44336')
          Toggle({ type: ToggleType.Switch, isOn: this.isConnected })
            .onChange((isOn) => {
              this.isConnected = isOn
              // 实际应用中这里会处理连接逻辑
            })
        }
        .padding({
          left: 16,
          right: 16,
          top: 8,
          bottom: 8
        })
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)
        .backgroundColor('#F5F5F5')
      }
      .backgroundColor('#E0E0E0')


      // 功能按钮区域
      Scroll() {
        Column() {
          Blank(30)

          // 连接按钮
          Button({ type: ButtonType.Capsule, stateEffect: true }) {
            Text(this.isConnected ? '断开连接' : '连接相机')
              .fontSize(18)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.comp_background_list_card'))
          }
          .width('80%')
          .height(48)
          .backgroundColor(this.isConnected ? '#F44336' : '#2196F3')
          .onClick(() => {
            this.isConnected = !this.isConnected
            // 实际应用中这里会处理连接/断开逻辑
          })

          Blank(15)

          // 连接模式设定按钮 - 点击弹出ActionSheet
          Button({ type: ButtonType.Capsule, stateEffect: true }) {
            Text('连接模式设定')
              .fontSize(18)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.comp_background_list_card'))
          }
          .width('80%')
          .height(48)
          .backgroundColor('#607D8B')
          .onClick(() => {
            this.showConnectionOptions()
          })

          Blank(15)

          // 下载照片按钮
          Button({ type: ButtonType.Capsule, stateEffect: true }) {
            Text('下载照片')
              .fontSize(18)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.comp_background_list_card'))
          }
          .width('80%')
          .height(48)
          .backgroundColor('#4CAF50')
          .enabled(this.isConnected)
          .opacity(this.isConnected ? 1 : 0.6)
          .onClick(() => {
            if (this.isConnected) {
              promptAction.showToast({ message: '开始下载照片' })
            }
          })

          Blank(15)


          // 遥控拍摄按钮
          Button({ type: ButtonType.Capsule, stateEffect: true }) {
            Text('遥控拍摄')
              .fontSize(18)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.white'))
          }
          .width('80%')
          .height(48)
          .backgroundColor($r('sys.color.comp_background_list_card'))
          .enabled(this.isConnected)
          .opacity(this.isConnected ? 1 : 0.6)
          .onClick(() => {
            //处理遥控拍摄逻辑

          })

          Blank(30)
        }
        .width('100%')
      }

    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.comp_background_list_card'))
  }

  // 显示连接模式选项（使用最新ActionSheet API）
  private showConnectionOptions():void {
    // 构建选项列表
    const sheetItems :SheetInfo[] = this.connectionOptions.map(option => ({
      title: option,
      action: () => {
        this.handleConnectionOption(option)
      }
    } as SheetInfo)) // 添加类型断言，确保对象符合 SheetInfo 接口


    // 调用最新的ActionSheet.show()方法
    ActionSheet.show({
      title: '连接模式设定',
      message: '请选择连接方式或相关操作', // 可选，可删除
      sheets: sheetItems,
      confirm: {
        value: '取消',
        action: () => {
          console.log('用户取消了操作')
        }
      }
    })
  }

  // 处理连接模式选项点击
  private handleConnectionOption(option: string): void {
    promptAction.showToast({ message: `已选择: ${option}` })

    // 根据选择的选项执行相应操作
    switch (option) {
      case '添加照相机':
        // 添加照相机逻辑
        break
      case '切换照相机':
        // 切换照相机逻辑
        break
      case '忽略照相机':
        // 忽略照相机逻辑
        break
      case 'WiFi AP模式连接':
        // WiFi AP模式连接逻辑
        break
      case 'WiFi STA模式连接':
        // WiFi STA模式连接逻辑
        break
      case '下载位置数据':
        // 下载位置数据逻辑
        break
    }
  }
}