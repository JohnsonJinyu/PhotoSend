// BigImagePage.ets
import { RectInfoInPx } from '../../utils/animation/ComponentAttrUtils';
import { AnimationProperties } from '../../CustomTransition/AnimationProperties';
import { MyNodeController, getMyNode, deleteMyNode } from '../../NodeContainer/CustomComponent';
import { CustomTransition } from '../../CustomTransition/CustomNavigationUtils';
import { ImageInfoWithPixelMap } from './CamPhotoPrePage';
import { common, UIAbility } from '@kit.AbilityKit';
import { ErrorEvent, MessageEvent, worker } from '@kit.ArkTS';
import { CamConnectionManager } from '../../utils/tools/CamConnectManager';
import picker from '@ohos.file.picker';
import fs from '@ohos.file.fs';
import { BusinessError } from '@ohos.base';
import { fileUri } from '@kit.CoreFileKit';

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
  tempFilePath: string;
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
  tempFilePath: string;
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
        console.log(`主线程收到 Worker 消息：${JSON.stringify(e.data)}`); // 打印完整消息
        const data = e.data;
        // 增加校验：如果 data 不存在，直接返回并提示错误
        if (!data) {
          console.error("主线程收到 Worker 消息，但 data 为 undefined");
          this.showToast("下载失败：消息解析异常");
          return;
        }
        switch (data.type) {
          case 'downloadSuccess':
            // 下载成功，在主线程使用 Picker 保存文件
            // 从沙箱读取文件并保存到用户指定位置
            await this.saveImageFromSandbox(data.name, data.tempFilePath);
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
  /**
   * 触发下载流程：创建沙箱临时路径（兼容旧逻辑，不变）
   */
  private async downLoadSinglePicture() {
    if (!this.currentPictureFolder || !this.currentPictureName) {
      this.showToast("图片信息缺失，下载失败！");
      return;
    }
    if (!this.downloadWorker) {
      this.showToast("下载服务初始化失败");
      return;
    }

    this.showToast("下载中...");

    try {
      // 构建沙箱临时路径（用 UIContext.filesDir，避免不存在的 API）
      const uiContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const filesDir = uiContext.filesDir; // 应用私有目录（无需权限）
      const timestamp = new Date().getTime();
      const fileExt = this.currentPictureName.split('.').pop() || 'jpg';
      const tempFileName = `camera_download_${timestamp}.${fileExt}`;
      const tempFilePath = `${filesDir}/${tempFileName}`;

      console.log(`主线程创建沙箱临时路径：${tempFilePath}`);

      // 向 Worker 发送消息（带 tempFilePath）
      const message: DownloadTaskMessage = {
        folder: this.currentPictureFolder,
        name: this.currentPictureName,
        tempFilePath: tempFilePath
      };
      this.downloadWorker.postMessage(message);

    } catch (error) {
      const err = error as BusinessError;
      console.error(`创建临时路径失败：${err.message}`);
      this.showToast(`下载失败：无法创建临时文件`);
    }
  }


  /**
   * 核心修改：按文档 DOWNLOAD 模式保存文件
   * 1. 从沙箱读取数据 → 2. 用 DOWNLOAD 模式保存到系统 Download/包名/ → 3. 清理临时文件
   */
  private async saveImageFromSandbox(fileName: string, tempFilePath: string) {
    let fileContent: ArrayBuffer | null = null;

    try {
      // -------------------------- 步骤1：强化沙箱文件读取与校验 --------------------------
      console.log(`从沙箱读取文件：${tempFilePath}`);

      // 验证沙箱文件存在且可读取 (使用数值 4 代替 fs.AccessMode.R_OK)
      await fs.access(tempFilePath, 4);
      console.log(`沙箱文件可读取：${tempFilePath}`);

      // 获取文件大小
      const fileStats = await fs.stat(tempFilePath);
      const expectedSize = fileStats.size;
      console.log(`沙箱文件预期大小：${expectedSize}字节`);

      // 读取文件
      const buffer = new ArrayBuffer(expectedSize);
      const tempFile = await fs.open(tempFilePath, fs.OpenMode.READ_ONLY);
      try {
        const bytesRead: number = await fs.read(tempFile.fd, buffer);
        console.log(`实际读取字节数：${bytesRead}`);

        // 校验读取完整性
        if (bytesRead !== expectedSize) {
          throw new Error(`读取不完整：预期=${expectedSize}，实际=${bytesRead}`);
        }
        fileContent = buffer;
      } finally {
        await fs.close(tempFile.fd);
      }

      // 校验 fileContent 有效性
      if (!fileContent || fileContent.byteLength !== expectedSize) {
        throw new Error(`数据无效：大小=${fileContent?.byteLength || 0}字节`);
      }
      console.log(`沙箱文件读取成功：${fileContent.byteLength}字节`);

      // -------------------------- 步骤2：DOWNLOAD 模式保存 --------------------------
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const documentPicker = new picker.DocumentViewPicker(context);
      const saveOptions = new picker.DocumentSaveOptions();
      saveOptions.pickerMode = picker.DocumentPickerMode.DOWNLOAD;

      const uris = await documentPicker.save(saveOptions);
      if (!uris || uris.length === 0) {
        throw new Error("未获取到 DOWNLOAD 目录 URI");
      }
      const baseUri = uris[0];
      console.log(`DOWNLOAD 基础 URI：${baseUri}`);

      // 拼接目标路径并验证权限
      const targetUri: fileUri.FileUri = new fileUri.FileUri(`${baseUri}/${fileName}`);
      const targetFilePath = targetUri.path;
      const targetDir = targetFilePath.substring(0, targetFilePath.lastIndexOf('/'));

      // 验证目标目录可写入 (使用数值 2 代替 fs.AccessMode.W_OK)
      await fs.access(targetDir, 2);
      console.log(`目标路径可写入：${targetFilePath}`);

      // -------------------------- 步骤3：优化写入参数 --------------------------
      const targetFile = await fs.open(targetFilePath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);
      try {
        await fs.write(targetFile.fd, fileContent); // 直接传递 ArrayBuffer
        console.log(`保存成功：${targetFilePath}`);
        this.showToast(`保存成功！路径：${targetFilePath}`);
      } finally {
        await fs.close(targetFile.fd);
      }

    } catch (error) {
      const err = error as BusinessError;
      console.error(`保存失败：错误码=${err.code}，信息=${err.message}`, error.stack);
      this.showToast(`保存失败：${err.message}`);

    } finally {
      // -------------------------- 步骤4：清理沙箱文件 --------------------------
      if (tempFilePath) {
        try {
          // 检查文件是否存在 (使用数值 0 代替 fs.AccessMode.F_OK)
          await fs.access(tempFilePath, 0);
          await fs.unlink(tempFilePath);
          console.log(`清理沙箱文件：${tempFilePath}`);
        } catch (cleanupErr) {
          const err = cleanupErr as BusinessError;
          console.warn(`清理失败：${err.message}`);
        }
      }
    }
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