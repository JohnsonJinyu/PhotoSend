/**
 *  机内照片下载页面
 * */

import nativeCamera, { ThumbnailInfo } from 'libentry.so'
import { image } from '@kit.ImageKit';

@Builder
export function CameraPicturesPageBuilder() {
  CameraPicturesPage();
}

// 子组件：仅显示图片（无文件名）
@Component
struct PhotoGridItem {
  // 接收缩略图的二进制数据
  @Prop thumbnailBuffer: ArrayBuffer;

  // 内部状态：当前图片的PixelMap和解码状态
  @State pixelMap: image.PixelMap | null = null;
  @State isLoading: boolean = true;

  // 组件初始化时解码图片
  aboutToAppear() {
    this.decodeThumbnail();
  }

  // 解码缩略图（ArrayBuffer → PixelMap）
  private async decodeThumbnail() {
    try {
      const imageSource = image.createImageSource(this.thumbnailBuffer);
      this.pixelMap = await imageSource.createPixelMap();
    } catch (err) {
      console.error(`图片解码失败：${err.message}`);
      this.pixelMap = null;
    } finally {
      this.isLoading = false;
    }
  }

  build() {
    Column() {
      // 加载中状态
      if (this.isLoading) {
        Column(){
          LoadingProgress()
            .size({ width: 24, height: 24 });
        }
        .width('100%')
        .height(150) // 固定高度，避免布局抖动
        .backgroundColor('#f0f0f0')
        .borderRadius(8)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }
      // 解码失败（显示默认图）
      else if (this.pixelMap === null) {
        Image($r('sys.media.ohos_app_icon'))
          .width('100%')
          .height(150)
          .objectFit(ImageFit.Cover)
          .borderRadius(8);
      }
      // 解码成功（显示缩略图）
      else {
        Image(this.pixelMap)
          .width('100%')
          .height(150) // 固定高度，确保网格整齐
          .objectFit(ImageFit.Cover) // 裁剪适配
          .borderRadius(8);
      }
    }
    .padding(5); // 网格项之间的间距
  }
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

          Grid(){
            ForEach(this.thumbnails,(item:ThumbnailInfo)=>{
              GridItem(){
                // 每个网格项使用子组件显示
                PhotoGridItem({ thumbnailBuffer: item.thumbnail })
              }
            }

            )
          }
          .columnsTemplate(`repeat(3, 1fr)`) // 补充网格列数配置（例如3列）
          .rowsGap(10)
          .columnsGap(10)
          .padding(16)
          .width('100%');

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