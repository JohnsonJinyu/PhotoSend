import { ArcSliderValueOptions } from '@kit.ArkUI'
import {CameraIsoDialog} from 'ets/component/CameraIsoDialog'
@Preview
@Component

export struct RemoteControl {

  // 当前ISO值，与浮窗双向绑定
  @State ISOValue:number=100
  // record current aperture value
  @State apertureValue:number=200
  // record current shutter value
  @State shutterValue:number=2.8

  // 弹窗控制器：正确传递双向绑定参数
  dialogController : CustomDialogController = new CustomDialogController({
    builder:CameraIsoDialog({iso:this.ISOValue}), // bind dialog component
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
            .onClick(()=>this.dialogController.open())

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
          Button("1/200")
            .fontSize(12)
            .height(18)
            .width(80)
        }

      }
      .width("100%")

    }
  }
}



