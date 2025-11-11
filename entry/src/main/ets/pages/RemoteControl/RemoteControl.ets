import nativeCamera from 'libentry.so'
import { IsoDialog } from 'ets/component/CameraControlDialog/IsoDialog'
import { ShutterSpeedDialog } from 'ets/component/CameraControlDialog/ShutterSpeedDialog'
import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit'
import { common } from '@kit.AbilityKit';
import getCamIpAndName from '../../utils/GetCameraIpAndName'
import { cameraParamManager, ParamOption } from '../../utils/CameraParamManager'
import { ApertureDialog } from '../../component/CameraControlDialog/ApertureDialog';
import { FocusModeDialog } from '../../component/CameraControlDialog/FocusModeDialog';
import { ExposureCompensationDialog } from '../../component/CameraControlDialog/ExposureCompensationDialog';
import { WhiteBalanceDialog } from '../../component/CameraControlDialog/WhiteBalanceDialog';
import { ExposureMeterModeDialog } from '../../component/CameraControlDialog/ExposureMeterModeDialog';
import { ExposureModeDialog } from '../../component/CameraControlDialog/ExposureModeDialog';


const scanner = new getCamIpAndName();
let cameraIp: string;


const evMap: Record<string, string> = {
  "-2": "-2",
  "-1.666": "-1 2/3",
  "-1.333": "-1 1/3",
  "-1": "-1",
  "-0.666": "-2/3",
  "-0.333": "-1/3",
  "0": "0",
  "0.333": "+1/3",
  "0.666": "+2/3",
  "1": "+1",
  "1.333": "+1 1/3",
  "1.666": "+1 2/3",
  "2": "+2"
};


interface ShutterOptionSec {
  original: string;
  sec: number | null;
}


@Builder
export function RemoteControlBuilder() {
  RemoteControl();
}


@Component
export struct RemoteControl {



  // 连接状态检查定时器ID
  private connectionCheckTimer: number = -1;

  // 状态管理
  @State isConnected: boolean = false;
  @State connectStatus: string = '未连接相机';
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

  private nativeLibDir: string = '';
  private timerId: number = -1; // 预览定时器ID
  private isProcessingPreview: boolean = false;

  // 弹窗控制器
  // ISO 值选择弹窗
  isoDialogController: CustomDialogController = new CustomDialogController({
    builder: IsoDialog({ selectedISOValue: this.ISOValue }),
    customStyle: true,
    alignment: DialogAlignment.Center,
    offset: { dx: 0, dy: 40 }
  });
  // 光圈选择弹窗
  apertureDialogController:CustomDialogController = new CustomDialogController({
    builder:ApertureDialog({selectedApertureValue:this.apertureValue}),
    customStyle:true,
    alignment:DialogAlignment.Center,
    offset: { dx: 0, dy: 40 }
  })

  // 快门速度选择弹窗
  shutterDialogController: CustomDialogController = new CustomDialogController({
    builder: ShutterSpeedDialog({ SelectedShutterValue: this.shutterValue }),
    customStyle: true,
    alignment: DialogAlignment.Center,
    offset: { dx: 0, dy: 40 }
  });

  // 曝光补偿选项弹窗
  evDialogController:CustomDialogController = new CustomDialogController({
    builder:ExposureCompensationDialog({selected_EV_Value:this.exposureCompensationValue}),
    customStyle:true,
    alignment:DialogAlignment.Center,
    offset: { dx: 0, dy: 40 }
  })

  // 曝光补偿选项弹窗
  ExposureMode_DialogController:CustomDialogController = new CustomDialogController({
    builder:ExposureModeDialog({selected_ExposureMode_Value:this.exposureProgramValue}),
    customStyle:true,
    alignment:DialogAlignment.Center,
    offset: { dx: 0, dy: 40 }
  })

  // 对焦模式选择弹窗
  Focus_Mode_DialogController:CustomDialogController = new CustomDialogController({
    builder:FocusModeDialog({selected_Focus_Mode_Value:$focusModeValue}),
    customStyle: true,
    alignment: DialogAlignment.Center,
    offset: { dx: 0, dy: 40 }
  })

  // 测光模式选择弹窗
  ExposureMeterMode_DialogController:CustomDialogController = new CustomDialogController({
    builder:ExposureMeterModeDialog({selected_ExposureMeterMode_Value:this.meterModeValue}),
    customStyle: true,
    alignment: DialogAlignment.Center,
    offset: { dx: 0, dy: 40 }
  })

  // 白平衡选择弹窗
  whiteBalance_DialogController:CustomDialogController = new CustomDialogController({
    builder:WhiteBalanceDialog({selectedI_WB_Value:this.whiteBalanceValue}),
    customStyle: true,
    alignment: DialogAlignment.Center,
    offset: { dx: 0, dy: 40 }
  })







  aboutToAppear(): void {
    this.checkConnection();

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

    this.startConnectionCheck();





  }

  aboutToDisappear(): void {
    cameraParamManager.removeListener(() => {
      // 保留原有逻辑
    });
    this.stopConnectionCheck();
  }




  /**
   * @function 开始检测连接状态
   * */
  private startConnectionCheck() {
    this.connectionCheckTimer = setInterval(() => {
      if (this.isConnected) {
        this.checkConnection();
      }
    }, 3000);
  }

  /**
   *  @function 停止检测连接状态
   * */
  private stopConnectionCheck() {
    if (this.connectionCheckTimer !== -1) {
      clearInterval(this.connectionCheckTimer);
      this.connectionCheckTimer = -1;
    }
  }




  /**
   * @function 同步相机参数到UI
   * */
  private syncParamToUI() {
    const isoParam = this.paramList.find(p => p.name === 'iso');
    if (isoParam) {
      this.ISOValue = isoParam.currentValue;
    }

    const shutterParam = this.paramList.find(p => p.name === 'shutter');
    if (shutterParam) {
      const currentShutterSec = this.parseShutterToSeconds(shutterParam.currentValue);
      if (currentShutterSec === null) {
        console.warn('快门值解析失败，原始值:', shutterParam.currentValue);
        return;
      }

      const shutterOptionsSec = shutterParam.options.map<ShutterOptionSec>(option => ({
        original: option,
        sec: this.parseShutterToSeconds(option)
      })).filter(item => item.sec !== null);

      const matchedOption = shutterOptionsSec.find(item =>
      Math.abs(item.sec as number - currentShutterSec) < 0.001
      );

      if (matchedOption) {
        this.shutterValue = matchedOption.original;
      } else {
        this.shutterValue = shutterParam.currentValue;
      }
    }

    const apertureParam = this.paramList.find(p => p.name === 'aperture');
    if (apertureParam) {
      const apertureDisplay = apertureParam.currentValue.replace(/f\//i, 'F');
      this.apertureValue = apertureDisplay;
    }

    const evParam = this.paramList.find(p => p.name === 'exposureCompensation');
    if (evParam) {
      this.exposureCompensationValue = this.formatExposureCompensation(evParam.currentValue);
    }

    const meterModeParam = this.paramList.find(p => p.name === 'exposureMeterMode');
    if (meterModeParam) {
      this.meterModeValue = meterModeParam.currentValue;
    }

    const wbParam = this.paramList.find(p => p.name === 'whiteBalance');
    if (wbParam) {
      this.whiteBalanceValue = wbParam.currentValue;
    }

    const focusModeParam = this.paramList.find(p => p.name === 'focusMode');
    if (focusModeParam) {
      const match = focusModeParam.currentValue.match(/[（(](.*?)[）)]/);
      this.focusModeValue = match ? match[1] : focusModeParam.currentValue.slice(-4).trim();
    }

    const exposureProgramParam = this.paramList.find(p => p.name === 'exposureProgram');
    if (exposureProgramParam) {
      const programAbbr = exposureProgramParam.currentValue.split('（')[0];
      this.exposureProgramValue = programAbbr;
    }
  }





  /**
   * @function 手动连接相机
   * */
  manualConnect() {
    // 完全保留原有逻辑
    const success = nativeCamera.ConnectCamera("Nikon Zf", "ptpip:192.168.1.1");
    cameraParamManager.updateConnectionStatus(success);
    this.isConnected = success;
    this.connectStatus = success ? '相机已连接' : '连接失败，请检查WiFi';
  }

  /**
   * @function 连接状态检测
   * */
  checkConnection() {
    // 完全保留原有逻辑
    const connected = nativeCamera.IsCameraConnected();
    if (connected !== this.isConnected) {
      cameraParamManager.updateConnectionStatus(connected);
      this.isConnected = connected;
      this.connectStatus = connected ? '相机已连接' : '未连接，请检查是否连接相机WiFi';
    }
  }


  /**
   * @function （仅优化定时器稳定性，未改核心逻辑）
   */
  startPreview() {
    if (this.previewRunning || !this.isConnected) {
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


  takeAndDownloadKnown() {
    // 完全保留原有逻辑
    try {
      const ok = nativeCamera.TakePhoto();
      if (!ok) {
        this.statusMessage = '拍照失败';
        return;
      }

      const folder = "DCIM/100CANON";
      const filename = "IMG_0001.JPG";
      const arrBuf: ArrayBuffer = nativeCamera.DownloadPhoto(folder, filename);
      if (!arrBuf) {
        this.statusMessage = '下载失败';
        return;
      }

      const context = getContext(this) as common.UIAbilityContext;
      const savePath = `${context.filesDir}/${filename}`;
      const fdAny = fileIo.openSync(savePath, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE);
      const uint8Arr = new Uint8Array(arrBuf);

      if (typeof fdAny === 'number') {
        fileIo.writeSync(fdAny, uint8Arr);
        fileIo.closeSync(fdAny);
      } else {
        fileIo.writeSync(fdAny.fd, uint8Arr);
        fileIo.closeSync(fdAny);
      }

      this.previewImage = savePath;
      this.photoList.push({ folder: savePath, name: filename });
      this.statusMessage = '拍照并保存成功';
    } catch (e) {
      console.error("异常: " + JSON.stringify(e));
      this.statusMessage = '拍照下载异常';
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


  private formatExposureCompensation(value: string): string {
    // 完全保留原有逻辑
    const num = parseFloat(value);
    if (isNaN(num)) {
      return 'NA';
    }
    const closestKey = Object.keys(evMap).find(key => {
      return Math.abs(parseFloat(key) - num) < 0.001;
    });
    return closestKey ? `${evMap[parseFloat(closestKey)]}` : `${num}`;
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
        .fontSize(14)
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
              .enabled(!this.isConnected)

          }


          // 连接状态指示
          Row({ space: 10 }) {
            Text(this.connectStatus)
              .fontSize(18)

            Circle()
              .borderRadius(12)
              .width(24)
              .height(24)
              .fill(this.isConnected ? '#00C853' : '#F44336')
              .shadow({
                radius: 8,
                color: this.isConnected ? 'rgba(0, 200, 83, 0.6)' : 'rgba(244, 67, 54, 0.6)',
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
              this.takeAndDownloadKnown()
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