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

@Preview
@Component
export struct FilePage {
  // 状态管理
  // 连接状态
  @State isConnected: boolean = false;
  @State connectStatus:string = '未连接相机';
  @State cameraList: CameraDevice[] = [];
  @State selectedCamera: CameraDevice | null = null;
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

  checkConnection(){
    let connected =   IsCameraConnected()  //等待执行完，把结果复制给connected
    this.isConnected = connected
    this.connectStatus = connected ? '相机已连接':'未连接，请检查是否连接相机WiFi'
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

      XComponent({
        id:'CameraPreview',//唯一标识
        type:'surface',
        controller:this.xComponentController
      })
        .width('100%')
        .height(250)






      // 参数控制蓝
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


      //拍照 图库栏
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