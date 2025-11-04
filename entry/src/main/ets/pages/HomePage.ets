import { CameraPage } from './CameraPage';
import { PicturesPage } from './PicturesPage';
import { MinePage } from './MinePage';


@Preview
@Entry
@Component
struct HomePage {
  private tabsController: TabsController = new TabsController();
  @State currentIndex: number = 0;
  @Provide('pageStack') pageStack: NavPathStack = new NavPathStack();


  build() {
    // 根容器：Navigation
    Navigation(this.pageStack) {
      Column() {

        Tabs({controller:this.tabsController,barPosition:BarPosition.End}){
          TabContent(){
            NavDestination(){
              CameraPage()
            }
            .title('相机')
            .hideBackButton(true)
          }
          .tabBar(this.buildTabBar('相机', $r('app.media.xiangji'), 0))

          TabContent(){
            NavDestination(){
              PicturesPage()
            }
            .title('相册')
            .hideBackButton(true)
          }
          .tabBar(this.buildTabBar('相册', $r('app.media.xiangce'), 1))

          TabContent(){
            NavDestination(){
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