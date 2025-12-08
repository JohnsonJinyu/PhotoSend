// CamPhotoPrePage.ets
import nativeCamera from 'libentry.so'
import image from '@ohos.multimedia.image';
import { createMyNode, getMyNode, clearAllMyNodes } from '../../NodeContainer/CustomComponent';
import { CustomTransition } from '../../CustomTransition/CustomNavigationUtils';
import { ComponentAttrUtils, RectInfoInPx } from '../../utils/animation/ComponentAttrUtils';
import { WindowUtils } from '../../utils/animation/WindowUtils';
import { CamConnectionManager } from '../../utils/tools/CamConnectManager';

// 定义懒加载数据源

export interface ImageInfoWithPixelMap {
  folder: string;
  filename: string;
  pixelMap: image.PixelMap | null;
  thumbnail?: ArrayBuffer; // 改为可选
}

export interface PhotoMeta {
  folder: string;
  filename: string;
  size?: number;
}

export interface BigImageParams {
  imageInfo: ImageInfoWithPixelMap;
}

@Builder
export function CameraPicturesPageBuilder() {
  CamPhotoPrePage();
}

@Component
export struct CamPhotoPrePage {
  @Consume('pageStack') pageStack: NavPathStack;
  private pageId: number = -1;
  private currentNodeKey: string = '';

  @State transitioningIndex: number = -1;
  @State isLoading: boolean = true;
  @State errorMsg: string = '';

  @State menuItems: Array<NavigationMenuItem> = [
    {
      value: '多选', action: () => {}
    },
    {
      value: '菜单', icon: $r('sys.media.ohos_ic_public_more'), action: () => {}
    }
  ];

  @State currentPage: number = 0;
  @State pageSize: number = 20;
  @State hasMore: boolean = true;
  @State totalCount: number = 0;
  @State isRefreshing: boolean = false;

  // 使用简单的数据源
  @State imageInfos: ImageInfoWithPixelMap[] = [];

  private camManager: CamConnectionManager | null = null;
  private loadMoreLock: boolean = false; // 防止重复加载

  aboutToAppear(): void {
    this.camManager = CamConnectionManager.getInstance();
    if (!this.camManager) {
      console.error("CameraPage 获取CamConnectionManager实例失败！");
      return;
    }

    this.camManager.pauseCheck();
    console.log("CameraPicturesPage：进入页面，暂停检测");

    // 初始化懒加载
    this.loadPhotoTotalCount();
  }

  // 加载照片总数
  async loadPhotoTotalCount() {
    try {
      this.totalCount = nativeCamera.GetPhotoTotalCount();
      console.log(`照片总数: ${this.totalCount}`);

      // 加载第一页数据
      await this.loadPhotoMetaList(0);
    } catch (error) {
      console.error(`获取照片总数失败: ${error}`);
      this.errorMsg = `加载失败: ${error}`;
      this.isLoading = false;
    }
  }

  // 加载照片元信息列表
  async loadPhotoMetaList(pageIndex: number): Promise<void> {
    if (this.isLoading && pageIndex > 0) return;
    if (this.loadMoreLock) return;

    this.isLoading = true;
    this.loadMoreLock = true;

    try {
      const photoMetas: PhotoMeta[] = nativeCamera.GetPhotoMetaList(pageIndex, this.pageSize);
      console.log(`加载第${pageIndex + 1}页，获取到${photoMetas.length}条数据`);

      if (photoMetas.length === 0) {
        this.hasMore = false;
      } else {
        // 转换元信息 - 修复类型问题
        const newImageInfos: ImageInfoWithPixelMap[] = [];
        for (let i = 0; i < photoMetas.length; i++) {
          const meta = photoMetas[i];
          const item: ImageInfoWithPixelMap = {
            folder: meta.folder,
            filename: meta.filename,
            pixelMap: null
          };
          newImageInfos.push(item);
        }

        // 合并数据
        let allImageInfos: ImageInfoWithPixelMap[];
        if (pageIndex === 0) {
          allImageInfos = newImageInfos;
        } else {
          // 不使用展开运算符，使用concat方法
          allImageInfos = this.imageInfos.concat(newImageInfos);
        }

        // 更新数据
        this.imageInfos = allImageInfos;

        this.currentPage = pageIndex;
        this.hasMore = photoMetas.length === this.pageSize;

        // 预加载缩略图
        this.preloadThumbnailsForPage(pageIndex);
      }
    } catch (error) {
      console.error(`加载照片列表失败: ${error}`);
      this.errorMsg = `加载失败: ${error}`;
    } finally {
      this.isLoading = false;
      this.isRefreshing = false;
      this.loadMoreLock = false;
    }
  }

  // 预加载缩略图
  preloadThumbnailsForPage(pageIndex: number) {
    const startIndex = pageIndex * this.pageSize;
    const endIndex = Math.min(startIndex + this.pageSize, this.imageInfos.length);

    const preloadCount = Math.min(5, endIndex - startIndex);
    for (let i = 0; i < preloadCount; i++) {
      const index = startIndex + i;
      if (index < this.imageInfos.length && !this.imageInfos[index].pixelMap) {
        this.loadSingleThumbnail(index);
      }
    }
  }

  // 按需加载单张缩略图
  async loadSingleThumbnail(index: number) {
    if (index < 0 || index >= this.imageInfos.length) return;

    const imageInfo = this.imageInfos[index];
    if (!imageInfo || imageInfo.pixelMap) return;

    try {
      const thumbnailBuffer = await new Promise<ArrayBuffer>((resolve, reject) => {
        nativeCamera.DownloadSingleThumbnail(
          imageInfo.folder,
          imageInfo.filename,
          (err: string | null, buffer: ArrayBuffer) => {
            if (err) {
              reject(new Error(err));
            } else {
              resolve(buffer);
            }
          }
        );
      });

      if (thumbnailBuffer && thumbnailBuffer.byteLength > 0) {
        const pixelMap = await this.convertArrayBufferToPixelMap(thumbnailBuffer, imageInfo.filename);

        // 修复：不使用扩展运算符，而是创建新对象
        const updatedImageInfo: ImageInfoWithPixelMap = {
          folder: imageInfo.folder,
          filename: imageInfo.filename,
          pixelMap: pixelMap,
          thumbnail: thumbnailBuffer
        };

        // 更新数组中的对应元素
        this.imageInfos[index] = updatedImageInfo;

        // 触发UI更新（使用新数组）
        this.imageInfos = this.imageInfos.slice();
      }
    } catch (error) {
      console.error(`加载缩略图失败: ${error}, 文件: ${imageInfo.filename}`);
    }
  }

  // 处理滚动事件
  onGridScroll(scrollOffset: number, visibleSize: number, contentSize: number) {
    if (this.imageInfos.length === 0) return;

    // 按需加载可见区域的缩略图
    const itemsPerRow = 4;
    const itemHeight = visibleSize / (this.imageInfos.length / itemsPerRow);
    const visibleStartIndex = Math.floor(scrollOffset / itemHeight) * itemsPerRow;
    const visibleEndIndex = Math.min(visibleStartIndex + 20, this.imageInfos.length);

    for (let i = Math.max(0, visibleStartIndex); i < visibleEndIndex; i++) {
      if (!this.imageInfos[i].pixelMap) {
        this.loadSingleThumbnail(i);
      }
    }

    // 滚动到底部加载更多
    if (!this.isLoading && this.hasMore && scrollOffset + visibleSize >= contentSize - 100) {
      this.loadPhotoMetaList(this.currentPage + 1);
    }
  }

  // 下拉刷新
  async onRefresh() {
    this.isRefreshing = true;
    this.hasMore = true;
    this.currentPage = 0;

    // 清空缓存
    if (typeof nativeCamera.ClearPhotoCache === 'function') {
      nativeCamera.ClearPhotoCache();
    }

    // 重置数据
    this.imageInfos = [];

    await this.loadPhotoTotalCount();
  }

  private doFinishTransition(uniqueKey: string): void {
    const node = getMyNode(uniqueKey);
    // 无需额外操作
  }

  private registerCustomTransition(): void {
    CustomTransition.getInstance().registerNavParam(this.pageId,
      (isPush: boolean, isExit: boolean, transitionProxy: NavigationTransitionProxy) => {
      }, 500);
  }

  private onGridItemClicked(index: number): void {
    if (index < 0 || index >= this.imageInfos.length) return;

    const currentImage = this.imageInfos[index];
    if (!currentImage) return;

    this.currentNodeKey = index.toString();
    this.transitioningIndex = index;

    const imageRect: RectInfoInPx = ComponentAttrUtils.getRectInfoById(
      WindowUtils.window.getUIContext(),
      `shared-image-${index}`
    );

    const param: Record<string, Object> = {
      "imageInfo": currentImage,
      "cardItemInfo": imageRect,
      "uniqueKey": this.currentNodeKey,
      "doDefaultTransition": () => {
        this.doFinishTransition(this.currentNodeKey);
      }
    };

    this.pageStack.pushPath({ name: 'BigImagePage', param: param });

    setTimeout(() => {
      this.transitioningIndex = -1;
    }, 500);

    const currentNode = getMyNode(this.currentNodeKey);
    if (currentNode) {
      currentNode.onRemove();
    }
  }

  // 单个buffer转PixelMap
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
        if (this.isLoading && this.imageInfos.length === 0) {
          Column({ space: 10 }) {
            LoadingProgress().size({ width: 40, height: 40 });
            Text('正在检索照片...').fontSize(16);
          }
          .margin({ top: 50 })
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else if (this.errorMsg) {
          Text(this.errorMsg).fontSize(16).padding(20);
        } else {
          // 显示照片统计
          Row() {
            Text(`共 ${this.totalCount} 张照片`)
              .fontSize(14)
              .fontColor(Color.Gray);

            if (this.isRefreshing) {
              LoadingProgress()
                .size({ width: 20, height: 20 })
                .margin({ left: 10 });
            }
          }
          .padding({ left: 16, top: 10, bottom: 5 })
          .width('100%')

          // 使用ForEach，因为Grid有自己的虚拟滚动
          Grid() {
            ForEach(this.imageInfos, (item: ImageInfoWithPixelMap, index: number) => {
              GridItem() {
                Stack() {
                  // 图片组件
                  Column() {
                    if (item.pixelMap) {
                      // 已加载缩略图
                      Image(item.pixelMap)
                        .width('100%')
                        .height('100%')
                        .objectFit(ImageFit.Cover)
                        .id(`shared-image-${index}`)
                        .visibility(this.transitioningIndex === index ? Visibility.None : Visibility.Visible)
                    } else {
                      // 缩略图未加载，显示占位符
                      Column() {
                        Image($r('app.media.ic_placeholder'))
                          .width(40)
                          .height(40)
                        Text('加载中...')
                          .fontSize(12)
                          .fontColor(Color.Gray)
                          .margin({ top: 5 })
                      }
                      .width('100%')
                      .height('100%')
                      .justifyContent(FlexAlign.Center)
                      .alignItems(HorizontalAlign.Center)
                      .backgroundColor(Color.White)
                      .border({ width: 1, color: '#f0f0f0' })
                    }
                  }
                  .width('100%')
                  .height('100%')

                  // NodeContainer
                  NodeContainer(getMyNode(index.toString()))
                    .width('100%')
                    .height('100%')
                    .onAppear(() => {
                      if (!getMyNode(index.toString())) {
                        createMyNode(this.getUIContext(), index.toString(), item.pixelMap);
                      }
                    })
                }
                .onClick(() => {
                  if (!item.pixelMap) {
                    this.loadSingleThumbnail(index).then(() => {
                      this.onGridItemClicked(index);
                    });
                  } else {
                    this.onGridItemClicked(index);
                  }
                })
              }
              .aspectRatio(1)
            }, (item: ImageInfoWithPixelMap) => `${item.folder}-${item.filename}`)
          }
          .columnsTemplate('1fr 1fr 1fr 1fr')
          .columnsGap(2)
          .rowsGap(2)
          .height('100%')
          .width('100%')
          .scrollBar(BarState.Off)
          .onScroll((scrollOffset: number, scrollState: ScrollState) => {
            // Grid的onScroll回调接收两个参数：scrollOffset和scrollState
            // 我们需要获取Grid的尺寸来计算可见区域
            // 这里简化处理：只根据滚动位置触发懒加载
            if (scrollOffset > 0) {
              // 计算可见区域的大致索引
              const visibleStartIndex = Math.floor(scrollOffset / 100) * 4; // 假设每项高度100px
              const visibleEndIndex = visibleStartIndex + 20; // 预加载多一些

              for (let i = Math.max(0, visibleStartIndex); i < Math.min(visibleEndIndex, this.imageInfos.length); i++) {
                if (!this.imageInfos[i].pixelMap) {
                  this.loadSingleThumbnail(i);
                }
              }

              // 滚动到底部加载更多
              if (!this.isLoading && this.hasMore) {
                // 我们不知道总高度，所以使用简单策略：当加载了足够多项目时自动加载下一页
                if (this.imageInfos.length > 0 && visibleEndIndex >= this.imageInfos.length - 10) {
                  this.loadPhotoMetaList(this.currentPage + 1);
                }
              }
            }
          })

          // 底部加载更多提示
          if (this.isLoading && this.imageInfos.length > 0) {
            Row() {
              LoadingProgress().size({ width: 20, height: 20 });
              Text('加载更多...').fontSize(14).margin({ left: 10 });
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
            .padding(20)
          }

          if (!this.hasMore && this.imageInfos.length > 0) {
            Text('没有更多照片了').fontSize(14).fontColor(Color.Gray).padding(20);
          }
        }
      }
      .width('100%')
      .height('100%');
    }
    .title('机内照片')
    .menus(this.menuItems)
    .width('100%')
    .height('100%')
    .onReady((context: NavDestinationContext) => {
      this.pageStack = context.pathStack;
      this.pageId = this.pageStack.getAllPathName().length - 1;
      this.registerCustomTransition();
    })
    .onDisAppear(() => {
      CustomTransition.getInstance().unRegisterNavParam(this.pageId);
      clearAllMyNodes();

      if (this.camManager) {
        this.camManager.resumeCheck();
        console.log("CameraPicturesPage：离开页面，恢复检测");
      }
    });
  }
}




/**
 *
 * 实现逻辑
 * aboutToAppear()
↓
loadPhotoTotalCount()
↓
GetPhotoTotalCount() // C++层获取总数
↓
loadPhotoMetaList(0) // 加载第一页元信息
↓
GetPhotoMetaList() // C++层获取元信息（无缩略图）
↓
转换为 ImageInfoWithPixelMap[] // 创建基本数据结构
↓
preloadThumbnailsForPage() // 预加载前5张缩略图
 *
 *

 *
 * */