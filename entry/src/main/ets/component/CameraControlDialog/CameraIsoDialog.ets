


@CustomDialog
export struct CameraIsoDialog{
  controller : CustomDialogController //控制器属性
  @Link iso:number // 双向绑定主页面数值
  @State currentValue:number = this.iso  // 弹窗内部临时值



  build() {

    Column(){
      // 自定义滑动提示文本
      Text(`${this.currentValue}`)
        .fontSize(12)
        .margin({bottom:10})
        .textAlign(TextAlign.Center)

      Slider({min:100,max:6400,step:100,style:SliderStyle.OutSet,value:this.currentValue})
        .showSteps(true)
        .showTips(false)
        .stepSize(10)
        .enableHapticFeedback(true) // 触感反馈， 需要配置vibrate权限
        .trackThickness(5) // 增加滑轨厚度，让刻度更清晰
        .onChange((value:number,mode:SliderChangeMode)=>{
          this.currentValue = value
          // 滑动结束后，同步到双向绑定的ISO 更新主页面
          if(mode == SliderChangeMode.End){
            this.iso = value
          }
        })




    }
    .width("100%")
    .padding(30)
  }
}