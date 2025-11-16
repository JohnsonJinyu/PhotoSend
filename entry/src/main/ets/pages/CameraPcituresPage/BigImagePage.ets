import image from '@ohos.multimedia.image';
import { Router } from '@kit.ArkUI';
import { BigImageParams } from './CameraPicturesPage';

//import { NavController } from '@ohos.navigator';




// 定义Builder，符合路由配置的buildFunction
@Builder
export function BigImagePageBuilder() {
  BigImagePage()
}

@Component
struct BigImagePage {

  private params: BigImageParams = {
    imageInfo: {
      folder: '',
      filename: '',
      pixelMap: null,
      thumbnail: new ArrayBuffer(0)
    }
  };

  // 关键：通过 aboutToAppear 生命周期接收参数
  // 当页面被 push 时，参数会被注入到组件的 this.params 中
  aboutToAppear() {
    // 从导航参数中获取传递的值（框架会自动填充）
    const navParams = this.params as BigImageParams;
    if (navParams?.imageInfo) {
      this.params = navParams;
    }
  }


  build() {
    NavDestination() {
      Column() {
        // 显示图片文件名
        Text(this.params.imageInfo.filename)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .padding({ left: 16, top: 10 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });

        // 显示大图
        Image(this.params.imageInfo.pixelMap || $r('app.media.ic_placeholder'))
          .width('100%')
          .height('calc(100% - 56px)')
          .objectFit(ImageFit.Contain)
          .padding(20)

      }
      .width('100%')
      .height('100%')
      .backgroundColor('#000000');
    }
    .title(this.params.imageInfo.filename) // 导航栏标题
    // 导航页标题（会显示在导航栏）
    /*.title(this.imageInfo.filename)*/
    // 支持手势返回（侧滑返回）

  }
}