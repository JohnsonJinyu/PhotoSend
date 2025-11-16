import { RectInfoInPx } from '../../utils/ComponentAttrUtils';
import { AnimationProperties } from '../../CustomTransition/AnimationProperties';
import { MyNodeController, getMyNode } from '../../NodeContainer/CustomComponent';
import { CustomTransition } from '../../CustomTransition/CustomNavigationUtils';
import { ImageInfoWithPixelMap } from './CameraPicturesPage';

// 扩展大图页参数接口，新增转场必需字段
export interface BigImageParams {
  imageInfo: ImageInfoWithPixelMap;
  cardItemInfo: RectInfoInPx; // 上一页点击元素的位置信息
  doDefaultTransition: (myController: MyNodeController) => void; // 上一页转场回调
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
  @State myNodeController: MyNodeController | undefined = new MyNodeController(false);

  private pageId: number = -1;
  private shouldDoDefaultTransition: boolean = false;
  private prePageDoFinishTransition: (myController: MyNodeController) => void = () => {}; // 上一页转场回调
  private cardItemInfo: RectInfoInPx = new RectInfoInPx(); // 上一页元素位置
  private params: BigImageParams = {
    imageInfo: { folder: '', filename: '', pixelMap: null, thumbnail: new ArrayBuffer(0) },
    cardItemInfo: new RectInfoInPx(),
    doDefaultTransition: () => {}
  };

  // 监听配置变化，触发转场注销（和PageTwo保持一致）
  @StorageProp('windowSizeChanged') @Watch('unRegisterNavParam') windowSizeChangedTime: number = 0;
  @StorageProp('onConfigurationUpdate') @Watch('unRegisterNavParam') onConfigurationUpdateTime: number = 0;

  aboutToAppear(): void {
    // 迁移上一页的自定义节点到当前页（转场核心）
    this.myNodeController = getMyNode();
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
      this.prePageDoFinishTransition(this.myNodeController!); // 通知上一页迁回节点
      this.shouldDoDefaultTransition = false;
      return true;
    }
    // 正常返回流程
    CustomTransition.getInstance().unRegisterNavParam(this.pageId);
    this.pageInfos.pop();
    this.prePageDoFinishTransition(this.myNodeController!);
    return true;
  }

  build() {
    NavDestination() {
      // 外层Stack：绑定转场动画属性，控制缩放、位移、裁切
      Stack({ alignContent: Alignment.TopStart }) {
        // 内层Stack：承载图片和转场载体，避免布局偏移
        Stack({ alignContent: Alignment.TopStart }) {
          Column() {
            // 大图展示（绑定动画过程中的尺寸适配）
            Image(this.params.imageInfo.pixelMap || $r('app.media.ic_placeholder'))
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Contain) // 大图用Contain，适配全屏
              .padding(20)

            // 转场载体：NodeContainer无子类，与图片完全重叠（转场核心）
            NodeContainer(this.myNodeController)
              .width('100%')
              .height('100%')
              .position({ x: 0, y: 0 })
          }
          .width('100%')
          .height('100%')
        }
        .position({ y: this.animationProperties.positionValue }) // 绑定动画Y轴位移
      }
      // 绑定转场动画属性（缩放、位移、尺寸、圆角）
      .scale({ x: this.animationProperties.scaleValue, y: this.animationProperties.scaleValue })
      .translate({ x: this.animationProperties.translateX, y: this.animationProperties.translateY })
      .width(this.animationProperties.clipWidth)
      .height(this.animationProperties.clipHeight)
      .borderRadius(this.animationProperties.radius)
      .expandSafeArea([SafeAreaType.SYSTEM]) // 沉浸式，适配状态栏/导航条
      .clip(true) // 裁切动画过程中的多余部分
    }
    .backgroundColor('#000000') // 大图页黑色背景
    .hideTitleBar(true) // 隐藏标题栏，适配一镜到底视觉
    .onReady((context: NavDestinationContext) => {
      // 1. 获取导航栈和页面ID
      this.pageInfos = context.pathStack;
      this.pageId = this.pageInfos.getAllPathName().length - 1;
      // 2. 解析上一页传递的转场参数
      const navParam = context.pathInfo?.param as BigImageParams;
      if (navParam) {
        this.params = navParam;
        this.prePageDoFinishTransition = navParam.doDefaultTransition;
        this.cardItemInfo = navParam.cardItemInfo;
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
    });
  }
}