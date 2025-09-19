import { promptAction } from "@kit.ArkUI"
import { common, Want } from '@kit.AbilityKit'


// 定义SheetInfo接口，用于ActionSheet
interface SheetInfo {
  title: string;
  action: () => void;
}

// 系统设置跳转参数接口
interface SystemSettingsWant {
  bundleName: string;
  abilityName: string;
  uri: string;
}
@Preview
@Component
export struct CameraPage {
  // 状态控制
  @State isConnected: boolean = false
  @State cameraImage: Resource = $r('app.media.camera_pre_zf')
  @State currentConnectionMode: string = 'WiFi-AP' // 默认选择WiFi-AP
  @State selectedModeIndex: number = 1 // 对应'WiFi-AP'的索引位置

  // 连接模式选项
  private connectionModes: string[] = ['蓝牙', 'WiFi-AP', 'WiFi-STA']

  // 连接模式操作选项列表
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
      this.buildCameraPreviewArea()

      // 功能按钮区域
      this.buildFunctionButtonsArea()
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.comp_background_list_card'))
  }

  /**
   * 构建相机预览区域
   */
  @Builder
  private buildCameraPreviewArea() {
    Column() {
      // 相机预览图
      Image(this.cameraImage)
        .width('100%')
        .height(250)
        .objectFit(ImageFit.Cover)

      // 连接状态和模式控制栏
      this.buildConnectionStatusBar()
    }
    .backgroundColor('#E0E0E0')
  }

  /**
   * 构建连接状态栏
   */
  @Builder
  private buildConnectionStatusBar() {
    Row() {
      // 连接状态文本
      Text(this.isConnected ? '已连接相机' : '未连接相机')
        .fontSize(14)
        .fontColor(this.isConnected ? '#00C853' : '#F44336')

      // 连接模式选择按钮 - 使用TextPickerDialog
      Button({ type: ButtonType.Normal, stateEffect: true }) {
        Row() {
          Text(`模式: ${this.currentConnectionMode}`)
            .fontSize(14)
            .fontColor('#333333')
        }
      }
      .backgroundColor('#E0E0E0')
      .borderRadius(12)
      .padding({ left: 10, right: 10, top: 4, bottom: 4 })
      .onClick(() => {
        this.showModePickerDialog()
      })

      // 连接开关
      Toggle({ type: ToggleType.Switch, isOn: this.isConnected })
        .onChange((isOn) => {
          this.isConnected = isOn
        })
    }
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
    .width('100%')
    .justifyContent(FlexAlign.SpaceBetween)
    .backgroundColor('#F5F5F5')
  }

  /**
   * 构建功能按钮区域
   */
  @Builder
  private buildFunctionButtonsArea() {
    Scroll() {
      Column() {
        Blank(30)

        // 连接/断开连接按钮
        Button({ type: ButtonType.Normal, stateEffect: true }) {
          Text(this.isConnected ? '断开连接' : '连接相机')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.comp_background_list_card'))
        }
        .width('80%')
        .height(48)
        .backgroundColor(this.isConnected ? '#F44336' : '#2196F3')
        .onClick(() => this.handleConnectionButtonClick())

        Blank(15)

        // 连接模式设定按钮
        Button({ type: ButtonType.Normal, stateEffect: true }) {
          Text('连接模式设定')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.comp_background_list_card'))
        }
        .width('80%')
        .height(48)
        .backgroundColor('#607D8B')
        .onClick(() => this.showConnectionOptions())

        Blank(15)

        // 下载照片按钮
        Button({ type: ButtonType.Normal, stateEffect: true }) {
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
        .onClick(() => this.handleDownloadPhotos())

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
        .onClick(() => this.handleRemoteShoot())

        Blank(30)
      }
      .width('100%')
    }
  }

  /**
   * 使用TextPickerDialog显示连接模式选择
   */
  private showModePickerDialog() {
    TextPickerDialog.show({
      range: this.connectionModes,
      selected: this.selectedModeIndex as number,
        onAccept: (result : TextPickerResult) => {
          // 确保获取的是单个索引值
          const selectedIndex = Array.isArray(result.index) ? result.index[0] : result.index;
          this.selectedModeIndex = selectedIndex;
          this.currentConnectionMode = this.connectionModes[selectedIndex];
        promptAction.showToast({
          message: `已选择${this.currentConnectionMode}模式`
        })
      },
      onCancel: () => {
        console.log('取消选择连接模式')
      }
    })
  }

  /**
   * 显示连接选项ActionSheet
   */
  private showConnectionOptions(): void {
    const sheetItems: SheetInfo[] = this.connectionOptions.map<SheetInfo>(option => ({
      title: option,
      action: () => this.handleConnectionOption(option)
    }))

    ActionSheet.show({
      title: '连接模式设定',
      message: '请选择连接方式或相关操作',
      sheets: sheetItems,
      confirm: {
        value: '取消',
        action: () => console.log('用户取消了操作')
      }
    })
  }

  /**
   * 处理连接按钮点击
   */
  private handleConnectionButtonClick() {
    if (!this.isConnected) {
      this.openSystemWifiSettings()
    } else {
      this.isConnected = false
      promptAction.showToast({ message: '已断开连接' })
    }
  }

  /**
   * 处理连接模式选项点击
   */
  private handleConnectionOption(option: string): void {
    promptAction.showToast({ message: `已选择: ${option}` })

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
        this.currentConnectionMode = 'WiFi-AP'
        this.selectedModeIndex = 1 // 更新索引
        break
      case 'WiFi STA模式连接':
        this.currentConnectionMode = 'WiFi-STA'
        this.selectedModeIndex = 2 // 更新索引
        break
      case '下载位置数据':
        // 下载位置数据逻辑
        break
    }
  }

  /**
   * 处理照片下载
   */
  private handleDownloadPhotos() {
    if (this.isConnected) {
      promptAction.showToast({ message: '开始下载照片' })
      // 实现下载逻辑
    }
  }

  /**
   * 处理遥控拍摄
   */
  private handleRemoteShoot() {
    if (this.isConnected) {
      promptAction.showToast({ message: '正在进行遥控拍摄' })
      // 实现遥控拍摄逻辑
    }
  }

  /**
   * 打开系统WiFi设置
   */
  private openSystemWifiSettings(): void {
  try {
      // 创建Want对象
      const want: Want = {
        bundleName: 'com.huawei.hmos.settings',
        abilityName: 'com.huawei.hmos.settings.MainAbility',
        uri: 'wifi_entry' // WiFi设置页面的URI
      };

      // 获取上下文并启动Ability
      const context = getContext(this) as common.UIAbilityContext;
      context.startAbility(want);
      console.info('启动系统WiFi设置成功');
    } catch (error) {
      console.error('启动系统WiFi设置失败:', error);
    }
  }
}
