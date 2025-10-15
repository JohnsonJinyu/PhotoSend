import { ArcSliderValueOptions } from '@kit.ArkUI'
import {CameraIsoDialog} from 'ets/component/CameraIsoDialog'
import { ShutterSpeedDialog } from 'ets/component/ShutterSpeedDialog'
@Preview
@Component

export struct RemoteControl {

  // 当前ISO值，与浮窗双向绑定
  @State ISOValue:number=100
  // record current aperture value
  @State apertureValue:number=2.8
  // record current shutter value
  @State shutterValue:string="1/200"

  // ISO弹窗控制器：正确传递双向绑定参数
  isoDialogController : CustomDialogController = new CustomDialogController({
    builder:CameraIsoDialog({iso:this.ISOValue}), // bind dialog component
    customStyle:true,
    alignment:DialogAlignment.Center
  })
  // shutter 弹窗控制器
  shutterDialogController : CustomDialogController = new CustomDialogController({
    builder:ShutterSpeedDialog({SelectedShutter:this.shutterValue}), // bind dialog component
    customStyle:true,
    alignment:DialogAlignment.Center
  })


  @Builder
  build() {
    Column() {
      Row({ space: 10 }) {

        Column() {
          Text("AF_MODE")
            .fontSize(12)
          Button("AF_C")
            .fontSize(12)
            .width(80)
            .height(18)
        }

        Column() {
          Text("ISO")
            .fontSize(12)

          Button(this.ISOValue.toString())
            .fontSize(12)
            .height(18)
            .width(80)
            .onClick(()=>this.isoDialogController.open())

        }

        Column() {
          Text("Aperture")
            .fontSize(12)
          Button("2.8")
            .fontSize(12)
            .width(80)
            .height(18)
        }

        Column() {
          Text("Shutter")
            .fontSize(12)
          Button(this.shutterValue.toString())
            .fontSize(12)
            .height(18)
            .width(80)
            .onClick(()=>{this.shutterDialogController.open()})
        }

      }
      .width("100%")

    }
  }
}



