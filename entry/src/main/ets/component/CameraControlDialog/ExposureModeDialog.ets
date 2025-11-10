// ExposureModeDialog.ets
@CustomDialog
export struct ExposureModeDialog {
  controller: CustomDialogController //控制器属性
  @Link selected_ExposureMode_Value: string // 双向绑定的ISO
  private ExposureMode_Options: string[] = ['M','A','S','P','AUTO']
  // 当前选中的索引（slider绑定的数值）
  @State currentIndex: number = this.ExposureMode_Options.indexOf(this.selected_ExposureMode_Value)

  build() {

    Column() {
      // 自定义滑动提示文本
      Text(`${this.ExposureMode_Options[this.currentIndex]}`)
        .fontSize(18)
        .margin({ bottom: 10 })
        .textAlign(TextAlign.Center)
        .fontColor("#ffffff")

      Slider({
        min: 0,
        max: this.ExposureMode_Options.length - 1,
        step: 1,
        style: SliderStyle.OutSet,
        value: this.currentIndex
      })
        .showSteps(true)
        .showTips(false)
        .stepSize(10)
        .trackColor("#666666")
        .selectedColor("#666666")
        .blockColor("#FFFFFF")
        .enableHapticFeedback(true) // 触感反馈， 需要配置vibrate权限
        .trackThickness(5) // 增加滑轨厚度，让刻度更清晰
        .onChange((value: number, mode: SliderChangeMode) => {
          this.currentIndex = Math.round(value)
          // 滑动结束后，同步到双向绑定的ExposureMode 更新主页面
          if (mode == SliderChangeMode.End) {
            this.selected_ExposureMode_Value = this.ExposureMode_Options[this.currentIndex]
          }
        })

    }
    .width("100%")
    .padding(30)
  }
}