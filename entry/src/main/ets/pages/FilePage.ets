import {
  IsCameraConnected,
  ConnectCamera,
  SetCameraParameter,
  TakePhoto,
  GetPreview,
  DownloadPhoto,
  Disconnect,
  CameraDevice,
  PhotoPathInfo
} from 'libentry.so';
import {IsoDialog} from 'ets/component/CameraControlDialog/IsoDialog'
import { ShutterSpeedDialog } from 'ets/component/CameraControlDialog/ShutterSpeedDialog'
import {image} from '@kit.ImageKit';

@Preview
@Component
export struct FilePage {
  // 状态管理
  // 连接状态
  @State isConnected: boolean = false;
  @State connectStatus:string = '未连接相机';

  // 用来存放预览视频帧
  @State previewPixelMap :PixelMap | null = null

  @State previewRunning: boolean = false; // 当前是否在预览
  private timerId: number = -1;   // 定时器ID


  @State previewImage: string = '';
  @State photoList: PhotoPathInfo[] = [];
  @State currentPreviewInterval: number = 0;
  @State statusMessage: string = '请连接相机';
  @State isoValue: string = '100';
  // 当前ISO值，与浮窗双向绑定
  @State ISOValue:string="100"
  // record current aperture value
  @State apertureValue:number=2.8
  // record current shutter value
  @State shutterValue:string="1/200"



  private xComponentController:XComponentController = new XComponentController()

  // ISO弹窗控制器：正确传递双向绑定参数
  isoDialogController : CustomDialogController = new CustomDialogController({
    builder:IsoDialog({selectedISO:this.ISOValue}), // bind dialog component
    customStyle:true,
    alignment:DialogAlignment.Center
  })
  // shutter 弹窗控制器
  shutterDialogController : CustomDialogController = new CustomDialogController({
    builder:ShutterSpeedDialog({SelectedShutter:this.shutterValue}), // bind dialog component
    customStyle:true,
    alignment:DialogAlignment.Center
  })


  aboutToAppear(): void {
    this.checkConnection()
  }



/**
 * @function 手动连接相机
 * */
   manualConnect(){
    // 这里假设型号和路径是固定的
    let success =  ConnectCamera('PTP/IP Camera','ptpip:192.168.1.1')
    if (success) {
      this.isConnected = true
      this.connectStatus = '相机已连接'
    }else {
      this.isConnected=false
      this.connectStatus='连接失败，请检查WiFi'
    }
  }

  /**
   * @function 检查连接状态
   * */
  checkConnection(){
    let connected =   IsCameraConnected()  //等待执行完，把结果复制给connected
    this.isConnected = connected
    this.connectStatus = connected ? '相机已连接':'未连接，请检查是否连接相机WiFi'
  }


  /**
   *@function 启动预览
   * */
  startPreview(){
    if (this.previewRunning) {
      return
    }
    this.previewRunning = true
    this.timerId = setInterval(()=>{
      this.updatePreview();
    },300) // 每300ms拉1帧
  }

  /**
   * @function 停止预览
   * */
  stopPreview(){
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
  async updatePreview(){
    // 从native获取Uint8Array
    const buffer:Uint8Array = GetPreview()
    if(!buffer) return

    // 解码选项可留空或按需填写（如密度、期望尺寸）
    const srcOps:image.SourceOptions= {
      sourceDensity: 0
    }

    // 创建ImageSource（传入压缩图片你的ArrayBuffer）
    const imgSrc:image.ImageSource=image.createImageSource(buffer.buffer as ArrayBuffer,srcOps)

    // 从ImageSource 生成PixelMap
    const pixelMap:image.PixelMap = await imgSrc.createPixelMap()

    // 更新到UI
    this.previewPixelMap = pixelMap
  }
  

  build() {
    Column(){
      // 状态栏
      Column({space:10}){

        Button('检测相机')
          .onClick(()=>{
            this
          })

        Text(this.connectStatus)
          .fontSize(18)
      }
      .margin({top:10})


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






      /**
       * 参数控制栏
       * */
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
          Text("ISO")
            .fontSize(12)

          Button(this.ISOValue.toString())
            .fontSize(12)
            .height(18)
            .width(70)
            .onClick(()=>this.isoDialogController.open())

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
            .onClick(()=>{this.shutterDialogController.open()})
        }

      }
      .width("100%")
      .padding(20)



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
      Row({space:10}){
        Button('图库')


        Button('拍照')
      }
      .margin({top:20})
    }
    .width("100%")
    .height("100%")
  }
}