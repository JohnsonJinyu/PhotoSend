import { ImageInfo } from "./LocalPhotoDataSource";
import Constants from "../../common/constants/Constants";
import { BusinessError } from '@kit.BasicServicesKit';
import { display } from "@kit.ArkUI";


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
struct LocalPhotoDetail {
  private params: ReceiveParams | null = null;
  private smallScroller: Scroller = new Scroller();
  private bigScroller: Scroller = new Scroller();
  @State deviceWidth: number = Constants.DEFAULT_WIDTH || 360;
  @State smallImgWidth: number = (this.deviceWidth - Constants.LIST_ITEM_SPACE * (Constants.SHOW_COUNT - 1)) / Constants.SHOW_COUNT;
  // 🔥 修复：大图宽度=屏幕宽度（之前加smallImgWidth是多余的，导致滚动偏移错误）
  @State imageWidth: number = this.deviceWidth;
  // 响应式索引（由小图List的中间项索引驱动，双向同步）
  @StorageLink('selectedIndex') selectedIndex: number = 0;
  private readonly DOUBLE_NUMBER = Constants.DOUBLE_NUMBER || 2;

  aboutToAppear() {
    try {
      const displayClass = display.getDefaultDisplaySync();
      const width = displayClass?.width / displayClass.densityPixels ?? Constants.DEFAULT_WIDTH;
      this.deviceWidth = width;
      this.smallImgWidth = (width - Constants.LIST_ITEM_SPACE * (Constants.SHOW_COUNT - 1)) / Constants.SHOW_COUNT;
      this.imageWidth = width; // 同步修复大图宽度
    } catch (error) {
      const err = error as BusinessError;
      console.error(`getDefaultDisplaySync failed, code=${err.code}, message=${err.message}`);
    }
  }

  onPageShow() {
    if (this.params && this.params.imageList.length > 0) {
      this.selectedIndex = this.params.selectedIndex;
      // 🔥 简化：小图List会自动对齐中心，只需同步大图位置
      this.bigScroller.scrollTo({
        xOffset: this.selectedIndex * this.imageWidth,
        yOffset: 0,
        animation: { duration: 0 }
      });
    }
  }

  // 🔥 核心简化：小图点击后，直接设置索引，List自动滚动到中心（无需手动计算偏移）
  private smallImgClickAction(index: number): void {
    if (index === this.selectedIndex) return;
    this.selectedIndex = index;
    // 同步大图位置
    this.bigScroller.scrollTo({
      xOffset: index * this.imageWidth,
      yOffset: 0,
      animation: { duration: 150, curve: Curve.EaseOut }
    });
  }

  // 🔥 大图滚动同步小图：直接通过偏移量计算索引，同步后小图自动居中
  private onBigScroll(xOffset: number): void {
    if (!this.params?.imageList || this.params.imageList.length === 0) return;
    // 精确计算当前大图索引（向下取整避免误差）
    const currentIndex = Math.floor(xOffset / this.imageWidth);
    const validIndex = Math.max(0, Math.min(currentIndex, this.params.imageList.length - 1));
    if (validIndex !== this.selectedIndex) {
      this.selectedIndex = validIndex;
    }
  }

  // 小图Builder：中间项高亮（保留边框，可选加缩放增强视觉效果）
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
      // 🔥 中间项高亮：索引匹配时显示边框（可选加.scale放大）
      .borderWidth(this.selectedIndex === index ? 3 : 0)
      .borderColor('#ffffff')
      .borderStyle(BorderStyle.Solid)
      // 可选：中间项轻微放大，增强视觉聚焦（类似示例的字体放大）
     // .scale(this.selectedIndex === index ? 1.05 : 1.0)
      //.transition(Transition.all(150)) // 缩放过渡动画
      .onClick(() => this.smallImgClickAction(index));
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.Bottom }) {
        // --------------- 大图区域（保持双向同步）---------------
        List({ scroller: this.bigScroller }) {
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
              .width(this.imageWidth) // 大图宽度=屏幕宽度（修复后）
            },
            (item: ImageInfo) => item.uri
          )
        }
        .scrollSnapAlign(ScrollSnapAlign.CENTER)
        .onDidScroll((xOffset: number, scrollState: ScrollState) => {
          if (scrollState === ScrollState.Scroll || scrollState === ScrollState.Fling) {
            this.onBigScroll(xOffset);
          }
        })
        .scrollBar(BarState.Off)
        .width('100%')
        .height('100%')
        .padding({ bottom: this.smallImgWidth + 20 }) // 预留小图区域
        .listDirection(Axis.Horizontal);

        // --------------- 小图区域（核心优化：参考示例思路）---------------
        List({
          scroller: this.smallScroller,
          space: Constants.LIST_ITEM_SPACE,
        }) {
          ForEach(
            this.params?.imageList || [],
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
        // 🔥 关键1：滚动后自动对齐中心（系统原生处理，无需手动计算）
        .scrollSnapAlign(ScrollSnapAlign.CENTER)
        // 🔥 关键2：滚动时获取中间项索引，直接同步到selectedIndex
        .onScrollIndex((_firstIndex: number, _lastIndex: number, centerIndex: number) => {
          if (this.params?.imageList && centerIndex >= 0 && centerIndex < this.params.imageList.length) {
            this.selectedIndex = centerIndex;
            // 同步大图位置（滚动过程中实时同步）
            this.bigScroller.scrollTo({
              xOffset: centerIndex * this.imageWidth,
              yOffset: 0,
              animation: { duration: 0 } // 无动画，避免冲突
            });
          }
        })
        .scrollBar(BarState.Off)
        .margin({ top: 16, bottom: 16 })
        .height(this.smallImgWidth + 12) // 预留边框+缩放空间
        .width('100%');
      }
      .width('100%')
      .height('100%');
    }
    .title(this.params?.imageList[this.selectedIndex]?.name || '图片详情')
    .backgroundColor('#000')
    .hideBackButton(false)
    .onReady((ctx: NavDestinationContext) => {
      try {
        this.params = ctx.pathInfo.param as ReceiveParams;
        if (this.params) {
          this.selectedIndex = this.params.selectedIndex;
          // 初始化大图位置（小图由系统自动居中）
          this.bigScroller.scrollTo({
            xOffset: this.selectedIndex * this.imageWidth,
            yOffset: 0,
            animation: { duration: 0 }
          });
        }
      } catch (e) {
        const err = e as BusinessError;
        console.error(`参数解析异常: code=${err.code}, message=${err.message}`);
      }
    });
  }
}