// ApertureDialog.ets
import nativeCamera from 'libentry.so'


// 定义一个接口用于存储光圈的结果（可选，增强类型安全）
interface ApertureInfo {
  current: string; // 光圈当前值（如"f/5.6"）
  choices: string[]; // 光圈可选值列表（如["f/2.8", "f/4", "f/5.6"]）
}


@CustomDialog
export struct ApertureDialog {
  controller: CustomDialogController //控制器属性
  @Link selectedApertureValue: string // 双向绑定的ISO


  private ApertureOptions: string[] = []
  // 当前选中的索引（slider绑定的数值）
  @State currentIndex: number = this.ApertureOptions.indexOf(this.selectedApertureValue)

  // 对话框显示前加载数据
  aboutToAppear() {
    // 使用异步避免阻塞
    setTimeout(() => {
      this.loadApertureOptions();
    }, 0);
  }


  // 加载相机实际支持的光圈可选值
  private loadApertureOptions() {
    const apertureInfoList = this.getApertureOptions();
    if (apertureInfoList.length > 0 && apertureInfoList[0].choices.length > 0) {
      // 正常获取到配置
      const apertureInfo = apertureInfoList[0];
      this.ApertureOptions = apertureInfo.choices;
      // 处理当前索引（确保在有效范围内）
      this.currentIndex = Math.max(0, Math.min(
        this.ApertureOptions.indexOf(apertureInfo.current),
        this.ApertureOptions.length - 1
      ));
      this.selectedApertureValue = this.ApertureOptions[this.currentIndex];
    } else {
      // 兜底：使用安全的默认值，避免空数组
      this.ApertureOptions = ["f/2.8", "f/4", "f/5.6"];
      this.currentIndex = 0;
      this.selectedApertureValue = this.ApertureOptions[0];
    }
  }

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
    // 调用底层接口获取所有配置参数（包含每个参数的可选值）
    const allConfigs = nativeCamera.GetCameraConfig();
    if (allConfigs.length === 0) {
      console.error("未获取到相机配置参数");
      return apertureResult;
    }

    // 3. 筛选出光圈参数（name为"aperture"）
    const apertureConfig = allConfigs.find(config => config.name === "f-number");
    if (apertureConfig) {
      apertureResult.push({
        current: apertureConfig.current, // 当前光圈值
        choices: apertureConfig.choices  // 实际支持的可选值列表
      });
      console.log("相机支持的光圈可选值：", apertureConfig.choices);
    } else {
      console.error("未找到光圈参数（name: f-number）");
    }
    return apertureResult;
  }

  build() {

    Column() {
      // 自定义滑动提示文本
      Text(`${this.ApertureOptions[this.currentIndex]}`)
        .fontSize(18)
        .margin({ bottom: 10 })
        .textAlign(TextAlign.Center)
        .fontColor("#ffffff")

      Slider({
        min: 0,
        max: this.ApertureOptions.length - 1,
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
          // 滑动结束后，同步到双向绑定的ISO 更新主页面
          if (mode == SliderChangeMode.End) {
            //this.selectedApertureValue = this.selectedApertureValue[this.currentIndex]
            // 从实际可选值数组中取值
            this.selectedApertureValue = this.ApertureOptions[this.currentIndex];
          }
        })


    }
    .width("100%")
    .padding(30)
  }
}