// LocalPhotoDetail.ets
import { ImageInfo } from "./LocalPhotoDataSource";


@Builder
export function LocalPhotoDetailBuilder() {
  LocalPhotoDetail();
}


@Component
struct LocalPhotoDetail{
  // 使用联合类型并初始化（需在arkts严格模式规范）
  @State receivedData:ImageInfo | null = null





  build() {
    NavDestination(){
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