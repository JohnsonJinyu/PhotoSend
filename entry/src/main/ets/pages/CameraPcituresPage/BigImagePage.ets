import image from '@ohos.multimedia.image';
//import { NavController } from '@ohos.navigator';

// 定义接收的参数类型
interface ImageInfo {
  folder: string;
  filename: string;
  pixelMap: image.PixelMap | null;
}

interface BigImageParams {
  imageInfo: ImageInfo; // 只传当前点击的图片信息（简化版）
  //navController: NavController; // 接收导航控制器，用于返回
}

// 定义Builder，符合路由配置的buildFunction
@Builder
export function BigImagePageBuilder() {
  BigImagePage()
}

@Component
struct BigImagePage {




  build() {
    NavDestination() {
      Column() {
        Text('图片名称')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .flexGrow(1)
          .padding({ left: 16 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });




        // 图片预览区（只显示当前图片，简化版）
        Image(/*this.imageInfo.pixelMap ||*/ $r('app.media.ic_placeholder'))
          .width('100%')
          .height('calc(100% - 56px)')
          .objectFit(ImageFit.Contain)
          .padding(20)
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#000000');
    }
    // 导航页标题（会显示在导航栏）
    /*.title(this.imageInfo.filename)*/
    // 支持手势返回（侧滑返回）

  }
}