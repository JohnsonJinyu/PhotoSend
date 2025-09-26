import { CameraPage } from './CameraPage'
import { FilePage } from './FilePage'
import { MinePage } from './MinePage'
import { PhonePage } from './PhonePage'


@Entry
@Component
struct HomePage{

  // 定义Tab 控制器
  private tabsController: TabsController = new TabsController()

  build() {

    Tabs({controller : this.tabsController}){

      TabContent(){
        CameraPage()
      }.tabBar('相机')

      TabContent(){
        PhonePage()
      }.tabBar('手机图')

      TabContent(){
        FilePage()

      }.tabBar('相机图')

      TabContent(){
        MinePage()
      }.tabBar('我的')

    }
    .height(`100%`)
    .margin({top:20})

  }
}
