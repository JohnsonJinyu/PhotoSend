// LocalPhotoDetail.ets
import { ImageInfo, LocalPhotoDataSource } from "./LocalPhotoDataSource";
import Constants from "../../common/constants/Constants";
import { BusinessError } from '@kit.BasicServicesKit';
import { display } from "@kit.ArkUI";

interface ReceiveParams {
  selectedIndex: number;
}

@Builder
export function LocalPhotoDetailBuilder() {
  LocalPhotoDetail();
}

@Component
struct LocalPhotoDetail {
  private dataSource: LocalPhotoDataSource = LocalPhotoDataSource.getInstance();
  private params: ReceiveParams | null = null;

  // 滚动控制器
  private smallScroller: Scroller = new Scroller();
  private bigScroller: Scroller = new Scroller();

  // 尺寸配置
  @State deviceWidth: number = Constants.DEFAULT_WIDTH || 360;
  @State smallImgWidth: number = (this.deviceWidth - Constants.LIST_ITEM_SPACE * (Constants.SHOW_COUNT - 1)) / Constants.SHOW_COUNT;
  @State imageWidth: number = this.deviceWidth;

  // 局部状态管理索引
  @State selectedIndex: number = 0;
  // 同步来源标记：避免循环触发（1=小图滚动, 2=大图滚动, 3=小图点击）
  @State syncSource: number = 0;

  /**
   * 生命周期：初始化设备尺寸
   */
  aboutToAppear() {
    try {
      const displayClass = display.getDefaultDisplaySync();
      const width = displayClass?.width / displayClass.densityPixels ?? Constants.DEFAULT_WIDTH;
      this.deviceWidth = width;
      this.smallImgWidth = (width - Constants.LIST_ITEM_SPACE * (Constants.SHOW_COUNT - 1)) / Constants.SHOW_COUNT;
      this.imageWidth = width;
    } catch (error) {
      const err = error as BusinessError;
      console.error(`获取屏幕尺寸失败: 错误码=${err.code}, 错误信息=${err.message}`);
    }
  }

  /**
   * 核心方法：计算小图item居中的偏移量，强制滚动到居中位置
   * @param targetIndex 目标图片索引
   */
  private scrollSmallToCenter(targetIndex: number): void {
    if (this.dataSource.totalCount() === 0 || targetIndex < 0 || targetIndex >= this.dataSource.totalCount()) {
      return;
    }

    // 单个小图item的总宽度（包含间距）
    const singleItemTotalWidth = this.smallImgWidth + Constants.LIST_ITEM_SPACE;
    // 小图List的可视区域中心位置
    const listCenterX = this.deviceWidth / 2;
    // 目标item的中心位置（相对于List的起始位置）
    const itemCenterX = targetIndex * singleItemTotalWidth + (this.smallImgWidth / 2);
    // 需要滚动的偏移量（让item中心和List中心重合）
    const targetOffsetX = itemCenterX - listCenterX;

    // 修正：scrollTo只传1个对象参数（包含animation配置）
    this.smallScroller.scrollTo({
      xOffset: targetOffsetX,
      yOffset: 0,
      animation: false  // 禁用动画，避免叠加
    });
  }

  /**
   * 生命周期：页面显示时初始化滚动位置
   */
  onPageShow() {
    if (this.params && this.dataSource.totalCount() > 0) {
      const targetIndex = Math.max(0, Math.min(this.params.selectedIndex, this.dataSource.totalCount() - 1));
      this.selectedIndex = targetIndex;

      // 大图初始化
      this.bigScroller.scrollToIndex(targetIndex, false);
      // 小图初始化：强制居中
      this.scrollSmallToCenter(targetIndex);
    }
  }

  /**
   * 小图点击事件：直接设置索引+强制居中
   */
  private smallImgClickAction(index: number): void {
    if (index === this.selectedIndex || this.dataSource.totalCount() === 0) return;

    const validIndex = Math.max(0, Math.min(index, this.dataSource.totalCount() - 1));
    this.syncSource = 3;
    this.selectedIndex = validIndex;

    // 大图同步
    this.bigScroller.scrollToIndex(validIndex, false);
    // 小图强制居中（核心修复）
    this.scrollSmallToCenter(validIndex);

    setTimeout(() => {
      this.syncSource = 0;
    }, 200); // 延长延迟，确保居中完成
  }

  /**
   * 小图构建器：选中项高亮
   */
  @Builder
  private SmallImgItemBuilder(item: ImageInfo, index: number): void {
    Image(item.uri)
      .width(this.smallImgWidth)
      .height(this.smallImgWidth)
      .orientation(ImageRotateOrientation.AUTO)
      .aspectRatio(1)
      .objectFit(ImageFit.Cover)
      .borderRadius(4)
      .backgroundColor('rgba(0,0,0,0.3)')
      .borderWidth(this.selectedIndex === index ? 3 : 0)
      .borderColor('#ffffff')
      .borderStyle(BorderStyle.Solid)
      .onClick(() => this.smallImgClickAction(index));
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.Bottom }) {
        // --------------- 大图List ---------------
        List({
          scroller: this.bigScroller,
          initialIndex: this.selectedIndex
        }) {
          ForEach(
            this.dataSource.dataList || [],
            (item: ImageInfo) => {
              ListItem() {
                Image(item.uri)
                  .width('100%')
                  .height('100%')
                  .orientation(ImageRotateOrientation.AUTO)
                  .objectFit(ImageFit.Contain)
                  .backgroundColor('#000');
              }
              .width(this.imageWidth);
            },
            (item: ImageInfo) => item.uri
          )
        }
        .scrollSnapAlign(ScrollSnapAlign.CENTER)
        .onScrollStop(() => {
          if (this.dataSource.totalCount() === 0 || this.syncSource !== 0) return;

          // 计算大图最终索引
          const finalIndex = Math.round(this.bigScroller.currentOffset().xOffset / this.imageWidth);
          const validIndex = Math.max(0, Math.min(finalIndex, this.dataSource.totalCount() - 1));

          if (validIndex !== this.selectedIndex) {
            this.syncSource = 2;
            this.selectedIndex = validIndex;
            // 小图强制居中（核心修复）
            this.scrollSmallToCenter(validIndex);

            setTimeout(() => {
              this.syncSource = 0;
            }, 200);
          }
        })
        .scrollBar(BarState.Off)
        .width('100%')
        .height('100%')
        .padding({ bottom: this.smallImgWidth + 20 })
        .listDirection(Axis.Horizontal);

        // --------------- 小图List ---------------
        List({
          scroller: this.smallScroller,
          space: Constants.LIST_ITEM_SPACE,
          initialIndex: this.selectedIndex
        }) {
          ForEach(
            this.dataSource.dataList || [],
            (item: ImageInfo, index: number) => {
              ListItem() {
                this.SmallImgItemBuilder(item, index);
              }
              .width(this.smallImgWidth)
              .aspectRatio(1)
              .padding(1);
            },
            (item: ImageInfo) => item.uri
          )
        }
        .listDirection(Axis.Horizontal)
        .scrollSnapAlign(ScrollSnapAlign.CENTER) // 保留原生拖动居中
        // 小图滚动同步到大图
        .onScrollIndex((_firstIndex: number, _lastIndex: number, centerIndex: number) => {
          if (this.dataSource.totalCount() === 0 || this.syncSource !== 0) return;

          const validCenterIndex = Math.max(0, Math.min(centerIndex, this.dataSource.totalCount() - 1));

          if (validCenterIndex !== this.selectedIndex) {
            this.syncSource = 1;
            this.selectedIndex = validCenterIndex;
            // 大图同步
            this.bigScroller.scrollToIndex(validCenterIndex, false);

            setTimeout(() => {
              this.syncSource = 0;
            }, 200);
          }
        })
        .scrollBar(BarState.Off)
        .margin({ top: 16, bottom: 16 })
        .height(this.smallImgWidth + 12)
        .width('100%');
      }
      .width('100%')
      .height('100%');
    }
    .title(() => {
      if (this.dataSource.totalCount() === 0) return '图片详情';
      const validIndex = Math.max(0, Math.min(this.selectedIndex, this.dataSource.totalCount() - 1));
      return this.dataSource.dataList[validIndex]?.name || '图片详情';
    })
    .backgroundColor('#000')
    .hideBackButton(false)
    .onReady((ctx: NavDestinationContext) => {
      try {
        this.params = ctx.pathInfo.param as ReceiveParams;
        if (this.params) {
          this.selectedIndex = this.params.selectedIndex;
        }
      } catch (e) {
        const err = e as BusinessError;
        console.error(`路由参数解析异常: 错误码=${err.code}, 错误信息=${err.message}`);
      }
    });
  }
}