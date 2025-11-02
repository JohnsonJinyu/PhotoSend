
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
@Preview
@Component
export struct FilePage {
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
  @State apertureValue: number = 2.8
  // record current shutter value
  @State shutterValue: string = "1/200"
  // 新增：用于UI展示的参数列表（从参数管理器获取）
  @State paramList: ParamOption[] = [];

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

  }

  // 页面销毁时移除监听器，避免内存泄漏
  aboutToDisappear(): void {
    cameraParamManager.removeListener(() => {
      // 这里需要传入与注册时相同的函数引用，实际开发中建议用命名函数
    });
  }

  // 将参数管理器的参数同步到页面UI状态
  private syncParamToUI() {
    console.log('开始同步参数到UI，当前paramList:', JSON.stringify(this.paramList));

    const isoParam = this.paramList.find(p => p.name === 'iso');
    if (isoParam) {
      this.ISOValue = isoParam.currentValue; // 同步ISO值到页面状态
      console.log('同步ISO值:', this.ISOValue);
    }

    const shutterParam = this.paramList.find(p => p.name === 'shutter');
    if (shutterParam) {
      this.shutterValue = shutterParam.currentValue; // 同步快门值
      console.log('同步快门值:', this.shutterValue);
    }

    const apertureParam = this.paramList.find(p => p.name === 'aperture');
    if (apertureParam) {
      this.apertureValue = parseFloat(apertureParam.currentValue); // 同步光圈值
      console.log('同步光圈值:', this.apertureValue);
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
    // 同步状态到参数管理器（关键步骤）
    cameraParamManager.updateConnectionStatus(connected);
    // 更新页面自身状态
    this.isConnected = connected;
    this.connectStatus = connected ? '相机已连接' : '未连接，请检查是否连接相机WiFi';
  }

  /**
   * @function 启动预览
   * */
  startPreview() {
    if (this.previewRunning) {
      return
    }
    this.previewRunning = true
    this.timerId = setInterval(() => {
      this.updatePreview();
    }, 300) // 每300ms拉1帧
  }

  /**
   * @function 停止预览
   * */
  stopPreview() {
    if (this.timerId !== -1) {
      clearInterval(this.timerId)
      this.timerId = -1
    }
    this.previewRunning = false
    this.previewPixelMap = null // 清空画面
  }

  /**
   * @function 拉取一帧预览
   * */
  async updatePreview() {
    // 从native获取Uint8Array
    const buffer: Uint8Array = nativeLibGphoto.GetPreview()
    if (!buffer) {
      return
    }

    // 解码选项可留空或按需填写（如密度、期望尺寸）
    const srcOps: image.SourceOptions = {
      sourceDensity: 0
    }

    // 创建ImageSource（传入压缩图片你的ArrayBuffer）
    const imgSrc: image.ImageSource = image.createImageSource(buffer.buffer as ArrayBuffer, srcOps)

    // 从ImageSource 生成PixelMap
    const pixelMap: image.PixelMap = await imgSrc.createPixelMap()

    // 更新到UI
    this.previewPixelMap = pixelMap
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


  //###############################################################################
  //          Build Area
  //###############################################################################


  build() {
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


        Text(this.connectStatus)
          .fontSize(18)

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
            Button("2.8")
              .fontSize(12)
              .width(70)
              .height(18)
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
            Text("Ev")
              .fontSize(12)
            Button(this.shutterValue.toString())
              .fontSize(12)
              .height(18)
              .width(70)
              .onClick(() => {
                this.shutterDialogController.open()
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
            Button("AF_C")
              .fontSize(12)
              .width(70)
              .height(18)
          }

          Column() {
            Text("测光")
              .fontSize(12)

            Button(this.ISOValue.toString())
              .fontSize(12)
              .height(18)
              .width(70)
              .onClick(() => this.isoDialogController.open())

          }

          Column() {
            Text("白平衡")
              .fontSize(12)
            Button("2.8")
              .fontSize(12)
              .width(70)
              .height(18)
          }

          Column() {
            Text("曝光模式")
              .fontSize(12)
            Button(this.shutterValue.toString())
              .fontSize(12)
              .height(18)
              .width(70)
              .onClick(() => {
                this.shutterDialogController.open()
              })
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