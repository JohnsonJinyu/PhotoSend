// LocalPhotoDetail.ets
import { ImageInfo, LocalPhotoDataSource } from "./LocalPhotoDataSource";
import Constants from "../../common/constants/Constants";
import { BusinessError } from '@kit.BasicServicesKit';
import { display } from "@kit.ArkUI";
import { systemShare } from "@kit.ShareKit";
import { fileUri } from "@kit.CoreFileKit";
import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';

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
  @State smallImgWidth: number = 50; // 调整为50，更美观的尺寸
  @State imageWidth: number = this.deviceWidth;
  // 局部状态管理索引
  @State selectedIndex: number = 0;
  // 同步来源标记：避免循环触发（1=小图滚动, 2=大图滚动, 3=小图点击）
  @State syncSource: number = 0;
  // 菜单项
  @State menuItems: Array<NavigationMenuItem> = [
    {
      value: '分享',
      icon: $r('sys.media.ohos_ic_public_share'),
      action: () => {
        this.sharePhoto()
      }
    },
  ];

  /**
   * 分享文件
   */
  async sharePhoto() {
    // ... 保持不变 ...
  }

  /**
   * 生命周期：初始化设备尺寸
   */
  aboutToAppear() {
    try {
      const displayClass = display.getDefaultDisplaySync();
      const width = displayClass?.width / displayClass.densityPixels ?? Constants.DEFAULT_WIDTH;
      this.deviceWidth = width;

      // 调整为50vp，更美观的尺寸
      this.smallImgWidth = 50;
      this.imageWidth = width;
    } catch (error) {
      const err = error as BusinessError;
      console.error(`获取屏幕尺寸失败: 错误码=${err.code}, 错误信息=${err.message}`);
    }
  }

  /**
   * 核心方法：计算小图item居中的偏移量，强制滚动到居中位置
   */
  private scrollSmallToCenter(targetIndex: number): void {
    if (this.dataSource.totalCount() === 0 || targetIndex < 0 || targetIndex >= this.dataSource.totalCount()) {
      return;
    }

    // 单个小图item的总宽度（包含间距）
    const singleItemTotalWidth = this.smallImgWidth + 8; // 调整为8vp间距
    // 小图List的可视区域中心位置
    const listCenterX = this.deviceWidth / 2;
    // 目标item的中心位置（相对于List的起始位置）
    const itemCenterX = targetIndex * singleItemTotalWidth + (this.smallImgWidth / 2);
    // 需要滚动的偏移量（让item中心和List中心重合）
    const targetOffsetX = itemCenterX - listCenterX;

    this.smallScroller.scrollTo({
      xOffset: targetOffsetX,
      yOffset: 0,
      animation: false
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
    if (index === this.selectedIndex || this.dataSource.totalCount() === 0) {
      return;
    }

    const validIndex = Math.max(0, Math.min(index, this.dataSource.totalCount() - 1));
    this.syncSource = 3;
    this.selectedIndex = validIndex;

    // 大图同步
    this.bigScroller.scrollToIndex(validIndex, false);
    // 小图强制居中（核心修复）
    this.scrollSmallToCenter(validIndex);

    setTimeout(() => {
      this.syncSource = 0;
    }, 200);
  }

  /**
   * 小图构建器：选中项高亮（参考华为相册设计）
   */
  @Builder
  private SmallImgItemBuilder(item: ImageInfo, index: number): void {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Image(item.uri)
        .width(this.selectedIndex === index ? this.smallImgWidth + 4 : this.smallImgWidth)
        .height(this.selectedIndex === index ? this.smallImgWidth + 4 : this.smallImgWidth)
        .aspectRatio(1)
        .objectFit(ImageFit.Cover)
        .borderRadius(4) // 调整为4vp圆角
        .rotate({ angle: item.rotationAngle || 0 })
        .backgroundColor('rgba(0,0,0,0.1)')
        .borderWidth(this.selectedIndex === index ? 2 : 0) // 边框调整为2
        .borderColor('#007DFF')
        .borderStyle(BorderStyle.Solid)
        .onClick(() => this.smallImgClickAction(index));

      // RAW文件角标
      if (item.isRawFile) {
        Text('RAW')
          .fontSize(8)
          .fontColor('#ffffff')
          .fontWeight(FontWeight.Medium)
          .backgroundColor('rgba(0, 0, 0, 0.7)')
          .padding({
            left: 3,
            right: 3,
            top: 1,
            bottom: 1
          })
          .borderRadius(2)
          .margin({ right: 3, bottom: 3 });
      }
    }
  }

  /**
   * 自定义工具栏构建器（参考华为相册的分层嵌套布局，但只保留数目和小图列表）
   */
  @Builder
  private ToolbarBuilder() {
    // 使用SafeArea处理底部安全距离

      Column() {
        // 位置信息栏 - 调整内边距，避免与内容重叠
        Row() {
          Blank()
          Text(`${this.selectedIndex + 1}/${this.dataSource.totalCount()}`)
            .fontSize(14)
            .fontColor('#ffffff')
            .fontWeight(FontWeight.Medium)
            .textAlign(TextAlign.Center)
            .opacity(0.9)
          Blank()
        }
        .width('100%')
        .height(24)
        .padding({ top: 8, bottom: 4 }) // 增加顶部内边距

        // 缩略图水平列表（参考华为相册）
        List({
          scroller: this.smallScroller,
          space: 8, // 调整为8vp间距
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
            },
            (item: ImageInfo) => item.uri
          )
        }
        .listDirection(Axis.Horizontal)
        .scrollSnapAlign(ScrollSnapAlign.CENTER)
        .lanes(1) // 单行显示，避免与工具栏重叠
        // 小图滚动同步到大图
        .onScrollIndex((_firstIndex: number, _lastIndex: number, centerIndex: number) => {
          if (this.dataSource.totalCount() === 0 || this.syncSource !== 0) {
            return;
          }

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
        .height(this.smallImgWidth + 6) // 调整为6vp
        .width('100%')
        .margin({ bottom: 8 })
      }
      .width('100%')
      // 调整总高度：位置信息栏(24+12) + 缩略图区域(50+6) + 底部间距(8) = 约100vp
      .height(36 + this.smallImgWidth + 6 + 8)
      .backgroundColor('rgba(0, 0, 0, 0.5)') // 稍微加深背景色
      .backdropBlur(15)
      .alignItems(HorizontalAlign.Center)
      // === 新增：底部内边距，创造安全距离和美观间距 ===
      .padding({ bottom: 12 }) // 关键！这个值可以根据您的设备预览效果微调

  }

  // 一个获取图片名称的方法
  private getTitle(): string {
    if (this.dataSource.totalCount() === 0) {
      return '图片详情';
    }

    const validIndex = Math.max(0, Math.min(this.selectedIndex, this.dataSource.totalCount() - 1));
    const item = this.dataSource.dataList[validIndex];

    if (item) {
      return item.name || '图片详情';
    }

    return '图片详情';
  }

  build() {
    NavDestination() {
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
                .orientation(
                  item.imageOrientation !== undefined && item.imageOrientation !== 0
                    ? item.imageOrientation
                    : ImageRotateOrientation.AUTO
                )
                .objectFit(ImageFit.Contain)
            }
            .width(this.imageWidth);
          },
          (item: ImageInfo) => item.uri
        )
      }
      .scrollSnapAlign(ScrollSnapAlign.CENTER)
      .friction(10)
      .onScrollStop(() => {
        if (this.dataSource.totalCount() === 0 || this.syncSource !== 0) {
          return;
        }

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
      .listDirection(Axis.Horizontal)
    }
    .width('100%')
    .height('100%')
    .title(this.getTitle(), {
      backgroundBlurStyle: BlurStyle.Thick,
      barStyle: BarStyle.STACK
    })
    .menus(this.menuItems)
    // 使用toolbarConfiguration，并设置系统预设样式
    // === 新增的关键行 ===
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP]) // 只避让顶部，让底部工具栏可以“贴底”
    .toolbarConfiguration(this.ToolbarBuilder(), {
      backgroundColor: Color.Transparent, // 透明背景，使用自定义背景色
      // 添加内边距选项，确保工具栏与内容区域有足够间距
    })
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