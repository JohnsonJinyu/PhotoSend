import { promptAction } from "@kit.ArkUI"
import { common, Want } from '@kit.AbilityKit'
import { BusinessError } from '@ohos.base'

// 定义相机信息接口
interface CameraInfo {
  name: string; // 相机名称
  model: string; // 相机型号
  ipAddress?: string; // IP地址(WiFi连接时)
  macAddress?: string; // MAC地址
  batteryLevel?: number; // 电池电量
  connectedMode: '蓝牙' | 'WiFi-AP' | 'WiFi-STA'; // 连接模式
}

// 定义SheetInfo接口，用于ActionSheet
interface SheetInfo {
  title: string;
  action: () => void;
}

// 定义系统设置配置接口
interface SettingItem {
  bundleName: string;
  abilityName: string;
  uri?: string;
  action?: string;
}

// 定义具体的连接模式类型
type ConnectionMode = '蓝牙' | 'WiFi-AP' | 'WiFi-STA';

@Preview
@Component
export struct CameraPage {
  // 状态控制
  @State isConnected: boolean = false
  @State cameraImage: Resource = $r('app.media.camera_pre_zf')
  @State currentConnectionMode: ConnectionMode = 'WiFi-AP'
  @State selectedModeIndex: number = 1
  @State cameraInfo: CameraInfo | null = null
  @State isDetecting: boolean = false
  @State connectionStatus: string = '未检测连接状态'
  // 连接模式选项
  private connectionModes: ConnectionMode[] = ['蓝牙', 'WiFi-AP', 'WiFi-STA']
  // 连接模式操作选项列表
  private connectionOptions: string[] = [
    '添加照相机',
    '切换照相机',
    '忽略照相机',
    '下载位置数据'
  ]

  // 页面加载时自动检测连接状态
  aboutToAppear() {
    this.startConnectionDetection();
    // 启动连接状态监听
    this.startConnectionListener();
  }

  // 页面销毁时清理资源
  aboutToDisappear() {
    this.stopConnectionListener();
  }

  build() {
    Column() {
      // 顶部相机图片展示区域
      this.buildCameraPreviewArea()

      // 相机信息展示区域
      this.buildCameraInfoArea()

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
   * 构建相机信息展示区域
   */
  @Builder
  private buildCameraInfoArea() {
    if (this.isConnected && this.cameraInfo) {
      Column() {
        Text('相机信息')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .margin(10)
          .alignSelf(ItemAlign.Start)

        Column() {
          Row() {
            Text('名称: ')
              .fontSize(14)
              .fontColor('#666666')
            Text(this.cameraInfo.name)
              .fontSize(14)
          }
          .padding({ bottom: 5 })

          Row() {
            Text('型号: ')
              .fontSize(14)
              .fontColor('#666666')
            Text(this.cameraInfo.model)
              .fontSize(14)
          }
          .padding({ bottom: 5 })

          Row() {
            Text('连接方式: ')
              .fontSize(14)
              .fontColor('#666666')
            Text(this.cameraInfo.connectedMode)
              .fontSize(14)
          }
          .padding({ bottom: 5 })

          if (this.cameraInfo.batteryLevel !== undefined) {
            Row() {
              Text('电池电量: ')
                .fontSize(14)
                .fontColor('#666666')
              Text(`${this.cameraInfo.batteryLevel}%`)
                .fontSize(14)
            }
          }
        }
        .padding({ left: 16, right: 16 })
      }
      .width('100%')
      .padding({ top: 10, bottom: 10 })
      .backgroundColor('#FFFFFF')
      .margin({ top: 10, left: 10, right: 10 })
      .borderRadius(8)
    }
  }

  /**
   * 构建连接状态栏
   */
  @Builder
  private buildConnectionStatusBar() {
    Row() {
      // 连接状态文本
      Text(this.connectionStatus)
        .fontSize(14)
        .fontColor(this.isConnected ? '#00C853' : '#F44336')

      // 连接模式选择按钮
      Button({ type: ButtonType.Normal, stateEffect: true }) {
        Row() {
          Text(`模式: ${this.currentConnectionMode}`)
            .fontSize(14)
            .fontColor('#333333')
        }
      }
      .backgroundColor('#E0E0E0')
      .borderRadius(12)
      .padding({
        left: 10,
        right: 10,
        top: 4,
        bottom: 4
      })
      .onClick(() => {
        this.showModePickerDialog()
      })

      // 连接开关
      Toggle({ type: ToggleType.Switch, isOn: this.isConnected })
        .onChange((isOn) => {
          if (isOn) {
            this.handleConnectCamera();
          } else {
            this.handleDisconnectCamera();
          }
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
          Row() {
            if (this.isDetecting) {
              Progress({ value: 50, total: 100, type: ProgressType.Linear })
                .width(20)
                .height(20)
                .color('#FFFFFF')
                .margin({ right: 10 })
            }
            Text(this.isConnected ? '断开连接' : '连接相机')
              .fontSize(18)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.comp_background_list_card'))
          }
        }
        .width('80%')
        .height(48)
        .backgroundColor(this.isConnected ? '#F44336' : '#2196F3')
        .onClick(() => {
          if (this.isConnected) {
            this.handleDisconnectCamera();
          } else {
            this.handleConnectCamera();
          }
        })
        .enabled(!this.isDetecting)

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
   * 显示连接模式选择对话框
   */
  private showModePickerDialog() {
    TextPickerDialog.show({
      range: this.connectionModes,
      selected: this.selectedModeIndex as number,
      onAccept: (result: TextPickerResult) => {
        const selectedIndex = Array.isArray(result.index) ? result.index[0] : result.index;
        this.selectedModeIndex = selectedIndex;
        this.currentConnectionMode = this.connectionModes[selectedIndex];
        try {
          promptAction.showToast({
            message: `已选择${this.currentConnectionMode}模式`
          })
        } catch (error) {
          console.error('显示提示失败:', error);
        }
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
   * 处理连接相机
   */
  private handleConnectCamera() {
    if (!this.isConnected && !this.isDetecting) {
      this.startConnectionDetection();
    }
  }

  /**
   * 处理断开连接
   */
  private handleDisconnectCamera() {
    if (this.isConnected) {
      this.isDetecting = true;
      this.connectionStatus = '正在断开连接...';

      // 模拟断开连接过程
      setTimeout(() => {
        this.isConnected = false;
        this.cameraInfo = null;
        this.isDetecting = false;
        this.connectionStatus = '已断开连接';

        try {
          promptAction.showToast({ message: '已断开连接' });
        } catch (error) {
          console.error('显示提示失败:', error);
        }
      }, 1500);
    }
  }

  /**
   * 处理连接模式选项点击
   */
  private handleConnectionOption(option: string): void {
    try {
      promptAction.showToast({ message: `已选择: ${option}` })
    } catch (error) {
      console.error('显示提示失败:', error);
    }

    switch (option) {
      case '添加照相机':
        // 添加照相机逻辑
        break;
      case '切换照相机':
        // 切换照相机逻辑
        break;
      case '忽略照相机':
        // 忽略照相机逻辑
        break;
      case 'WiFi AP模式连接':
        this.currentConnectionMode = 'WiFi-AP';
        this.selectedModeIndex = 1;
        break;
      case 'WiFi STA模式连接':
        this.currentConnectionMode = 'WiFi-STA';
        this.selectedModeIndex = 2;
        break;
      case '下载位置数据':
        // 下载位置数据逻辑
        break;
    }
  }

  /**
   * 处理照片下载
   */
  private handleDownloadPhotos() {
    if (this.isConnected) {
      try {
        promptAction.showToast({ message: '开始下载照片' })
      } catch (error) {
        console.error('显示提示失败:', error);
      }
      // 实现下载逻辑
    }
  }

  /**
   * 处理遥控拍摄
   */
  private handleRemoteShoot() {
    if (this.isConnected) {
      try {
        promptAction.showToast({ message: '正在进行遥控拍摄' })
      } catch (error) {
        console.error('显示提示失败:', error);
      }
      // 实现遥控拍摄逻辑
    }
  }

  /**
   * 开始连接检测
   */
  private startConnectionDetection() {
    this.isDetecting = true;
    this.connectionStatus = `正在检测${this.currentConnectionMode}连接...`;

    // 根据当前连接模式检测连接
    switch (this.currentConnectionMode) {
      case '蓝牙':
        this.detectBluetoothConnection();
        break;
      case 'WiFi-AP':
      case 'WiFi-STA':
        this.detectWiFiConnection();
        break;
    }
  }

  /**
   * 检测蓝牙连接
   */
  private detectBluetoothConnection() {
    // 模拟蓝牙连接检测过程
    setTimeout(() => {
      // 这里应该是实际的蓝牙连接检测逻辑
      const isConnected = Math.random() > 0.3; // 模拟70%概率连接成功

      if (isConnected) {
        this.isConnected = true;
        this.connectionStatus = '已通过蓝牙连接';
        // 获取相机信息
        this.fetchCameraInfo('蓝牙');
      } else {
        this.isConnected = false;
        this.connectionStatus = '蓝牙连接检测失败';
        // 提示用户手动连接
        this.promptManualConnection();
      }
      this.isDetecting = false;
    }, 2000);
  }

  /**
   * 检测WiFi连接
   */
  private detectWiFiConnection() {
    // 模拟WiFi连接检测过程
    setTimeout(() => {
      // 这里应该是实际的WiFi连接检测逻辑
      const isConnected = Math.random() > 0.3; // 模拟70%概率连接成功

      if (isConnected) {
        this.isConnected = true;
        this.connectionStatus = `已通过${this.currentConnectionMode}连接`;
        // 获取相机信息
        this.fetchCameraInfo(this.currentConnectionMode);
      } else {
        this.isConnected = false;
        this.connectionStatus = `${this.currentConnectionMode}连接检测失败`;
        // 提示用户手动连接
        this.promptManualConnection();
      }
      this.isDetecting = false;
    }, 2000);
  }

  /**
   * 提示用户手动连接
   */
  private promptManualConnection() {
    AlertDialog.show({
      title: '连接失败',
      message: `未检测到${this.currentConnectionMode}连接，是否前往设置页面进行连接？`,
      confirm: {
        value: '前往设置',
        action: () => {
          this.navigateWithOldApi();
        }
      }/*,
      cancel: {
        value: '取消',
        action: () => {}
      }*/
    });
  }

  /**
   * 获取相机信息
   */
  private fetchCameraInfo(connectedMode: ConnectionMode) {
    // 模拟获取相机信息
    setTimeout(() => {
      // 实际应用中应该从相机设备获取真实信息
      this.cameraInfo = {
        name: '相机设备',
        model: 'DSC-RX100M7',
        ipAddress: connectedMode !== '蓝牙' ? '192.168.1.100' : undefined,
        macAddress: '00:1A:2B:3C:4D:5E',
        batteryLevel: Math.floor(Math.random() * 100),
        connectedMode: connectedMode
      };

      try {
        promptAction.showToast({
          message: `已连接到${this.cameraInfo.name}`
        });
      } catch (error) {
        console.error('显示提示失败:', error);
      }
    }, 1000);
  }

  /**
   * 启动连接状态监听
   */
  private startConnectionListener() {
    // 模拟连接状态监听
    this.connectionListener = setInterval(() => {
      if (this.isConnected) {
        // 随机模拟连接断开(1%概率)
        if (Math.random() < 0.01) {
          this.isConnected = false;
          this.connectionStatus = '连接已断开';
          this.cameraInfo = null;

          try {
            promptAction.showToast({ message: '与相机的连接已断开' });
          } catch (error) {
            console.error('显示提示失败:', error);
          }
        } else if (this.cameraInfo && this.cameraInfo.batteryLevel) {
          // 模拟更新电池电量
          this.cameraInfo.batteryLevel = Math.max(0, this.cameraInfo.batteryLevel - 1);
        }
      }
    }, 5000);
  }

  /**
   * 停止连接状态监听
   */
  private stopConnectionListener() {
    if (this.connectionListener) {
      clearInterval(this.connectionListener);
      this.connectionListener = null;
    }
  }

  // 连接状态监听器
  private connectionListener: number | null = null;

  /**
   * 使用旧版API跳转设置页面
   */
  private navigateWithOldApi() {
    // 1. 根据当前模式获取对应配置
    let config: SettingItem | undefined;
    switch (this.currentConnectionMode) {
      case '蓝牙':
        config = {
          bundleName: 'com.huawei.hmos.settings',
          abilityName: 'com.huawei.hmos.settings.MainAbility',
          action: 'action.settings.bluetooth'
        };
        break;
      case 'WiFi-AP':
      case 'WiFi-STA':
        config = {
          bundleName: 'com.huawei.hmos.settings',
          abilityName: 'com.huawei.hmos.settings.MainAbility',
          uri: 'wifi_entry'
        };
        break;
      default:
        config = undefined;
        break;
    }

    // 2. 检查配置是否存在
    if (!config) {
      try {
        promptAction.showToast({ message: '未找到对应的设置页面' });
      } catch (error) {
        console.error('显示提示失败:', error);
      }
      return;
    }

    // 3. 创建Want对象
    const want: Want = {
      bundleName: config.bundleName,
      abilityName: config.abilityName
    };
    if (config.uri) {
      want.uri = config.uri;
    }
    if (config.action) {
      want.action = config.action;
    }

    // 4. 获取上下文并启动Ability
    const context = getContext(this) as common.UIAbilityContext;
    if (context && context.startAbility) {
      context.startAbility(want)
        .then(() => {
          console.info(`成功跳转至${this.currentConnectionMode}设置页面`);
          try {
            promptAction.showToast({ message: `正在打开${this.currentConnectionMode}设置...` });
          } catch (error) {
            console.error('显示提示失败:', error);
          }
        })
        .catch((err: BusinessError) => {
          console.error(`跳转失败: code=${err.code}, message=${err.message}`);
          try {
            promptAction.showToast({ message: `打开${this.currentConnectionMode}设置失败` });
          } catch (error) {
            console.error('显示提示失败:', error);
          }
        });
    } else {
      try {
        promptAction.showToast({ message: '无法获取应用上下文' });
      } catch (error) {
        console.error('显示提示失败:', error);
      }
    }
  }
}
