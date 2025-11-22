// BigImagePage.ets
import { RectInfoInPx } from '../../utils/animation/ComponentAttrUtils';
import { AnimationProperties } from '../../CustomTransition/AnimationProperties';
import { MyNodeController, getMyNode, deleteMyNode } from '../../NodeContainer/CustomComponent';
import { CustomTransition } from '../../CustomTransition/CustomNavigationUtils';
import { ImageInfoWithPixelMap } from './CamPhotoPrePage';
import { common } from '@kit.AbilityKit';
import { ErrorEvent, MessageEvent, worker } from '@kit.ArkTS';
import { CamConnectionManager } from '../../utils/tools/CamConnectManager';
import picker from '@ohos.file.picker';
import fs from '@ohos.file.fs';
import { BusinessError } from '@ohos.base';

// 扩展大图页参数接口
export interface BigImageParams {
  imageInfo: ImageInfoWithPixelMap;
  cardItemInfo: RectInfoInPx;
  uniqueKey: string;
  doDefaultTransition: () => void;
}

// --- 【修改点 1：更新消息结构】 ---
// Worker -> 主线程：下载成功消息
interface DownloadSuccessMessage {
  type: 'downloadSuccess';
  name: string;
  imageBuffer: ArrayBuffer;
}
// Worker -> 主线程：下载失败消息
interface DownloadFailureMessage {
  type: 'error';
  message?: string;
  name?: string;
}
// 合并Worker消息类型
type WorkerResponseMessage = DownloadSuccessMessage | DownloadFailureMessage;

// 主线程 -> Worker：下载任务消息
interface DownloadTaskMessage {
  folder: string;
  name: string;
}

// 定义Builder
@Builder
export function BigImagePageBuilder() {
  BigImagePage();
}

@Component
export struct BigImagePage {
  @State pageInfos: NavPathStack = new NavPathStack();
  @State animationProperties: AnimationProperties = new AnimationProperties(this.getUIContext());
  @State title: string = '';
  @State currentPictureFolder: string = '';
  @State currentPictureName: string = '';
  private myNodeController: MyNodeController | undefined;
  private downloadWorker: worker.ThreadWorker | null = null;
  private pageId: number = -1;
  private shouldDoDefaultTransition: boolean = false;
  private prePageDoFinishTransition: () => void = () => {};
  private cardItemInfo: RectInfoInPx = new RectInfoInPx();
  private params: BigImageParams = {
    imageInfo: { folder: '', filename: '', pixelMap: null, thumbnail: new ArrayBuffer(0) },
    cardItemInfo: new RectInfoInPx(),
    uniqueKey: '',
    doDefaultTransition: () => {}
  };
  private currentNodeKey: string = '';
  private camManager: CamConnectionManager | null = null;
  @StorageProp('windowSizeChanged') @Watch('unRegisterNavParam') windowSizeChangedTime: number = 0;
  @StorageProp('onConfigurationUpdate') @Watch('unRegisterNavParam') onConfigurationUpdateTime: number = 0;

  aboutToAppear(): void {
    this.camManager = CamConnectionManager.getInstance();
    if (!this.camManager) {
      console.error("CameraPage 获取CamConnectionManager实例失败！");
      return;
    }
    this.camManager.stopConnectionCheck();
    console.log("BigImagePage：下载开始，彻底停止检测");

    // --- 【修改点 2：更新 Worker 消息监听】 ---
    try {
      this.downloadWorker = new worker.ThreadWorker('../../workers/DownloadMessage.ets');

      // 监听 Worker 消息，处理下载结果
      this.downloadWorker.onmessage = async (e: MessageEvent<WorkerResponseMessage>) => {
        const data = e.data;
        switch (data.type) {
          case 'downloadSuccess':
            // 下载成功，在主线程使用 Picker 保存文件
            await this.saveImageWithPicker(data.name, data.imageBuffer);
            break;
          case 'error':
            this.showToast(`下载失败：${data.message}`);
            break;
        }
      };

      this.downloadWorker.onerror = (e: ErrorEvent) => {
        console.error(`Worker错误：${e.message}`);
        this.showToast(`下载异常：${e.message}`);
        this.terminateWorker();
      };
    } catch (err) {
      console.error(`创建Worker失败：${(err as Error).message}`);
    }
  }

  aboutToDisappear(): void {
    this.terminateWorker();
    if (this.camManager) {
      this.camManager.startConnectionCheck();
    }
  }

  private terminateWorker(): void {
    if (this.downloadWorker) {
      this.downloadWorker.terminate();
      this.downloadWorker = null;
    }
  }

  private unRegisterNavParam(): void {
    this.shouldDoDefaultTransition = true;
  }

  private onBackPressed(): boolean {
    if (this.shouldDoDefaultTransition) {
      CustomTransition.getInstance().unRegisterNavParam(this.pageId);
      this.pageInfos.pop();
      this.prePageDoFinishTransition();
      this.shouldDoDefaultTransition = false;
      return true;
    }
    this.pageInfos.pop();
    return true;
  }

  /**
   * @description 触发下载流程
   */
  private downLoadSinglePicture() {
    if (!this.currentPictureFolder || !this.currentPictureName) {
      this.showToast("图片信息缺失，下载失败！");
      return;
    }
    if (!this.downloadWorker) {
      this.showToast("下载服务初始化失败");
      return;
    }

    this.showToast("下载中...");

    // --- 【修改点 3：向 Worker 发送简化的任务消息】 ---
    const message: DownloadTaskMessage = {
      folder: this.currentPictureFolder,
      name: this.currentPictureName
    };
    this.downloadWorker.postMessage(message);
  }

  /**
   * @description 【新增】在主线程使用 DocumentViewPicker 保存图片
   * @param fileName 文件名
   * @param imageBuffer 图片二进制数据
   */
  private async saveImageWithPicker(fileName: string, imageBuffer: ArrayBuffer) {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const documentPicker = new picker.DocumentViewPicker(context);

      const saveOptions = new picker.DocumentSaveOptions();
      saveOptions.pickerMode = picker.DocumentPickerMode.DOWNLOAD;
      saveOptions.newFileNames = [fileName];

      console.log(`准备使用 Picker 保存文件: ${fileName}`);

      // 调用 Picker.save() 获取文件 Uri
      const uris = await documentPicker.save(saveOptions);

      if (uris && uris.length > 0) {
        const fileUri = uris[0];
        console.log(`Picker 返回文件 Uri: ${fileUri}`);

        // 将图片数据写入文件
        const file = await fs.open(fileUri, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
        await fs.write(file.fd, new Uint8Array(imageBuffer));
        await fs.close(file.fd);

        this.showToast(`保存成功！路径: ${fileUri}`);
      } else {
        throw new Error('文件保存被取消或失败');
      }
    } catch (error) {
      const err = error as BusinessError;
      console.error(`使用 Picker 保存文件失败: ${err.code} - ${err.message}`);
      this.showToast(`保存失败：${err.message}`);
    }
  }

  // 辅助方法：显示 Toast
  private showToast(message: string) {
    this.getUIContext().getPromptAction().showToast({
      message: message,
      duration: 2000,
      bottom: 80
    });
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        Stack({ alignContent: Alignment.TopStart }) {
          Column() {
            if (this.myNodeController) {
              NodeContainer(this.myNodeController)
                .opacity(this.animationProperties.showDetailContent ? 0 : 1)
                .visibility(this.animationProperties.showDetailContent ? Visibility.None : Visibility.Visible)
                .transition(TransitionEffect.OPACITY)
            }
            if (this.animationProperties.showDetailContent) {
              Image(this.params.imageInfo.pixelMap || $r('app.media.ic_placeholder'))
                .objectFit(ImageFit.Contain)
                .padding(20)
            }
          }
          .alignItems(HorizontalAlign.Start)
        }
        .position({ y: this.animationProperties.positionValue })
      }
      .scale({ x: this.animationProperties.scaleValue, y: this.animationProperties.scaleValue })
      .translate({ x: this.animationProperties.translateX, y: this.animationProperties.translateY })
      .width(this.animationProperties.clipWidth)
      .height(this.animationProperties.clipHeight)
      .borderRadius(this.animationProperties.radius)
      .expandSafeArea([SafeAreaType.SYSTEM])
      .clip(true)
    }
    .title(this.title)
    .menus([
      {
        value: 'downloadSinglePicture',
        icon: ($r('app.media.ic_download')),
        action: () => {
          this.downLoadSinglePicture(); // 点击菜单触发下载
        }
      }
    ])
    .backgroundColor('#000000')
    .onReady((context: NavDestinationContext) => {
      this.pageInfos = context.pathStack;
      this.pageId = this.pageInfos.getAllPathName().length - 1;
      const navParam = context.pathInfo?.param as BigImageParams;
      if (navParam) {
        this.params = navParam;
        this.title = this.params.imageInfo.filename;
        this.currentPictureName = this.params.imageInfo.filename;
        this.currentPictureFolder = this.params.imageInfo.folder;
        this.prePageDoFinishTransition = navParam.doDefaultTransition;
        this.cardItemInfo = navParam.cardItemInfo;
        this.currentNodeKey = navParam.uniqueKey;
        this.myNodeController = getMyNode(this.currentNodeKey);
      }
      CustomTransition.getInstance().registerNavParam(this.pageId,
        (isPush: boolean, isExit: boolean, transitionProxy: NavigationTransitionProxy) => {
          this.animationProperties.doAnimation(
            this.cardItemInfo, isPush, isExit, transitionProxy, 0,
            this.prePageDoFinishTransition, this.myNodeController
          );
        }, 500);
    })
    .onBackPressed(() => this.onBackPressed())
    .onDisAppear(() => {
      CustomTransition.getInstance().unRegisterNavParam(this.pageId);
      deleteMyNode(this.currentNodeKey);
    });
  }
}