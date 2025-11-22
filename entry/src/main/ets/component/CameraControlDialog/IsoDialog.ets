// IsoDialog.ets
import { CameraHelper } from 'ets/utils/tools/CameraHelper';

import Log from '@ohos.hilog';

const TAG = 'IsoDialog';
const domain = 1





@CustomDialog
export struct IsoDialog {
  controller: CustomDialogController
  @Link selectedISOValue: string
  private IsoOptions: string[] = [];
  @State currentIndex: number = 0;



  constructor(controller: CustomDialogController, selectedISOValue: string) {
    super();
    this.controller = controller;
    this.selectedISOValue = selectedISOValue;
    this.initIsoOptions();
  }



  aboutToAppear(): void {
    Log.info(domain, TAG, '在build函数中，IsoOptions的值为: %{public}s', this.IsoOptions.join(','));
    // 遍历打印IsoOptions数组内容
    this.IsoOptions.forEach((option, index) => {
      Log.info(domain, TAG, 'IsoOptions[%d]: %s', index, option);
    });
  }


  async initIsoOptions() {
    const cameraHelper = CameraHelper.getInstance();
    const options = cameraHelper.getIsoOptions();
    if (options.length === 0) {
      cameraHelper.onIsoOptionsUpdate = (newOptions) => {
        this.IsoOptions = newOptions;
        this.currentIndex = this.IsoOptions.indexOf(this.selectedISOValue);
        Log.info(1,TAG, 'IsoOptions received in IsoDialog: %{public}s', this.IsoOptions.join(','));
      };
    } else {
      this.IsoOptions = options;
      this.currentIndex = this.IsoOptions.indexOf(this.selectedISOValue);
      Log.info(1,TAG, 'IsoOptions received in IsoDialog: %{public}s', this.IsoOptions.join(','));
    }
  }

  build() {

    Column() {
      Text(`${this.IsoOptions[this.currentIndex]}`)
        .fontSize(18)
        .margin({ bottom: 10 })
        .textAlign(TextAlign.Center)
        .fontColor("#FFFFFF");

      Slider({
        min: 0,
        max: this.IsoOptions.length - 1,
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
        .enableHapticFeedback(true)
        .trackThickness(5)
        .onChange((value: number, mode: SliderChangeMode) => {
          this.currentIndex = Math.round(value);
          if (mode == SliderChangeMode.End) {
            this.selectedISOValue = this.IsoOptions[this.currentIndex];
          }
        });
    }
    .width("100%")
    .padding(30);
  }
}