import nativeCamera, { ThumbnailInfo } from 'libentry.so'
import image from '@ohos.multimedia.image';
import { createMyNode, getMyNode, MyNodeController } from '../../NodeContainer/CustomComponent';
import { CustomTransition } from '../../CustomTransition/CustomNavigationUtils';
import { ComponentAttrUtils, RectInfoInPx } from '../../utils/ComponentAttrUtils';
import { WindowUtils } from '../../utils/WindowUtils';

export interface ImageInfoWithPixelMap {
  folder: string;
  filename: string;
  pixelMap: image.PixelMap | null;
  // 新增：保存原始buffer用于大图（可选，根据需要）
  thumbnail: ArrayBuffer;
}


// 定义跳转到大图页的参数接口
export interface BigImageParams {
  imageInfo: ImageInfoWithPixelMap; // 包含要传递的图片信息
}

@Builder
export function CameraPicturesPageBuilder() {
  CameraPicturesPage();
}


@Component
export struct CameraPicturesPage {
  @Consume('pageStack') pageStack: NavPathStack;

  private pageId:number=-1
  @State myNodeController:MyNodeController|undefined= new MyNodeController(false)

  @State thumbnails: ThumbnailInfo[] = [];
  @State imageInfos: ImageInfoWithPixelMap[] = [];
  @State isLoading: boolean = true;
  @State errorMsg: string = '';
  @State menuItems: Array<NavigationMenuItem> = [
    {
      value: '多选', action: () => {
    }
    },
    {
      value: '菜单', icon: $r('sys.media.ohos_ic_public_more'), action: () => {
    }
    }
  ];

  aboutToAppear(): void {
    this.loadThumbnails();

    let node = getMyNode()
    if (node == undefined) {
      // 新建自定义节点
      createMyNode(this.getUIContext())
    }
    this.myNodeController =getMyNode()
  }

  private doFinishTransition():void{
    // pageTwo 结束转场时，将节点从pageTwo迁回PageOne
    this.myNodeController = getMyNode()
  }

  private registerCustomTransition(): void {
    // 注册自定义动画协议
    CustomTransition.getInstance().registerNavParam(this.pageId,
      (isPush: boolean, isExit: boolean, transitionProxy: NavigationTransitionProxy) => {}, 500);
  }


  private onGridItemClicked(index: number): void {
    // 1. 获取当前点击的图片数据
    const currentImage = this.imageInfos[index];
    if (!currentImage) return;

    // 2. 获取点击图片元素的位置信息（需给Image设置唯一id）
    const imageRect: RectInfoInPx = ComponentAttrUtils.getRectInfoById(
      WindowUtils.window.getUIContext(),
      `shared-image-${index}` // 与GridItem中Image的id对应
    );

    // 3. 构建转场参数（包含图片数据、位置信息、转场回调）
    const param: Record<string, Object> = {
      "imageInfo": currentImage,
      "cardItemInfo": imageRect,
      "doDefaultTransition": (myController: MyNodeController) => {
        this.doFinishTransition(); // 转场结束后迁回节点
      }
    };

    // 4. 跳转大图页并触发转场
    this.pageStack.pushPath({ name: 'BigImagePage', param: param });

    // 5. 自定义节点从当前页面下树（转场过程中节点迁移到目标页）
    if (this.myNodeController) {
      this.myNodeController.onRemove();
    }
  }



  // 加载缩略图数据
  loadThumbnails() {
    this.isLoading = true;
    nativeCamera.GetThumbnailList((err: string | null, result: ThumbnailInfo[]) => {
      if (err) {
        this.errorMsg = `获取失败：${err}`;
        this.isLoading = false;
        return;
      }

      this.convertThumbnailsToPixelMaps(result).then(() => {
        this.isLoading = false;
      }).catch(() => {
        this.isLoading = false;
      });
    });
  }

  // 批量转换缩略图（修复for循环解构问题）
  async convertThumbnailsToPixelMaps(thumbnails: ThumbnailInfo[]) {
    const newImageInfos: ImageInfoWithPixelMap[] = [];
    for (let i = 0; i < thumbnails.length; i++) {
      const item = thumbnails[i];
      try {
        if (!item.thumbnail || item.thumbnail.byteLength === 0) {
          throw new Error('无效的缩略图数据');
        }
        // 转换为PixelMap（复用你的现有方法）
        const pixelMap = await this.convertArrayBufferToPixelMap(item.thumbnail, item.filename);
        newImageInfos.push({
          folder: item.folder,
          filename: item.filename,
          pixelMap: pixelMap,
          thumbnail: item.thumbnail // 保存原始buffer，方便大图使用
        });
      } catch (err) {
        console.error(`转换失败：${(err as Error).message}`);
        newImageInfos.push({
          folder: item.folder,
          filename: item.filename,
          pixelMap: null,
          thumbnail: item.thumbnail || new ArrayBuffer(0)
        });
      }
    }
    this.imageInfos = newImageInfos;
  }

  // 单个buffer转PixelMap（修复imageInfo.format问题）
  async convertArrayBufferToPixelMap(buffer: ArrayBuffer, filename: string): Promise<image.PixelMap> {
    const uint8Buffer = new Uint8Array(buffer);
    if (uint8Buffer.length < 2 || uint8Buffer[0] !== 0xFF || uint8Buffer[1] !== 0xD8) {
      throw new Error(`不是有效的JPEG数据`);
    }
    const imageSource = image.createImageSource(buffer);
    if (!imageSource) {
      throw new Error(`创建ImageSource失败`);
    }
    const imageInfo = await imageSource.getImageInfo();
    if (!imageInfo || imageInfo.size.width === 0 || imageInfo.size.height === 0) {
      throw new Error(`获取图片信息失败`);
    }
    const pixelMapOptions: image.InitializationOptions = {
      size: { width: imageInfo.size.width, height: imageInfo.size.height },
      pixelFormat: image.PixelMapFormat.RGBA_8888,
      alphaType: image.AlphaType.OPAQUE,
      editable: false
    };
    const pixelMap = await imageSource.createPixelMap(pixelMapOptions);
    if (!pixelMap) {
      throw new Error(`创建PixelMap失败`);
    }
    return pixelMap;
  }







  build() {
    NavDestination() {
      Column() {
        if (this.isLoading) {
          Column({ space: 10 }) {
            LoadingProgress().size({ width: 40, height: 40 });
            Text('正在检索照片...').fontSize(16);
          }.margin({ top: 50 });
        } else if (this.errorMsg) {
          Text(this.errorMsg).fontSize(16).padding(20);
        } else {
          Text(`共找到 ${this.imageInfos.length} 张照片`).fontSize(14).padding({ left: 16, top: 10 });
          Grid() {
            ForEach(this.imageInfos, (item: ImageInfoWithPixelMap, index: number) => {
              GridItem() {
                // 用 Stack 让图片和 NodeContainer 重叠（视觉上还是图片，NodeContainer 是转场载体）
                Stack() {
                  // 图片组件（独立存在，不嵌套在 NodeContainer 内）
                  Column() {
                    Image(item.pixelMap || $r('app.media.ic_placeholder'))
                      .width('100%')
                      .height('100%')
                      .objectFit(ImageFit.Cover)
                      .id(`shared-image-${index}`) // 唯一ID，用于获取位置
                  }

                  // NodeContainer 独立存在，无子类，仅作为转场载体
                  NodeContainer(this.myNodeController)
                    .width('100%')
                    .height('100%')
                }
                // 点击事件绑定到 Stack（触发转场）
                .onClick(() => this.onGridItemClicked(index))
                // 移除冗余的 TapGesture（避免重复触发）
              }
              .aspectRatio(1)

            }, (item: ImageInfoWithPixelMap) => item.filename + item.folder);
          }
          // 关键：设置4列网格，自适应屏幕宽度
          .columnsTemplate('1fr 1fr 1fr 1fr') // 4列平均分配宽度
          .multiSelectable(true)
          .supportAnimation(true)
          .columnsGap(2) // 列间距
          .rowsGap(0.01) // 行间距
          .height('100%')
          .width('100%')
        }
      }.width('100%').height('100%');
    }
    .title('机内照片')
    .menus(this.menuItems)
    .width('100%')
    .height('100%')
    // 新增：注册转场、获取页面信息
    .onReady((context: NavDestinationContext) => {
      this.pageStack = context.pathStack;
      this.pageId = this.pageStack.getAllPathName().length - 1;
      this.registerCustomTransition();
    })
    // 新增：注销转场、节点下树
    .onDisAppear(() => {
      CustomTransition.getInstance().unRegisterNavParam(this.pageId);

      if (this.myNodeController) {
        this.myNodeController.onRemove();
      }
    });
  }
}