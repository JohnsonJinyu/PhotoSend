//BigImagePage.ets
import { RectInfoInPx } from '../../utils/ComponentAttrUtils';
import { AnimationProperties } from '../../CustomTransition/AnimationProperties';
import { MyNodeController, getMyNode,deleteMyNode } from '../../NodeContainer/CustomComponent';
import { CustomTransition } from '../../CustomTransition/CustomNavigationUtils';
import { ImageInfoWithPixelMap } from './CameraPicturesPage';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { common } from '@kit.AbilityKit';
import { ErrorEvent, MessageEvent, url, worker} from '@kit.ArkTS'
import { CamConnectionManager } from '../../utils/CamConnectManager';

// 扩展大图页参数接口，新增转场必需字段
// 扩展BigImageParams，新增uniqueKey字段
export interface BigImageParams {
  imageInfo: ImageInfoWithPixelMap;
  cardItemInfo: RectInfoInPx; // 上一页点击元素的位置信息
  uniqueKey: string; // 新增：当前转场节点的唯一标识
  doDefaultTransition: () => void; // 回调无需传node，改为通过key归位
}


// 复用Worker中的消息结构接口（也可单独定义在共享文件中）
interface DownloadMessage {
  folder: string;
  name: string;
  filesDir: string;
}
interface PostMessageData {
  type: 'success' | 'error';
  message?: string;
  savePath?: string;
}

// 定义Builder，符合路由配置的buildFunction
@Builder
export function BigImagePageBuilder() {
  BigImagePage();
}


@Component
export struct BigImagePage {
  @State pageInfos: NavPathStack = new NavPathStack();
  @State animationProperties: AnimationProperties = new AnimationProperties(this.getUIContext());

  @State title: string = '';
  @State currentPictureFolder:string=''
  @State currentPictureName:string = ''
  //@State myNodeController: MyNodeController | undefined = new MyNodeController(false);
  // 🔥 不再初始化单例，改为通过key动态获取
  private myNodeController: MyNodeController | undefined;
  // 新增：Worker实例
  private downloadWorker: worker.ThreadWorker | null = null;

  private pageId: number = -1;
  private shouldDoDefaultTransition: boolean = false;
  //private prePageDoFinishTransition: (myController: MyNodeController) => void = () => {}; // 上一页转场回调
  private prePageDoFinishTransition: () => void = () => {};
  private cardItemInfo: RectInfoInPx = new RectInfoInPx(); // 上一页元素位置
  private params: BigImageParams = {
    imageInfo: { folder: '', filename: '', pixelMap: null, thumbnail: new ArrayBuffer(0) },
    cardItemInfo: new RectInfoInPx(),
    uniqueKey:'',   // 初始化空key
    doDefaultTransition: () => {}
  };

  // 新增：当前转场节点的唯一标识
  private currentNodeKey: string = '';


  // 1. 声明单例变量（用于存储通过getInstance()获取的实例）
  private camManager: CamConnectionManager | null = null;

  // 监听配置变化，触发转场注销（和PageTwo保持一致）
  @StorageProp('windowSizeChanged') @Watch('unRegisterNavParam') windowSizeChangedTime: number = 0;
  @StorageProp('onConfigurationUpdate') @Watch('unRegisterNavParam') onConfigurationUpdateTime: number = 0;


  saveButtonOptions: SaveButtonOptions = {
    icon: SaveIconStyle.FULL_FILLED,
    text: SaveDescription.SAVE_IMAGE,
    buttonType: ButtonType.Capsule
  } // 设置安全控件按钮属性。




  aboutToAppear(): void {

    // 2. 通过静态方法获取实例（复用EntryAbility创建的单例）
    this.camManager = CamConnectionManager.getInstance();
    if (!this.camManager) {
      console.error("CameraPage 获取CamConnectionManager实例失败！");
      return;
    }


    // 2. 创建Worker并设置消息监听
    try {
      // 注意：Worker脚本路径需根据实际项目结构调整（相对于当前文件）
      this.downloadWorker = new worker.ThreadWorker('../../workers/DownloadMessage.ets');

      // 监听Worker发送的消息（处理下载结果）
      this.downloadWorker.onmessage = (e: MessageEvent<PostMessageData>) => {
        const data = e.data;
        if (data.type === 'success') {
          this.getUIContext().getPromptAction().showToast({
            message: `下载成功，保存至：${data.savePath}`,
            duration: 2000,
            bottom: 80
          });
        } else {
          this.getUIContext().getPromptAction().showToast({
            message: `下载失败：${data.message}`,
            duration: 2000,
            bottom: 80
          });
        }
      };

      // 监听Worker错误
      this.downloadWorker.onerror = (e: ErrorEvent) => {
        console.error(`Worker错误：${e.message}`);
        this.getUIContext().getPromptAction().showToast({
          message: `下载异常：${e.message}`,
          duration: 2000,
          bottom: 80
        });
        // 错误发生后销毁Worker，避免异常状态
        this.terminateWorker();
      };
    } catch (err) {
      console.error(`创建Worker失败：${(err as Error).message}`);
    }


  }

  aboutToDisappear(): void {
    this.terminateWorker()
  }

  // 销毁Worker（页面消失或出错时调用）
  private terminateWorker(): void {
    if (this.downloadWorker) {
      this.downloadWorker.terminate(); // 终止Worker运行
      this.downloadWorker = null;
    }
  }


  // 配置变化时标记需执行默认转场
  private unRegisterNavParam(): void {
    this.shouldDoDefaultTransition = true;
  }

  // 处理返回逻辑（返回时触发上一页转场回调，释放资源）
  private onBackPressed(): boolean {
    if (this.shouldDoDefaultTransition) {
      CustomTransition.getInstance().unRegisterNavParam(this.pageId);
      this.pageInfos.pop();
      //this.prePageDoFinishTransition(this.myNodeController!); // 通知上一页迁回节点
      this.prePageDoFinishTransition(); // 回调上一页，通过key归位
      this.shouldDoDefaultTransition = false;
      return true;
    }
    this.pageInfos.pop();
    return true;
  }


  /**
   * @description 下载单张照片
   * */
  // 完善下载方法：通过Worker执行下载（替代原有的setTimeout逻辑）
  private async downLoadSinglePicture() {
    if (!this.currentPictureFolder || !this.currentPictureName) {
      this.getUIContext().getPromptAction().showToast({
        message: "图片信息缺失，下载失败！",
        duration: 2000,
        bottom: 80
      });
      return;
    }

    if (!this.downloadWorker) {
      this.getUIContext().getPromptAction().showToast({
        message: "下载服务初始化失败",
        duration: 2000,
        bottom: 80
      });
      return;
    }

    // 显示下载中提示
    this.getUIContext().getPromptAction().showToast({
      message: "下载中！",
      duration: 3000,
      bottom: 80
    });

    try {
      // 获取文件存储目录（主线程获取后传给Worker）
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const filesDir = context.filesDir;
      if (!filesDir) {
        throw new Error("无法获取文件存储目录");
      }

      // 向Worker发送下载任务（包含必要参数）
      const message: DownloadMessage = {
        folder: this.currentPictureFolder,
        name: this.currentPictureName,
        filesDir: filesDir
      };
      this.downloadWorker.postMessage(message);
    } catch (err) {
      console.error(`下载参数准备失败：${(err as Error).message}`);
      this.getUIContext().getPromptAction().showToast({
        message: `下载失败：${(err as Error).message}`,
        duration: 2000,
        bottom: 80
      });
    }
  }

  build() {
    NavDestination() {
      // 外层Stack：绑定转场动画属性，控制缩放、位移、裁切
      Stack({ alignContent: Alignment.TopStart }) {
        // 内层Stack：承载图片和转场载体，避免布局偏移
        Stack({ alignContent: Alignment.TopStart }) {
          Column() {
            // 🔥 渲染当前key对应的节点（和上一页点击的图片一致）
            if (this.myNodeController){
              NodeContainer(this.myNodeController)
              // 绑定动画属性的透明度：转场结束后透明度变为0，隐藏占位图
                .opacity(this.animationProperties.showDetailContent ? 0 : 1)
                .visibility(this.animationProperties.showDetailContent ? Visibility.None : Visibility.Visible)
                .transition(TransitionEffect.OPACITY) // 增加透明度过渡，避免突兀
            }

            if (this.animationProperties.showDetailContent){
              Image(this.params.imageInfo.pixelMap || $r('app.media.ic_placeholder'))
                .objectFit(ImageFit.Contain)
                .padding(20)

              SaveButton(this.saveButtonOptions)  //创建安全控件按钮
                .onClick(async (event,result:SaveButtonOnClickResult)=>{
                  if (result == SaveButtonOnClickResult.SUCCESS) {
                    try {
                      let context:Context = this.getUIContext().getHostContext() as common.UIAbilityContext
                      let phAccessHelper =photoAccessHelper.getPhotoAccessHelper(context)
                      // 需要确保fileUri对应的资源存在。
                      let fileUri = ''
                      let assetChangeRequest: photoAccessHelper.MediaAssetChangeRequest =
                        photoAccessHelper.MediaAssetChangeRequest.createImageAssetRequest(context, fileUri);
                      await phAccessHelper.applyChanges(assetChangeRequest);
                      console.info('createAsset successfully, uri: ' + assetChangeRequest.getAsset().uri);
                    }catch (err){
                      console.error(`create asset failed with error: ${err.code}, ${err.message}`);
                    }
                  }else {
                    console.error('SaveButtonOnClickResult create asset failed');
                  }
                })
            }

          }
          .alignItems(HorizontalAlign.Start)

        }
        .position({ y: this.animationProperties.positionValue }) // 绑定动画Y轴位移
      }
      .scale({ x: this.animationProperties.scaleValue, y: this.animationProperties.scaleValue })
      .translate({ x: this.animationProperties.translateX, y: this.animationProperties.translateY })
      .width(this.animationProperties.clipWidth)
      .height(this.animationProperties.clipHeight)
      .borderRadius(this.animationProperties.radius)
      // expandSafeArea使得Stack做沉浸式效果，向上扩到状态栏，向下扩到导航条
      .expandSafeArea([SafeAreaType.SYSTEM])
      // 对高度进行裁切
      .clip(true)
    }
    .title(this.title)
    .menus([
      {
        value:'downloadSinglePicture',
        icon:($r('app.media.ic_download')),
        action:()=>{
          if (this.camManager) {
            this.camManager.pauseCheck()
          }

          this.downLoadSinglePicture()
        }
      }
    ])
    .backgroundColor('#000000') // 大图页黑色背景
    //.hideTitleBar(true) // 隐藏标题栏，适配一镜到底视觉
    .onReady((context: NavDestinationContext) => {
      // 1. 获取导航栈和页面ID
      this.pageInfos = context.pathStack;
      this.pageId = this.pageInfos.getAllPathName().length - 1;
      // 2. 解析上一页传递的转场参数
      // 🔥 解析参数时，获取uniqueKey并保存
      const navParam = context.pathInfo?.param as BigImageParams;
      if (navParam) {
        this.params = navParam;
        this.title = this.params.imageInfo.filename; // 触发状态更新
        this.currentPictureName = this.params.imageInfo.filename  // 名称更新用于保存文件
        this.currentPictureFolder = this.params.imageInfo.folder // 目录更新用于保存文件
        this.prePageDoFinishTransition = navParam.doDefaultTransition;
        this.cardItemInfo = navParam.cardItemInfo;
        this.currentNodeKey = navParam.uniqueKey; // 保存当前节点的唯一标识
        this.myNodeController = getMyNode(this.currentNodeKey); // 通过key获取节点

      }
      // 3. 注册自定义转场动画（和PageTwo逻辑一致）
      CustomTransition.getInstance().registerNavParam(this.pageId,
        (isPush: boolean, isExit: boolean, transitionProxy: NavigationTransitionProxy) => {
          this.animationProperties.doAnimation(
            this.cardItemInfo, isPush, isExit, transitionProxy, 0,
            this.prePageDoFinishTransition, this.myNodeController
          );
        }, 500);
    })
    .onBackPressed(() => this.onBackPressed()) // 绑定返回逻辑
    .onDisAppear(() => {
      // 页面消失时注销转场，释放资源
      CustomTransition.getInstance().unRegisterNavParam(this.pageId);
      // 🔥 页面消失时，删除当前节点（避免内存泄漏）
      deleteMyNode(this.currentNodeKey);
    });
  }
}