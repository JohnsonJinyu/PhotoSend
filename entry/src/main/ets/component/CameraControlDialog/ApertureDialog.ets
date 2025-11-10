// ApertureDialog.ets
import nativeCamera from 'libentry.so'


// 定义一个接口用于存储光圈的结果（可选，增强类型安全）
interface ApertureInfo {
  current: string; // 光圈当前值（如"f/5.6"）
  choices: string[]; // 光圈可选值列表（如["f/2.8", "f/4", "f/5.6"]）
}


@CustomDialog
export struct ApertureDialog{
  controller : CustomDialogController //控制器属性
  @Link selectedApertureValue :string // 双向绑定的ISO

  private ApertureOptions:string[]=[ "f/2.8", "f/4", "f/5.6"]


  // 当前选中的索引（slider绑定的数值）
  @State currentIndex:number = this.ApertureOptions.indexOf(this.selectedApertureValue)



  // 获取光圈信息并保存到数组的函数
  getApertureOptions(): ApertureInfo[] {
  // 存储结果的数组（此处按需求设计为单元素数组，因光圈参数唯一）
  const apertureResult: ApertureInfo[] = [];

  // 1. 检查相机是否已连接
  if (!nativeCamera.IsCameraConnected()) {
    console.error("相机未连接，无法获取光圈参数");
    return apertureResult;
  }

  // 2. 调用接口获取所有配置参数
  const allConfigs: nativeCamera.ConfigItem[] = nativeCamera.GetCameraConfig();
  if (allConfigs.length === 0) {
    console.error("未获取到任何相机配置参数");
    return apertureResult;
  }

  // 3. 筛选出光圈参数（name为"aperture"）
  const apertureConfig = allConfigs.find(config => config.name === "aperture");

  // 4. 提取并保存结果
  if (apertureConfig) {
    apertureResult.push({
      current: apertureConfig.current,
      choices: apertureConfig.choices
    });
    console.log("成功获取光圈信息：", apertureResult);
  } else {
    console.error("未找到光圈参数（name: aperture）");
  }

  return apertureResult;
}







  build() {

    Column(){
      // 自定义滑动提示文本
      Text(`${this.ApertureOptions[this.currentIndex]}`)
        .fontSize(18)
        .margin({bottom:10})
        .textAlign(TextAlign.Center)

      Slider({
        min:0,
        max:this.ApertureOptions.length-1,
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
            this.selectedApertureValue = this.selectedApertureValue[this.currentIndex]
          }
        })




    }
    .width("100%")
    .padding(30)
  }

}