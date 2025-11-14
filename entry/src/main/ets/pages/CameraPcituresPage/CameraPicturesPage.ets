/**
 *  机内照片下载页面
 * */

import nativeCamera, { ThumbnailInfo } from 'libentry.so'
import { image } from '@kit.ImageKit';

@Builder
export function CameraPicturesPageBuilder() {
  CameraPicturesPage();
}


@Component
export struct CameraPicturesPage {
  // 状态管理

  @State selectedPhotos: number[] = []
  //@State photos:photoItem[]=[]
  @State isMoreMenuShow: boolean = false

  // 存储照片缩略图信息（包含文件名、路径等）
  @State thumbnails: ThumbnailInfo[] = [];
  // 加载状态（控制加载提示显示）
  @State isLoading: boolean = true;
  // 错误信息（获取失败时显示）
  @State errorMsg: string = '';

  @State isSelectMode: boolean = false
  @State selectedIndices: number[] = [];  // 选中的图片索引

  // 瀑布流配置
  private columnCount: number = 2; // 2列布局
  private spacing: number = 10;    // 列间距和行间距
  @State pixelMap: image.PixelMap | null = null; // 存储解码后的PixelMap


  @State menuItems:Array<NavigationMenuItem>=[
    {
      value:'多选',
      action:()=>{

      }
    },
    {
      value:'菜单',
      icon:$r('sys.media.ohos_ic_public_more'),
      action:()=>{

      }
    }
  ]



  aboutToAppear(): void{

    this.loadThumbnails()

  }


  // 异步解码缩略图
  /*private async decodeThumbnail() {
    try {
      this.pixelMap = await this.bufferToPixelMap(this.thumbnail);
    } catch (err) {
      console.error(`解码失败：${(err as BusinessError).message}`);
      this.pixelMap = null;
    } finally {
      this.isLoading = false;
    }
  }*/


  // 加载缩略图列表（复用原有异步逻辑）
  private loadThumbnails(): void {
    this.isLoading = true;
    nativeCamera.GetThumbnailList((err: string | null, result: ThumbnailInfo[]) => {
      if (err) {
        this.errorMsg = `获取失败：${err}`;
        console.error(this.errorMsg);
      } else {
        this.thumbnails = result;
        console.log(`成功获取${result.length}张照片`);
      }
      this.isLoading = false;
    });
  }


  // 将缩略图的ArrayBuffer转为PixelMap（供Image组件显示）
  private async bufferToPixelMap(buffer: ArrayBuffer): Promise<image.PixelMap | null> {
    try {
      const imageSource = image.createImageSource(buffer); // 创建图片源
      const pixelMap = await imageSource.createPixelMap(); // 解码为PixelMap
      return pixelMap;
    } catch (err) {
      console.error(`缩略图解码失败：${err.message}`);
      return null; // 失败时返回null，显示默认图
    }
  }




  build() {
    NavDestination() {
      Column() {
        // 加载中状态
        if (this.isLoading) {
          Column({ space: 10 }) {
            LoadingProgress()
             // .color($r('sys.color.primary'))
              .size({ width: 40, height: 40 });
            Text('正在检索照片...')
              .fontSize(16)
              //fontColor($r('sys.color.secondary_text'));
          }
          .margin({ top: 50 });
        }

        // 错误状态
        else if (this.errorMsg) {
          Text(this.errorMsg)
            .fontSize(16)
            //.fontColor($r('sys.color.error'))
            .padding(20);
        }

        // 成功获取数据，展示照片信息
        else {
          // 照片数量提示
          Text(`共找到 ${this.thumbnails.length} 张照片`)
            .fontSize(14)
           // .fontColor($r('sys.color.secondary_text'))
            .padding({ left: 16, top: 10 });

          WaterFlow(){
            ForEach(
              this.thumbnails,
              (item:ThumbnailInfo)=>{
               FlowItem(){
                 Column(){
                   // 缩略图显示（核心）
                   Image(this.pixelMap) // 失败时显示默认图标
                     .width('100%')        // 宽度占满列
                     .height('auto')       // 高度自适应图片比例（瀑布流关键）
                     .objectFit(ImageFit.Cover) // 图片裁剪适配
                     .borderRadius(8);     // 圆角美化

                   // 可选：显示文件名（底部文字）
                   Text(item.filename)
                     .fontSize(12)
                     .padding({ top: 5 })
                     .maxLines(1)          // 文件名过长时截断
                     .textOverflow({ overflow: TextOverflow.Ellipsis });
                 }
                 .padding(5)
               }
              }
            )
          }

        }
      }
      .width('100%')
      .height('100%');
    }
    .title('机内照片')
    .menus(this.menuItems)
    .width('100%')
    .height('100%');
  }
}