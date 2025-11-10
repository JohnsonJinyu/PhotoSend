// ExposureMeterModeDialog.ets  测光模式

@CustomDialog
export struct ExposureMeterModeDialog {
  controller: CustomDialogController //控制器属性
  @Link selected_ExposureMeterMode_Value: string // 双向绑定的ISO
  private ExposureMeterMode_Options: string[] = ['平均','中央重点平均','点测光','暗部重点测光']
  // 当前选中的索引（slider绑定的数值）
  @State currentIndex: number = this.ExposureMeterMode_Options.indexOf(this.selected_ExposureMeterMode_Value)

  build() {

    Column() {
      // 自定义滑动提示文本
      Text(`${this.ExposureMeterMode_Options[this.currentIndex]}`)
        .fontSize(18)
        .margin({ bottom: 10 })
        .textAlign(TextAlign.Center)
        .fontColor("#ffffff")

      Slider({
        min: 0,
        max: this.ExposureMeterMode_Options.length - 1,
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
          // 滑动结束后，同步到双向绑定的ExposureMeterMode 更新主页面
          if (mode == SliderChangeMode.End) {
            this.selected_ExposureMeterMode_Value = this.ExposureMeterMode_Options[this.currentIndex]
          }
        })

    }
    .width("100%")
    .padding(30)
  }
}