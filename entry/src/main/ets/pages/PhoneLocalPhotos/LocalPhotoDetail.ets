import { ImageInfo } from "./LocalPhotoDataSource";
import Constants from "../../common/constants/Constants";
import { BusinessError } from '@kit.BasicServicesKit';

// 滚动偏移接口（适配API20/21）
interface ScrollOffset {
  xOffset: number;
  yOffset: number;
}

// 滚动类型枚举（和官方一致）
enum ScrollTypeEnum {
  STOP = 'onScrollStop',
  SCROLL = 'onScroll'
}

// 参数接口
interface ReceiveParams {
  imageList: ImageInfo[];
  selectedIndex: number;
}

@Builder
export function LocalPhotoDetailBuilder() {
  LocalPhotoDetail();
}

@Component
struct LocalPhotoDetail{
  private params: ReceiveParams | null = null;
  private smallScroller: Scroller = new Scroller();
  private bigScroller: Scroller = new Scroller();
  @State deviceWidth: number = Constants.DEFAULT_WIDTH || 360;
  @State smallImgWidth: number = (this.deviceWidth - Constants.LIST_ITEM_SPACE * (Constants.SHOW_COUNT - 1)) / Constants.SHOW_COUNT;
  @State imageWidth: number = this.deviceWidth + this.smallImgWidth; // 官方宽度计算
  @StorageLink('selectedIndex') selectedIndex: number = 0;
  private readonly DOUBLE_NUMBER = Constants.DOUBLE_NUMBER || 2;

  // 小图项总宽度（宽度+间距）
  private get smallItemTotalWidth(): number {
    return this.smallImgWidth + Constants.LIST_ITEM_SPACE;
  }

  aboutToAppear() {
    try {
      // 重新计算尺寸（和官方一致）
      this.smallImgWidth = (this.deviceWidth - Constants.LIST_ITEM_SPACE * (Constants.SHOW_COUNT - 1)) / Constants.SHOW_COUNT;
      this.imageWidth = this.deviceWidth + this.smallImgWidth;
    } catch (error) {
      const err = error as BusinessError;
      console.error(`初始化失败: code=${err.code}, message=${err.message}`);
    }
  }

  onPageShow() {
    if (this.params) {
      this.selectedIndex = this.params.selectedIndex;
      // 初始化滚动位置（同步大图小图）
      this.smallScroller.scrollToIndex(this.selectedIndex, true); // 增加动画，同步体验
      this.bigScroller.scrollToIndex(this.selectedIndex, true);
      setTimeout(() => this.centerSmallSelectedItem(), 100);
    }
  }

  // 小图点击事件：切换+居中（保留现有逻辑）
  private smallImgClickAction(index: number): void {
    this.selectedIndex = index;
    this.bigScroller.scrollToIndex(index, true); // 大图同步切换
    this.smallScroller.scrollToIndex(index, true); // 小图同步切换
    this.centerSmallSelectedItem();
  }

  // 小图居中（保留现有逻辑）
  private centerSmallSelectedItem(): void {
    const centerOffset = (this.deviceWidth - this.smallItemTotalWidth) / 2;
    const targetOffset = this.selectedIndex * this.smallItemTotalWidth - centerOffset;
    const maxOffset = Math.max(0, (this.params?.imageList.length || 1 - 1) * this.smallItemTotalWidth - centerOffset);
    const finalOffset = Math.min(targetOffset, maxOffset);

    this.smallScroller.scrollTo({
      xOffset: finalOffset,
      yOffset: 0,
      animation: { duration: 200, curve: Curve.EaseOut }
    });
  }

  // 1. 修复：小图滚动同步大图（补充scrollToIndex，确保绑定）
  private smallScrollAction(type: ScrollTypeEnum): void {
    const currentOffset = this.smallScroller.currentOffset() as ScrollOffset;
    let currentIndex = Math.round((currentOffset.xOffset + this.smallImgWidth / this.DOUBLE_NUMBER) / this.smallItemTotalWidth);

    if (this.params?.imageList) {
      currentIndex = Math.max(0, Math.min(currentIndex, this.params.imageList.length - 1));
    }

    this.selectedIndex = currentIndex;
    if (type === ScrollTypeEnum.SCROLL) {
      this.bigScroller.scrollTo({ xOffset: currentIndex * this.imageWidth, yOffset: 0 });
    } else {
      // 关键：小图滚动停止后，大图同步切换到对应索引
      this.bigScroller.scrollToIndex(currentIndex, true);
      this.centerSmallSelectedItem();
    }
  }

  // 2. 修复：大图滚动同步小图（补充scrollToIndex，确保绑定）
  private bigScrollAction(type: ScrollTypeEnum): void {
    const currentOffset = this.bigScroller.currentOffset() as ScrollOffset;
    let currentIndex = Math.round((currentOffset.xOffset + this.smallItemTotalWidth / this.DOUBLE_NUMBER) / this.imageWidth);

    if (this.params?.imageList) {
      currentIndex = Math.max(0, Math.min(currentIndex, this.params.imageList.length - 1));
    }

    this.selectedIndex = currentIndex;
    if (type === ScrollTypeEnum.SCROLL) {
      this.smallScroller.scrollTo({ xOffset: currentIndex * this.smallItemTotalWidth, yOffset: 0 });
    } else {
      // 关键：大图滚动停止后，小图同步切换到对应索引
      this.smallScroller.scrollToIndex(currentIndex, true);
      this.centerSmallSelectedItem();
    }
  }

  // 3. 修复：小图白色边框（增强样式优先级，确保显示）
  @Builder
  private SmallImgItemBuilder(item: ImageInfo, index: number): void {
    Image(item.uri)
      .width(this.smallImgWidth)
      .height(this.smallImgWidth)
      .orientation(ImageRotateOrientation.AUTO)
      .aspectRatio(1)
      .objectFit(ImageFit.Cover)
      .borderRadius(4)
      // 增强：增加背景色，让白色边框更明显；提升边框优先级
      .backgroundColor('rgba(0,0,0,0.3)')
      .borderWidth(this.selectedIndex === index ? 3 : 0)
      .borderColor('#ffffff')
      .borderStyle(BorderStyle.Solid) // 明确边框样式（API20/21支持）
      .onClick(() => this.smallImgClickAction(index));
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.Bottom }) {
        // --------------- 大图区域（保留现有Swiper效果）---------------
        List({
          scroller: this.bigScroller,
          initialIndex: this.selectedIndex
        }) {
          ForEach(
            this.params?.imageList || [],
            (item: ImageInfo) => {
              ListItem() {
                Image(item.uri)
                  .width('100%')
                  .height('100%')
                  .orientation(ImageRotateOrientation.AUTO)
                  .objectFit(ImageFit.Contain)
                  .backgroundColor('#000');
              }
              .padding({
                left: this.smallImgWidth / this.DOUBLE_NUMBER,
                right: this.smallImgWidth / this.DOUBLE_NUMBER
              })
              .width(this.imageWidth)
            },
            (item: ImageInfo) => item.uri
          )
        }
        .scrollSnapAlign(ScrollSnapAlign.CENTER)
        .onDidScroll((_, scrollState) => {
          if (scrollState === ScrollState.Fling) {
            this.bigScrollAction(ScrollTypeEnum.SCROLL);
          }
        })
        .scrollBar(BarState.Off)
        .onScrollStop(() => this.bigScrollAction(ScrollTypeEnum.STOP))
        .width('100%')
        .height('100%')
        .padding({ bottom: this.smallImgWidth * this.DOUBLE_NUMBER })
        .listDirection(Axis.Horizontal);

        // --------------- 小图区域（修复绑定+边框）---------------
        List({
          scroller: this.smallScroller,
          space: Constants.LIST_ITEM_SPACE,
          initialIndex: this.selectedIndex
        }) {
          ForEach(
            this.params?.imageList || [],
            (item: ImageInfo, index: number) => {
              ListItem() {
                this.SmallImgItemBuilder(item, index);
              }
              .width(this.smallImgWidth)
              .aspectRatio(1)
              // 增强：ListItem增加内边距，避免边框被裁剪
              .padding(1);
            },
            (item: ImageInfo) => item.uri
          )
        }
        .scrollSnapAlign(ScrollSnapAlign.CENTER)
        .listDirection(Axis.Horizontal)
        .onDidScroll((_, scrollState) => {
          if (scrollState === ScrollState.Fling) {
            this.smallScrollAction(ScrollTypeEnum.SCROLL);
          }
        })
        .scrollBar(BarState.Off)
        .onScrollStop(() => this.smallScrollAction(ScrollTypeEnum.STOP))
        .margin({
          top: $r('app.float.detail_list_margin') || 16,
          bottom: $r('app.float.detail_list_margin') || 16
        })
        .height(this.smallImgWidth + 6) // 预留边框空间（3px边框+1px内边距）
        .width('100%');
      }
      .width('100%')
      .height(Constants.FULL_PERCENT);
    }
    .title(this.params?.imageList[this.selectedIndex]?.name || '图片详情')
    .backgroundColor('#000')
    .hideBackButton(false)
    .onReady((ctx: NavDestinationContext) => {
      try {
        this.params = ctx.pathInfo.param as ReceiveParams;
        this.selectedIndex = this.params?.selectedIndex || 0;
      } catch (e) {
        const err = e as BusinessError;
        console.error(`参数解析异常: code=${err.code}, message=${err.message}`);
      }
    });
  }
}