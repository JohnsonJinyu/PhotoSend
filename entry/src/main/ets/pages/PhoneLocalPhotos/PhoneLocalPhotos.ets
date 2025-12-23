// PhoneLocalPhotos.ets
// 以Gird显示的图片里表页面
import { promptAction } from "@kit.ArkUI";
import { MyNodeController } from "../../NodeContainer/CustomComponent";
import { ExifReader } from "./ExifReader";
import { ImageInfo, LocalPhotoDataSource } from './LocalPhotoDataSource';


// 👇 新增：定义跳转详情页的参数接口（和 LocalPhotoDetail 中的 ReceiveParams 结构一致）
interface PhotoDetailParams {
  selectedIndex: number;
}



@Preview
@Component
export struct PhoneLocalPhotos {
  @Consume('pageStack') pageStack: NavPathStack;
  private pageId = 2
  //@State myNodeController:MyNodeController|undefined = new MyNodeController()



  @State private dataSource: LocalPhotoDataSource = LocalPhotoDataSource.getInstance(); // 用单例
  @State isLoading: boolean = true;
  @State isRefreshing: boolean = false;
  @StorageLink('selectedIndex') selectedIndex:number = 0  // 记录当前选中的图片索引（用于传递给详情页）

  @Link @Watch('onPathChange') appStoragePath: string;

  // 路径变化回调（不变）
  private onPathChange(newPath: string, oldPath: string) {
    console.log(`路径变化：旧=${oldPath}，新=${newPath}`);
    if (newPath && newPath !== oldPath) {
      this.dataSource.updatePath(newPath);
      this.loadImages();
    }
  }

  // 组件初始化（不变）
  async aboutToAppear() {
    if (this.appStoragePath) {
      this.dataSource.updatePath(this.appStoragePath);
      await this.loadImages();
    }
  }

  // 加载图片（不变）
  private async loadImages() {
    const isInitialLoad = this.dataSource.totalCount() === 0;
    isInitialLoad ? (this.isLoading = true) : (this.isRefreshing = true);

    try {
      await this.dataSource.loadData();
    } catch (err) {
      promptAction.showToast({ message: '加载图片失败' });
    } finally {
      this.isLoading = false;
      this.isRefreshing = false;
    }
  }

  // --------------- 关键：用 @Builder 封装单个 GridItem 布局（直观易懂）---------------
  @Builder
  private ImageGridItem(item: ImageInfo, index: number) {
    GridItem() {
      Column() {
        // 使用Stack来叠加图片和RAW标记
        Stack() {
          Image(item.uri)
            .width('100%')
            .aspectRatio(1)
            .objectFit(ImageFit.Cover)
            .borderRadius(4)
            .syncLoad(false)
            .autoResize(true)
            .dynamicRangeMode(DynamicRangeMode.HIGH)
            .rotate({ angle: item.rotationAngle || 0 })
            .geometryTransition(item.uri, { follow: false })
            .onClick(() => {
              this.selectedIndex = index;
              const detailParams: PhotoDetailParams = {
                selectedIndex: index
              };
              this.pageStack.pushPathByName("LocalPhotoDetail", detailParams, true);
            })

          // RAW文件标记 - 使用position和margin的组合
          if (item.isRawFile) {
            Text('RAW')
              .fontSize(10)
              .fontColor('#ffffff')
              .backgroundColor('rgba(0, 0, 0, 0.7)')
              .padding({ left: 4, right: 4, top: 2, bottom: 2 })
              .borderRadius(2)
              // 关键修改：position使用百分比 + 负的margin
              .position({
                right: 4,  // 距离右边4px
                bottom: 4  // 距离底部4px
              })
              .hitTestBehavior(HitTestMode.None) // 关键：让点击事件穿透
          }
        }
        .width('100%')
        .aspectRatio(1)

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
  }

  // --------------- UI 渲染（扁平化结构，一眼看懂）---------------
  build() {
    Column() {
      // 加载中提示
      if (this.isLoading) {
        Progress({ value: 0, type: ProgressType.Capsule })
          .width(40)
          .height(40)
          .margin({ top: 50 });
      }
      // 无数据提示
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
      // 图片列表（核心：扁平化 LazyForEach 写法）
      else {
        Refresh({
          refreshing: this.isRefreshing,
          promptText: "正在刷新"
        }) {
          // 1. 外层是 Grid 容器（常规布局）
          Grid() {
            // 2. Grid 直接包含 LazyForEach，生成 GridItem
            LazyForEach(
              this.dataSource, // 第1参数：数据源（和 ForEach 的数组作用一样）
              (item: ImageInfo,index:number) => {
                // 第2参数：生成每个 GridItem（直接调用封装好的 Builder，直观！）
                this.ImageGridItem(item,index);
              },
              (item: ImageInfo) => item.uri // 第3参数：唯一键（和 ForEach 的 key 作用一样）
            )

          }
          // Grid 的布局属性（常规写法）
          .columnsTemplate('1fr 1fr')
          .columnsGap(10)
          .rowsGap(10)
          .padding(10)
          .width('100%');
        }
        .refreshOffset(96)
        .pullToRefresh(true)
        .onRefreshing(() => {
          this.loadImages();
        });
      }
    }
    .width('100%')
    .height('100%');
  }
}