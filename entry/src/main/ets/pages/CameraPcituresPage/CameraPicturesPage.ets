import nativeCamera, { ThumbnailInfo } from 'libentry.so'
import image from '@ohos.multimedia.image';
import { router } from '@kit.ArkUI';

interface ImageInfoWithPixelMap {
  folder: string;
  filename: string;
  pixelMap: image.PixelMap | null;

  // 新增：保存原始buffer用于大图（可选，根据需要）
  thumbnail: ArrayBuffer;
}

@Builder
export function CameraPicturesPageBuilder() {
  CameraPicturesPage();
}


@Component
export struct CameraPicturesPage {
  @Consume('pageStack') pageStack: NavPathStack;

  @State thumbnails: ThumbnailInfo[] = [];
  @State imageInfos: ImageInfoWithPixelMap[] = [];
  @State isLoading: boolean = true;
  @State errorMsg: string = '';
  @State menuItems: Array<NavigationMenuItem> = [
    {
      value: '多选', action: () => {
    }
    },
    {
      value: '菜单', icon: $r('sys.media.ohos_ic_public_more'), action: () => {
    }
    }
  ];

  aboutToAppear(): void {
    this.loadThumbnails();
  }

  // 加载缩略图数据
  loadThumbnails() {
    this.isLoading = true;
    nativeCamera.GetThumbnailList((err: string | null, result: ThumbnailInfo[]) => {
      if (err) {
        this.errorMsg = `获取失败：${err}`;
        this.isLoading = false;
        return;
      }

      this.convertThumbnailsToPixelMaps(result).then(() => {
        this.isLoading = false;
      }).catch(() => {
        this.isLoading = false;
      });
    });
  }

  // 批量转换缩略图（修复for循环解构问题）
  async convertThumbnailsToPixelMaps(thumbnails: ThumbnailInfo[]) {
    const newImageInfos: ImageInfoWithPixelMap[] = [];
    for (let i = 0; i < thumbnails.length; i++) {
      const item = thumbnails[i];
      try {
        if (!item.thumbnail || item.thumbnail.byteLength === 0) {
          throw new Error('无效的缩略图数据');
        }
        // 转换为PixelMap（复用你的现有方法）
        const pixelMap = await this.convertArrayBufferToPixelMap(item.thumbnail, item.filename);
        newImageInfos.push({
          folder: item.folder,
          filename: item.filename,
          pixelMap: pixelMap,
          thumbnail: item.thumbnail // 保存原始buffer，方便大图使用
        });
      } catch (err) {
        console.error(`转换失败：${(err as Error).message}`);
        newImageInfos.push({
          folder: item.folder,
          filename: item.filename,
          pixelMap: null,
          thumbnail: item.thumbnail || new ArrayBuffer(0)
        });
      }
    }
    this.imageInfos = newImageInfos;
  }

  // 单个buffer转PixelMap（修复imageInfo.format问题）
  async convertArrayBufferToPixelMap(buffer: ArrayBuffer, filename: string): Promise<image.PixelMap> {
    const uint8Buffer = new Uint8Array(buffer);
    if (uint8Buffer.length < 2 || uint8Buffer[0] !== 0xFF || uint8Buffer[1] !== 0xD8) {
      throw new Error(`不是有效的JPEG数据`);
    }
    const imageSource = image.createImageSource(buffer);
    if (!imageSource) {
      throw new Error(`创建ImageSource失败`);
    }
    const imageInfo = await imageSource.getImageInfo();
    if (!imageInfo || imageInfo.size.width === 0 || imageInfo.size.height === 0) {
      throw new Error(`获取图片信息失败`);
    }
    const pixelMapOptions: image.InitializationOptions = {
      size: { width: imageInfo.size.width, height: imageInfo.size.height },
      pixelFormat: image.PixelMapFormat.RGBA_8888,
      alphaType: image.AlphaType.OPAQUE,
      editable: false
    };
    const pixelMap = await imageSource.createPixelMap(pixelMapOptions);
    if (!pixelMap) {
      throw new Error(`创建PixelMap失败`);
    }
    return pixelMap;
  }

  // 点击图片跳转到大图页面
  openBigImage(index: number) {

    this.pageStack.pushPathByName('BigImagePage',null,true)
  }

  build() {
    NavDestination() {
      Column() {
        if (this.isLoading) {
          Column({ space: 10 }) {
            LoadingProgress().size({ width: 40, height: 40 });
            Text('正在检索照片...').fontSize(16);
          }.margin({ top: 50 });
        } else if (this.errorMsg) {
          Text(this.errorMsg).fontSize(16).padding(20);
        } else {
          Text(`共找到 ${this.imageInfos.length} 张照片`).fontSize(14).padding({ left: 16, top: 10 });
          Grid() {
            ForEach(this.imageInfos, (item: ImageInfoWithPixelMap, index: number) => {
              GridItem() {
                // 单个图片项：填充网格，添加点击效果
                Column() {
                  Image(item.pixelMap || $r('app.media.ic_placeholder')) // 占位图需自行准备
                    .width('100%')
                    .height('100%')
                    .objectFit(ImageFit.Cover) // 填充裁剪，保持比例
                  //.borderRadius(4); // 轻微圆角
                }
                //.backgroundColor('#f9f9f9') // 背景色，区分图片边界
                .onClick(() => this.openBigImage(index)) // 点击查看大图

                .gesture(
                  TapGesture()
                    .onAction(() => this.openBigImage(index))
                );
              }
              .aspectRatio(1)

            }, (item: ImageInfoWithPixelMap) => item.filename + item.folder);
          }
          // 关键：设置4列网格，自适应屏幕宽度
          .columnsTemplate('1fr 1fr 1fr 1fr') // 4列平均分配宽度
          .multiSelectable(true)
          .supportAnimation(true)
          .columnsGap(2) // 列间距
          .rowsGap(0.01) // 行间距
          .height('100%')
          .width('100%')
        }
      }.width('100%').height('100%');
    }.title('机内照片').menus(this.menuItems).width('100%').height('100%');
  }
}