// HomePage.ets

import { CameraPage } from './CameraPage/CameraPage';
import { PhoneLocalPhotos } from './PhoneLocalPhotos/PhoneLocalPhotos';
import { MinePage } from './MinePage/MinePage';
import { AnimateCallback, CustomTransition } from '../CustomTransition/CustomNavigationUtils';
import { CreateLocalDirUtil } from '../utils/tools/CreateLocalDir';
import { common } from '@kit.AbilityKit';
import dataPreferences from '@ohos.data.preferences';
import { PtpConnectionManager } from '../utils/PtpConnectionManager';

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
  
  // 相机连接状态
  @State cameraConnected: boolean = false;
  @State connectionMessage: string = '正在检测相机...';

  // 用于下面的创建目录
  private context = this.getUIContext().getHostContext() as common.UIAbilityContext;

  // 允许进行自定义转场的页面名称
  private allowedCustomTransitionFromPageName: string[] = ['CameraPicturesPage','PhoneLocalPhotos'];
  private allowedCustomTransitionToPageName: string[] = ['BigImagePage','LocalPhotoDetail'];




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
    try {
      // 1. 创建 download 下的目录
      this.appStoragePath = await CreateLocalDirUtil.createOrGetDir(this.context);
      console.log(`获取到应用专属目录：${this.appStoragePath}`);

      // 2. 设置默认相机 IP
      PtpConnectionManager.setDefaultCamera('192.168.1.1', 15740);
      PtpConnectionManager.setAutoReconnect(false);
      console.info(TAG, '已关闭自动重连，使用最小会话实验模式进行启动检测');

      // 3. 添加连接状态监听器
      PtpConnectionManager.addListener((state: boolean, message: string) => {
        console.info(TAG, `收到连接状态更新：state=${state}, message=${message}`);
        this.cameraConnected = state;
        this.connectionMessage = message;
      });
        
      // 4. 启动自动检测连接（使用 PTP/IP）
      const result = await PtpConnectionManager.autoDetectAndConnect();
      console.info(TAG, `自动检测结果：${JSON.stringify(result)}`);
        
    } catch {
      console.error(`初始化失败`);
    }
  }

  build() {
    // 根容器：Navigation
    Navigation(this.pageStack) {
      Column() {
        
        // 顶部连接状态栏
        Row() {
          Text(this.cameraConnected ? '✓ 已连接' : '✗ 未连接')
            .fontSize(14)
            .fontColor(this.cameraConnected ? '#007DFF' : '#999999')
            .margin({ right: 8 })
          
          Blank()
          
          Text(this.connectionMessage)
            .fontSize(14)
            .fontColor('#666666')
          
          Blank()
          
          // 未连接时显示连接按钮
          if (!this.cameraConnected) {
            Button('手动连接')
              .fontSize(12)
              .backgroundColor('#007DFF')
              .onClick(async () => {
                await this.handleManualConnect();
              })
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })
        .backgroundColor('#F5F5F5')

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
              PhoneLocalPhotos({ appStoragePath: $appStoragePath })
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

      // 需要对转场页面是否注册了animation进行判断，来决定是否进行自定义转场
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

  // 自定义底部 Tab 样式（增加内边距避免贴边）
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
    .justifyContent(FlexAlign.Center);
  }
  
  // 处理手动连接按钮点击
  private async handleManualConnect(): Promise<void> {
    console.info(TAG, '用户点击手动连接按钮');
    this.connectionMessage = '正在连接...';
    
    const result = await PtpConnectionManager.manualConnect();
    console.info(TAG, `手动连接结果：${JSON.stringify(result)}`);
  }
}