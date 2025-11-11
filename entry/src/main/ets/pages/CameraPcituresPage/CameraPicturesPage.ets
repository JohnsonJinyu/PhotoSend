@Builder
export function CameraPicturesPageBuilder() {
  CameraPicturesPage();
}


@Component
export struct CameraPicturesPage {
  // 状态管理
  @State isSelectMode: boolean = false
  @State selectedPhotos: number[] = []
  //@State photos:photoItem[]=[]
  @State isMoreMenuShow: boolean = false


  @State menuItems:Array<NavigationMenuItem>=[
    {
      value:'多选',
      icon:$r('sys.media.ohos_ic_public_select_all'),
      action:()=>{

      }
    },
    {
      value:'菜单',
      icon:$r('sys.media.ohos_ic_public_more'),
      action:()=>{

      }
    }
  ]



  build() {

    NavDestination() {

      Column() {
        // 照片瀑布流
        WaterFlow() {

        }
      }
      .width('100%')
      .height('100%')

    }
    .title('机内照片')
    .menus()
    .width('100%')
    .height('100%')
    .menus(this.menuItems)
  }
}