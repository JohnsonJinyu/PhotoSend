//HomePage.ets

import { CameraPage } from './CameraPage/CameraPage';
import { PhoneLocalPhotos } from './PhoneLocalPhotos/PhoneLocalPhotos';
import { MinePage } from './MinePage/MinePage';
import { AnimateCallback, CustomTransition } from '../CustomTransition/CustomNavigationUtils';
import { CreateLocalDirUtil } from '../utils/tools/CreateLocalDir';
import { common } from '@kit.AbilityKit';
import dataPreferences from '@ohos.data.preferences';

const TAG: string = 'HomePage';
const DOMAIN = 0x00201;


@Preview
@Entry
@Component
struct HomePage {
  private tabsController: TabsController = new TabsController();
  @State currentIndex: number = 0;
  @State appStoragePath: string = ''; // 存储目录路径
  @Provide('pageStack') pageStack: NavPathStack = new NavPathStack();

  // 用于下面的创建目录
  private context = this.getUIContext().getHostContext() as common.UIAbilityContext;

  // 允许进行自定义转场的页面名称
  private allowedCustomTransitionFromPageName: string[] = ['CameraPicturesPage'];
  private allowedCustomTransitionToPageName: string[] = ['BigImagePage'];

  private isCustomTransitionEnabled(fromName: string, toName: string): boolean {
    // 点击和返回均需要进行自定义转场，因此需要分别判断
    if ((this.allowedCustomTransitionFromPageName.includes(fromName)
      && this.allowedCustomTransitionToPageName.includes(toName)) ||
      this.allowedCustomTransitionFromPageName.includes(toName)
        && this.allowedCustomTransitionToPageName.includes(fromName)) {
      return true
    }
    return false
  }

  async aboutToAppear(): Promise<void> {

    // 创建download下的目录
    //CreateLocalDirUtil.createOrGetDir(this.context);
    try {
      // 调用工具类获取目录路径（首次创建，后续直接读取）
      this.appStoragePath = await CreateLocalDirUtil.createOrGetDir(this.context);
      console.log(`获取到应用专属目录：${this.appStoragePath}`);

      // 后续逻辑：加载目录下的图片（示例）
      //await this.loadImagesFromDir();
    } catch (error) {
      console.error(`获取目录失败：${JSON.stringify(error)}`);
      //this.isLoading = false;
    }
  }

  build() {
    // 根容器：Navigation
    Navigation(this.pageStack) {
      Column() {

        Tabs({ controller: this.tabsController, barPosition: BarPosition.End }) {
          TabContent() {
            NavDestination() {
              CameraPage()
            }
            .title('相机')
            .hideBackButton(true)
          }
          .tabBar(this.buildTabBar('相机', $r('app.media.xiangji'), 0))

          TabContent() {
            NavDestination() {
              PhoneLocalPhotos()
            }
            .title('相册')
            .hideBackButton(true)
          }
          .tabBar(this.buildTabBar('相册', $r('app.media.xiangce'), 1))

          TabContent() {
            NavDestination() {
              MinePage()
            }
            .title('我的')
            .hideBackButton(true)
          }
          .tabBar(this.buildTabBar('我的', $r('app.media.wode'), 2))
        }
        .barMode(BarMode.Fixed)
        .onChange((index: number) => {
          this.currentIndex = index;
        })
        .scrollable(true)

      }

    }
    .hideTitleBar(false) // 显示标题栏（否则菜单按钮无法显示）
    .mode(NavigationMode.Auto)
    .hideBackButton(true) // 根导航隐藏返回按钮
    .hideToolBar(true)
    // 自定义转场-实现一镜到底
    .customNavContentTransition((from: NavContentInfo, to: NavContentInfo, operation: NavigationOperation) => {
      if ((!from || !to) || (!from.name || !to.name)) {
        return undefined;
      }

      // 通过from和to的name对自定义转场路由进行管控
      if (!this.isCustomTransitionEnabled(from.name, to.name)) {
        return undefined;
      }

      // 需要对专场页面是否注册了animation进行判断，来决定是否进行自定义转场
      let fromParam: AnimateCallback = CustomTransition.getInstance().getAnimateParam(from.index)
      let toParam: AnimateCallback = CustomTransition.getInstance().getAnimateParam(to.index)
      if (!fromParam.animation || !toParam.animation) {
        return undefined;
      }

      // 一切判断完成后，构造customAnimation给系统侧调用，执行自定义转场动画
      let customAnimation: NavigationAnimatedTransition = {
        onTransitionEnd: (isSuccess: boolean) => {
          console.info(TAG, `current transition result is ${isSuccess}`);
        },
        timeout: 2000,
        transition: (transitionProxy: NavigationTransitionProxy) => {
          console.info(TAG, 'trigger transition callback');
          if (fromParam.animation) {
            fromParam.animation(operation == NavigationOperation.PUSH, true, transitionProxy)
          }
          if (toParam.animation) {
            toParam.animation(operation == NavigationOperation.PUSH, false, transitionProxy)
          }
        }
      }
      return customAnimation
    })

  }

  // 自定义底部Tab样式（增加内边距避免贴边）
  @Builder
  buildTabBar(title: string, icon: Resource, index: number) {
    Column({ space: 4 }) {
      Image(icon)
        .width(24)
        .height(24)
        .fillColor(this.currentIndex === index ? '#007DFF' : '#666666');
      Text(title)
        .fontSize(12)
        .fontColor(this.currentIndex === index ? '#007DFF' : '#666666');
    }
    .width('100%')
    .height(56)
    //.padding({ top: 8, bottom: 8 }) // Tab项内部增加内边距
    .justifyContent(FlexAlign.Center);
  }
}