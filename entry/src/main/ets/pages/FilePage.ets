import {
  GetCameraList,
  ConnectCamera,
  SetCameraParameter,
  TakePhoto,
  GetPreview,
  DownloadPhoto,
  DisconnectCamera,
  CameraDevice,
  PhotoPathInfo
} from 'libentry.so';

@Preview
@Component
export struct FilePage {
  // 状态管理（类型显式，无any）
  @State cameraList: CameraDevice[] = [];
  @State selectedCamera: CameraDevice | null = null;
  @State isConnected: boolean = false;
  @State isMockMode: boolean = true;
  @State previewBase64: string = '';
  @State currentPhotoPath: PhotoPathInfo | null = null;
  @State apertureValue: string = 'f/5.6';
  @State shutterValue: string = '1/100';
  @State isoValue: string = '100';
  @State operationLogs: string[] = [];

  // 2. 修复：函数显式返回类型（void）+ 参数无any
  private addLog(log: string): void {
    const time: string = new Date().toTimeString().slice(0, 8);
    this.operationLogs.unshift(`[${time}] ${log}`);
    this.operationLogs = this.operationLogs.slice(0, 20);
  }

  // 模拟数据函数（显式返回类型）
  private getMockCameraList(): CameraDevice[] {
    return [{ name: "模拟相机 - Nikon D850", path: "usb:001,005" }];
  }

  private getMockPreviewBase64(): string {
    return 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
  }

  private getMockPhotoPath(): PhotoPathInfo {
    return { folder: "/DCIM/100NIKON", name: "DSC_0001.JPG" };
  }

  // 核心功能：显式返回类型+参数类型
  private fetchCameraList(): void {
    try {
      this.addLog("开始检测相机...");
      const list: CameraDevice[] = this.isMockMode ? this.getMockCameraList() : GetCameraList();
      this.cameraList = list;

      if (list.length === 0) {
        this.selectedCamera = null;
        this.addLog("未检测到相机，请检查热点/USB连接");
      } else if (list.length === 1) {
        this.selectedCamera = list[0];
        this.addLog(`检测到1台设备：${list[0].name}（路径：${list[0].path}）`);
      } else {
        this.selectedCamera = null;
        this.addLog(`检测到${list.length}台设备，请选择连接`);
      }
    } catch (e) {
      this.addLog(`检测相机失败：${JSON.stringify(e)}`);
    }
  }

  private connectSelectedCamera(): void {
    if (!this.selectedCamera) {
      this.addLog("请先检测并确认设备！");
      return;
    }
    try {
      this.addLog(`连接设备：${this.selectedCamera.name}`);
      const isSuccess: boolean =
        this.isMockMode ? true : ConnectCamera(this.selectedCamera.name, this.selectedCamera.path);
      this.isConnected = isSuccess;
      this.addLog(`${this.isMockMode ? '【模拟】' : '【真实】'}连接${isSuccess ? '成功' : '失败'}`);
      if (isSuccess) {
        this.previewBase64 = '';
        this.currentPhotoPath = null;
      }
    } catch (e) {
      this.addLog(`连接失败：${JSON.stringify(e)}`);
      this.isConnected = false;
    }
  }

  // 3. 修复：desc变量作用域（提到try外，避免catch块未定义）
  private setCameraParam(paramName: string, paramValue: string): void {
    if (!this.isConnected || !paramValue.trim()) {
      const desc: string = paramName === 'aperture' ? '光圈' : paramName === 'shutter-speed' ? '快门' : 'ISO';
      this.addLog(this.isConnected ? "请输入有效值！" : "请先连接相机！");
      return;
    }
    // desc定义提到try外，确保catch可访问
    const desc: string = paramName === 'aperture' ? '光圈' : paramName === 'shutter-speed' ? '快门' : 'ISO';
    try {
      const isSuccess: boolean = this.isMockMode ? true : SetCameraParameter(paramName, paramValue);
      this.addLog(`${this.isMockMode ? '【模拟】' : '【真实】'}${desc}设置${isSuccess ? '成功' : '失败'}`);
    } catch (e) {
      this.addLog(`${desc}设置失败：${JSON.stringify(e)}`);
    }
  }

  private takePhoto(): void {
    if (!this.isConnected) {
      this.addLog("请先连接相机！");
      return;
    }
    try {
      const path: PhotoPathInfo = this.isMockMode ? this.getMockPhotoPath() : TakePhoto();
      this.currentPhotoPath = path;
      this.addLog(`${this.isMockMode ? '【模拟】' : '【真实】'}拍照成功，路径：${path.folder}/${path.name}`);
    } catch (e) {
      this.addLog(`拍照失败：${JSON.stringify(e)}`);
    }
  }

  private getCameraPreview(): void {
    if (!this.isConnected) {
      this.addLog("请先连接相机！");
      return;
    }
    try {
      const data: string = this.isMockMode ? this.getMockPreviewBase64() : GetPreview();
      this.previewBase64 = data;
      this.addLog(`${this.isMockMode ? '【模拟】' : '【真实】'}获取预览成功`);
    } catch (e) {
      this.addLog(`预览失败：${JSON.stringify(e)}`);
      this.previewBase64 = '';
    }
  }

  private downloadPhoto(): void {
    if (!this.isConnected || !this.currentPhotoPath) {
      this.addLog(this.isConnected ? "请先拍照！" : "请先连接相机！");
      return;
    }
    try {
      const photoFolder: string = this.currentPhotoPath.folder;
      const photoName: string = this.currentPhotoPath.name;
      const data: string = this.isMockMode ? this.getMockPreviewBase64() : DownloadPhoto(photoFolder, photoName);
      this.addLog(`${this.isMockMode ? '【模拟】' : '【真实】'}下载照片成功`);
    } catch (e) {
      this.addLog(`下载失败：${JSON.stringify(e)}`);
    }
  }

  private disconnectCamera(): void {
    if (!this.isConnected) {
      this.addLog("相机未连接！");
      return;
    }
    try {
      const isSuccess: boolean = this.isMockMode ? true : DisconnectCamera();
      if (isSuccess) {
        this.isConnected = false;
        this.previewBase64 = '';
        this.currentPhotoPath = null;
        this.selectedCamera = null;
      }
      this.addLog(`${this.isMockMode ? '【模拟】' : '【真实】'}断开连接${isSuccess ? '成功' : '失败'}`);
    } catch (e) {
      this.addLog(`断开失败：${JSON.stringify(e)}`);
    }
  }

  build() {
    Column() {

      // 模拟模式开关
      Row() {
        Text("模拟测试模式：")
          .fontSize(16);
        Toggle({ type: ToggleType.Switch, isOn: this.isMockMode })
          .onChange((isOn: boolean): void => { // 4. 修复：显式参数类型+返回类型
            this.isMockMode = isOn;
            this.addLog(`模拟模式${isOn ? '启用' : '禁用'}`);
          });
      }

      // 相机连接区域
      Column() {
        // 检测相机按钮
        Button("检测已连接相机")
          .width(200)
          .height(44)
          .backgroundColor('#2196F3')
          .fontColor(Color.White)
          .onClick((): void => this.fetchCameraList());

        // 动态设备信息
        if (this.cameraList.length === 0 && this.operationLogs.length > 0) {
          Column({ space: 4 }) {
            Text("未发现相机，请检查：")
              .fontSize(14)
              .fontColor('#F44336');
            Text("1. 相机热点已开启 / USB已插好")
              .fontSize(12)
              .fontColor('#666');
            Text("2. 相机已开机并处于可控制状态")
              .fontSize(12)
              .fontColor('#666');
          }
          .width('100%')
        } else if (this.cameraList.length === 1 && this.selectedCamera) {
          Column({ space: 8 }) {
            Text("当前检测到设备")
              .fontSize(14)
              .fontColor('#666');
            Text(`型号：${this.selectedCamera.name}`)
              .fontSize(16)
              .fontColor('#333');
            Text(`连接路径：${this.selectedCamera.path}`)
              .fontSize(14)
              .fontColor('#666');
            Button("确认连接")
              .width(150)
              .height(40)
              .backgroundColor('#4CAF50')
              .fontColor(Color.White)
              .onClick((): void => this.connectSelectedCamera())
              .enabled(!this.isConnected);
          }

        } else if (this.cameraList.length > 1) {
          // 5. 修复：List无itemAlign，用alignItems+ItemAlign枚举
          List() { // 替换itemAlign为alignItems
            ForEach(this.cameraList, (camera: CameraDevice): void => { // 显式参数类型
              ListItem() {
                Row({ space: 12 }) {
                  Text(`型号：${camera.name}`)
                    .flexGrow(1);
                  Text(`路径：${camera.path}`)
                    .fontSize(12)
                    .fontColor('#666');
                }
                .width('100%')
                .padding(12)
                .backgroundColor(this.selectedCamera?.path === camera.path ? '#E3F2FD' : '#fff')
                .borderRadius(8)

                //.onClick((): void => this.selectedCamera = camera)
              }
            });
          }.width('100%')
          .height(200)
          .padding(10)

          //.alignListItem(ItemAlign.Center)

          Button("连接选中设备")
            .width(150)
            .height(40)
            .backgroundColor('#4CAF50')
            .fontColor(Color.White)
            .onClick((): void => this.connectSelectedCamera())
            .enabled(this.selectedCamera && !this.isConnected);
        }

        // 连接状态提示：6. 修复：无marginTop，用margin对象
        Text(`当前状态：${this.isConnected ? `已连接 [${this.selectedCamera?.name}]` : '未连接'}`)
          .fontSize(14)
          .fontColor(this.isConnected ? '#4CAF50' : '#F44336')
          .width('100%')
          .textAlign(TextAlign.Center)
          .margin({ top: 8 }); // 替换marginTop为margin({ top: 8 })

        // 断开连接按钮
        if (this.isConnected) {
          Button("断开相机连接")
            .width(150)
            .height(40)
            .backgroundColor('#F44336')
            .fontColor(Color.White)
            .onClick((): void => this.disconnectCamera());
        }
      }
      .width('100%')


      // 参数设置+核心操作

      Row() {
        // 光圈设置：
        Column() {
          Text("光圈：")
            .width(60)
            .fontSize(14)
          TextInput({ placeholder: "f/5.6", text: this.apertureValue })
            .width('flex-grow')
            .height(40)
            .padding(12)
            .backgroundColor('#fff')
            .border({ width: 1, color: '#eee', radius: 4 })
          //.onChange((v: string): void => this.apertureValue = v); // 显式string类型
          Button("设置")
            .width(80)
            .height(40)
            .backgroundColor('#2196F3')
            .fontColor(Color.White)
            .onClick((): void => this.setCameraParam('aperture', this.apertureValue));
        }
        .margin(10)

        // 快门设置
        Column() {
          Text("快门：")
            .width(60)
            .fontSize(14)
            .textAlign(TextAlign.End);
          TextInput({ placeholder: "1/100", text: this.shutterValue })
            .width('flex-grow')
            .height(40)
            .padding(12)
            .backgroundColor('#fff')
            .border({ width: 1, color: '#eee', radius: 4 })
          //.onChange((v: string): void => this.shutterValue = v); // 显式类型
          Button("设置")
            .width(80)
            .height(40)
            .backgroundColor('#2196F3')
            .fontColor(Color.White)
            .onClick((): void => this.setCameraParam('shutter-speed', this.shutterValue));
        }
        .margin(10)

        // ISO设置
        Column() {
          Text("ISO：")
            .width(60)
            .fontSize(14)
            .textAlign(TextAlign.End);
          TextInput({ placeholder: "100", text: this.isoValue })
            .width('flex-grow')
            .height(40)
            .padding(12)
            .backgroundColor('#fff')
            .border({ width: 1, color: '#eee', radius: 4 })
          //.onChange((v: string): void => this.isoValue = v); // 显式类型
          Button("设置")
            .width(80)
            .height(40)
            .backgroundColor('#2196F3')
            .fontColor(Color.White)
            .onClick((): void => this.setCameraParam('iso', this.isoValue));
        }
        .margin(10)

      }

      .width('100%')
      .enabled(this.isConnected)
      .opacity(this.isConnected ? 1 : 0.6)

      // 核心操作按钮 拍照、获取预览、下载照片
      Column() { // 替换marginTop
        Button("拍照")
          .width(120)
          .height(40)
          .backgroundColor('#FF9800')
          .fontColor(Color.White)
          .margin(10)
          .onClick((): void => this.takePhoto());

        Button("获取预览")
          .width(120)
          .height(40)
          .backgroundColor('#2196F3')
          .fontColor(Color.White)
          .margin(10)
          .onClick((): void => this.getCameraPreview());

        Button("下载照片")
          .width(120)
          .height(40)
          .backgroundColor('#4CAF50')
          .fontColor(Color.White)
          .margin(10)
          .onClick((): void => this.downloadPhoto())
          .enabled(this.currentPhotoPath !== null);
      }
      .margin(10)

      // 预览+日志
      Column() {
        Text("实时预览")
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .width('100%');

        if (this.previewBase64) {
          Image(`data:image/jpeg;base64,${this.previewBase64}`)
            .width('100%')
            .height(240)
            .objectFit(ImageFit.Contain)
            .backgroundColor('#f5f5f5')
            .borderRadius(8);
        } else {
          Text("点击'获取预览'显示图像")
            .width('100%')
            .height(240)
            .backgroundColor('#f5f5f5')
            .textAlign(TextAlign.Center)
            .padding({ top: 100 }) // 替换paddingTop
            .fontColor('#666')
            .borderRadius(8);
        }

        // 6. 操作日志区域（API20 兼容 + 语法正确）
        Column() {
          // 日志标题
          Text("操作日志")
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .width('100%');

          // 核心滚动区域：List 替代 ScrollView（语法+API20 双正确）
          /*List() {
            ListItem() {
              ForEach(this.operationLogs, (log: string): void => {
                Text(log)
                  .fontSize(12)
                  .fontColor('#333')
                  .width('100%')
                  .textAlign(TextAlign.Start);
              });
            }

          }*/
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#fafafa')
        .borderRadius(8)
        .padding(12)

        //.alignItems(ItemAlign.Start)
      }
      .width('100%')
      .padding(20)
      .flexGrow(1)
    }
    .width('100%')
    .padding(20)
    .flexGrow(1)
  }
}