import { socket } from "@kit.NetworkKit";
import { common } from "@kit.AbilityKit";
import  fs  from "@ohos.file.fs"
import { promptAction, UIContext } from "@kit.ArkUI";

// 图片信息模型
interface ImageInfo {
  uri: string;
  name: string;
  modifyTime: number;
  dateStr: string;
}

@Preview
@Component
export struct PhoneLocalPictures {
  @State images: ImageInfo[] = []
  @State isLoading: boolean = true
  @State appStoragePath: string = ``

  uiContext = this.getUIContext()

  private context = this.uiContext?.getHostContext() as common.UIAbilityContext;

  // 页面初始化时获取图片
  async aboutToAppear() {
    try {
      // 获取应用沙箱存储路径 (API20正确方法)
      this.appStoragePath = this.context.cacheDir;

      // 加载图片
      await this.loadImages();
    }catch (error){

      console.error('获取存储路径失败: ' + JSON.stringify(error));
      this.isLoading = false;

    }
  }

  // 加载并处理图片
  async loadImages() {
    try {
      this.isLoading = true;
      const imageFiles: ImageInfo[] = [];

      // 读取目录下的所有文件
      const fileList = await fs.listFile(this.appStoragePath);

      // 筛选图片文件并获取信息
      for (const fileName of fileList) {
        // 检查文件是否为图片
        if (this.isImageFile(fileName)) {
          const filePath = this.appStoragePath + '/' + fileName;

          // 获取文件信息
          const stat = await fs.stat(filePath);

          // 直接使用stat.mtime（已为时间戳），无需转换
          const modifyTime = stat.mtime;

          // 格式化日期时再转换为Date对象
          const dateStr = this.formatDate(new Date(modifyTime));

          imageFiles.push({
            uri: 'file://' + filePath,
            name: fileName,
            modifyTime: modifyTime, // 文件修改时间戳

            dateStr: dateStr
          });
        }
      }

      // 按修改时间排序(最新的在前面)
      imageFiles.sort((a, b) => b.modifyTime - a.modifyTime);
      this.images = imageFiles;
    } catch (err) {
      console.error('加载图片失败: ' + JSON.stringify(err));
      //promptAction.showToast({ message: '加载图片失败' });
    } finally {
      this.isLoading = false;
    }
  }

  // 判断是否为图片文件
  isImageFile(fileName: string): boolean {
    const imageExtensions = ['.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp'];
    const ext = fileName.substring(fileName.lastIndexOf('.')).toLowerCase();
    return imageExtensions.includes(ext);
  }

  // 格式化日期显示
  formatDate(date: Date): string {
    const year = date.getFullYear();
    const month = this.padZero(date.getMonth() + 1);
    const day = this.padZero(date.getDate());
    const hour = this.padZero(date.getHours());
    const minute = this.padZero(date.getMinutes());
    return `${year}-${month}-${day} ${hour}:${minute}`;
  }

  // 数字补零
  padZero(num: number): string {
    return num < 10 ? '0' + num : num.toString();
  }

  // 时间轴节点组件
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
    Column() {
      // 页面标题
      Row() {
        Text('图片时间轴')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .margin({ top: 10, bottom: 10 })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)

      // 加载状态
      if (this.isLoading) {
        Progress({ value: 0, type: ProgressType.Capsule })
          .width(40)
          .height(40)
          .margin({ top: 50 })
      }
      // 无图片状态
      else if (this.images.length === 0) {
        Column() {
          Text('📷') // 用相机emoji替代图片
            .fontSize(50)
            .margin({ bottom: 20 })
          Text('本地无图')
            .fontSize(16)
            .fontColor('#999999')
        }
        .width('100%')
        .height('80%')
        .justifyContent(FlexAlign.Center)
      }
      // 图片时间轴列表
      else {
        List({ space: 10 }) {
          ForEach(this.images, (item: ImageInfo, index: number) => {
            ListItem() {
              Row() {
                // 时间轴节点
                this.TimeLineDot(index === 0, index === this.images.length - 1)

                // 图片和信息
                Column() {
                  // 日期时间
                  Text(item.dateStr)
                    .fontSize(14)
                    .fontColor('#666666')
                    .margin({ bottom: 8 })

                  // 图片
                  Image(item.uri)
                    .width('100%')
                    .height(200)
                    .objectFit(ImageFit.Cover)
                    .borderRadius(8)
                    .margin({ bottom: 8 })

                  // 文件名
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

