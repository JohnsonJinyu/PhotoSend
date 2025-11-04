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
  private toolBarItems: ToolbarItem[] = [
    {
      value: '相机',
      icon: $r('app.media.xiangji'),
      action: () => {
        this.currentIndex = 0;
        //this.pageStack.replacePath({name:'CameraPage'})
      }
    },
    {
      value: '相册',
      icon: $r('app.media.xiangce'),
      action: () => {
        this.currentIndex = 1;
        //this.pageStack.replacePath({name:'PicturesPage'})
      }
    },
    {
      value: '我的',
      icon: $r('app.media.wode'),
      action: () => {
        this.currentIndex = 2;
        //this.pageStack.replacePath({name:'MinePage'})
      }
    }

  ]

  build() {
    // 根容器：Navigation
    Navigation() {
      Column() {
        if (this.currentIndex === 0) {
          NavDestination() {
            CameraPage()
          }.title('相机')
        } else if (this.currentIndex == 1) {
          NavDestination() {
            PicturesPage()
          }
          .title('相册')
        } else if (this.currentIndex == 2) {
          NavDestination() {
            MinePage()
          }
          .title('我的')
        }
      }

    }
    .hideTitleBar(false) // 显示标题栏（否则菜单按钮无法显示）
    .mode(NavigationMode.Auto)
    .hideBackButton(true) // 根导航隐藏返回按钮
    .toolbarConfiguration(this.toolBarItems)

  }
}