/**
 *  机内照片下载页面
 * */

import nativeCamera, { ThumbnailInfo } from 'libentry.so'

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

  // 存储照片缩略图信息（包含文件名、路径等）
  @State thumbnails: ThumbnailInfo[] = [];
  // 加载状态（控制加载提示显示）
  @State isLoading: boolean = true;
  // 错误信息（获取失败时显示）
  @State errorMsg: string = '';


  @State menuItems:Array<NavigationMenuItem>=[
    {
      value:'多选',
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

  aboutToAppear(): void{



    this.isLoading = true;
    this.errorMsg = '';
    // 调用C++异步接口，传入回调函数（与类型声明匹配）
    nativeCamera.GetThumbnailList((err: string | null, result: ThumbnailInfo[]) => {
      if (err) {
        this.errorMsg = `获取失败：${err}`;
        console.error(this.errorMsg);
      } else {
        this.thumbnails = result;
        console.log(`成功获取${result.length}张照片`);
      }
      this.isLoading = false;
    });

  }


  build() {
    NavDestination() {
      Column() {
        // 加载中状态
        if (this.isLoading) {
          Column({ space: 10 }) {
            LoadingProgress()
             // .color($r('sys.color.primary'))
              .size({ width: 40, height: 40 });
            Text('正在检索照片...')
              .fontSize(16)
              //fontColor($r('sys.color.secondary_text'));
          }
          .margin({ top: 50 });
        }

        // 错误状态
        else if (this.errorMsg) {
          Text(this.errorMsg)
            .fontSize(16)
            //.fontColor($r('sys.color.error'))
            .padding(20);
        }

        // 成功获取数据，展示照片信息
        else {
          // 照片数量提示
          Text(`共找到 ${this.thumbnails.length} 张照片`)
            .fontSize(14)
           // .fontColor($r('sys.color.secondary_text'))
            .padding({ left: 16, top: 10 });

          // 用List展示照片信息（文件名+路径）
          List({ space: 10 }) {
            ForEach(this.thumbnails, (item: ThumbnailInfo, index: number) => {
              ListItem() {
                Column({ space: 5 }) {
                  // 文件名
                  Text(`照片名：${item.filename}`)
                    .fontSize(16)
                    .fontWeight(FontWeight.Medium);
                  // 文件路径（可选，调试用）
                  Text(`路径：${item.folder}`)
                    .fontSize(12)
                    //.fontColor($r('sys.color.secondary_text'));
                }
                .padding(16)
                //.backgroundColor($r('sys.color.background'))
                .borderRadius(10)
                .width('100%');
              }
            }, (item:ThumbnailInfo) => item.filename + item.folder); // 唯一键
          }
          .padding(16)
          .width('100%')
          .flexGrow(1); // 占满剩余空间
        }
      }
      .width('100%')
      .height('100%');
    }
    .title('机内照片')
    .menus(this.menuItems)
    .width('100%')
    .height('100%');
  }
}