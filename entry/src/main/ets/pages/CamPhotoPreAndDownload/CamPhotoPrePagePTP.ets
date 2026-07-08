// CamPhotoPrePagePTP.ets - 基于 PTP/IP 协议的纯 ArkTS 实现
// 保持与原有 CamPhotoPrePage 相同的 UI 布局和交互
import { nativeCamera, ScanProgressInfo } from '../../ptpip/PtpCompatLayer';
import image from '@ohos.multimedia.image';
import { createMyNode, getMyNode, clearAllMyNodes } from '../../NodeContainer/CustomComponent';
import { CustomTransition } from '../../CustomTransition/CustomNavigationUtils';
import { ComponentAttrUtils, RectInfoInPx } from '../../utils/animation/ComponentAttrUtils';
import { WindowUtils } from '../../utils/animation/WindowUtils';
import { ImageInfoWithPixelMap } from '../../types/CameraTypes';
import type { PhotoMeta as PtpPhotoMeta } from '../../ptpip/PtpTypes';

@Builder
export function CameraPicturesPageBuilder() {
  CamPhotoPrePagePTP();
}

@Component
export struct CamPhotoPrePagePTP {
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

  @State scanProgressInfo: ScanProgressInfo = {
    scanning: false,
    current: 0,
    total: 0,
    cached: false
  };

  private scanTimer: number = 0;
  private activeThumbnailDownloads: number = 0;
  private thumbnailQueue: number[] = [];
  private thumbnailCache: Map<number, image.PixelMap> = new Map();

  private loadMoreLock: boolean = false;

  aboutToAppear(): void {
    console.info('CamPhotoPrePagePTP', '页面加载，使用 PTP/IP 协议');
    
    // 启动异步加载
    this.startAsyncLoading();
  }

  // 启动异步加载
  private async startAsyncLoading(): Promise<void> {
    try {
      this.isLoading = true;
      this.errorMsg = '';

      // 1. 先启动异步扫描
      const scanStarted = await nativeCamera.StartAsyncScan();
      if (!scanStarted) {
        this.errorMsg = '启动扫描失败';
        this.isLoading = false;
        return;
      }

      console.log("异步扫描已启动（PTP/IP）");

      // 2. 设置定时器检查扫描进度
      this.startScanProgressCheck();

    } catch (error) {
      const err = error as Error;
      console.error('启动异步加载失败:', err);
      this.errorMsg = '启动失败：' + err.message;
      this.isLoading = false;
    }
  }

  // 启动扫描进度检查
  private startScanProgressCheck(): void {
    if (this.scanTimer > 0) {
      clearInterval(this.scanTimer);
    }

    this.scanTimer = setInterval(() => {
      try {
        // 获取扫描进度
        const progress: ScanProgressInfo = nativeCamera.GetScanProgress();
        this.scanProgressInfo = progress;
        console.log(`扫描进度：${progress.current}/${progress.total}, 扫描中：${progress.scanning}, 已缓存：${progress.cached}`);

        // 如果扫描完成且已缓存
        if (!progress.scanning && progress.cached && progress.total > 0) {
          this.onScanComplete(progress.total);
        }

        // 如果扫描失败或取消
        if (!progress.scanning && !progress.cached && progress.total === 0) {
          this.onScanFailed();
        }
      } catch (error) {
        console.error('检查扫描进度失败:', error);
      }
    }, 500);
  }

  // 扫描失败处理
  private onScanFailed(): void {
    if (this.scanTimer > 0) {
      clearInterval(this.scanTimer);
      this.scanTimer = 0;
    }

    this.errorMsg = '扫描照片失败，请重试';
    this.isLoading = false;
  }

  // 批量加载多页数据
  private async loadMultiplePages(startPage: number): Promise<void> {
    console.log(`🔥🔥 PTP: loadMultiplePages 被调用了！🔥🔥`);
    
    const maxPages = Math.ceil(this.totalCount / this.pageSize);
    const targetPages = Math.min(5, maxPages);  // 最多加载 5 页 (100 张)
    
    console.log(`🔄 开始批量加载：从第${startPage}页开始，目标加载${targetPages}页，totalCount=${this.totalCount}`);
    
    for (let page = startPage; page < targetPages; page++) {
      console.log(`👉 准备加载第${page + 1}页`);
      await this.loadPhotoMetaList(page);
      console.log(`✅ 第${page + 1}页加载完成`);
      
      // 短暂延迟，避免阻塞 UI
      await new Promise<void>((resolve) => setTimeout(resolve, 50));
    }
    
    console.log(`🎉 批量加载完成，当前总照片数：${this.imageInfos.length}`);
  }

  // 扫描完成处理
  private onScanComplete(totalCount: number): void {
    if (this.scanTimer > 0) {
      clearInterval(this.scanTimer);
      this.scanTimer = 0;
    }
  
    console.log(`🎉 扫描完成（PTP/IP），照片总数：${totalCount}`);
    this.totalCount = totalCount;
    this.isLoading = false;
  
    // 批量加载多页数据
    console.log(`🚀 开始调用 loadMultiplePages`);
    this.loadMultiplePages(0);
  }

  // 加载照片元信息列表
  async loadPhotoMetaList(pageIndex: number): Promise<void> {
    if (this.isLoading && pageIndex > 0) return;
    if (this.loadMoreLock) return;

    this.isLoading = true;
    this.loadMoreLock = true;

    try {
      // 使用 PTP/IP 兼容层 API
      const photoMetas: PtpPhotoMeta[] = nativeCamera.GetPhotoMetaList(pageIndex, this.pageSize);
      console.log(`加载第${pageIndex + 1}页，获取到${photoMetas.length}条数据（PTP/IP）`);

      if (photoMetas.length === 0) {
        this.hasMore = false;
      } else {
        // 转换元信息
        const newImageInfos: ImageInfoWithPixelMap[] = [];
        for (let i = 0; i < photoMetas.length; i++) {
          const meta = photoMetas[i];
          const item = new ImageInfoWithPixelMap(meta.folder, meta.filename, null);
          newImageInfos.push(item);
        }

        // 合并数据
        let allImageInfos: ImageInfoWithPixelMap[];
        if (pageIndex === 0) {
          allImageInfos = newImageInfos;
        } else {
          allImageInfos = this.imageInfos.concat(newImageInfos);
        }

        // 更新数据
        this.imageInfos = allImageInfos;
        this.currentPage = pageIndex;
        this.hasMore = photoMetas.length === this.pageSize;
        
        console.log(`📊 当前总照片数：${this.imageInfos.length}, hasMore=${this.hasMore}`);
                
        // 延迟预加载
        setTimeout(() => {
          this.preloadFirstScreenThumbnails(pageIndex);
        }, 100);
      }
    } catch (error) {
      const err = error as Error;
      console.error(`加载照片列表失败：${err.message}`);
      this.errorMsg = `加载失败：${err.message}`;
    } finally {
      this.isLoading = false;
      this.isRefreshing = false;
      this.loadMoreLock = false;
    }
  }

  // 预加载第一屏缩略图
  private preloadFirstScreenThumbnails(pageIndex: number): void {
    const startIndex = pageIndex * this.pageSize;
    const endIndex = Math.min(startIndex + 40, this.imageInfos.length);
  
    console.log(`预加载缩略图：从${startIndex}到${endIndex}, 共${endIndex - startIndex}张`);
    for (let i = startIndex; i < endIndex; i++) {
      if (!this.imageInfos[i].pixelMap) {
        this.loadSingleThumbnailWithConcurrency(i);
      }
    }
  }

  // 缩略图加载（带并发控制）
  private async loadSingleThumbnailWithConcurrency(index: number): Promise<void> {
    if (index < 0 || index >= this.imageInfos.length) return;

    const imageInfo = this.imageInfos[index];
    if (!imageInfo || imageInfo.pixelMap) return;

    // 先检查缓存
    if (this.thumbnailCache.has(index)) {
      console.log(`✅ 使用缓存的缩略图：index=${index}`);
      const cachedPixelMap = this.thumbnailCache.get(index)!;
      this.updateImageInfoWithPixelMap(index, imageInfo, cachedPixelMap);
      return;
    }

    // 降低并发数到 1，避免相机 I/O 冲突
    if (this.activeThumbnailDownloads >= 1) {
      if (!this.thumbnailQueue.includes(index)) {
        this.thumbnailQueue.push(index);
        console.log(`⏳ 缩略图加入队列：index=${index}, 队列长度=${this.thumbnailQueue.length}`);
      }
      return;
    }

    this.activeThumbnailDownloads++;
    const startTime = Date.now();
    console.log(`🚀 开始下载缩略图：index=${index}, 文件=${imageInfo.filename}`);
    
    try {
      await this.loadSingleThumbnail(index);
      const duration = Date.now() - startTime;
      console.log(`✅ 缩略图加载完成：index=${index}, 耗时=${duration}ms`);
    } catch (error) {
      console.error(`❌ 缩略图加载失败：index=${index}, error=${(error as Error).message}`);
    } finally {
      this.activeThumbnailDownloads--;

      // 处理队列中的下一个
      if (this.thumbnailQueue.length > 0 && this.activeThumbnailDownloads < 1) {
        const nextIndex = this.thumbnailQueue.shift();
        if (nextIndex !== undefined) {
          this.loadSingleThumbnailWithConcurrency(nextIndex);
        }
      }
    }
  }

  // 加载单个缩略图
  private async loadSingleThumbnail(index: number): Promise<void> {
    if (index < 0 || index >= this.imageInfos.length) return;
  
    const imageInfo = this.imageInfos[index];
    if (!imageInfo || imageInfo.pixelMap) return;
  
    console.log(`📡 [${index}] 准备调用 nativeCamera.DownloadSingleThumbnail`);
    
    return new Promise<void>((resolve, reject) => {
      nativeCamera.DownloadSingleThumbnail(
        imageInfo.folder,
        imageInfo.filename,
        async (err: string | null, buffer: ArrayBuffer) => {
          console.log(`📡 [${index}] 回调执行，err=${err}, buffer.size=${buffer ? buffer.byteLength : 'null'}`);
          
          if (err) {
            console.error(`❌ [${index}] 下载失败：${err}`);
            reject(new Error(err));
            return;
          }
          
          if (!buffer || buffer.byteLength === 0) {
            console.error(`❌ [${index}] 数据为空`);
            reject(new Error('缩略图数据为空'));
            return;
          }
  
          try {
            console.log(`🔄 [${index}] 开始解码 PixelMap`);
            const pixelMap = await this.convertArrayBufferToPixelMap(buffer, imageInfo.filename);
            console.log(`✅ [${index}] PixelMap 解码成功`);
            
            // 缓存 pixelMap
            this.thumbnailCache.set(index, pixelMap);
            
            this.updateImageInfoWithPixelMap(index, imageInfo, pixelMap);
            resolve();
          } catch (error) {
            console.error(`❌ [${index}] 解码失败：${(error as Error).message}`);
            reject(error);
          }
        }
      );
    });
  }
  
  // 辅助方法：更新 ImageInfo 并触发 UI 刷新
  private updateImageInfoWithPixelMap(index: number, imageInfo: ImageInfoWithPixelMap, pixelMap: image.PixelMap): void {
    this.imageInfos[index].pixelMap = pixelMap;
    this.imageInfos[index].thumbnail = undefined;
    
    console.log(`✅ Grid 已更新：index=${index}, 文件=${imageInfo.filename}`);
  }

  // 滚动事件处理
  private handleScrollLogic(scrollOffset: number): void {
    if (this.imageInfos.length === 0) return;

    // 计算可见区域
    const itemsPerRow = 4;
    const visibleStartIndex = Math.floor(scrollOffset / 100) * itemsPerRow;
    const visibleEndIndex = Math.min(visibleStartIndex + 8, this.imageInfos.length);

    // 按需加载可见区域的缩略图
    for (let i = Math.max(0, visibleStartIndex); i < visibleEndIndex; i++) {
      if (!this.imageInfos[i].pixelMap) {
        this.loadSingleThumbnailWithConcurrency(i);
      }
    }

    // 滚动到底部加载更多
    if (!this.isLoading && this.hasMore && scrollOffset > 0) {
      const totalItems = this.imageInfos.length;
      const visibleItems = visibleEndIndex - visibleStartIndex;
      if (visibleEndIndex >= totalItems - visibleItems) {
        this.loadPhotoMetaList(this.currentPage + 1);
      }
    }
  }

  // 滚动事件（防抖）
  private onGridScrollDebounced = (() => {
    let lastScrollTime = 0;
    let scrollTimer: number = 0;

    return (scrollOffset: number) => {
      const now = Date.now();
      if (now - lastScrollTime < 200) {
        if (scrollTimer > 0) {
          clearTimeout(scrollTimer);
        }
        scrollTimer = setTimeout(() => {
          this.handleScrollLogic(scrollOffset);
        }, 200);
        return;
      }

      lastScrollTime = now;
      this.handleScrollLogic(scrollOffset);
    };
  })();

  // 下拉刷新
  async onRefresh(): Promise<void> {
    this.isRefreshing = true;
    this.hasMore = true;
    this.currentPage = 0;

    // 清空缓存
    nativeCamera.ClearPhotoCache();
    
    // 清空缩略图缓存
    this.thumbnailCache.clear();
    this.thumbnailQueue = [];
    this.activeThumbnailDownloads = 0;

    // 重置数据
    this.imageInfos = [];

    // 重新启动扫描
    await this.startAsyncLoading();
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

  // ArrayBuffer 转 PixelMap
  async convertArrayBufferToPixelMap(buffer: ArrayBuffer, filename: string): Promise<image.PixelMap> {
    const uint8Buffer = new Uint8Array(buffer);
    if (uint8Buffer.length < 2 || uint8Buffer[0] !== 0xFF || uint8Buffer[1] !== 0xD8) {
      throw new Error(`不是有效的 JPEG 数据`);
    }

    const imageSource = image.createImageSource(buffer);
    if (!imageSource) {
      throw new Error(`创建 ImageSource 失败`);
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
      throw new Error(`创建 PixelMap 失败`);
    }

    return pixelMap;
  }

  build() {
    NavDestination() {
      Column() {
        // 显示扫描状态
        if (this.scanProgressInfo.scanning) {
          this.buildScanningView()
        } else if (this.isLoading && this.imageInfos.length === 0) {
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
          // 显示照片内容
          this.buildContentView()
        }
      }
      .width('100%')
      .height('100%');
    }
    .title('机内照片（PTP/IP）')
    .menus(this.menuItems)
    .width('100%')
    .height('100%')
    .onReady((context: NavDestinationContext) => {
      this.pageStack = context.pathStack;
      this.pageId = this.pageStack.getAllPathName().length - 1;
      this.registerCustomTransition();
    })
    .onDisAppear(() => {
      // 清理定时器
      if (this.scanTimer > 0) {
        clearInterval(this.scanTimer);
        this.scanTimer = 0;
      }

      CustomTransition.getInstance().unRegisterNavParam(this.pageId);
      clearAllMyNodes();
    });
  }

  @Builder
  buildScanningView() {
    Column({ space: 15 }) {
      LoadingProgress()
        .size({ width: 40, height: 40 })
        .color('#007DFF')

      Text('正在扫描照片...')
        .fontSize(16)
        .fontColor('#333333')

      if (this.scanProgressInfo.total > 0) {
        Text(`已扫描 ${this.scanProgressInfo.current}/${this.scanProgressInfo.total}`)
          .fontSize(14)
          .fontColor('#666666')
          .margin({ top: 5 })

        // 进度条
        Row() {
          Stack() {
            Column()
              .width('100%')
              .height(6)
              .backgroundColor('#EEEEEE')
              .borderRadius(3)

            Column()
              .width(`${Math.min(100, (this.scanProgressInfo.current / this.scanProgressInfo.total) * 100)}%`)
              .height(6)
              .backgroundColor('#007DFF')
              .borderRadius(3)
          }
        }
        .width('80%')
        .height(6)
        .margin({ top: 10 })
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  buildContentView() {
    Column() {
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

      // 使用 ForEach，因为 Grid 有自己的虚拟滚动
      Grid() {
        ForEach(this.imageInfos, (item: ImageInfoWithPixelMap, index: number) => {
          GridItem() {
            this.buildGridItem(item, index)
          }
          .aspectRatio(1)
        }, (item: ImageInfoWithPixelMap, index: number) => `${index}-${item.folder}-${item.filename}`)
      }
      .columnsTemplate('1fr 1fr 1fr 1fr')
      .columnsGap(2)
      .rowsGap(2)
      .height('100%')
      .width('100%')
      .scrollBar(BarState.Off)
      .onScroll((scrollOffset: number, scrollState: ScrollState) => {
        this.onGridScrollDebounced(scrollOffset);
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

  @Builder
  buildGridItem(item: ImageInfoWithPixelMap, index: number) {
    Stack() {
      // 图片组件
      Column() {
        if (item.pixelMap) {
          // 已加载缩略图 - 强制重新渲染
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
        this.loadSingleThumbnailWithConcurrency(index);
        setTimeout(() => {
          this.onGridItemClicked(index);
        }, 500);
      } else {
        this.onGridItemClicked(index);
      }
    })
  }
}
