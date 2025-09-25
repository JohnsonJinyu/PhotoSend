import { promptAction } from "@kit.ArkUI"
import { common, Want } from '@kit.AbilityKit'
import { BusinessError } from '@ohos.base'


// 定义具体的连接模式类型
type ConnectionMode = '蓝牙' | 'WiFi-AP' | 'WiFi-STA';


// 用于存储单个选中值，包含一个 select 数字属性和 set 方法来更新该值
class modeSelectedValue {
  select: number = 2

  set(val: number) {
    this.select = val
  }
}

// 用于存储多个选中值，包含一个 select 数字数组属性和 set 方法来更新该数组
class modeSelectedArray {
  select: number[] = []

  set(val: number[]) {
    this.select = val
  }
}

@Preview
@Component
export struct CameraPage {
  // 状态控制
  @State currentConnectionMode: ConnectionMode = 'WiFi-AP'
  @State selectedModeIndex: number = 1
  // 连接模式选项
  private modeOptions: ConnectionMode[] = ['蓝牙', 'WiFi-AP', 'WiFi-STA']

  // 连接模式操作选项列表


  build() {
    Column() {

      //顶部图片显示区域
      Image($r(`app.media.camera_pre_zf`))
        .width(`100%`)
        .height(300)


      // 型号显示区域
      Text(`nikon zf`)
        .fontSize(24)
        .padding(20)

      Row() {
        Button(`链接相机`)
          .buttonStyle(ButtonStyleMode.EMPHASIZED)
          .fontSize(22)
          .height(50)
          .width(140)
          .margin({ right: 10 })

        Button(`模式:${this.currentConnectionMode}`)
          .fontSize(12)
          .width(120)
          .height(50)
          .onClick(() => {
            this.getUIContext().showTextPickerDialog({
              // range：选择器的选项列表，这里绑定组件中定义的连接模式数组（['蓝牙', 'WiFi-AP', 'WiFi-STA']）
              // 作用：决定弹窗中显示哪些可选项目
              range: this.modeOptions,
              // selected：初始选中项的索引，绑定组件的状态变量selectedModeIndex
              // 作用：打开弹窗时，默认选中上一次用户确认的选项（保证状态连贯性）
              selected: this.selectedModeIndex,
              onAccept: (value: TextPickerResult) => {
                //1、确保索引有效（单选项选选择器的index是number类型）
                if(typeof value.index == `number`)
                {
                  //2、更新选中索引的状态变量（下次打开选择其实默认选中当前项）
                  this.selectedModeIndex = value.index
                  //3、根据索引更新当前模式的状态变量（直接影响UI显示）
                  this.currentConnectionMode = this.modeOptions[value.index]
                }

                //设置select为按下确定按钮时候选中项index，这样当弹窗再次弹出时显示选中的是上一次确定的选项
                // 以下代码是保留的"选中值存储"逻辑（可根据实际需求决定是否保留）
                // 创建存储单个选中值和多个选中值的实例
                // 设计意图：兼容单选/多选场景，用不同的类分别存储（虽然当前是单选，但保留扩展性）
                let selectedVal = new modeSelectedValue()
                let selectedArr = new modeSelectedArray()
                // 判断索引是否存在（避免空值报错）
                if (value.index) {
                  // 根据索引类型（单个数字/数组）调用不同的set方法存储
                  // 当前场景是单选，会走selectedVal.set()，将索引存入modeSelectedValue实例
                  value.index instanceof Array ? selectedArr.set(value.index) : selectedVal.set(value.index)

                }
                console.info("TextPickerDialog:onAccept()" + JSON.stringify(value))
              },
              onCancel: () => {
                console.info("TextPickerDialog:onCancel()")
              },
              // onChange：用户在弹窗中切换选项时（未点击确定前）实时触发的回调
              // 作用：实时获取用户的选择过程（比如用户从"蓝牙"滑到"WiFi-AP"时触发）
              // 当前仅用于打印日志，方便调试时观察选择变化过程
              onChange:(value:TextPickerResult) =>{
                console.info("TextPickerDialog:onChange()"+JSON.stringify(value))
              }

            })
          })
      }
      .padding(20)


      Button(`遥控拍照`)
        .fontSize(22)
        .width(280)
        .height(50)


      Button('下载照片')
        .fontSize(22)
        .width(280)
        .height(50)
        .margin({ top: 20 })


      Blank(10)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.comp_background_list_card'))
  }
}
