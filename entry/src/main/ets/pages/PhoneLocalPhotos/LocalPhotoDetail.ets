// LocalPhotoDetail.ets
// 以双List显示的图片详情页
import { ImageInfo } from "./LocalPhotoDataSource";
import Constants from "../../common/constants/Constants"


enum ScrollTypeEnum {
  STOP = 'onScrollStop',
  SCROLL = 'onScroll'
}


// 👇 第一步：统一参数接口（和列表页 PhotoDetailParams 完全一致）
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
  // 3. 接收参数（和官方一致，从路由获取）
  private params: ReceiveParams | null = null;




  // 双List共用Scroller，实现联动
  private smallScroller:Scroller = new Scroller()
  private bigScroller:Scroller = new Scroller()
  @State deviceWidth: number = Constants.DEFAULT_WIDTH || 360; // 默认宽度（适配Constants）
  @State smallImgWidth: number = (this.deviceWidth - Constants.LIST_ITEM_SPACE * (Constants.SHOW_COUNT - 1)) / Constants.SHOW_COUNT;
  @State imageWidth: number = this.deviceWidth; // 大图宽度=屏幕宽度（简化官方逻辑）
  @StorageLink('selectedIndex') selectedIndex: number = 0;



  // 5. 复制官方组件初始化逻辑（获取屏幕宽度）
  aboutToAppear() {
    try {
      // 若Constants中没有DEFAULT_WIDTH，可手动设置为360或通过display API获取（参考官方）
      this.smallImgWidth = (this.deviceWidth - Constants.LIST_ITEM_SPACE * (Constants.SHOW_COUNT - 1)) / Constants.SHOW_COUNT;
      this.imageWidth = this.deviceWidth;
    } catch (error) {
      console.error(`初始化失败: ${JSON.stringify(error)}`);
    }
  }


  // 6. 页面显示时，同步滚动到选中索引（和官方一致）
  onPageShow() {
    if (this.params) {
      this.selectedIndex = this.params.selectedIndex;
      this.smallScroller.scrollToIndex(this.selectedIndex);
      this.bigScroller.scrollToIndex(this.selectedIndex);
    }
  }

  // 7. 小图点击事件（和官方一致：切换选中索引，同步双List）
  private smallImgClickAction(index: number): void {
    this.selectedIndex = index;
    this.smallScroller.scrollToIndex(index);
    this.bigScroller.scrollToIndex(index);
  }


  // 8. 小图滚动联动逻辑（完全复制官方计算方式）
  private smallScrollAction(type: ScrollTypeEnum): void {
    const smallItemWidth = this.smallImgWidth + Constants.LIST_ITEM_SPACE;
    // 计算当前滚动到的索引
    this.selectedIndex = Math.round(((this.smallScroller.currentOffset().xOffset as number) + smallItemWidth / 2) / smallItemWidth);
    if (type === ScrollTypeEnum.SCROLL) {
      // 滚动中：同步大图位置
      this.bigScroller.scrollTo({ xOffset: this.selectedIndex * this.imageWidth, yOffset: 0 });
    } else {
      // 滚动停止：校准小图位置
      this.smallScroller.scrollTo({ xOffset: this.selectedIndex * smallItemWidth, yOffset: 0 });
    }
  }

  // 9. 大图滚动联动逻辑（完全复制官方计算方式 大图滚动联动逻辑（完全复制官方计算方式）
  private bigScrollAction(type: ScrollTypeEnum): void {
    const smallItemWidth = this.smallImgWidth + Constants.LIST_ITEM_SPACE;
    // 计算当前滚动到的索引
    this.selectedIndex = Math.round(((this.bigScroller.currentOffset().xOffset as number) + this.imageWidth / 2) / this.imageWidth);
    if (type === ScrollTypeEnum.SCROLL) {
      // 滚动中：同步小图位置
      this.smallScroller.scrollTo({ xOffset: this.selectedIndex * smallItemWidth, yOffset: 0 });
    } else {
      // 滚动停止：校准大图位置
      this.bigScroller.scrollTo({ xOffset: this.selectedIndex * this.imageWidth, yOffset: 0 });
    }
  }



  // 10. 小图Item构建器（和官方@Builder逻辑一致）
  @Builder
  private SmallImgItemBuilder(item: ImageInfo, index: number) {
    Image(item.uri)
      .width(this.smallImgWidth)
      .height(this.smallImgWidth)
      .aspectRatio(1)
      .objectFit(ImageFit.Cover)
      .borderRadius(4)
      // 选中项高亮边框（和官方一致）
      .borderWidth(this.selectedIndex === index ? 2 : 0)
      .borderColor('#ffffff')
      .onClick(() => this.smallImgClickAction(index));
  }




  build() {
    NavDestination() {
      // 11. 复制官方Stack布局（双List叠加，小图在底部）
      Stack({ alignContent: Alignment.Bottom }) {
        // --------------- 大图List（完全对齐官方）---------------
        List({
          scroller: this.bigScroller,
          initialIndex: this.selectedIndex
        }) {
          // ForEach绑定完整图片数组（和官方一致）
          ForEach(
            this.params?.imageList || [],
            (item: ImageInfo) => {
              ListItem() {
                Image(item.uri)
                  .width(this.imageWidth)
                  .height('100%')
                  .objectFit(ImageFit.Contain)
                  .backgroundColor('#000');
              }
              .padding({ left: 16, right: 16 }) // 左右内边距（和官方一致）
            },
            (item: ImageInfo) => item.uri // 唯一键（官方要求）
          )
        }
        // 横向滚动（核心：官方是横向，不是纵向）
        .listDirection(Axis.Horizontal)
        // 滚动事件监听（联动核心，完全复制官方）
        .onDidScroll((_, scrollState) => {
          if (scrollState === ScrollState.Fling) {
            this.bigScrollAction(ScrollTypeEnum.SCROLL);
          }
        })
        .onScrollStop(() => this.bigScrollAction(ScrollTypeEnum.STOP))
        .scrollBar(BarState.Off) // 隐藏滚动条（和官方一致）
        .width('100%')
        .height('100%')
        .padding({ bottom: this.smallImgWidth + 20 }); // 底部内边距，避免遮挡小图

        // --------------- 小图List（完全对齐官方）---------------
        List({
          scroller: this.smallScroller,
          space: Constants.LIST_ITEM_SPACE,
          initialIndex: this.selectedIndex
        }) {
          // ForEach绑定完整图片数组（和官方一致）
          ForEach(
            this.params?.imageList || [],
            (item: ImageInfo, index: number) => {
              ListItem() {
                this.SmallImgItemBuilder(item, index); // 调用@Builder构建小图
              }
              .width(this.smallImgWidth)
            },
            (item: ImageInfo) => item.uri // 唯一键（官方要求）
          )
        }
        // 横向滚动（核心：官方是横向）
        .listDirection(Axis.Horizontal)
        // 滚动事件监听（联动核心，完全复制官方）
        .onDidScroll((_, scrollState) => {
          if (scrollState === ScrollState.Fling) {
            this.smallScrollAction(ScrollTypeEnum.SCROLL);
          }
        })
        .onScrollStop(() => this.smallScrollAction(ScrollTypeEnum.STOP))
        .scrollBar(BarState.Off) // 隐藏滚动条（和官方一致）
        .width('100%')
        .height(this.smallImgWidth)
        .padding({ left: 16, right: 16, bottom: 16 }) // 内边距（和官方一致）
        .backgroundColor('rgba(0,0,0,0.7)'); // 半透明背景（和官方一致）
      }
    }
    // 标题显示当前图片名称（修复之前的错误：从imageList中取当前索引的name）
    .title(this.params?.imageList[this.selectedIndex]?.name || '图片详情')
    .backgroundColor('#000')
    .hideBackButton(false)
    // 12. 正确接收路由参数（和列表页PhotoDetailParams对应）
    .onReady((ctx: NavDestinationContext) => {
      try {
        this.params = ctx.pathInfo.param as ReceiveParams;
        // 初始化选中索引
        this.selectedIndex = this.params?.selectedIndex || 0;
      } catch (e) {
        console.error(`参数解析异常: ${JSON.stringify(e)}`);
      }
    });
  }
}