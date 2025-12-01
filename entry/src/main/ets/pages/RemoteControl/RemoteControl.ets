//RemoteControl.ets
import nativeCamera from 'libentry.so'
import { IsoDialog } from 'ets/component/CameraControlDialog/IsoDialog'
import { ShutterSpeedDialog } from 'ets/component/CameraControlDialog/ShutterSpeedDialog'
import { image } from '@kit.ImageKit';
import { cameraParamManager, ParamOption } from '../../utils/tools/CameraParamManager'
import { ApertureDialog } from '../../component/CameraControlDialog/ApertureDialog';
import { FocusModeDialog } from '../../component/CameraControlDialog/FocusModeDialog';
import { ExposureCompensationDialog } from '../../component/CameraControlDialog/ExposureCompensationDialog';
import { WhiteBalanceDialog } from '../../component/CameraControlDialog/WhiteBalanceDialog';
import { ExposureMeterModeDialog } from '../../component/CameraControlDialog/ExposureMeterModeDialog';
import { ExposureModeDialog } from '../../component/CameraControlDialog/ExposureModeDialog';
import { CamConnectionManager } from '../../utils/tools/CamConnectManager';
import { ConnectionStateResult } from '../../utils/tools/cam_connect_type';


@Builder
export function RemoteControlBuilder() {
  RemoteControl();
}


@Component
export struct RemoteControl {




  // 同步全局连接状态（和CameraPage一样的响应式变量）
  @State currentState: ConnectionStateResult = { state: false, message: '未连接相机！' };
  @State previewPixelMap: PixelMap | null = null; // 预览帧
  @State previewRunning: boolean = false; // 预览运行状态
  @State previewImage: string = '';
  @State photoList: nativeCamera.PhotoPathInfo[] = [];
  @State currentPreviewInterval: number = 0;
  @State statusMessage: string = '请连接相机';

  // 参数状态（与弹窗绑定部分未改动）
  @State ISOValue: string = "NA";
  @State apertureValue: string = 'NA';
  @State shutterValue: string = "NA";
  @State paramList: ParamOption[] = [];
  @State exposureCompensationValue: string = "NA";
  @State meterModeValue: string = "NA";
  @State whiteBalanceValue: string = "NA";
  @State focusModeValue: string = "NA";
  @State exposureProgramValue: string = "NA";
  private timerId: number = -1; // 预览定时器ID
  private isProcessingPreview: boolean = false;
  // 1. 声明单例变量（用于存储通过getInstance()获取的实例）
  private camManager: CamConnectionManager | null = null;


  // 弹窗控制器
  // ISO 值选择弹窗
  isoDialogController: CustomDialogController = new CustomDialogController({
    builder: IsoDialog({ selectedISOValue: this.ISOValue }),
    customStyle: true,
    alignment: DialogAlignment.Center,
    offset: { dx: 0, dy: 0 }
  });
  // 光圈选择弹窗
  apertureDialogController:CustomDialogController = new CustomDialogController({
    builder:ApertureDialog({selectedApertureValue:this.apertureValue}),
    customStyle:true,
    alignment:DialogAlignment.Center,
    offset: { dx: 0, dy: 0 }
  })

  // 快门速度选择弹窗
  shutterDialogController: CustomDialogController = new CustomDialogController({
    builder: ShutterSpeedDialog({ SelectedShutterValue: this.shutterValue }),
    customStyle: true,
    alignment: DialogAlignment.Center,
    offset: { dx: 0, dy: 0 }
  });

  // 曝光补偿选项弹窗
  evDialogController:CustomDialogController = new CustomDialogController({
    builder:ExposureCompensationDialog({selected_EV_Value:this.exposureCompensationValue}),
    customStyle:true,
    alignment:DialogAlignment.Center,
    offset: { dx: 0, dy: 0 }
  })

  // 曝光补偿选项弹窗
  ExposureMode_DialogController:CustomDialogController = new CustomDialogController({
    builder:ExposureModeDialog({selected_ExposureMode_Value:this.exposureProgramValue}),
    customStyle:true,
    alignment:DialogAlignment.Center,
    offset: { dx: 0, dy: 0 }
  })

  // 对焦模式选择弹窗
  Focus_Mode_DialogController:CustomDialogController = new CustomDialogController({
    builder:FocusModeDialog({selected_Focus_Mode_Value:$focusModeValue}),
    customStyle: true,
    alignment: DialogAlignment.Center,
    offset: { dx: 0, dy: 0 }
  })

  // 测光模式选择弹窗
  ExposureMeterMode_DialogController:CustomDialogController = new CustomDialogController({
    builder:ExposureMeterModeDialog({selected_ExposureMeterMode_Value:this.meterModeValue}),
    customStyle: true,
    alignment: DialogAlignment.Center,
    offset: { dx: 0, dy: 0 }
  })

  // 白平衡选择弹窗
  whiteBalance_DialogController:CustomDialogController = new CustomDialogController({
    builder:WhiteBalanceDialog({selectedI_WB_Value:this.whiteBalanceValue}),
    customStyle: true,
    alignment: DialogAlignment.Center,
    offset: { dx: 0, dy: 0 }
  })







  aboutToAppear(): void {

    // 2. 通过静态方法获取实例（复用EntryAbility创建的单例）
    this.camManager = CamConnectionManager.getInstance();
    if (!this.camManager) {
      console.error("CameraPage 获取CamConnectionManager实例失败！");
      return;
    }


    // 🔥 1. 注册全局状态监听器（同步连接状态）
    this.camManager.addListener(this.handleGlobalStateChange);
    // 🔥 2. 初始化状态：从全局单例获取（首次加载用）
    this.currentState = this.camManager.getCurrentState();
    console.log(`RemoteControl 初始化状态：${JSON.stringify(this.currentState)}`);


    // 🔥 3. 参数管理同步全局连接状态（不再自己调用updateConnectionStatus）
    cameraParamManager.updateConnectionStatus(this.currentState.state);




    // 核心修改1：参数同步添加节流（1秒最多1次），避免频繁更新触发UI闪烁
    let lastSyncTime = 0;
    const throttleInterval = 1000; // 节流间隔：1秒
    cameraParamManager.addListener(() => {
      const now = Date.now();
      if (now - lastSyncTime > throttleInterval) { // 超过间隔才同步
        this.paramList = cameraParamManager.getParams();
        this.syncParamToUI();
        lastSyncTime = now;
      }
    });

    // 初始同步参数
    this.paramList = cameraParamManager.getParams();
    this.syncParamToUI();




  }

  aboutToDisappear(): void {
    cameraParamManager.removeListener(() => {
      // 保留原有逻辑
    });
  }


  // 🔥 新增：全局状态变化回调（同步到当前页面）
  private handleGlobalStateChange = (state: boolean, message: string) => {
    console.log(`RemoteControl 全局状态更新：state=${state}，message=${message}`);
    // 更新本地响应式变量，触发UI刷新
    this.currentState = { state, message };
    // 同步参数管理的连接状态（确保参数刷新逻辑正常）
    cameraParamManager.updateConnectionStatus(state);

    // 状态变化时的联动逻辑（原有）
    if (state) {
      // 已连接：启动预览
      this.startPreview();
    } else {
      // 已断开：停止预览
      this.stopPreview();
    }
  };






  /**
   * @function 同步相机参数到UI
   * */
  // 简化 syncParamToUI 方法，仅保留参数提取和直接赋值
  private syncParamToUI() {
    // ISO：直接用原始值（如"ISO 320"）
    const isoParam = this.paramList.find(p => p.name === 'iso');
    if (isoParam) {
      this.ISOValue = isoParam.currentValue;
    }

    // 光圈：直接用原始值（如"f/1"），移除 replace 格式化
    const apertureParam = this.paramList.find(p => p.name === 'aperture');
    if (apertureParam) {
      this.apertureValue = apertureParam.currentValue; // 不再替换为"F1"，直接显示"f/1"
    }

    // 快门：直接用原始值（如"1/125s"），移除解析匹配逻辑
    const shutterParam = this.paramList.find(p => p.name === 'shutter');
    if (shutterParam) {
      this.shutterValue = shutterParam.currentValue; // 不再处理，直接显示
    }

    // 曝光补偿：直接用原始值（如"0.0 档"），移除 formatExposureCompensation 转换
    const evParam = this.paramList.find(p => p.name === 'exposureCompensation');
    if (evParam) {
      this.exposureCompensationValue = evParam.currentValue;
    }

    // 曝光模式：直接用原始值（如"S（快门优先）"）
    const exposureProgramParam = this.paramList.find(p => p.name === 'exposureProgram');
    if (exposureProgramParam) {
      this.exposureProgramValue = exposureProgramParam.currentValue;
    }

    // 对焦模式：直接用原始值（如"连续自动对焦（AF-C）"）
    const focusModeParam = this.paramList.find(p => p.name === 'focusMode');
    if (focusModeParam) {
      this.focusModeValue = focusModeParam.currentValue; // 移除正则提取逻辑
    }

    // 测光模式：直接用原始值（如"点测光"）
    const meterModeParam = this.paramList.find(p => p.name === 'exposureMeterMode');
    if (meterModeParam) {
      this.meterModeValue = meterModeParam.currentValue;
    }

    // 白平衡：直接用原始值（如"自动"）
    const wbParam = this.paramList.find(p => p.name === 'whiteBalance');
    if (wbParam) {
      this.whiteBalanceValue = wbParam.currentValue;
    }
  }





  /**
   * @function 手动连接相机
   * */
  manualConnect() {
    if (!this.currentState.state) { // 未连接时才调用
      this.statusMessage = '正在连接相机...';
      if (this.camManager) {
        this.camManager.connectCamera().then((success) => {
          // 连接结果由全局状态回调处理，这里无需额外更新
          if (!success) {
            this.statusMessage = '连接失败，请检查WiFi';
          }
        });
      }
      }

  }




  /**
   * @function （仅优化定时器稳定性，未改核心逻辑）
   */
  startPreview() {
    if (this.previewRunning || !this.currentState.state) {
      return;
    }
    this.previewRunning = true;
    this.isProcessingPreview = false;

    const updateFrame = () => {
      if (!this.previewRunning) {
        this.timerId = -1;
        return;
      }

      if (this.isProcessingPreview) {
        this.timerId = setTimeout(updateFrame, 10);
        return;
      }

      this.updatePreview().then(() => {
        // 保持15FPS目标间隔
        this.timerId = setTimeout(updateFrame, 67);
      }).catch(() => {
        this.timerId = setTimeout(updateFrame, 67);
      });
    };

    this.timerId = setTimeout(updateFrame, 0);
    console.log('预览已启动（目标15FPS）');
  }


  /**
   * @function 停止预览
   * */
  stopPreview() {
    // 完全保留原有逻辑
    if (!this.previewRunning) {
      return;
    }
    this.previewRunning = false;
    if (this.timerId !== -1) {
      clearTimeout(this.timerId);
      this.timerId = -1;
    }
    if (this.previewPixelMap) {
      this.previewPixelMap.release().catch((e: Error) => {
        console.error('停止预览时释放资源失败:', e);
      });
      this.previewPixelMap = null;
    }
    this.isProcessingPreview = false;
    console.log('预览已停止');
  }


  /**
   * 核心修改2：预览帧更新逻辑优化
   * 1. 先创建新帧再释放旧帧，避免空白期
   * 2. 减少预览帧更新对UI的冲击
   */
  async updatePreview() {
    const startTime = Date.now();
    this.isProcessingPreview = true;
    try {
      if (!nativeCamera.IsCameraConnected()) {
        console.warn('相机已断开连接，停止预览');
        this.stopPreview();
        return;
      }

      // 获取预览数据（保留原有逻辑）
      const arrayBuffer: ArrayBuffer = nativeCamera.GetPreview();
      if (!arrayBuffer || !(arrayBuffer instanceof ArrayBuffer)) {
        console.error('GetPreview返回无效的ArrayBuffer');
        return;
      }
      const buffer = new Uint8Array(arrayBuffer);
      if (buffer.length === 0) {
        console.warn('无效的预览数据，长度为0');
        return;
      }

      // 核心优化：先创建新的PixelMap，再处理旧帧
      const srcOps: image.SourceOptions = {
        sourceDensity: 0,
        //format: image.Format.JPEG // 明确格式加速解码（新增）
      };
      const imgSrc: image.ImageSource = image.createImageSource(
        buffer.buffer as ArrayBuffer,
        srcOps
      );
      if (!imgSrc) {
        console.error('创建ImageSource失败');
        return;
      }

      // 1. 先创建新帧（临时变量存储）
      const newPixelMap: image.PixelMap = await imgSrc.createPixelMap();
      // 2. 保存旧帧引用
      const oldPixelMap = this.previewPixelMap;
      // 3. 直接更新预览帧（无空白期）
      this.previewPixelMap = newPixelMap;
      // 4. 延迟释放旧帧（确保新帧已渲染）
      if (oldPixelMap) {
        setTimeout(() => {
          oldPixelMap.release().catch((e:Error) => console.error('释放旧帧失败:', e));
        }, 100); // 延迟100ms释放，避免新帧未渲染完成
      }

      const frameTime = Date.now() - startTime;
      console.log(`单帧处理耗时：${frameTime}ms，目标67ms`);

    } catch (e) {
      console.error('预览处理异常:', e);
      this.stopPreview();
      this.statusMessage = '预览异常: ' + (e instanceof Error ? e.message : String(e));
    } finally {
      this.isProcessingPreview = false;
    }
  }




  getCameraInfo() {
    // 完全保留原有逻辑
    try {
      const camInfo = nativeCamera.GetCameraStatus();
      console.log("相机连接状态：", camInfo.isSuccess);
      console.log("电量：", camInfo.batteryLevel);
      console.log("当前光圈：", camInfo.aperture);
      console.log("当前快门：", camInfo.shutter);
      console.log("当前ISO：", camInfo.iso);
      console.log("曝光补偿：", camInfo.exposureCompensation + "EV");
      console.log("白平衡：", camInfo.whiteBalance);
      console.log("拍摄模式：", camInfo.captureMode);
      console.log("剩余可拍张数：", camInfo.remainingPictures);
      console.log("曝光模式", camInfo.exposureProgram);
      console.log(`对焦模式：${camInfo.focusMode}`);
      console.log(`测光模式：${camInfo.exposureMeterMode}`);
    } catch (e) {
      console.error("获取相机信息失败：", e);
    }
  }

  parseShutterToSeconds(shutterStr: string): number | null {
    // 完全保留原有逻辑
    const str = shutterStr.replace(/s$/i, '').trim();
    if (str.includes('/')) {
      const parts = str.split('/').map(Number);
      const numerator = parts[0];
      const denominator = parts[1];
      if (!isNaN(numerator) && !isNaN(denominator) && denominator !== 0) {
        return numerator / denominator;
      }
    }
    const num = parseFloat(str);
    return isNaN(num) ? null : num;
  }





  /**
   * @description 构建相机参数控制按钮的UI组件
   * 用于统一渲染相机各项参数（如ISO、光圈、快门等）的控制按钮，包含参数标签和当前值展示
   * @param {string} label - 参数标签文本（如"ISO"、"光圈"，用于标识参数类型）
   * @param {string} value - 参数当前值（如"100"、"F2.8"，展示当前参数的设定值）
   * @param {() => void} onClick - 点击按钮时的回调函数（通常用于打开对应参数的设置弹窗）
   * @returns 包含标签文本和参数值按钮的Column布局组件，统一参数控制按钮的样式和交互逻辑
   */
  @Builder
  private buildParamButton(label: string, value: string, onClick: () => void) {
    Column({ space: 4 }) {
      Text(label)
        .fontSize(12)
        .fontColor('#666') // 浅色标签区分主次
        .width('100%')
        .textAlign(TextAlign.Center)

      Button(value)
        .fontSize(6)
        .height(36)
        .width('100%') // 自适应网格宽度
      //  .backgroundColor('#f5f5f5')
        .fontColor('#333')
        .borderRadius(6)
        .onClick(onClick)
    }
    .padding({ left: 4, right: 4 })
  }







  // 构建UI（完全保留原有结构，未改动）
  build() {
    NavDestination() {
      Column() {

        // 顶部控制区域
        Column({ space: 10 }) {
          Row({ space: 10 }) {
            Button('配置打印')
              .onClick(() => {
                this.getCameraInfo()
              })


            Button('手动连接相机')
              .onClick(() => {
                this.manualConnect();
              })
              .enabled(!this.currentState.state)

          }


          // 连接状态指示
          Row({ space: 10 }) {
            Text(this.currentState.message)
              .fontSize(18)

            Circle()
              .borderRadius(12)
              .width(24)
              .height(24)
              .fill(this.currentState.state ? '#00C853' : '#F44336')
              .shadow({
                radius: 8,
                color: this.currentState.state ? 'rgba(0, 200, 83, 0.6)' : 'rgba(244, 67, 54, 0.6)',
                offsetX: 0,
                offsetY: 0
              })
              .animation({ duration: 300 });
          }
        }
        .margin({ top: 10 })



        /**
         * @description 预览画面显示区域
         * */
        Column() {
          if (this.previewPixelMap) {
            Image(this.previewPixelMap)
              .width('100%')
              .height(250)
              .objectFit(ImageFit.Contain)
          } else if (!this.previewRunning) {
            Text('未启动预览')
              .width('100%')
              .height(250)
              .backgroundColor(Color.Black)
              .fontColor(Color.White)
              .fontSize(16)
              .textAlign(TextAlign.Center)
          }
        }
        .margin({ top: 10 })




        // 参数控制栏
        Column() {
          // 第一组：曝光核心参数（ISO、光圈、快门、曝光补偿）
          Grid(){
            GridItem(){this.buildParamButton('ISO',this.ISOValue,()=>{this.isoDialogController.open()})}
            GridItem(){ this.buildParamButton('光圈', this.apertureValue, () => {this.apertureDialogController.open()}) }
            GridItem() { this.buildParamButton('快门', this.shutterValue, () =>{this.shutterDialogController.open()} ) }
            GridItem() { this.buildParamButton('曝光补偿', this.exposureCompensationValue, () => { this.evDialogController.open() }) }
          }
          .columnsTemplate('1fr 1fr 1fr 1fr') // 4列网格
          .columnsGap(8)
          .padding(10)
          .height(80)  // 固定第一组网格高度（按钮36 + 间距 + 内边距）
          .backgroundColor('#f9f9f9')  // 可选：添加背景色区分区域
          .borderRadius(8)

          // 第二组：拍摄模式参数（曝光模式、对焦模式）
          Grid() {
            GridItem() { this.buildParamButton('曝光模式', this.exposureProgramValue, () =>{this.ExposureMode_DialogController.open() } ) }
            GridItem() { this.buildParamButton('对焦模式', this.focusModeValue, () => {this.Focus_Mode_DialogController.open() }) }
            GridItem() { this.buildParamButton('测光模式', this.meterModeValue, () => {this.ExposureMeterMode_DialogController.open() }) }
            GridItem() { this.buildParamButton('白平衡', this.whiteBalanceValue, () => {this.whiteBalance_DialogController.open() }) }
          }
          .columnsTemplate('1fr 1fr 1fr 1fr')
          .columnsGap(8)
          .padding(10)
          .height(80)  // 固定第二组网格高度
          .backgroundColor('#f9f9f9')
          .borderRadius(8)
          .margin({ top: 8 })  // 两组之间添加间距


        }
        .width("100%")
        .padding({ left: 10, right: 10 })  // 左右留边，避免内容贴边




        /**
         * @function 预览按钮区域
         * */
        Row({ space: 10 }) {
          Button('启动预览')
            .enabled(!this.previewRunning)
            .onClick(() => this.startPreview())

          Button('停止预览')
            .enabled(this.previewRunning)
            .onClick(() => this.stopPreview())
        }
        .margin({ top: 10 })


        /**
         *@function 拍照按钮区域
         * */
        Row({ space: 10 }) {
          Button('图库')
          Button('拍照')
            .onClick(() => {
              //this.takeAndDownloadKnown()
            })
        }
        .margin({ top: 20 })
      }
      .width("100%")
      .height("100%")
    }
    .title('遥控拍照')
  }
}