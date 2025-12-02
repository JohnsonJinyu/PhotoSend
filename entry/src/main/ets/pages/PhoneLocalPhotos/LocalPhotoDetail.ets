// LocalPhotoDetail.ets
// 以双List显示的图片详情页
import { ImageInfo } from "./LocalPhotoDataSource";
import Constants from "../../common/constants/Constants"

@Builder
export function LocalPhotoDetailBuilder() {
  LocalPhotoDetail();
}


@Component
struct LocalPhotoDetail{
  // 使用联合类型并初始化（需在arkts严格模式规范）
  @State receivedData:ImageInfo | null = null

  private smallScroller:Scroller = new Scroller()
  private bigScroller:Scroller = new Scroller()


  @StorageLink('selectedIndex') selectedIndex: number = 0;





  build() {
    NavDestination(){
      Stack({alignContent:Alignment.Bottom}){

        //显示大图的list
        List({scroller:this.bigScroller,initialIndex: this.selectedIndex}){

        }
        .width('100%')
        .height('100%')

        // 显示小图的List
        List({scroller:this.smallScroller,space:Constants.LIST_ITEM_SPACE,initialIndex: this.selectedIndex}){

        }
        .width('100%')
        .height('100%')  // 需要调整
      }

      Column(){
        Image(this.receivedData?.uri)
          .width('100%')
      }
    }
    .title(this.receivedData?.name)
    .onReady((ctx:NavDestinationContext)=>{
      try {
        this.receivedData = ctx.pathInfo.param as ImageInfo
      }catch (e){
        console.error(`参数解析异常: ${JSON.stringify(e)}`);
      }
    })
  }
}