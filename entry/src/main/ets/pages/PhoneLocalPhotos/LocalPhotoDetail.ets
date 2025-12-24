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
  @State smallImgWidth: number =
    (this.deviceWidth - Constants.LIST_ITEM_SPACE * (Constants.SHOW_COUNT - 1)) / Constants.SHOW_COUNT;
  @State imageWidth: number = this.deviceWidth;
  // 局部状态管理索引
  @State selectedIndex: number = 0;
  // 同步来源标记：避免循环触发（1=小图滚动, 2=大图滚动, 3=小图点击）
  @State syncSource: number = 0;
  @State isTitleBarDisplay:boolean = false
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
   * */
  async sharePhoto() {
    try {
      // 获取UIAbilityContext
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      if (!context) {
        console.error('无法获取UIAbilityContext');
        this.getUIContext().getPromptAction().showToast({
          message: "分享失败：无法获取上下文"
        })
        return;
      }

      const validIndex = Math.max(0, Math.min(this.selectedIndex, this.dataSource.totalCount() - 1));
      const item = this.dataSource.dataList[validIndex];

      // 获取文件URI
      let filePath = item.uri;
      console.info('分享文件路径:', filePath);

      // 移除 file:// 前缀，获取纯路径
      let purePath = filePath;
      if (purePath.startsWith('file://')) {
        purePath = purePath.substring(7); // 移除 "file://"
      }

      console.info('处理后的纯路径:', purePath);

      // 使用 fileUri.getUriFromPath 获取正确的URI
      let shareUri: string;
      try {
        shareUri = fileUri.getUriFromPath(purePath);
        console.info('fileUri转换后的URI:', shareUri);
      } catch (uriError) {
        console.warn('使用fileUri转换失败，尝试直接使用路径:', purePath);
        // 如果转换失败，尝试使用原始URI
        shareUri = filePath;
      }

      // 获取文件扩展名
      const fileName = item.name || '';
      let fileExtension = '';
      const dotIndex = fileName.lastIndexOf('.');
      if (dotIndex > 0) {
        fileExtension = fileName.substring(dotIndex).toLowerCase();
      }

      // 有两种方案：1、文件后缀名获得UTD类型ID；2、根据MIME类型获取UTD类型ID
      // 查询链接：https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/uniform-data-type-list#%E5%9F%BA%E7%A1%80%E7%B1%BB%E5%9E%8B

      // 尝试直接根据文件后缀名获取UTD类型ID，因为raw文件没有被包含在MIME类型里面
      let utd_id = 'general.image' //设置UTD-ID的默认值为所有图片的基类型
      if (fileExtension === '.png') {
        utd_id = 'general.png'
      } else if (fileExtension === '.jpg' || fileExtension === 'jpeg' || fileExtension === '.jpe') {
        utd_id = 'general.jpeg'
      } else if (fileExtension === '.nef' || fileExtension === '.raw' ||
        fileExtension === '.arw' || fileExtension === '.cr2' ||
        fileExtension === '.dng') {
        utd_id = 'general.raw-image'
      }

      console.info('文件扩展名:', fileExtension, 'utd_id:', utd_id);


      // 创建分享数据 - 直接使用utdType
      let shareData: systemShare.SharedData = new systemShare.SharedData({
        utd: utd_id, // 直接使用string类型的UTD-ID
        uri: shareUri, // 使用转换后的URI
        title: item.name || '图片分享',
        description: '来自应用分享的图片',
      });

      // 构建ShareController
      let controller: systemShare.ShareController = new systemShare.ShareController(shareData);

      // 显示分享面板
      if (canIUse("SystemCapability.Collaboration.SystemShare")) {
        controller.show(context, {
          previewMode: systemShare.SharePreviewMode.DEFAULT,
          selectionMode: systemShare.SelectionMode.SINGLE
        }).catch(() => {
          return
        });
      } else {
        this.getUIContext().getPromptAction().showToast({
          message:"系统版本过低，暂不支持分享"
        })
      }


      console.info('分享面板调起成功');
    } catch (error) {
      const err = error as BusinessError;
      console.error(`分享失败: 错误码=${err.code}, 错误信息=${err.message}`);

      // 添加用户提示
      promptAction.showToast({
        message: `分享失败: ${err.code === 401 ? '参数错误' : err.message}`,
        duration: 3000
      });
    }
  }

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
    }, 200); // 延长延迟，确保居中完成
  }

  /**
   * 小图构建器：选中项高亮
   */
  @Builder
  private SmallImgItemBuilder(item: ImageInfo, index: number): void {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Image(item.uri)
        .width(this.selectedIndex === index ? this.smallImgWidth + 4 : this.smallImgWidth)
        .height(this.selectedIndex === index ? this.smallImgWidth + 4 : this.smallImgWidth)
        .aspectRatio(1)
        .objectFit(ImageFit.Cover)
        .borderRadius(4)
        .rotate({ angle: item.rotationAngle || 0 })
        .backgroundColor('rgba(0,0,0,0.3)')
        .borderWidth(this.selectedIndex === index ? 2 : 0)  // 减小边框宽度
        .borderColor('#ff4081')  // 使用更醒目的颜色
        .borderStyle(BorderStyle.Solid)
        .onClick(() => this.smallImgClickAction(index));

      // RAW文件角标
      if (item.isRawFile) {
        Text('RAW')
          .fontSize(8)
          .fontColor('#ffffff')
          .backgroundColor('rgba(0, 0, 0, 0.7)')
          .padding({
            left: 2,
            right: 2,
            top: 1,
            bottom: 1
          })
          .borderRadius(1)
          .margin({ right: 2, bottom: 2 });
      }
    }
  }

  // 一个获取图片名称的方法
  private getTitle(): string {
    if (this.dataSource.totalCount() === 0) {
      return '图片详情';
    }

    const validIndex = Math.max(0, Math.min(this.selectedIndex, this.dataSource.totalCount() - 1));
    const item = this.dataSource.dataList[validIndex];

    /*if (item) {
      const fileName = item.name || '';
      // 去除文件扩展名
      return fileName.lastIndexOf('.') > 0
        ? fileName.substring(0, fileName.lastIndexOf('.'))
        : fileName;
    }*/

    if (item) {
      return item.name || '图片详情';
    }

    return '图片详情';
  }

  /**
   *  切换标题栏是否显示
   * */
  private changeTitleBarDisplayStatus(){
    if (this.isTitleBarDisplay) {
      this.isTitleBarDisplay=false
    }else if (this.isTitleBarDisplay == false) {
      this.isTitleBarDisplay=true
    }
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
                  // 关键修改：使用orientation属性而不是rotate
                  .orientation(
                    // 根据是否为RAW文件决定使用orientation还是rotate
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
        .margin({ top: 16, bottom: 16 })
        .height(this.smallImgWidth + 12)
        .width('100%');
      }
      .width('100%')
      .height('100%');
    }
    .title(this.getTitle(),{
      backgroundBlurStyle:BlurStyle.Thick,
      barStyle:BarStyle.STACK
    })
    .hideTitleBar(this.isTitleBarDisplay)
    .menus(this.menuItems)
    //.backgroundColor('#000')
    .hideBackButton(false)
    .onClick(()=>{
      this.changeTitleBarDisplayStatus()
    })
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