




@Builder
export function CameraPicturesPageBuilder() {
  CameraPicturesPage();
}

@Component
export struct CameraPicturesPage {

  // 状态管理
  @State isSelectMode: boolean = false
  @State selectedPhotos: number[]=[]
  //@State photos:photoItem[]=[]
  @State isMoreMenuShow:boolean=false

  build() {

    NavDestination() {

      Column() {
        // 照片瀑布流
        WaterFlow(){

        }

      }
      .width('100%')
      .height('100%')

    }
    .title('机内照片')
    .menus()
    .width('100%')
    .height('100%')
  }
}