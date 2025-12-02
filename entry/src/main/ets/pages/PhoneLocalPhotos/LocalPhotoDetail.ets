import { ImageInfo } from "./LocalPhotoDataSource";
import Constants from "../../common/constants/Constants";
import { BusinessError } from '@kit.BasicServicesKit';
import { display } from "@kit.ArkUI";

// 滚动偏移接口（适配API20/21）
interface ScrollOffset {
  xOffset: number;
  yOffset: number;
}

// 滚动类型枚举（和官方一致）
enum scrollTypeEnum {
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
  @State imageWidth: number = this.deviceWidth + this.smallImgWidth;
  @StorageLink('selectedIndex') selectedIndex: number = 0; // 响应式索引（双向绑定核心）
  private readonly DOUBLE_NUMBER = Constants.DOUBLE_NUMBER || 2;

  // 小图项总宽度（宽度+间距，核心计算依据）
  private get smallItemTotalWidth(): number {
    return this.smallImgWidth + Constants.LIST_ITEM_SPACE;
  }

  aboutToAppear() {
    try {
      const displayClass = display.getDefaultDisplaySync();
      const width = displayClass?.width / displayClass.densityPixels ?? Constants.DEFAULT_WIDTH;
      this.deviceWidth = width;
      this.smallImgWidth = (width - Constants.LIST_ITEM_SPACE * (Constants.SHOW_COUNT - 1)) / Constants.SHOW_COUNT;
      this.imageWidth = this.deviceWidth + this.smallImgWidth;
    } catch (error) {
      const err = error as BusinessError;
      console.error(`getDefaultDisplaySync failed, code=${err.code}, message=${err.message}`);
    }
  }

  onPageShow() {
    if (this.params) {
      this.selectedIndex = this.params.selectedIndex;
      // 初始化大图位置（小图位置由centerSmallSelectedItem统一控制）
      this.bigScroller.scrollTo({ xOffset: this.selectedIndex * this.imageWidth, yOffset: 0 });
      this.centerSmallSelectedItem(); // 初始就让选中项（第一张）居中，无延迟
    }
  }

  // 核心优化：选中项固定在屏幕正中心（X/2位置），其他项堆栈式排列
  private centerSmallSelectedItem(): void {
    if (!this.params?.imageList || this.params.imageList.length === 0) return;

    // 关键计算：让选中项的「中心点」和屏幕「中心点」完全重合
    const screenCenter = this.deviceWidth / 2; // 屏幕正中心X坐标
    const itemCenter = this.smallItemTotalWidth / 2; // 单个小图项的中心点X坐标（相对于列表）
    // 目标偏移量 = 选中项左侧偏移量 + 项中心点 - 屏幕中心点
    // 结果：选中项永远固定在屏幕X/2位置，前面的项向左堆叠，后面的项向右堆叠
    let targetOffset = (this.selectedIndex * this.smallItemTotalWidth) + itemCenter - screenCenter;

    // 边界限制：避免列表滚动超出范围（第一张图不能向左滚，最后一张不能向右滚）
    const minOffset = 0;
    const maxOffset = Math.max(0, (this.params.imageList.length - 1) * this.smallItemTotalWidth + itemCenter - screenCenter);
    targetOffset = Math.min(Math.max(targetOffset, minOffset), maxOffset);

    // 强制滚动到目标位置（忽略原有滚动状态，确保居中优先级最高）
    this.smallScroller.scrollTo({
      xOffset: targetOffset,
      yOffset: 0,
      animation: { duration: 150, curve: Curve.EaseOut } // 加快动画，更跟手
    });
  }

  // 小图点击事件（点击后直接固定居中）
  private smallImgClickAction(index: number): void {
    this.selectedIndex = index;
    this.bigScroller.scrollTo({ xOffset: this.selectedIndex * this.imageWidth, yOffset: 0 });
    this.centerSmallSelectedItem(); // 点击后立即固定居中
  }

  // 1. 小图滚动同步大图（滚动停止后固定居中）
  private smallScrollAction(type: scrollTypeEnum): void {
    // 计算当前滚动到的索引
    this.selectedIndex = Math.round(
      (this.smallScroller.currentOffset().xOffset as number + this.smallImgWidth / this.DOUBLE_NUMBER) / this.smallItemTotalWidth
    );
    // 边界校验
    this.selectedIndex = Math.max(0, Math.min(this.selectedIndex, (this.params?.imageList.length || 1) - 1));

    if (type === scrollTypeEnum.SCROLL) {
      this.bigScroller.scrollTo({ xOffset: this.selectedIndex * this.imageWidth, yOffset: 0 });
    } else {
      this.bigScroller.scrollTo({ xOffset: this.selectedIndex * this.imageWidth, yOffset: 0 });
      this.centerSmallSelectedItem(); // 滚动停止后，强制固定选中项到中心
    }
  }

  // 2. 大图滚动同步小图（滚动停止后固定居中）
  private bigScrollAction(type: scrollTypeEnum): void {
    // 计算当前滚动到的索引
    this.selectedIndex = Math.round(
      (this.bigScroller.currentOffset().xOffset as number + this.smallItemTotalWidth / this.DOUBLE_NUMBER) / this.imageWidth
    );
    // 边界校验
    this.selectedIndex = Math.max(0, Math.min(this.selectedIndex, (this.params?.imageList.length || 1) - 1));

    if (type === scrollTypeEnum.SCROLL) {
      this.smallScroller.scrollTo({ xOffset: this.selectedIndex * this.smallItemTotalWidth, yOffset: 0 });
    } else {
      this.smallScroller.scrollTo({ xOffset: this.selectedIndex * this.smallItemTotalWidth, yOffset: 0 });
      this.centerSmallSelectedItem(); // 滚动停止后，强制固定选中项到中心
    }
  }

  // 小图Builder（响应式边框，选中项始终高亮）
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
        // --------------- 大图区域（整页切换，同步索引）---------------
        List({ scroller: this.bigScroller, initialIndex: this.selectedIndex }) {
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
            this.bigScrollAction(scrollTypeEnum.SCROLL);
          }
        })
        .scrollBar(BarState.Off)
        .onScrollStop(() => this.bigScrollAction(scrollTypeEnum.STOP))
        .width('100%')
        .height('100%')
        .padding({ bottom: this.smallImgWidth * this.DOUBLE_NUMBER })
        .listDirection(Axis.Horizontal);

        // --------------- 小图区域（选中项固定居中，堆栈式排列）---------------
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
              .padding(1); // 防边框裁剪
            },
            (item: ImageInfo) => item.uri
          )
        }
        .listDirection(Axis.Horizontal)
        .onDidScroll((_, scrollState) => {
          if (scrollState === ScrollState.Fling) {
            this.smallScrollAction(scrollTypeEnum.SCROLL);
          }
        })
        .scrollBar(BarState.Off)
        .onScrollStop(() => this.smallScrollAction(scrollTypeEnum.STOP))
        .margin({
          top: $r('app.float.detail_list_margin') || 16,
          bottom: $r('app.float.detail_list_margin') || 16
        })
        .height(this.smallImgWidth + 6) // 预留边框空间
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
        // 页面就绪后再校准一次居中（确保初始位置100%正确）
        setTimeout(() => this.centerSmallSelectedItem(), 50);
      } catch (e) {
        const err = e as BusinessError;
        console.error(`参数解析异常: code=${err.code}, message=${err.message}`);
      }
    });
  }
}