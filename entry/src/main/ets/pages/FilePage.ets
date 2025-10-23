import {

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
  @State isConnected: boolean = false;
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

  build() {
    Column(){
      // 状态栏
      Row({space:10}){
        Text('camera disconnect')

        Button('检测相机')
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