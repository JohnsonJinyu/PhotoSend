


@CustomDialog
export struct IsoDialog{
  controller : CustomDialogController //控制器属性
  @Link selectedISO :string // 双向绑定的ISO

  private IsoOptions:string[]=['100','125','160','200','250','320','400','500','640','800','1000','1250','1600',
  '3200','6400','51200','12800','25600','512000']

  // 当前选中的索引（slider绑定的数值）
  @State currentIndex:number = this.IsoOptions.indexOf(this.selectedISO)

  build() {

    Column(){
      // 自定义滑动提示文本
      Text(`${this.IsoOptions[this.currentIndex]}`)
        .fontSize(18)
        .margin({bottom:10})
        .textAlign(TextAlign.Center)

      Slider({
        min:0,
        max:this.IsoOptions.length-1,
        step:1,
        style:SliderStyle.OutSet,
        value:this.currentIndex
      })
        .showSteps(true)
        .showTips(false)
        .stepSize(10)
        .enableHapticFeedback(true) // 触感反馈， 需要配置vibrate权限
        .trackThickness(5) // 增加滑轨厚度，让刻度更清晰
        .onChange((value:number,mode:SliderChangeMode)=>{
          this.currentIndex = Math.round(value)
          // 滑动结束后，同步到双向绑定的ISO 更新主页面
          if(mode == SliderChangeMode.End){
            this.selectedISO = this.IsoOptions[this.currentIndex]
          }
        })




    }
    .width("100%")
    .padding(30)
  }
}