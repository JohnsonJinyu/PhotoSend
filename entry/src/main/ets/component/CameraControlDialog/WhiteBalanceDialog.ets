
// WhiteBalanceDialog.ets


@CustomDialog
export struct WhiteBalanceDialog {
  controller: CustomDialogController //控制器属性
  @Link selectedI_WB_Value: string // 双向绑定的WB_Value
  private WhiteBalance_Options: string[] = ['2','4','5','6','7','32784','32785','32786','32787','32790']
  // 当前选中的索引（slider绑定的数值）
  @State currentIndex: number = this.WhiteBalance_Options.indexOf(this.selectedI_WB_Value)

  build() {

    Column() {
      // 自定义滑动提示文本
      Text(`${this.WhiteBalance_Options[this.currentIndex]}`)
        .fontSize(18)
        .margin({ bottom: 10 })
        .textAlign(TextAlign.Center)

      Slider({
        min: 0,
        max: this.WhiteBalance_Options.length - 1,
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
          // 滑动结束后，同步到双向绑定的wb 更新主页面
          if (mode == SliderChangeMode.End) {
            this.selectedI_WB_Value = this.WhiteBalance_Options[this.currentIndex]
          }
        })

    }
    .width("100%")
    .padding(30)
  }
}