// LocalPhotoDetail.ets
import { ImageInfo, LocalPhotoDataSource } from "./LocalPhotoDataSource";
import Constants from "../../common/constants/Constants";
import { BusinessError } from '@kit.BasicServicesKit';
import { display } from "@kit.ArkUI";
import { systemShare } from "@kit.ShareKit";
import { fileUri } from "@kit.CoreFileKit";
import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';

// 路由参数接口，用于接收从其他页面传入的图片索引
interface ReceiveParams {
  selectedIndex: number;
}

/**
 * 分享文件类型映射表
 * 用于根据文件扩展名确定对应的UTD(Uniform Type Definition)类型ID
 * UTD是HarmonyOS中统一的数据类型标识
 */
const FILE_TYPE_MAPPING: Record<string, string> = {
  '.png': 'general.png',
  '.jpg': 'general.jpeg',
  '.jpeg': 'general.jpeg',
  '.jpe': 'general.jpeg',
  '.nef': 'general.raw-image',
  '.raw': 'general.raw-image',
  '.arw': 'general.raw-image',
  '.cr2': 'general.raw-image',
  '.dng': 'general.raw-image'
};

/**
 * 同步来源枚举
 * 用于跟踪当前是哪部分触发的滚动同步，避免循环触发
 * NONE: 无同步来源
 * SMALL_SCROLL: 小图滚动触发的同步
 * BIG_SCROLL: 大图滚动触发的同步
 * SMALL_CLICK: 小图点击触发的同步
 */
enum SyncSource {
  NONE = 0,
  SMALL_SCROLL = 1,
  BIG_SCROLL = 2,
  SMALL_CLICK = 3
}

// 常量定义
const DEFAULT_IMAGE_TYPE: string = 'general.image'; // 默认图片UTD类型
const SYNC_DELAY: number = 200; // 同步延迟时间，避免频繁触发

/**
 * 构建器函数，用于在路由中创建LocalPhotoDetail组件
 */
@Builder
export function LocalPhotoDetailBuilder() {
  LocalPhotoDetail();
}

/**
 * 本地照片详情页组件
 * 功能：展示大图预览，底部显示小图缩略图列表
 * 支持：左右滑动切换图片、点击小图切换、分享图片、显示/隐藏标题栏
 */
@Component
export struct LocalPhotoDetail {
  // MARK: - 依赖注入
  // 数据源，存储和管理所有图片数据
  private dataSource: LocalPhotoDataSource = LocalPhotoDataSource.getInstance();

  // MARK: - 路由参数
  // 从路由接收的参数，包含初始选中的图片索引
  private params: ReceiveParams | null = null;

  // MARK: - 滚动控制器
  // 控制小图列表的滚动
  private smallScroller: Scroller = new Scroller();
  // 控制大图列表的滚动
  private bigScroller: Scroller = new Scroller();

  // MARK: - 状态管理
  @State deviceWidth: number = Constants.DEFAULT_WIDTH || 360; // 设备屏幕宽度（物理像素）
  @State selectedIndex: number = 0; // 当前选中的图片索引
  @State syncSource: SyncSource = SyncSource.NONE; // 当前同步来源，防止循环触发
  @State isTitleBarDisplay: boolean = false; // 标题栏是否显示
  @State smallImgWidth: number = 0; // 小图宽度，根据屏幕宽度动态计算
  @State imageWidth: number = 0; // 大图宽度，等于屏幕宽度

  // MARK: - 菜单配置
  // 导航栏菜单项配置
  private menuItems: Array<NavigationMenuItem> = [
    {
      value: '分享',
      icon: $r('sys.media.ohos_ic_public_share'),
      action: () => this.sharePhoto()
    },
  ];

  // MARK: - 生命周期
  /**
   * 组件即将显示时调用
   * 初始化设备尺寸，计算图片显示尺寸
   */
  aboutToAppear(): void {
    this.initializeDeviceSize();
  }

  /**
   * 页面显示时调用
   * 初始化滚动位置，确保显示正确的图片
   */
  onPageShow(): void {
    this.initializeScrollPosition();
  }

  // MARK: - 初始化方法
  /**
   * 初始化设备尺寸
   * 获取设备屏幕信息，计算设备宽度
   */
  private initializeDeviceSize(): void {
    try {
      const displayClass = display.getDefaultDisplaySync();
      // 计算逻辑像素宽度：物理像素 / 屏幕密度
      const width = displayClass?.width / displayClass.densityPixels ?? Constants.DEFAULT_WIDTH;
      this.deviceWidth = width;
      this.calculateImageDimensions();
    } catch (error) {
      const err = error as BusinessError;
      console.error(`获取屏幕尺寸失败: 错误码=${err.code}, 错误信息=${err.message}`);
    }
  }

  /**
   * 计算图片显示尺寸
   * 根据屏幕宽度、显示数量、间距计算小图宽度
   * 大图宽度等于屏幕宽度
   */
  private calculateImageDimensions(): void {
    this.smallImgWidth = (this.deviceWidth - Constants.LIST_ITEM_SPACE * (Constants.SHOW_COUNT - 1)) / Constants.SHOW_COUNT;
    this.imageWidth = this.deviceWidth;
  }

  /**
   * 初始化滚动位置
   * 根据路由参数设置初始显示的图片，并滚动到对应位置
   */
  private initializeScrollPosition(): void {
    if (!this.params || this.dataSource.totalCount() === 0) {
      return;
    }

    const targetIndex = Math.max(0, Math.min(this.params.selectedIndex, this.dataSource.totalCount() - 1));
    this.selectedIndex = targetIndex;

    // 初始化大图滚动位置
    this.bigScroller.scrollToIndex(targetIndex, false);

    // 初始化小图滚动位置
    this.scrollSmallToCenter(targetIndex);
  }

  // MARK: - 辅助方法
  /**
   * 获取当前选中的图片信息
   * @returns 当前图片信息，如果没有图片则返回null
   */
  private getCurrentImage(): ImageInfo | null {
    if (this.dataSource.totalCount() === 0) {
      return null;
    }
    const validIndex = Math.max(0, Math.min(this.selectedIndex, this.dataSource.totalCount() - 1));
    return this.dataSource.dataList[validIndex];
  }

  /**
   * 获取当前图片的名称，用于标题栏显示
   * @returns 图片名称，如果无图片则返回默认文本
   */
  private getImageName(): string {
    const image = this.getCurrentImage();
    return image?.name || '图片详情';
  }

  // MARK: - 滚动控制
  /**
   * 将小图滚动到居中位置
   * @param targetIndex 目标图片索引
   */
  private scrollSmallToCenter(targetIndex: number): void {
    const totalCount = this.dataSource.totalCount();
    if (totalCount === 0 || targetIndex < 0 || targetIndex >= totalCount) {
      return;
    }

    // 计算单个小图项的总宽度（包括间距）
    const singleItemTotalWidth = this.smallImgWidth + Constants.LIST_ITEM_SPACE;
    // 小图列表可视区域的中心点
    const listCenterX = this.deviceWidth / 2;
    // 目标图片项的中心点位置
    const itemCenterX = targetIndex * singleItemTotalWidth + (this.smallImgWidth / 2);
    // 需要滚动的偏移量
    const targetOffsetX = itemCenterX - listCenterX;

    // 滚动到计算出的位置，禁用动画避免抖动
    this.smallScroller.scrollTo({
      xOffset: targetOffsetX,
      yOffset: 0,
      animation: false
    });
  }

  // MARK: - 事件处理
  /**
   * 大图滚动停止事件处理
   * 计算当前显示的大图索引，同步小图位置
   */
  private onBigScrollStop(): void {
    const totalCount = this.dataSource.totalCount();
    if (totalCount === 0 || this.syncSource !== SyncSource.NONE) {
      return;
    }

    // 根据滚动偏移量计算当前索引（每个大图宽度相同）
    const finalIndex = Math.round(this.bigScroller.currentOffset().xOffset / this.imageWidth);
    const validIndex = Math.max(0, Math.min(finalIndex, totalCount - 1));

    if (validIndex !== this.selectedIndex) {
      this.syncSource = SyncSource.BIG_SCROLL;
      this.selectedIndex = validIndex;
      this.scrollSmallToCenter(validIndex);
      this.resetSyncSource();
    }
  }

  /**
   * 小图滚动索引变化事件处理
   * 当小图滚动时，同步大图位置
   * @param centerIndex 小图列表的中心索引
   */
  private onSmallScrollIndexChange(centerIndex: number): void {
    const totalCount = this.dataSource.totalCount();
    if (totalCount === 0 || this.syncSource !== SyncSource.NONE) {
      return;
    }

    const validCenterIndex = Math.max(0, Math.min(centerIndex, totalCount - 1));

    if (validCenterIndex !== this.selectedIndex) {
      this.syncSource = SyncSource.SMALL_SCROLL;
      this.selectedIndex = validCenterIndex;
      this.bigScroller.scrollToIndex(validCenterIndex, false);
      this.resetSyncSource();
    }
  }

  /**
   * 小图点击事件处理
   * 点击小图时切换到大图，并确保小图居中
   * @param index 被点击的小图索引
   */
  private onSmallImageClick(index: number): void {
    const totalCount = this.dataSource.totalCount();
    if (index === this.selectedIndex || totalCount === 0) {
      return;
    }

    const validIndex = Math.max(0, Math.min(index, totalCount - 1));
    this.syncSource = SyncSource.SMALL_CLICK;
    this.selectedIndex = validIndex;
    this.bigScroller.scrollToIndex(validIndex, false);
    this.scrollSmallToCenter(validIndex);
    this.resetSyncSource();
  }

  /**
   * 切换标题栏显示状态
   * 点击页面空白区域时切换标题栏的显示/隐藏
   */
  private toggleTitleBarDisplay(): void {
    this.isTitleBarDisplay = !this.isTitleBarDisplay;
  }

  /**
   * 重置同步来源标记
   * 在同步完成后延迟重置，避免循环触发
   */
  private resetSyncSource(): void {
    setTimeout(() => {
      this.syncSource = SyncSource.NONE;
    }, SYNC_DELAY);
  }

  // MARK: - 分享功能
  /**
   * 分享当前选中的图片
   * 调用系统分享功能，支持分享到其他应用
   */
  private async sharePhoto(): Promise<void> {
    try {
      // 获取UIAbility上下文，用于系统分享
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      if (!context) {
        this.showToast('分享失败：无法获取上下文');
        return;
      }

      const image = this.getCurrentImage();
      if (!image) {
        this.showToast('没有可分享的图片');
        return;
      }

      // 处理文件路径，获取可分享的URI
      const shareUri = this.processFilePath(image.uri);
      // 根据文件名获取UTD类型ID
      const utdId = this.getUtdId(image.name);

      // 创建分享数据对象
      const shareData = new systemShare.SharedData({
        utd: utdId,
        uri: shareUri,
        title: image.name || '图片分享',
        description: '来自应用分享的图片',
      });

      // 显示分享面板
      await this.showShareSheet(context, shareData);

    } catch (error) {
      const err = error as BusinessError;
      console.error(`分享失败: 错误码=${err.code}, 错误信息=${err.message}`);
      this.showToast(`分享失败: ${err.code === 401 ? '参数错误' : err.message}`);
    }
  }

  /**
   * 处理文件路径，转换为系统可识别的URI
   * @param filePath 原始文件路径
   * @returns 处理后的文件URI
   */
  private processFilePath(filePath: string): string {
    let purePath = filePath;
    // 移除file://前缀，获取纯路径
    if (purePath.startsWith('file://')) {
      purePath = purePath.substring(7);
    }

    try {
      // 使用fileUri API将路径转换为URI
      return fileUri.getUriFromPath(purePath);
    } catch (uriError) {
      console.warn('使用fileUri转换失败，尝试直接使用路径:', purePath);
      return filePath;
    }
  }

  /**
   * 根据文件名获取UTD类型ID
   * @param fileName 文件名
   * @returns UTD类型ID
   */
  private getUtdId(fileName: string): string {
    const dotIndex = fileName.lastIndexOf('.');
    if (dotIndex > 0) {
      const extension = fileName.substring(dotIndex).toLowerCase();
      // 从映射表中查找对应的UTD类型，找不到则使用默认类型
      return FILE_TYPE_MAPPING[extension] || DEFAULT_IMAGE_TYPE;
    }
    return DEFAULT_IMAGE_TYPE;
  }

  /**
   * 显示系统分享面板
   * @param context UIAbility上下文
   * @param shareData 分享数据
   */
  private async showShareSheet(context: common.UIAbilityContext, shareData: systemShare.SharedData): Promise<void> {
    // 检查系统是否支持分享功能
    if (!canIUse("SystemCapability.Collaboration.SystemShare")) {
      this.showToast("系统版本过低，暂不支持分享");
      return;
    }

    const controller = new systemShare.ShareController(shareData);
    // 显示分享面板，允许用户选择分享方式
    await controller.show(context, {
      previewMode: systemShare.SharePreviewMode.DEFAULT, // 默认预览模式
      selectionMode: systemShare.SelectionMode.SINGLE // 单选模式
    }).catch(() => {
      // 用户取消分享，不处理异常
    });
  }

  /**
   * 显示提示信息
   * @param message 提示消息内容
   */
  private showToast(message: string): void {
    promptAction.showToast({
      message,
      duration: 3000
    });
  }

  // MARK: - 视图构建器
  /**
   * 小图项构建器
   * @param item 图片信息
   * @param index 图片索引
   */
  @Builder
  private SmallImageItem(item: ImageInfo, index: number) {
    Stack({ alignContent: Alignment.BottomEnd }) {
      // 图片显示区域
      Image(item.uri)
      // 选中状态时增加4像素边框宽度，突出显示
        .width(this.selectedIndex === index ? this.smallImgWidth + 4 : this.smallImgWidth)
        .height(this.selectedIndex === index ? this.smallImgWidth + 4 : this.smallImgWidth)
        .aspectRatio(1) // 保持正方形
        .objectFit(ImageFit.Cover) // 覆盖填充
        .borderRadius(4) // 圆角边框
        .rotate({ angle: item.rotationAngle || 0 }) // 应用旋转角度
        .backgroundColor('rgba(0,0,0,0.3)') // 半透明背景
        .borderWidth(this.selectedIndex === index ? 2 : 0) // 选中时显示边框
        .borderColor('#ff4081') // 边框颜色
        .borderStyle(BorderStyle.Solid)
        .onClick(() => this.onSmallImageClick(index)); // 点击事件

      // RAW文件角标（仅当是RAW文件时显示）
      if (item.isRawFile) {
        Text('RAW')
          .fontSize(8)
          .fontColor('#ffffff')
          .backgroundColor('rgba(0, 0, 0, 0.7)')
          .padding({ left: 2, right: 2, top: 1, bottom: 1 })
          .borderRadius(1)
          .margin({ right: 2, bottom: 2 });
      }
    }
  }

  // MARK: - 主构建函数
  /**
   * 组件构建函数
   * 构建页面的UI结构
   */
  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.Bottom }) {
        // --------------- 大图List ---------------
        // 横向滚动的大图列表，每屏显示一张大图
        List({
          scroller: this.bigScroller,
          initialIndex: this.selectedIndex // 初始显示索引
        }) {
          ForEach(
            this.dataSource.dataList || [],
            (item: ImageInfo) => {
              ListItem() {
                Image(item.uri)
                  .width('100%')
                  .height('100%')
                  // 处理图片方向：优先使用图片自带的方向信息，否则自动识别
                  .orientation(
                    item.imageOrientation !== undefined && item.imageOrientation !== 0
                      ? item.imageOrientation
                      : ImageRotateOrientation.AUTO
                  )
                  .objectFit(ImageFit.Contain) // 保持宽高比，完整显示图片
              }
              .width(this.imageWidth); // 每个列表项宽度等于屏幕宽度
            },
            (item: ImageInfo) => item.uri // 使用URI作为唯一键
          )
        }
        .scrollSnapAlign(ScrollSnapAlign.CENTER) // 滚动后居中停靠
        .friction(10) // 滚动摩擦力，控制滚动惯性
        .onScrollStop(() => this.onBigScrollStop()) // 滚动停止事件
        .scrollBar(BarState.Off) // 隐藏滚动条
        .width('100%')
        .height('100%')
        // 底部留出空间显示小图列表
        .padding({ bottom: this.smallImgWidth + 20 })
        .listDirection(Axis.Horizontal); // 横向滚动

        // --------------- 小图List ---------------
        // 横向滚动的小图列表，显示所有图片的缩略图
        List({
          scroller: this.smallScroller,
          space: Constants.LIST_ITEM_SPACE, // 小图间距
          initialIndex: this.selectedIndex
        }) {
          ForEach(
            this.dataSource.dataList || [],
            (item: ImageInfo, index: number) => {
              ListItem() {
                // 使用小图项构建器
                this.SmallImageItem(item, index);
              }
              .width(this.smallImgWidth) // 固定宽度
              .aspectRatio(1) // 保持正方形
              .padding(1); // 内边距
            },
            (item: ImageInfo) => item.uri
          )
        }
        .listDirection(Axis.Horizontal)
        .scrollSnapAlign(ScrollSnapAlign.CENTER) // 滚动后居中停靠
        // 小图滚动时同步大图位置
        .onScrollIndex((_firstIndex: number, _lastIndex: number, centerIndex: number) => {
          this.onSmallScrollIndexChange(centerIndex);
        })
        .scrollBar(BarState.Off)
        .margin({ top: 16, bottom: 16 }) // 上下边距
        .height(this.smallImgWidth + 12) // 固定高度
        .width('100%');
      }
      .width('100%')
      .height('100%');
    }
    // 导航目的地配置
    .title(this.getImageName(), {
      backgroundBlurStyle: BlurStyle.Thick, // 厚模糊背景
      barStyle: BarStyle.STACK // 堆叠样式
    })
    .hideTitleBar(this.isTitleBarDisplay) // 控制标题栏显示/隐藏
    .menus(this.menuItems) // 设置菜单项
    .hideBackButton(false) // 显示返回按钮
    .onClick(() => this.toggleTitleBarDisplay()) // 点击页面切换标题栏
    .onReady((ctx: NavDestinationContext) => {
      // 导航准备完成时，解析路由参数
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