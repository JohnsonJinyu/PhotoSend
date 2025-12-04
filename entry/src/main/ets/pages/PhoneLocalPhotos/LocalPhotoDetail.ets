// LocalPhotoDetail.ets
// 导入数据类型：图片信息结构定义
import { ImageInfo, LocalPhotoDataSource } from "./LocalPhotoDataSource";
// 导入全局常量：默认宽度、间距、显示数量等（统一配置，便于维护）
import Constants from "../../common/constants/Constants";
// 导入基础工具：错误类型定义（用于异常捕获）
import { BusinessError } from '@kit.BasicServicesKit';
// 导入UI工具：获取设备屏幕信息（适配不同设备尺寸）
import { display } from "@kit.ArkUI";

/**
 * 接收路由参数的接口定义（列表页→详情页的通信契约）
 * - selectedIndex：列表页点击的图片索引（从0开始）
 */
interface ReceiveParams {
  selectedIndex: number;
}

/**
 * 组件构建器（供路由配置时直接调用，鸿蒙路由标准用法）
 */
@Builder
export function LocalPhotoDetailBuilder() {
  LocalPhotoDetail();
}

/**
 * 图片详情页核心组件
 * 功能：展示大图+小图导航，支持双向同步（大图滚动→小图选中居中，小图滚动→大图同步）
 */
@Component
struct LocalPhotoDetail {
  // 全局单例数据源
  private dataSource: LocalPhotoDataSource = LocalPhotoDataSource.getInstance();
  // 路由传递的初始索引
  private params: ReceiveParams | null = null;

  // 滚动控制器
  private smallScroller: Scroller = new Scroller();
  private bigScroller: Scroller = new Scroller();

  // 尺寸配置
  @State deviceWidth: number = Constants.DEFAULT_WIDTH || 360;
  @State smallImgWidth: number = (this.deviceWidth - Constants.LIST_ITEM_SPACE * (Constants.SHOW_COUNT - 1)) / Constants.SHOW_COUNT;
  @State imageWidth: number = this.deviceWidth;

  // 核心：选中索引（和小图List的centerIndex双向绑定）
  @StorageLink('selectedIndex') selectedIndex: number = 0;

  // 固定常量
  private readonly DOUBLE_NUMBER = Constants.DOUBLE_NUMBER || 2;

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
   * 生命周期：页面显示时初始化滚动位置
   */
  onPageShow() {
    if (this.params && this.dataSource.totalCount() > 0) {
      // 安全校验初始索引
      const targetIndex = Math.max(0, Math.min(this.params.selectedIndex, this.dataSource.totalCount() - 1));
      this.selectedIndex = targetIndex;

      // 大图：滚动到目标索引
      this.bigScroller.scrollToIndex(targetIndex);
      // 小图：滚动到目标索引（结合scrollSnapAlign(CENTER)自动居中）
      this.smallScroller.scrollToIndex(targetIndex);
    }
  }

  /**
   * 小图点击事件：直接滚动到对应索引（系统自动居中）
   */
  private smallImgClickAction(index: number): void {
    if (index === this.selectedIndex || this.dataSource.totalCount() === 0) return;

    const validIndex = Math.max(0, Math.min(index, this.dataSource.totalCount() - 1));
    this.selectedIndex = validIndex;

    // 大图同步滚动
    this.bigScroller.scrollToIndex(validIndex);
    // 小图滚动到索引（系统自动居中）
    this.smallScroller.scrollToIndex(validIndex);
  }

  /**
   * 大图滚动同步：计算当前索引，让小图同步居中
   */
  private onBigScroll(xOffset: number): void {
    if (this.dataSource.totalCount() === 0) return;

    // 计算大图当前显示的索引
    const currentIndex = Math.round(xOffset / this.imageWidth);
    const validIndex = Math.max(0, Math.min(currentIndex, this.dataSource.totalCount() - 1));

    if (validIndex !== this.selectedIndex) {
      this.selectedIndex = validIndex;
      // 小图滚动到该索引（系统自动居中）
      this.smallScroller.scrollToIndex(validIndex, false);
    }
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
      // 选中项高亮（边框）
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
          initialIndex: this.selectedIndex // 初始索引兜底
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
        .onDidScroll((xOffset: number, scrollState: ScrollState) => {
          if (scrollState === ScrollState.Scroll || scrollState === ScrollState.Fling) {
            this.onBigScroll(xOffset);
          }
        })
        .onScrollStop(() => {
          // 滚动停止后校准
          const finalIndex = Math.round(this.bigScroller.currentOffset().xOffset / this.imageWidth);
          const validIndex = Math.max(0, Math.min(finalIndex, this.dataSource.totalCount() - 1));
          if (validIndex !== this.selectedIndex) {
            this.selectedIndex = validIndex;
            this.smallScroller.scrollToIndex(validIndex);
          }
        })
        .scrollBar(BarState.Off)
        .width('100%')
        .height('100%')
        .padding({ bottom: this.smallImgWidth + 20 })
        .listDirection(Axis.Horizontal);

        // --------------- 小图List（核心：参考示例的onScrollIndex）---------------
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
        .scrollSnapAlign(ScrollSnapAlign.CENTER) // 系统原生居中对齐（关键）
        // 核心：监听滚动索引，获取系统计算的中间项索引（参考你的示例）
        .onScrollIndex((_firstIndex: number, _lastIndex: number, centerIndex: number) => {
          if (this.dataSource.totalCount() === 0) return;

          // 安全校验中间项索引
          const validCenterIndex = Math.max(0, Math.min(centerIndex, this.dataSource.totalCount() - 1));

          // 同步到选中索引
          if (validCenterIndex !== this.selectedIndex) {
            this.selectedIndex = validCenterIndex;
            // 大图同步滚动到该索引
            this.bigScroller.scrollToIndex(validCenterIndex);
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