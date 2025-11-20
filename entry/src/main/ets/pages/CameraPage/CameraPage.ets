// CameraPage.ets
import { common, Want } from '@kit.AbilityKit'

import { BusinessError } from '@ohos.base'
import { camConnectionManager, ConnectionStateResult } from '../../utils/CamConnectManager';
import { CameraHelper } from 'ets/utils/CameraHelper';

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


@Component
export struct CameraPage {
  @Consume('pageStack') pageStack: NavPathStack;
  // 定义响应式变量(@state 确保UI能够实时更新
  @State currentState: ConnectionStateResult = { state: false, message: `未连接相机！` }
  // 新增：控制加载控件显示的状态
  @State isLoading: boolean = false;
  // 状态控制
  @State currentConnectionMode: ConnectionMode = 'WiFi-AP'
  @State selectedModeIndex: number = 1
  // 4. 状态更新示例（比如连接成功/失败时更新状态） 在下面用
  // 连接成功时
  //this.isDeviceConnected = true;
  // 连接失败/断开时
  // this.isDeviceConnected = false;

  // 连接模式选项
  private modeOptions: ConnectionMode[] = ['蓝牙', 'WiFi-AP', 'WiFi-STA']
  // 相机型号选项
  private SupportNikonModel: string[] =
    ['Zf', 'Zfc', 'Z9', 'Z8', 'Z7', 'Z7_2', 'Z6', 'Z6_2', 'Z6 III', 'Z5', 'Z50', 'Z30']
  // 预计支持的相机厂商
  private SupportCamManufacturer: string[] = ['Nikon', 'Sony', 'Canon']
  // 连接模式操作选项列表
  // 设置默认相机厂商
  @State currentCamManufacturer: string = 'Nikon'
  // 定义默认相机型号
  @State currentCamModel: string = 'Zf'

  aboutToAppear() {
    // 注册监听器
    camConnectionManager.addListener(this.handleStateChange);

    // 初始化 直接从店里获取当前状态（首次加载UI使用）
    this.currentState = camConnectionManager.getCurrentState()


    // 2. 新增：初始化时同步默认的厂商和型号到管理器
    camConnectionManager.updateCameraInfo(this.currentCamManufacturer, this.currentCamModel);
  }

  aboutToDisappear() {
    // 移除监听器
    camConnectionManager.removeListener(this.handleStateChange);
  }

  // 🔥 状态同步回调：单例状态变化时触发，更新组件的响应式变量
  private handleStateChange = (state: boolean, message: string) => {
    // 直接更新 currentState，因 @State 修饰，UI会自动刷新
    console.log(`UI监听器触发：新state=${state}，新message=${message}`) // 🔥 新增日志
    this.currentState = { state, message };
    // 连接状态变化后，关闭加载控件
    if (this.isLoading) {
      this.isLoading = false;
    }
  };

  build() {

    Stack({ alignContent: Alignment.Center }) {
      Column({ space: 10 }) {

        //顶部图片显示区域
        Image($r(`app.media.camera_pre_zf`))
          .width(`100%`)
          .height(300)


        // 设备型号显示区域
        Row() {

          Button(this.currentCamManufacturer)
            .buttonStyle(ButtonStyleMode.NORMAL)
            .width(120)
            .fontWeight(FontWeight.Medium)
            .onClick(() => {
              this.getUIContext().showTextPickerDialog({
                range: this.SupportCamManufacturer,
                defaultPickerItemHeight: 36,
                canLoop: true,
                selected: this.selectedModeIndex,
                onAccept: (value: TextPickerResult) => {
                  if (typeof value.index == 'number') {
                    this.selectedModeIndex = value.index
                    this.currentCamManufacturer = this.SupportCamManufacturer[value.index]
                    // 同步到管理器：厂商变化时更新
                    camConnectionManager.updateCameraInfo(this.currentCamManufacturer, this.currentCamModel);
                  }
                }

              })
            })


          Button(this.currentCamModel)
            .buttonStyle(ButtonStyleMode.NORMAL)
            .width(80)
            .fontWeight(FontWeight.Medium)
            .onClick(() => {
              this.getUIContext().showTextPickerDialog({
                range: this.SupportNikonModel,
                // selected：初始选中项的索引，绑定组件的状态变量selectedModeIndex
                // 作用：打开弹窗时，默认选中上一次用户确认的选项（保证状态连贯性）
                selected: this.selectedModeIndex,
                onAccept: (value: TextPickerResult) => {
                  //1、确保索引有效（单选项选选择器的index是number类型）
                  if (typeof value.index == `number`) {
                    //2、更新选中索引的状态变量（下次打开选择其实默认选中当前项）
                    this.selectedModeIndex = value.index
                    //3、根据索引更新当前模式的状态变量（直接影响UI显示）
                    this.currentCamModel = this.SupportNikonModel[value.index]
                    // 同步到管理器：型号变化时更新
                    camConnectionManager.updateCameraInfo(this.currentCamManufacturer, this.currentCamModel);
                  }
                }
              })
            })

        }


        // 🔥 设备连接状态栏：直接使用 currentState（单例同步过来的状态）
        Row() {
          // 显示设备连接状态
          Text(`设备状态:${this.currentState.message}`)
            .fontSize(16)
            .padding(10)


          // LED灯：根据 currentState.state 变化颜色
          Circle()
            .borderRadius(12) // 圆角为宽度的一半，确保正圆
            .width(24) // 设置宽度为24vp
            .height(24) // 高度与宽度一致，形成正圆
            .fill(this.currentState.state ? '#00C853' : '#F44336') //绿色=已连接 ，红色=未连接
            // 阴影效果增强发光感
            .shadow({
              radius: 8, //阴影模糊半径
              color: this.currentState.state ? 'rgba(0, 200, 83, 0.6)' : 'rgba(244, 67, 54, 0.6)', // 阴影颜色与主体一致，降低透明度
              offsetX: 0,
              offsetY: 0
            })
            .animation({ duration: 300 }); //颜色切换添加300ms过度

        }


        Row() {

          // 跳转WiFi或蓝牙设置页面，让用户手动选择连接
          Button(`跳转WIFI设置`)
            .buttonStyle(ButtonStyleMode.EMPHASIZED)
            .fontSize(12)
            .height(40)
            .width(140)
            .margin({ right: 10 })
            .onClick(async () => { //异步回调，因为startAbility可能需要等待结果
              try {
                //1、更具当前选中的连接模式，构造对应系统页面的want(跳转参数)
                let targetWant: Want; // Want 是ArkUI中用于跨能力跳转的参数对象
                // 2、调用系统能力，发起跳转（需要传入组件上下文）
                let context = getContext(this) as common.UIAbilityContext
                // const uiAbilityContext = getContext(this) as common.UIAbilityContext

                switch (this.currentConnectionMode) {
                  // case 1:wifi
                  case `WiFi-AP`:
                  case `WiFi-STA`:
                    targetWant = {
                      bundleName: 'com.huawei.hmos.settings',
                      abilityName: 'com.huawei.hmos.settings.MainAbility',
                      uri: 'wifi_entry',

                    };
                    break

                  //case 2:bluetooth
                  case `蓝牙`: {
                    targetWant = {
                      bundleName: 'com.huawei.hmos.settings',
                      abilityName: 'com.huawei.hmos.settings.MainAbility',
                      uri: 'bluetooth_entry',
                    };
                    break;
                  }

                  default:

                    return; //终止后续逻辑
                }


                if (!context) {
                  throw new Error("获取应用上下文失败（华为设备）");
                }

                // 关键调整：移除内层catch，统一用外层try-catch处理错误
                await context.startAbility(targetWant);


              } catch (error) {
                const err = error as BusinessError;
                //promptAction.showToast({ message: `跳转失败：${err.message || '未知错误'}` });
                console.error(`跳转系统设置失败：${JSON.stringify(err)}`);
              }
            })


          Button(`模式:${this.currentConnectionMode}`)
            .fontSize(12)
            .width(120)
            .height(40)
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
                  if (typeof value.index == `number`) {
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
                onChange: (value: TextPickerResult) => {
                  console.info("TextPickerDialog:onChange()" + JSON.stringify(value))
                }

              })
            })
        }


        Button('手动连接相机')
          .fontSize(16)
          .width(280)
          .height(40)
          .enabled(!this.currentState.state)
          .onClick(() => {

            // 提前实例化CameraHelper
            const cameraHelper = CameraHelper.getInstance();

            // 仅当未连接时才触发连接并显示加载
            if (!this.currentState.state) {
              this.isLoading = true; // 显示加载控件
              camConnectionManager.connectCamera();
            }
          })


        Button(`遥控拍照`)
          .fontSize(20)
          .width(280)
          .height(40)
          .margin({ top: 10 })
          .onClick(() => {
            this.pageStack.pushPathByName('RemoteControl', null, true)
          })


        Button('下载照片')
          .fontSize(20)
          .width(280)
          .height(40)
          .margin({ top: 10 })
          .onClick(() => {
            this.pageStack.pushPathByName('CameraPicturesPage', null, true)
          })


      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('sys.color.comp_background_list_card'))




    }
  }
}
