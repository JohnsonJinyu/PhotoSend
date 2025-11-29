// PhoneLocalPhotos.ets
import { promptAction } from "@kit.ArkUI";
// 导入数据管理类、模型、LazyForEach（官方必需）
import {  ImageInfo, LocalPhotoDataSource } from './LocalPhotoDataSource';

@Preview
@Component
export struct PhoneLocalPhotos {
  // 1. 注入数据管理实例（UI层不存储数据，仅持有数据类引用）
  @State private dataSource: LocalPhotoDataSource = new LocalPhotoDataSource();
  @State isLoading: boolean = true;
  @State isRefreshing: boolean = false;
  // 路径变化时，同步更新到数据层
  @Link @Watch('onPathChange') appStoragePath: string;

  // 2. 路径变化回调（仅通知数据层更新路径，不处理数据）
  private onPathChange(newPath: string, oldPath: string) {
    console.log(`路径变化：旧=${oldPath}，新=${newPath}`);
    if (newPath && newPath !== oldPath) {
      this.dataSource.updatePath(newPath); // 同步路径到数据层
      this.loadImages(); // 触发数据加载
    }
  }

  // 3. 组件初始化（仅调用数据层加载方法）
  async aboutToAppear() {
    if (this.appStoragePath) {
      this.dataSource.updatePath(this.appStoragePath); // 初始化路径
      await this.loadImages();
    }
  }

  // 4. 加载图片（仅调用数据层方法，不写任何数据逻辑）
  private async loadImages() {
    // 区分初始化和刷新状态（UI层仅管理UI状态）
    const isInitialLoad = this.dataSource.totalCount() === 0;
    isInitialLoad ? (this.isLoading = true) : (this.isRefreshing = true);

    try {
      await this.dataSource.loadData(); // 调用数据层加载数据
    } catch (err) {
      // UI层仅处理用户提示，不处理数据错误细节
      promptAction.showToast({ message: '加载图片失败' });
    } finally {
      // 重置UI状态
      this.isLoading = false;
      this.isRefreshing = false;
    }
  }

  // 5. UI渲染（仅渲染数据，无数据操作）
  build() {
    Column() {
      // 初始化加载提示
      if (this.isLoading) {
        Progress({ value: 0, type: ProgressType.Capsule })
          .width(40)
          .height(40)
          .margin({ top: 50 });
      }
      // 无数据提示（通过数据层获取总数）
      else if (this.dataSource.totalCount() === 0) {
        Column() {
          Text('📷')
            .fontSize(50)
            .margin({ bottom: 20 });
          Text('暂无图片')
            .fontSize(16)
            .fontColor('#999999');
        }
        .width('100%')
        .height('80%')
        .justifyContent(FlexAlign.Center);
      }
      // 图片列表（官方 LazyForEach 标准用法）
      else {
        Refresh({
          refreshing: this.isRefreshing, // 绑定正确的刷新状态
          promptText: "正在刷新"
        }) {
          Grid() {
            // --------------- 官方 LazyForEach 三参数用法 ---------------
            LazyForEach(
              this.dataSource, // 第1参数：IDataSource 实例（类型完全匹配）
              (item: ImageInfo) => { // 第2参数：项生成器（仅渲染UI）
                GridItem() {
                  Column() {
                    Image(item.uri)
                      .width('100%')
                      .aspectRatio(1)
                      .objectFit(ImageFit.Cover)
                      .borderRadius(4)
                      .syncLoad(false) // 异步加载

                      .dynamicRangeMode(DynamicRangeMode.HIGH)
                      .orientation(ImageRotateOrientation.AUTO);

                    Text(item.name)
                      .fontSize(12)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .margin({ top: 4, bottom: 8 })
                      .width('100%')
                      .textAlign(TextAlign.Center);
                  }
                  .padding(5);
                }
              },
              (item: ImageInfo) => item.uri // 第3参数：唯一键（与数据层保持一致）
            );
          }
          .columnsTemplate('1fr 1fr')
          .columnsGap(10)
          .rowsGap(10)
          .padding(10)
          .width('100%');
        }
        .refreshOffset(96)
        .pullToRefresh(true)
        .onRefreshing(() => {
          this.loadImages(); // 下拉刷新仅调用加载方法
        });
      }
    }
    .width('100%')
    .height('100%');
  }
}