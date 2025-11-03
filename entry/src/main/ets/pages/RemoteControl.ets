
import nativeLibGphoto from 'libentry.so'
import { IsoDialog } from 'ets/component/CameraControlDialog/IsoDialog'
import { ShutterSpeedDialog } from 'ets/component/CameraControlDialog/ShutterSpeedDialog'
import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit'
import { common } from '@kit.AbilityKit';
import getCamIpAndName from '../utils/GetCameraIpAndName'
import { cameraParamManager,ParamOption  } from '../utils/CameraParamManager'


const scanner = new getCamIpAndName();
let cameraIp:string



const evMap:Record<string,string>={
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
}


interface ShutterOptionSec {
  original: string;
  sec: number | null;
}

@Preview
@Component
export struct RemoteControl {
  @Consume('pageStack') pageStack: NavPathStack;


  // 新增：连接状态检查定时器ID
  private connectionCheckTimer: number = -1;


  // 状态管理
  // 连接状态
  @State isConnected: boolean = false;
  @State connectStatus: string = '未连接相机';
  // 用来存放预览视频帧
  @State previewPixelMap: PixelMap | null = null
  @State previewRunning: boolean = false; // 当前是否在预览
  private timerId: number = -1; // 定时器ID
  @State previewImage: string = '';
  @State photoList: nativeLibGphoto.PhotoPathInfo[] = [];
  @State currentPreviewInterval: number = 0;
  @State statusMessage: string = '请连接相机';
  @State isoValue: string = '100';
  // 当前ISO值，与浮窗双向绑定
  @State ISOValue: string = "100"
  // record current aperture value
  @State apertureValue: string  = ''
  // record current shutter value
  @State shutterValue: string = "1/200"
  // 新增：用于UI展示的参数列表（从参数管理器获取）
  @State paramList: ParamOption[] = [];

  // 新增：曝光补偿、测光模式、白平衡、对焦模式的状态变量
  @State exposureCompensationValue: string = "NA"; // 曝光补偿
  @State meterModeValue: string = "NA"; // 测光模式
  @State whiteBalanceValue: string = "NA"; // 白平衡
  @State focusModeValue: string = "NA"; // 对焦模式
  @State exposureProgramValue: string = "NA"; // 曝光模式（P/A/S/M等）



  private nativeLibDir: string = '';



  // ISO弹窗控制器：正确传递双向绑定参数
  isoDialogController: CustomDialogController = new CustomDialogController({
    builder: IsoDialog({ selectedISO: this.ISOValue }), // bind dialog component
    customStyle: true,
    alignment: DialogAlignment.Center
  })
  // shutter 弹窗控制器
  shutterDialogController: CustomDialogController = new CustomDialogController({
    builder: ShutterSpeedDialog({ SelectedShutter: this.shutterValue }), // bind dialog component
    customStyle: true,
    alignment: DialogAlignment.Center
  })




  aboutToAppear(): void {
    this.checkConnection()


    // 注册参数变化监听器（关键步骤）
    cameraParamManager.addListener(() => {
      // 当参数更新时，同步到页面状态
      this.paramList = cameraParamManager.getParams();
      // 同步具体参数到UI（如ISO、快门等）
      this.syncParamToUI();
    });

    // 初始同步一次参数
    this.paramList = cameraParamManager.getParams();
    this.syncParamToUI();


    // 启动连接状态定时检查（每3秒一次）
    this.startConnectionCheck();

  }

  // 页面销毁时移除监听器，避免内存泄漏
  aboutToDisappear(): void {
    cameraParamManager.removeListener(() => {
      // 这里需要传入与注册时相同的函数引用，实际开发中建议用命名函数
    });

    // 停止连接状态检查定时器
    this.stopConnectionCheck();
  }








  // 启动连接状态定时检查
  private startConnectionCheck() {
    this.connectionCheckTimer = setInterval(() => {
      // 仅在当前标记为已连接时才检查（优化性能）
      if (this.isConnected) {
        this.checkConnection();
      }
    }, 3000); // 3秒检查一次
  }

  // 停止连接状态检查
  private stopConnectionCheck() {
    if (this.connectionCheckTimer !== -1) {
      clearInterval(this.connectionCheckTimer);
      this.connectionCheckTimer = -1;
    }
  }





  // 将参数管理器的参数同步到页面UI状态
  private syncParamToUI() {
    //console.log('开始同步参数到UI，当前paramList:', JSON.stringify(this.paramList));

    const isoParam = this.paramList.find(p => p.name === 'iso');
    if (isoParam) {
      this.ISOValue = isoParam.currentValue; // 同步ISO值到页面状态
     // console.log('同步ISO值:', this.ISOValue);
    }

    // 同步快门速度值
    const shutterParam = this.paramList.find(p => p.name === 'shutter');
    if (shutterParam) {
      // 转换当前值为秒数（如"0.6s" → 0.6）
      const currentShutterSec = this.parseShutterToSeconds(shutterParam.currentValue);
      if (currentShutterSec === null) {
        console.warn('快门值解析失败，原始值:', shutterParam.currentValue);
        return;
      }

      // 转换选项中的值为秒数，用于匹配（如"1/1000" → 0.001）
      const shutterOptionsSec = shutterParam.options.map<ShutterOptionSec>(option => ({
        original: option,
        sec: this.parseShutterToSeconds(option)
      })).filter(item => item.sec !== null);

      // 检查当前值是否在选项中（允许微小精度误差，如0.333和1/3）
      const matchedOption = shutterOptionsSec.find(item =>
      Math.abs(item.sec as number - currentShutterSec) < 0.001 // 类型断言为number
      );

      if (matchedOption) {
      //  console.log('快门值匹配成功:', matchedOption.original);
        this.shutterValue = matchedOption.original; // 用选项中的原始格式显示
      } else {
      //  console.log('快门值未在选项中，使用原始值:', shutterParam.currentValue);
        this.shutterValue = shutterParam.currentValue;
      }
    }

    // 同步光圈值
    const apertureParam = this.paramList.find(p => p.name === 'aperture');
    if (apertureParam) {
      const apertureDisplay = apertureParam.currentValue.replace(/f\//i, 'F');
      this.apertureValue = apertureDisplay; // 现在类型匹配
     // console.log('光圈显示值:', this.apertureValue);
    }


    // 新增：同步曝光补偿
    const evParam = this.paramList.find(p => p.name === 'exposureCompensation');
    if (evParam) {
      this.exposureCompensationValue = this.formatExposureCompensation(evParam.currentValue);
    }

    // 新增：同步测光模式（注意参数名与相机返回一致，日志中为"exposureMeterMode"）
    const meterModeParam = this.paramList.find(p => p.name === 'exposureMeterMode');
    if (meterModeParam) {
      this.meterModeValue = meterModeParam.currentValue; // 显示如"Multi Spot"
    }



    // 新增：同步白平衡
    const wbParam = this.paramList.find(p => p.name === 'whiteBalance');
    if (wbParam) {
      this.whiteBalanceValue = wbParam.currentValue; // 显示如"Automatic"
    }

    // 新增：同步对焦模式（注意参数名与相机返回一致，日志中为"focusMode"）（提取英文缩写）
    const focusModeParam = this.paramList.find(p => p.name === 'focusMode');
    if (focusModeParam) {
      // 使用正则表达式提取括号中的英文部分（如从"连续自动对焦（AF-C）"中提取"AF-C"）
      const match = focusModeParam.currentValue.match(/[（(](.*?)[）)]/);

      // 若匹配失败，直接截取最后3-4个字符（适用于"AF-S"、"AF-C"等固定长度）
      this.focusModeValue = match ? match[1] : focusModeParam.currentValue.slice(-4).trim();
    }


    // 新增，同步曝光模式
    const exposureProgramParam = this.paramList.find(p => p.name === 'exposureProgram');
    if (exposureProgramParam) {
      // 从"P（程序自动）"中提取"P"，从"A（光圈优先）"中提取"A"等
      const programAbbr = exposureProgramParam.currentValue.split('（')[0];
      this.exposureProgramValue = programAbbr;
    }
  }
/**
 * @function 自动连接相机
 * */
  // 自动连接相机（修改版，可选）
  autoDetectCamera() {
    const cameraList = nativeLibGphoto.GetAvailableCameras();
    if (cameraList.length === 0) {
      this.connectStatus = '未连接到相机';
      cameraParamManager.updateConnectionStatus(false); // 同步断开状态
      return;
    }
    const GeneratedDestructArray_1 = cameraList[0].split('|');
    const model = GeneratedDestructArray_1[0];
    const path = GeneratedDestructArray_1[1];
    const isConnected = nativeLibGphoto.ConnectCamera(model, path);
    if (isConnected) {
      this.connectStatus = '相机连接成功';
      cameraParamManager.updateConnectionStatus(true); // 同步成功状态
    } else {
      cameraParamManager.updateConnectionStatus(false); // 同步失败状态
    }
  }





  /**
   * @function 手动连接相机
   * */
  manualConnect() {
    // 这里假设型号和路径是固定的
    const success = nativeLibGphoto.ConnectCamera("Nikon Zf", "ptpip:192.168.1.1");
    // 同步状态到参数管理器（关键步骤）
    cameraParamManager.updateConnectionStatus(success);

    // 更新页面自身状态
    this.isConnected = success;
    this.connectStatus = success ? '相机已连接' : '连接失败，请检查WiFi';
  }

  /**
   * @function 检查连接状态
   * */
  checkConnection() {
    const connected = nativeLibGphoto.IsCameraConnected();
    // 若状态发生变化，同步到参数管理器
    if (connected !== this.isConnected) {
      cameraParamManager.updateConnectionStatus(connected);
      this.isConnected = connected;
      this.connectStatus = connected ? '相机已连接' : '未连接，请检查是否连接相机WiFi';
    }
  }

  /**
   * @function 启动预览
   * */
  startPreview() {
    if (this.previewRunning || !this.isConnected) {
      return;
    }
    this.previewRunning = true;
    this.timerId = setInterval(() => {
      this.updatePreview();
    }, 500); // 500ms一帧，平衡流畅度和性能
    console.log('预览已启动');
  }

  /**
   * @function 停止预览
   * */
  stopPreview() {
    if (!this.previewRunning) {
      return;
    }
    clearInterval(this.timerId);
    this.timerId = -1;
    this.previewRunning = false;
    this.previewPixelMap = null;
    console.log('预览已停止');
  }

  /**
   * @function 拉取一帧预览
   * */
  async updatePreview() {
    try {
      const buffer: Uint8Array = nativeLibGphoto.GetPreview();
      if (!buffer || buffer.length === 0) {
        console.warn('预览数据为空');
        return;
      }

      // 移除不兼容的format属性，由系统自动识别图像格式
      const srcOps: image.SourceOptions = {
        sourceDensity: 0
      };

      const imgSrc: image.ImageSource = image.createImageSource(buffer.buffer as ArrayBuffer, srcOps);
      const pixelMap: image.PixelMap = await imgSrc.createPixelMap();
      this.previewPixelMap = pixelMap;
    } catch (e) {
      console.error('预览解码失败:', e);
      this.stopPreview();
      this.statusMessage = '预览异常，请检查相机连接';
    }
  }

  /**
   * 拍照逻辑
   * */
  async takeAndDownloadKnown() {
    try {
      const ok = nativeLibGphoto.TakePhoto();
      if (!ok) {
        this.statusMessage = '拍照失败';
        return;
      }

      // 临时写死文件夹和文件名
      const folder = "DCIM/100CANON";
      const filename = "IMG_0001.JPG";

      const arrBuf: ArrayBuffer = nativeLibGphoto.DownloadPhoto(folder, filename);
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
        const uint8Arr = new Uint8Array(arrBuf);

        // File 对象写法（不要调用 fdAny.writeSync/closeSync）
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




  /**
   * 配置打印
   * */

  async  getCameraInfo() {
  try {
    // 调用Native接口，返回包含所有信息的对象
    const camInfo = nativeLibGphoto.GetCameraStatus();

    // 解析信息（示例）
    console.log("相机连接状态：", camInfo.isSuccess);
    console.log("电量：", camInfo.batteryLevel);
    console.log("当前光圈：", camInfo.aperture);
    console.log("当前快门：", camInfo.shutter);
    console.log("当前ISO：", camInfo.iso);
    console.log("曝光补偿：", camInfo.exposureCompensation + "EV");
    console.log("白平衡：", camInfo.whiteBalance);
    console.log("拍摄模式：", camInfo.captureMode);
    //console.log("剩余空间：", (camInfo.freeSpaceBytes / 1024 / 1024).toFixed(2) + "MB");
    console.log("剩余可拍张数：", camInfo.remainingPictures);
    console.log("曝光模式",camInfo.exposureProgram);
    console.log(`对焦模式：${camInfo.focusMode}`);       // 如"连续自动对焦（AF-C）"
    console.log(`测光模式：${camInfo.exposureMeterMode}`); // 如"矩阵测光"

  } catch (e) {
    console.error("获取相机信息失败：", e);
  }
}





  // 在 FilePage 中新增曝光补偿格式转换函数
  private formatExposureCompensation(value: string): string {
    const num = parseFloat(value);
    if (isNaN(num)) {
      return 'NA';
    }

    // 查找最接近的映射值
    const closestKey = Object.keys(evMap).find(key => {
      return Math.abs(parseFloat(key) - num) < 0.001;
    });

    // 返回转换后的值（带EV单位）
    return closestKey ? `${evMap[parseFloat(closestKey)]}` : `${num}`;
  }





  /**
   * 将快门速度字符串转为秒数（数值）
   * @param shutterStr 快门速度字符串（如"1/1000"、"0.6s"、"2s"）
   * @returns 对应的秒数（如0.001、0.6、2）
   */
  parseShutterToSeconds(shutterStr: string): number | null {
  // 移除可能的单位"s"
  const str = shutterStr.replace(/s$/i, '').trim();
  // 处理分数形式（如"1/1000"）
  if (str.includes('/')) {
    const parts = str.split('/').map(Number);
    const numerator = parts[0];
    const denominator = parts[1];
    if (!isNaN(numerator) && !isNaN(denominator) && denominator !== 0) {
      return numerator / denominator;
    }
  }
  // 处理小数/整数形式（如"0.6"、"2"）
  const num = parseFloat(str);
  return isNaN(num) ? null : num;
}










  //###############################################################################
  //          Build Area
  //###############################################################################


  build() {
    NavDestination(){
      Column() {
        // 功能测试区
        Column({ space: 10 }) {
          Row({space:10}){
            Button('配置打印')
              .onClick(() => {
                this.getCameraInfo()
              })

            Button('检测相机')
              .onClick(() => {
                this.checkConnection()
              })

          }


          Row({space:10}){
            Button('手动连接相机')
              .onClick(() => {
                this.manualConnect(); // 点击触发手动连接
              })
              .enabled(!this.isConnected) // 连接中时禁用按钮


            Button('IP测试')
              .onClick(async ()=>{
                /*let camIP = await scanner.getLocalSubnet()
                if (camIP!=null) {
                  scanner.getCameraName(camIP)
                }*/

              })
          }

          Row({space:10}){
            Text(this.connectStatus)
              .fontSize(18)

            // LED灯
            Circle()
              .borderRadius(12) // 圆角为宽度的一半，确保正圆
              .width(24) // 设置宽度为24vp
              .height(24) // 高度与宽度一致，形成正圆
              .fill(this.isConnected ? '#00C853' : '#F44336') //绿色=已连接 ，红色=未连接
              // 阴影效果增强发光感
              .shadow({
                radius:8, //阴影模糊半径
                color: this.isConnected ? 'rgba(0, 200, 83, 0.6)' : 'rgba(244, 67, 54, 0.6)', // 阴影颜色与主体一致，降低透明度
                offsetX: 0,
                offsetY:0
              })
              .animation({duration:300}); //颜色切换添加300ms过度
          }



        }
        .margin({ top: 10 })

        Column() {
          if (this.previewPixelMap) {
            Image(this.previewPixelMap)
              .width('100%')
              .height(250)
              .objectFit(ImageFit.Contain)
          } else {
            Text(this.previewRunning ? '正在加载预览...' : '未启动预览')
              .width('100%')
              .height(250)
              .backgroundColor(Color.Black)
              .fontColor(Color.White)
              .fontSize(16)
              .textAlign(TextAlign.Center)
          }
        }
        .margin({ top: 10 })


        /**
         * 参数控制栏
         * */
        Column(){

          // 第一排参数设置
          Row({ space: 10 }) {

            Column() {
              Text("ISO")
                .fontSize(12)

              Button(this.ISOValue.toString())
                .fontSize(12)
                .height(18)
                .width(70)
                .onClick(() => this.isoDialogController.open())

            }

            Column() {
              Text("Aperture")
                .fontSize(12)
              Button(this.apertureValue.toString())
                .fontSize(12)
                .height(18)
                .width(70)
                // 可选：添加点击事件打开光圈设置弹窗
                .onClick(() => {
                  // this.apertureDialogController.open();
                })
            }

            Column() {
              Text("Shutter")
                .fontSize(12)
              Button(this.shutterValue.toString())
                .fontSize(12)
                .height(18)
                .width(70)
                .onClick(() => {
                  this.shutterDialogController.open()
                })
            }

            Column() {
              Text("EV")
                .fontSize(12)
              Button(this.exposureCompensationValue) // 绑定曝光补偿值（如"0EV"）
                .fontSize(12)
                .height(18)
                .width(70)
                .onClick(() => {
                  // 可选：打开曝光补偿设置弹窗
                })
            }



          }
          .width("100%")
          .padding(10)


          // 第二排参数设置
          Row({ space: 10 }) {
            Column() {
              Text("AF_MODE")
                .fontSize(12)
              Button(this.focusModeValue) // 绑定对焦模式（如"连续自动对焦（AF-C）"）
                .fontSize(12)
                .width(70)
                .height(18)
            }

            Column() {
              Text("测光")
                .fontSize(12)

              Button(this.meterModeValue) // 绑定测光模式（如"Multi Spot"）
                .fontSize(12)
                .width(70)
                .height(18)

            }

            Column() {
              Text("白平衡")
                .fontSize(12)
              Button(this.whiteBalanceValue) // 绑定白平衡（如"Automatic"）
                .fontSize(12)
                .width(70)
                .height(18)
            }

            Column() {
              Text("曝光模式")
                .fontSize(12)
              Button(this.exposureProgramValue) // 绑定曝光模式缩写（如"P"、"A"）
                .fontSize(12)
                .height(18)
                .width(70)
            }


          }
          .width("100%")
          .padding(10)

        }
        .width("100%")










        /**
         * 预览控制栏（调试用）
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
         * 底部控制栏
         * */
        Row({ space: 10 }) {
          Button('图库')


          Button('拍照')
            .onClick(()=>{
              this.takeAndDownloadKnown()
            })
        }
        .margin({ top: 20 })
      }
      .width("100%")
      .height("100%")
    }

  }
}