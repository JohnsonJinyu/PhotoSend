// AsyncImage.ets - 简化版
import { ImageInfo } from './LocalPhotoDataSource';

@Component
export struct AsyncImage {
  @Prop item: ImageInfo;

  build() {
    Stack() {
      // 关键修改：添加 sourceSize 限制解码尺寸
      Image(this.item.uri)
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
        .borderRadius(4)
        .syncLoad(false)  // 异步加载
        .autoResize(true) // 启用自动调整

        .rotate({ angle: this.item.rotationAngle || 0 })

      // RAW文件标记
      if (this.item.isRawFile) {
        Text('RAW')
          .fontSize(10)
          .fontColor('#ffffff')
          .backgroundColor('rgba(0, 0, 0, 0.7)')
          .padding({ left: 4, right: 4, top: 2, bottom: 2 })
          .borderRadius(2)
          .position({
            right: 4,
            bottom: 4
          })
          .hitTestBehavior(HitTestMode.None)
      }
    }
    .width('100%')
    .aspectRatio(1)
    .backgroundColor('#f5f5f5') // 简单的占位背景
    .borderRadius(4)
  }
}