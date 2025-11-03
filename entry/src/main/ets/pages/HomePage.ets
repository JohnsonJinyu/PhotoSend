import { CameraPage } from './CameraPage';
import { PhonePage } from './PhonePage';
import { MinePage } from './MinePage';


// 定义底部工具栏项（绑定点击事件）
let ToolBar_Camera: ToolbarItem = {
  value: "相机",
  icon: $r('app.media.xiangji'),
  action: () => {
  }
};
let ToolBar_Photo: ToolbarItem = {
  value: "相册",
  icon: $r('app.media.xiangce'),
  action: () => {
  }
};
let ToolBar_Mine: ToolbarItem = {
  value: "我的",
  icon: $r('app.media.wode'),
  action: () => {
  }
};
let TooBar: ToolbarItem[] = [ToolBar_Camera, ToolBar_Photo, ToolBar_Mine];

@Entry
@Component
struct HomePage {
  private tabsController: TabsController = new TabsController();
  @State currentIndex: number = 0;

  build() {
    // 根容器：Navigation
    Navigation() {
      // 内部Tabs，添加内边距避免贴边
      Tabs({ controller: this.tabsController, barPosition: BarPosition.End }) {
        // 1. 相机页面
        TabContent() {
          NavDestination() {
            CameraPage()
          }
          .title('相机')
          .hideBackButton(true) // 子页面也隐藏返回按钮
        }
        .tabBar(this.buildTabBar('相机', $r('app.media.xiangji'), 0))

        // 2. 相册页面
        TabContent() {
          NavDestination() {
            PhonePage()
          }
          .title('相册')
          .hideBackButton(true) // 子页面隐藏返回按钮
        }
        .tabBar(this.buildTabBar('相册', $r('app.media.xiangce'), 1))

        // 3. 我的页面
        TabContent() {
          NavDestination() {
            MinePage()
          }
          .title('我的')
          .hideBackButton(true) // 子页面隐藏返回按钮
        }
        .tabBar(this.buildTabBar('我的', $r('app.media.wode'), 2))
      }
      .barMode(BarMode.Fixed)
      .onChange((index: number) => {
        this.currentIndex = index;
      })
      // Tabs内容区添加内边距（避免顶部贴边）
      .padding({ top: 16 })
      // 底部工具栏适配安全区域（避免被设备底部导航条遮挡）
      .margin({ bottom: 10 })
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true) // 显示标题栏（否则菜单按钮无法显示）
    .mode(NavigationMode.Auto)
    .hideBackButton(true) // 根导航隐藏返回按钮
    // 导航栏添加内边距（避免内容贴边）
    .padding({ top: 16, bottom: 16 })
    .width('100%')
    .height('100%');
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
    .padding({ top: 8, bottom: 8 }) // Tab项内部增加内边距
    .justifyContent(FlexAlign.Center);
  }
}