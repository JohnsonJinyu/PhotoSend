//BigImagePage.ets
import { RectInfoInPx } from '../../utils/ComponentAttrUtils';
import { AnimationProperties } from '../../CustomTransition/AnimationProperties';
import { MyNodeController, getMyNode,deleteMyNode } from '../../NodeContainer/CustomComponent';
import { CustomTransition } from '../../CustomTransition/CustomNavigationUtils';
import { ImageInfoWithPixelMap } from './CameraPicturesPage';

// 扩展大图页参数接口，新增转场必需字段
// 扩展BigImageParams，新增uniqueKey字段
export interface BigImageParams {
  imageInfo: ImageInfoWithPixelMap;
  cardItemInfo: RectInfoInPx; // 上一页点击元素的位置信息
  uniqueKey: string; // 新增：当前转场节点的唯一标识
  doDefaultTransition: () => void; // 回调无需传node，改为通过key归位
}

// 定义Builder，符合路由配置的buildFunction
@Builder
export function BigImagePageBuilder() {
  BigImagePage();
}

@Component
struct BigImagePage {
  @State pageInfos: NavPathStack = new NavPathStack();
  @State animationProperties: AnimationProperties = new AnimationProperties(this.getUIContext());
  //@State myNodeController: MyNodeController | undefined = new MyNodeController(false);
  // 🔥 不再初始化单例，改为通过key动态获取
  private myNodeController: MyNodeController | undefined;


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

  // 监听配置变化，触发转场注销（和PageTwo保持一致）
  @StorageProp('windowSizeChanged') @Watch('unRegisterNavParam') windowSizeChangedTime: number = 0;
  @StorageProp('onConfigurationUpdate') @Watch('unRegisterNavParam') onConfigurationUpdateTime: number = 0;

  aboutToAppear(): void {
    // 迁移上一页的自定义节点到当前页（转场核心）
    //this.myNodeController = getMyNode();
    // 🔥 通过key获取CameraPicturesPage传递的节点（不再获取单例）
    this.myNodeController = getMyNode(this.currentNodeKey);
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
    .title(this.params.imageInfo.filename)
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