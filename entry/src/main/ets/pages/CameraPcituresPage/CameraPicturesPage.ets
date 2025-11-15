import nativeCamera, { ThumbnailInfo } from 'libentry.so'
import image from '@ohos.multimedia.image';

interface ImageInfoWithPixelMap {
  folder: string;
  filename: string;
  pixelMap: image.PixelMap | null;
}

@Builder
export function CameraPicturesPageBuilder() {
  CameraPicturesPage();
}

@Component
export struct CameraPicturesPage {
  @State thumbnails: ThumbnailInfo[] = [];
  @State imageInfos: ImageInfoWithPixelMap[] = [];
  @State isLoading: boolean = true;
  @State errorMsg: string = '';
  @State menuItems: Array<NavigationMenuItem> = [
    { value: '多选', action: () => {} },
    { value: '菜单', icon: $r('sys.media.ohos_ic_public_more'), action: () => {} }
  ];

  aboutToAppear(): void {
    this.isLoading = true;
    this.errorMsg = '';
    nativeCamera.GetThumbnailList((err: string | null, result: ThumbnailInfo[]) => {
      if (err) {
        this.errorMsg = `获取失败：${err}`;
        console.error(`[回调] 错误：${this.errorMsg}`);
        this.isLoading = false;
        return;
      }

      // 接收数据时的校验日志
      console.log(`[回调] 成功获取${result.length}张照片，开始校验数据`);
      for (let i = 0; i < result.length; i++) {
        const item = result[i];
        const bufferValid = !!item.thumbnail && item.thumbnail.byteLength > 0;
        console.log(`[回调] 第${i}个文件（${item.filename}）：` +
          `buffer存在=${!!item.thumbnail}，长度=${item.thumbnail?.byteLength || 0}字节`);
        if (!bufferValid) {
          console.error(`[回调] 第${i}个文件的buffer无效！`);
        }
      }

      this.thumbnails = result;
      console.log(`[转换] 开始将${result.length}个buffer转为PixelMap`);
      this.convertThumbnailsToPixelMaps().then(() => {
        console.log(`[转换] 所有文件转换完成，共${this.imageInfos.length}个结果`);
        this.isLoading = false;
      }).catch((err: Error) => {
        console.error(`[转换] 转换过程整体异常：${err.message}`);
        this.isLoading = false;
      });
    });
  }

  // 批量转换缩略图（修复for循环解构问题）
  async convertThumbnailsToPixelMaps() {
    const newImageInfos: ImageInfoWithPixelMap[] = [];
    // 改用传统for循环，避免解构赋值
    for (let index = 0; index < this.thumbnails.length; index++) {
      const item = this.thumbnails[index];
      try {
        console.log(`[转换] 开始处理第${index}个文件：${item.filename}`);
        if (!item.thumbnail) {
          throw new Error(`buffer为空`);
        }
        if (item.thumbnail.byteLength === 0) {
          throw new Error(`buffer长度为0`);
        }

        const pixelMap = await this.convertArrayBufferToPixelMap(item.thumbnail, item.filename);
        newImageInfos.push({
          folder: item.folder,
          filename: item.filename,
          pixelMap: pixelMap
        });
        console.log(`[转换] 第${index}个文件（${item.filename}）转换成功`);
      } catch (err) { // 显式指定err类型为Error
        console.error(`[转换] 第${index}个文件（${item.filename}）转换失败：${err.message}`);
        newImageInfos.push({
          folder: item.folder,
          filename: item.filename,
          pixelMap: null
        });
      }
    }
    this.imageInfos = newImageInfos; // 补充之前遗漏的赋值
  }

  // 单个buffer转PixelMap（修复imageInfo.format问题）
  async convertArrayBufferToPixelMap(buffer: ArrayBuffer, filename: string): Promise<image.PixelMap> {
    console.log(`[转PixelMap] ${filename}：buffer长度=${buffer.byteLength}字节，开始处理`);

    // 验证JPEG文件头
    const uint8Buffer = new Uint8Array(buffer);
    if (uint8Buffer.length < 2 || uint8Buffer[0] !== 0xFF || uint8Buffer[1] !== 0xD8) {
      throw new Error(`不是有效的JPEG数据（文件头错误：0x${uint8Buffer[0].toString(16)} 0x${uint8Buffer[1].toString(16)}）`);
    }

    // 创建ImageSource
    console.log(`[转PixelMap] ${filename}：开始创建ImageSource`);
    const imageSource = image.createImageSource(buffer);
    if (!imageSource) {
      throw new Error(`创建ImageSource失败`);
    }

    // 获取图片信息（删除format访问）
    console.log(`[转PixelMap] ${filename}：开始获取ImageInfo`);
    const imageInfo = await imageSource.getImageInfo();
    console.log(`[转PixelMap] ${filename}：获取到图片信息：宽=${imageInfo.size.width}，高=${imageInfo.size.height}`); // 移除format
    if (!imageInfo || imageInfo.size.width === 0 || imageInfo.size.height === 0) {
      throw new Error(`获取ImageInfo失败（宽高为0）`);
    }

    // 创建PixelMap
    console.log(`[转PixelMap] ${filename}：开始创建PixelMap`);
    const pixelMapOptions: image.InitializationOptions = {
      size: {
        width: imageInfo.size.width,
        height: imageInfo.size.height
      },
      pixelFormat: image.PixelMapFormat.RGBA_8888,
      alphaType: image.AlphaType.OPAQUE,
      editable: false
    };
    const pixelMap = await imageSource.createPixelMap(pixelMapOptions);
    if (!pixelMap) {
      throw new Error(`创建PixelMap失败`);
    }

    console.log(`[转PixelMap] ${filename}：PixelMap创建成功`);
    return pixelMap;
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
          Text(`共找到 ${this.thumbnails.length} 张照片`).fontSize(14).padding({ left: 16, top: 10 });
          List({ space: 10 }) {
            ForEach(this.imageInfos, (item: ImageInfoWithPixelMap) => {
              ListItem() {
                Column({ space: 5 }) {
                  if (item.pixelMap) {
                    Image(item.pixelMap).width(80).height(80).objectFit(ImageFit.Contain);
                  } else {
                    Text('暂无图片').width(80).height(80).textAlign(TextAlign.Center);
                  }
                  Text(`照片名：${item.filename}`).fontSize(16).fontWeight(FontWeight.Medium);
                  Text(`路径：${item.folder}`).fontSize(12);
                }.padding(16).borderRadius(10).width('100%');
              }
            }, (item: ImageInfoWithPixelMap) => item.filename + item.folder);
          }.padding(16).width('100%').flexGrow(1);
        }
      }.width('100%').height('100%');
    }.title('机内照片').menus(this.menuItems).width('100%').height('100%');
  }
}