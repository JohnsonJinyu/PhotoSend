
@CustomDialog
export struct ShutterSpeedDialog{
  controller : CustomDialogController //控制器属性
  //双向绑定主页的选中值（字符串类型）
  @Link SelectedShutter:string
  // 定义所有快门速度的选项
  private shutterOptions:string[]=["1/8000","1/4000","1/3200","1/2500","1/2000","1/1600","1/1250",
  "1/1000","1/800","1/640","1/500","1/400","1/320","1/250","1/200","1/160","1/125","1/100","1/80","1/60",
  "1/50","1/40","1/30","1/20","1/15","1/8","1/4","1/2","1","2","4","8"]

  // 当前选中的索引（slider绑定的数值）
  @State currentIndex:number = this.shutterOptions.indexOf(this.SelectedShutter)


  build() {
    Column({space:15}){
      // 当前选中的快门值，字符串显示
      Text(`${this.shutterOptions[this.currentIndex]}`)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)

      Slider({
        min:0,
        max:this.shutterOptions.length-1,
        step:1,// 步长为1，确保智能选中整数索引
        style:SliderStyle.OutSet,
        value:this.currentIndex
      })
        .showSteps(true)
        .showTips(false)
        .enableHapticFeedback(true)
        .trackColor('#CCCCCC') // 轨道整体颜色（灰色，可自定义）
        .selectedColor('#CCCCCC') // 选中区域颜色 → 与轨道颜色一致，消除填充感
        .blockColor($r('sys.color.comp_background_list_card')) // 滑块颜色（白色，突出显示）
        .trackThickness(6)
        .onChange((value:number,mode:SliderChangeMode)=>{
          this.currentIndex=Math.round(value)
          // 滑动结束后同步到主页面
          if(mode == SliderChangeMode.End){
            this.SelectedShutter = this.shutterOptions[this.currentIndex]
          }
        })

    }
  }
}