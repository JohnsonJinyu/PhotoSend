// PhoneLocalPhotos.ets
import fs from "@ohos.file.fs"
import { promptAction } from "@kit.ArkUI";
import { uri } from "@kit.ArkTS";

// 图片信息模型
interface ImageInfo {
  uri: string;
  name: string;
  modifyTime: number;
  dateStr: string;
}

@Preview
@Component
export struct PhoneLocalPhotos {
  @State images: ImageInfo[] = []
  @State isLoading: boolean = true;

  // 正确写法：@Watch 装饰在 @Link 变量上，指定触发的方法名
  @Link @Watch('onPathChange') appStoragePath: string;

  // 普通方法：作为 @Watch 的回调（不需要任何装饰器）
  private onPathChange(newPath: string, oldPath: string) {
    console.log(`路径变化：旧=${oldPath}，新=${newPath}`);
    if (newPath && newPath !== oldPath) {
      this.loadImages(); // 路径变了就重新加载图片
    }
  }

  // 组件初始化时，如果路径已存在，直接加载图片
  async aboutToAppear() {
    if (this.appStoragePath) {
      await this.loadImages();
    }
  }

  // 加载图片的逻辑（保持不变）
  async loadImages() {
    if (!this.appStoragePath) {
      this.isLoading = false;
      return;
    }

    try {
      this.isLoading = true;
      const imageFiles: ImageInfo[] = [];

      // 读取应用专属目录下的文件
      const fileList = await fs.listFile(this.appStoragePath);

      // 筛选图片文件
      for (const fileName of fileList) {
        if (this.isImageFile(fileName)) {
          const filePath = `${this.appStoragePath}/${fileName}`;
          const stat = await fs.stat(filePath);
          const modifyTime = stat.mtime;
          const dateStr = this.formatDate(new Date(modifyTime));

          imageFiles.push({
            uri:  `file://${filePath}`, // 关键：拼接成标准的 URI 格式
            name: fileName,
            modifyTime: modifyTime,
            dateStr: dateStr
          });
           // 添加此行日志
       //console.log(`拼接的图片uri为：${}`)
        }
      }

      // 按修改时间排序
      imageFiles.sort((a, b) => b.modifyTime - a.modifyTime);
      this.images = imageFiles;
    } catch (err) {
      console.error('加载图片失败: ' + JSON.stringify(err));
      promptAction.showToast({ message: '加载图片失败' });
    } finally {
      this.isLoading = false;
    }
  }

  // 其他辅助方法（保持不变）
  isImageFile(fileName: string): boolean {
    const imageExtensions = ['.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp'];
    const ext = fileName.substring(fileName.lastIndexOf('.')).toLowerCase();
    return imageExtensions.includes(ext);
  }

  formatDate(date: Date): string {
    const year = date.getFullYear();
    const month = this.padZero(date.getMonth() + 1);
    const day = this.padZero(date.getDate());
    const hour = this.padZero(date.getHours());
    const minute = this.padZero(date.getMinutes());
    return `${year}-${month}-${day} ${hour}:${minute}`;
  }

  padZero(num: number): string {
    return num < 10 ? '0' + num : num.toString();
  }

  @Builder TimeLineDot(isFirst: boolean, isLast: boolean) {
    Column() {
      if (!isFirst) {
        Divider()
          .vertical(true)
          .height('100%')
          .color('#DDDDDD')
      }
      Circle()
        .width(12)
        .height(12)
        .fill('#007DFF')
      if (!isLast) {
        Divider()
          .vertical(true)
          .height('100%')
          .color('#DDDDDD')
      }
    }
    .width(12)
  }

  build() {
    // 保持不变
    Column() {
      Row() {
        Text('图片时间轴')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .margin({ top: 10, bottom: 10 })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)

      if (this.isLoading) {
        Progress({ value: 0, type: ProgressType.Capsule })
          .width(40)
          .height(40)
          .margin({ top: 50 })
      }
      else if (this.images.length === 0) {
        Column() {
          Text('📷')
            .fontSize(50)
            .margin({ bottom: 20 })
          Text('暂无图片')
            .fontSize(16)
            .fontColor('#999999')
        }
        .width('100%')
        .height('80%')
        .justifyContent(FlexAlign.Center)
      }
      else {
        List({ space: 10 }) {
          ForEach(this.images, (item: ImageInfo, index: number) => {
            ListItem() {
              Row() {
                this.TimeLineDot(index === 0, index === this.images.length - 1)
                Column() {
                  Text(item.dateStr)
                    .fontSize(14)
                    .fontColor('#666666')
                    .margin({ bottom: 8 })
                  Image(item.uri)
                    .width('100%')
                    .height(200)
                    .objectFit(ImageFit.Cover)
                    .borderRadius(8)
                    .margin({ bottom: 8 })
                  Text(item.name)
                    .fontSize(14)
                    .fontColor('#333333')
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .width('90%')
                .padding({ left: 10 })
              }
              .width('100%')
              .padding({ left: 20, right: 20, top: 5, bottom: 5 })
            }
          }, (item: ImageInfo) => item.uri)
        }
        .width('100%')
        .padding({ top: 10 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
  }
}