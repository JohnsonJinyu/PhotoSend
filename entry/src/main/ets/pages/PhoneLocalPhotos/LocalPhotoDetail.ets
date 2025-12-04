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
 * 功能：展示大图+小图导航，支持双向同步（大图滚动→小图选中，小图点击→大图切换）
 */
@Component
struct LocalPhotoDetail {
  // 全局单例数据源（保留你的优势，避免重复加载文件）
  private dataSource: LocalPhotoDataSource = LocalPhotoDataSource.getInstance();
  // 核心参数：存储列表页传递的选中索引
  private params: ReceiveParams | null = null;

  // 滚动控制器：分别控制小图列表和大图列表的滚动
  private smallScroller: Scroller = new Scroller(); // 小图列表滚动器
  private bigScroller: Scroller = new Scroller();   // 大图列表滚动器

  // 尺寸配置：适配不同设备屏幕（响应式更新）
  @State deviceWidth: number = Constants.DEFAULT_WIDTH || 360; // 设备屏幕宽度（默认360px兜底）
  // 小图宽度：(屏幕宽度 - 间距*(显示数量-1)) / 显示数量（均匀分布小图）
  @State smallImgWidth: number = (this.deviceWidth - Constants.LIST_ITEM_SPACE * (Constants.SHOW_COUNT - 1)) / Constants.SHOW_COUNT;
  @State imageWidth: number = this.deviceWidth; // 大图宽度=屏幕宽度（保证全屏显示）

  // 响应式索引：全局同步的选中索引（@StorageLink实现跨组件同步）
  @StorageLink('selectedIndex') selectedIndex: number = 0;

  // 固定常量：倍数配置（复用全局常量，避免硬编码）
  private readonly DOUBLE_NUMBER = Constants.DOUBLE_NUMBER || 2;

  /**
   * 生命周期：组件即将出现时执行（初始化设备尺寸）
   * 作用：获取当前设备的真实屏幕宽度，动态计算小图/大图尺寸，适配不同设备
   */
  aboutToAppear() {
    try {
      // 获取设备默认显示信息（包含屏幕宽高、像素密度等）
      const displayClass = display.getDefaultDisplaySync();
      // 计算真实屏幕宽度（物理宽度 / 像素密度 = 逻辑宽度，避免适配问题）
      const width = displayClass?.width / displayClass.densityPixels ?? Constants.DEFAULT_WIDTH;
      this.deviceWidth = width; // 更新屏幕宽度
      // 重新计算小图宽度（基于真实屏幕宽度）
      this.smallImgWidth = (width - Constants.LIST_ITEM_SPACE * (Constants.SHOW_COUNT - 1)) / Constants.SHOW_COUNT;
      this.imageWidth = width; // 同步大图宽度=真实屏幕宽度
    } catch (error) {
      // 捕获屏幕信息获取失败的异常（避免崩溃）
      const err = error as BusinessError;
      console.error(`获取屏幕尺寸失败: 错误码=${err.code}, 错误信息=${err.message}`);
    }
  }

  /**
   * 生命周期：页面显示时执行（同步大图/小图位置，核心修复点）
   * 参考官方示例：用scrollToIndex直接按索引滚动，无需计算偏移量
   */
  onPageShow() {
    // 校验：参数存在且图片列表非空（避免空指针）
    if (this.params && this.dataSource.totalCount() > 0) {
      // 安全校验索引：确保不越界
      const targetIndex = Math.max(0, Math.min(this.params.selectedIndex, this.dataSource.totalCount() - 1));
      this.selectedIndex = targetIndex;

      // 核心修复：用官方的scrollToIndex（按索引滚动，无尺寸计算误差）
      this.bigScroller.scrollToIndex(targetIndex);
      this.smallScroller.scrollToIndex(targetIndex);
    }
  }

  /**
   * 核心交互：小图点击事件
   * 逻辑：点击小图→更新选中索引→同步滚动大图到对应位置
   * @param index 点击的小图索引
   */
  private smallImgClickAction(index: number): void {
    // 避免重复点击（当前已选中的小图，点击无响应）
    if (index === this.selectedIndex) return;

    // 安全校验索引
    const validIndex = Math.max(0, Math.min(index, this.dataSource.totalCount() - 1));
    this.selectedIndex = validIndex;

    // 参考官方：用scrollToIndex滚动，无需计算xOffset
    this.bigScroller.scrollToIndex(validIndex);
    this.smallScroller.scrollToIndex(validIndex);
  }

  /**
   * 核心交互：大图滚动同步事件（修复索引计算精度）
   * 逻辑：大图滚动时→计算当前显示的图片索引→同步到小图
   * @param xOffset 大图横向滚动的偏移量
   */
  private onBigScroll(xOffset: number): void {
    // 校验：图片列表存在且非空（避免空指针）
    if (!this.dataSource || this.dataSource.totalCount() === 0) return;

    // 修复：用Math.round（四舍五入）替代Math.floor，参考官方示例提升精度
    const currentIndex = Math.round(xOffset / this.imageWidth);
    // 安全校验：索引不能越界
    const validIndex = Math.max(0, Math.min(currentIndex, this.dataSource.totalCount() - 1));

    // 索引变化时才更新（避免频繁触发同步）
    if (validIndex !== this.selectedIndex) {
      this.selectedIndex = validIndex;
      // 滚动中：轻量同步小图（无动画，避免卡顿）
      this.smallScroller.scrollToIndex(validIndex, false);
    }
  }

  /**
   * 小图统一构建器（复用样式，避免重复代码）
   * 功能：小图基础样式+选中状态高亮（边框）
   * @param item 图片数据（包含uri等信息）
   * @param index 小图索引
   */
  @Builder
  private SmallImgItemBuilder(item: ImageInfo, index: number): void {
    Image(item.uri) // 小图图片（显示缩略图）
      .width(this.smallImgWidth) // 动态宽度（适配不同设备）
      .height(this.smallImgWidth) // 正方形小图（aspectRatio=1）
      .orientation(ImageRotateOrientation.AUTO) // 自动旋转图片（适配拍摄时的旋转角度）
      .aspectRatio(1) // 强制正方形比例
      .objectFit(ImageFit.Cover) // 裁剪填充（避免小图变形）
      .borderRadius(4) // 圆角（优化视觉体验）
      .backgroundColor('rgba(0,0,0,0.3)') // 背景色（图片加载前占位）
      // 选中状态高亮：当前索引=选中索引时，显示3px白色边框
      .borderWidth(this.selectedIndex === index ? 3 : 0)
      .borderColor('#ffffff') // 选中边框颜色
      .borderStyle(BorderStyle.Solid) // 边框样式：实线
      .onClick(() => this.smallImgClickAction(index)); // 绑定小图点击事件
  }

  /**
   * UI构建：核心布局（大图+小图导航叠加）
   */
  build() {
    // 导航容器（鸿蒙页面标准容器，包含标题、返回按钮）
    NavDestination() {
      // 栈布局（Stack）：大图区域在下层，小图导航在上层（底部对齐）
      Stack({ alignContent: Alignment.Bottom }) {
        // --------------- 大图展示区域（核心功能区，修复点：恢复initialIndex）---------------
        List({
          scroller: this.bigScroller,
          initialIndex: this.selectedIndex // 参考官方：初始索引兜底，双保险
        }) {
          // 循环渲染所有图片（从单例数据源获取）
          ForEach(
            this.dataSource.dataList || [], // 数据源：全局单例的图片列表
            (item: ImageInfo) => {
              ListItem() { // 每个大图对应的列表项
                Image(item.uri) // 大图图片
                  .width('100%') // 宽度占满容器
                  .height('100%') // 高度占满容器
                  .orientation(ImageRotateOrientation.AUTO) // 自动旋转图片
                  .objectFit(ImageFit.Contain) // 等比例缩放（避免图片拉伸，显示完整）
                  .backgroundColor('#000'); // 黑色背景（大图加载前占位，提升视觉体验）
              }
              .width(this.imageWidth) // 每个列表项宽度=屏幕宽度（确保一次只显示一张大图）
            },
            (item: ImageInfo) => item.uri // 唯一键：用图片uri标识（避免重复渲染）
          )
        }
        .scrollSnapAlign(ScrollSnapAlign.CENTER) // 滚动后自动居中（确保大图完整显示）
        // 大图滚动事件：滚动中/惯性滚动时，同步索引到小图
        .onDidScroll((xOffset: number, scrollState: ScrollState) => {
          if (scrollState === ScrollState.Scroll || scrollState === ScrollState.Fling) {
            this.onBigScroll(xOffset);
          }
        })
        // 新增：滚动停止后精准校准（参考官方，避免惯性导致索引偏差）
        .onScrollStop(() => {
          const finalIndex = Math.round(this.bigScroller.currentOffset().xOffset / this.imageWidth);
          const validIndex = Math.max(0, Math.min(finalIndex, this.dataSource.totalCount() - 1));
          if (validIndex !== this.selectedIndex) {
            this.selectedIndex = validIndex;
            this.smallScroller.scrollToIndex(validIndex); // 同步小图到精准位置
          }
        })
        .scrollBar(BarState.Off) // 隐藏滚动条（优化全屏体验）
        .width('100%') // 宽度占满屏幕
        .height('100%') // 高度占满屏幕
        .padding({ bottom: this.smallImgWidth + 20 }) // 底部预留小图区域（避免大图被遮挡）
        .listDirection(Axis.Horizontal); // 列表方向：横向滚动

        // --------------- 小图导航区域（辅助切换区，修复点：加initialIndex+滚动停止校准）---------------
        List({
          scroller: this.smallScroller, // 小图滚动器
          space: Constants.LIST_ITEM_SPACE, // 小图之间的间距（全局常量统一配置）
          initialIndex: this.selectedIndex // 参考官方：初始索引兜底
        }) {
          // 循环渲染小图（和大图数据源一致）
          ForEach(
            this.dataSource.dataList || [],
            (item: ImageInfo, index: number) => {
              ListItem() {
                this.SmallImgItemBuilder(item, index); // 调用小图构建器（复用样式）
              }
              .width(this.smallImgWidth) // 小图列表项宽度=小图宽度
              .aspectRatio(1) // 正方形列表项
              .padding(1); // 内边距（优化点击区域）
            },
            (item: ImageInfo) => item.uri // 唯一键：图片uri
          )
        }
        .listDirection(Axis.Horizontal) // 横向滚动
        .scrollSnapAlign(ScrollSnapAlign.CENTER) // 滚动后自动居中（选中的小图在中间）
        // 小图滚动停止后校准（参考官方，确保索引精准）
        .onScrollStop(() => {
          const smallItemWidth = this.smallImgWidth + Constants.LIST_ITEM_SPACE;
          const centerIndex = Math.round(this.smallScroller.currentOffset().xOffset / smallItemWidth);
          const validIndex = Math.max(0, Math.min(centerIndex, this.dataSource.totalCount() - 1));
          if (validIndex !== this.selectedIndex) {
            this.selectedIndex = validIndex;
            this.bigScroller.scrollToIndex(validIndex); // 同步大图到精准位置
          }
        })
        .scrollBar(BarState.Off) // 隐藏小图滚动条
        .margin({ top: 16, bottom: 16 }) // 上下边距（优化布局）
        .height(this.smallImgWidth + 12) // 小图区域高度=小图宽度+预留边框/缩放空间
        .width('100%'); // 宽度占满屏幕
      }
      .width('100%')
      .height('100%');
    }
    // 导航栏标题：显示当前选中图片的名称（安全校验索引，避免越界）
    .title(() => {
      if (this.dataSource.totalCount() === 0) {
        return '图片详情';
      }
      const validIndex = Math.max(0, Math.min(this.selectedIndex, this.dataSource.totalCount() - 1));
      return this.dataSource.dataList[validIndex]?.name || '图片详情';
    })
    .backgroundColor('#000') // 导航栏背景色（和大图背景一致，视觉统一）
    .hideBackButton(false) // 显示返回按钮（允许返回列表页）
    /**
     * 路由参数接收：页面初始化时执行（保留，用于解析初始选中索引）
     */
    .onReady((ctx: NavDestinationContext) => {
      try {
        // 解析路由参数（转换为ReceiveParams类型，类型安全）
        this.params = ctx.pathInfo.param as ReceiveParams;
        if (this.params) {
          // 初始化选中索引（和列表页点击的一致）
          this.selectedIndex = this.params.selectedIndex;
        }
      } catch (e) {
        // 捕获参数解析异常（避免页面崩溃）
        const err = e as BusinessError;
        console.error(`路由参数解析异常: 错误码=${err.code}, 错误信息=${err.message}`);
      }
    });
  }
}