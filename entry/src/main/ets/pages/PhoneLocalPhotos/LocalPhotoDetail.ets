import { ImageInfo } from "./LocalPhotoDataSource";
import Constants from "../../common/constants/Constants"

// 1. 复制官方枚举（滚动类型）
enum ScrollTypeEnum {
  STOP = 'onScrollStop',
  SCROLL = 'onScroll'
}

// 2. 统一参数接口（和列表页一致）
interface ReceiveParams {
  imageList: ImageInfo[]; // 完整图片数组
  selectedIndex: number;  // 选中索引
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
  // 3. 修复：大图宽度=屏幕宽度+小图宽度（和官方完全一致，关键！）
  @State smallImgWidth: number = (this.deviceWidth - Constants.LIST_ITEM_SPACE * (Constants.SHOW_COUNT - 1)) / Constants.SHOW_COUNT;
  @State imageWidth: number = this.deviceWidth + this.smallImgWidth; // 核心修复：官方原图逻辑
  @StorageLink('selectedIndex') selectedIndex: number = 0;

  aboutToAppear() {
    try {
      // 重新计算尺寸（和官方一致）
      this.smallImgWidth = (this.deviceWidth - Constants.LIST_ITEM_SPACE * (Constants.SHOW_COUNT - 1)) / Constants.SHOW_COUNT;
      this.imageWidth = this.deviceWidth + this.smallImgWidth; // 同步修复
    } catch (error) {
      console.error(`初始化失败: ${JSON.stringify(error)}`);
    }
  }

  onPageShow() {
    if (this.params) {
      this.selectedIndex = this.params.selectedIndex;
      this.smallScroller.scrollToIndex(this.selectedIndex);
      this.bigScroller.scrollToIndex(this.selectedIndex);
    }
  }

  private smallImgClickAction(index: number): void {
    this.selectedIndex = index;
    this.smallScroller.scrollToIndex(index);
    this.bigScroller.scrollToIndex(index);
  }

  // 4. 修复：小图滚动计算（和官方完全一致）
  private smallScrollAction(type: ScrollTypeEnum): void {
    const smallItemWidth = this.smallImgWidth + Constants.LIST_ITEM_SPACE;
    this.selectedIndex = Math.round(((this.smallScroller.currentOffset().xOffset as number) + smallItemWidth / 2) / smallItemWidth);
    if (type === ScrollTypeEnum.SCROLL) {
      // 滚动偏移=索引×大图宽度（官方原图逻辑）
      this.bigScroller.scrollTo({ xOffset: this.selectedIndex * this.imageWidth, yOffset: 0 });
    } else {
      this.smallScroller.scrollTo({ xOffset: this.selectedIndex * smallItemWidth, yOffset: 0 });
    }
  }

  // 5. 修复：大图滚动计算（和官方完全一致）
  private bigScrollAction(type: ScrollTypeEnum): void {
    const smallItemWidth = this.smallImgWidth + Constants.LIST_ITEM_SPACE;
    // 滚动偏移÷大图宽度=当前索引（官方原图逻辑）
    this.selectedIndex = Math.round(((this.bigScroller.currentOffset().xOffset as number) + this.imageWidth / 2) / this.imageWidth);
    if (type === ScrollTypeEnum.SCROLL) {
      this.smallScroller.scrollTo({ xOffset: this.selectedIndex * smallItemWidth, yOffset: 0 });
    } else {
      this.bigScroller.scrollTo({ xOffset: this.selectedIndex * this.imageWidth, yOffset: 0 });
    }
  }

  @Builder
  private SmallImgItemBuilder(item: ImageInfo, index: number) {
    Image(item.uri)
      .width(this.smallImgWidth)
      .height(this.smallImgWidth)
      .aspectRatio(1)
      .objectFit(ImageFit.Cover)
      .borderRadius(4)
      .borderWidth(this.selectedIndex === index ? 2 : 0)
      .borderColor('#ffffff')
      .onClick(() => this.smallImgClickAction(index));
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.Bottom }) {
        // --------------- 大图List（核心修复：和官方完全一致）---------------
        List({
          scroller: this.bigScroller,
          initialIndex: this.selectedIndex
        }) {
          ForEach(
            this.params?.imageList || [],
            (item: ImageInfo) => {
              ListItem() {
                Image(item.uri)
                  .width('100%') // 占满ListItem宽度
                  .height('100%')
                  .objectFit(ImageFit.Contain)
                  .backgroundColor('#000');
              }
              // 6. 修复：左右padding=小图宽度的一半（官方原图逻辑，关键！）
              .padding({
                left: this.smallImgWidth / 2,
                right: this.smallImgWidth / 2
              })
              .width(this.imageWidth) // ListItem宽度=大图宽度（核心！）
            },
            (item: ImageInfo) => item.uri
          )
        }
        .listDirection(Axis.Horizontal)
        .onDidScroll((_, scrollState) => {
          if (scrollState === ScrollState.Fling) {
            this.bigScrollAction(ScrollTypeEnum.SCROLL);
          }
        })
        .onScrollStop(() => this.bigScrollAction(ScrollTypeEnum.STOP))
        .scrollBar(BarState.Off)
        .width('100%')
        .height('100%')
        // 7. 修复：底部padding=小图宽度×2（避免遮挡，和官方一致）
        .padding({ bottom: this.smallImgWidth * 2 });

        // --------------- 小图List（无需修改，保持和官方一致）---------------
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
            },
            (item: ImageInfo) => item.uri
          )
        }
        .listDirection(Axis.Horizontal)
        .onDidScroll((_, scrollState) => {
          if (scrollState === ScrollState.Fling) {
            this.smallScrollAction(ScrollTypeEnum.SCROLL);
          }
        })
        .onScrollStop(() => this.smallScrollAction(ScrollTypeEnum.STOP))
        .scrollBar(BarState.Off)
        .width('100%')
        .height(this.smallImgWidth)
        .padding({ left: 16, right: 16, bottom: 16 })
        .backgroundColor('rgba(0,0,0,0.7)');
      }
    }
    .title(this.params?.imageList[this.selectedIndex]?.name || '图片详情')
    .backgroundColor('#000')
    .hideBackButton(false)
    .onReady((ctx: NavDestinationContext) => {
      try {
        this.params = ctx.pathInfo.param as ReceiveParams;
        this.selectedIndex = this.params?.selectedIndex || 0;
      } catch (e) {
        console.error(`参数解析异常: ${JSON.stringify(e)}`);
      }
    });
  }
}