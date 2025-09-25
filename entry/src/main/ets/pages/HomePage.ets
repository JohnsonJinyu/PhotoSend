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
      }.tabBar('手机')

      TabContent(){
        FilePage()

      }.tabBar('文件')

      TabContent(){
        MinePage()
      }.tabBar('我的')
    }
  }
}
