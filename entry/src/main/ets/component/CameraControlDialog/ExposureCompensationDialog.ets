// ExposureCompensationDialog.ets  曝光补偿


@CustomDialog
export struct ExposureCompensationDialog {
  controller: CustomDialogController //控制器属性
  @Link selected_EV_Value: string // 双向绑定的EV_Value
  private EV_Options: string[] = ['-2','-1.7','-1.3','-1','-0.7','-0.3','0','0.3',
  '0.7','1','1.3','1.7','2']
  // 当前选中的索引（slider绑定的数值）
  @State currentIndex: number = this.EV_Options.indexOf(this.selected_EV_Value)



  build() {
    Column() {
      // 自定义滑动提示文本
      Text(`${this.EV_Options[this.currentIndex]}`)
        .fontSize(18)
        .margin({ bottom: 10 })
        .textAlign(TextAlign.Center)

      Slider({
        min: 0,
        max: this.EV_Options.length - 1,
        step: 1,
        style: SliderStyle.OutSet,
        value: this.currentIndex
      })
        .showSteps(true)
        .showTips(false)
        .stepSize(10)
        .enableHapticFeedback(true) // 触感反馈， 需要配置vibrate权限
        .trackThickness(5) // 增加滑轨厚度，让刻度更清晰
        .onChange((value: number, mode: SliderChangeMode) => {
          this.currentIndex = Math.round(value)
          // 滑动结束后，同步到双向绑定的ev 更新主页面
          if (mode == SliderChangeMode.End) {
            this.selected_EV_Value = this.EV_Options[this.currentIndex]
          }
        })

    }
    .width("100%")
    .padding(30)
  }
}