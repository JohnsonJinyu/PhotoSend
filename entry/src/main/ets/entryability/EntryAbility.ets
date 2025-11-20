import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { display, window } from '@kit.ArkUI';
import nativeEntry from 'libentry.so'
import common from '@ohos.app.ability.common';
import { WindowUtils } from '../utils/WindowUtils';
import { CamConnectionManager } from '../utils/CamConnectManager';

const DOMAIN = 0x0000;
const TAG: string = 'EntryAbility';

// 程序入口处的onWindowStageCreate增加对窗口宽高等的抓取
export default class EntryAbility extends UIAbility {
  private currentBreakPoint: string = '';

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);


    // 获取上下文
    let context: common.Context = this.context;

    // 直接通过context获取应用信息，直接方位nativeLibraryDir
    let appInfo = context.getApplicationContext().applicationInfo
    let nativeLibDir = appInfo.nativeLibraryPath.toString()

    hilog.info(DOMAIN, 'testTag', 'API 20获取的nativeLibraryDir: %{public}s', nativeLibDir);

    // 初始化 gphoto2 插件目录
    nativeEntry.SetGPhotoLibDirs(nativeLibDir);


    // 主线程主动初始化单例，仅执行一次
    // 2. 通过静态方法获取单例（主线程仅执行一次）
    const camManager = CamConnectionManager.getInstance();
    console.log('主线程初始化 CamConnectionManager 单例成功');


    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');


    // *********************************关于一镜到底的代码的相关项******************************
    // 获取窗口高度
    WindowUtils.window = windowStage.getMainWindowSync()
    WindowUtils.windowWidth_px = WindowUtils.window.getWindowProperties().windowRect.width
    WindowUtils.windowHeight_px = WindowUtils.window.getWindowProperties().windowRect.height

    this.updateBreakpoint(WindowUtils.windowWidth_px)

    // 获取上方避让区（状态栏等）高度
    let avoidArea = WindowUtils.window.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM)
    WindowUtils.topAvoidAreaHeight_px = avoidArea.topRect.height

    // 获取导航条高度
    let navigationArea = WindowUtils.window.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR)
    WindowUtils.topAvoidAreaHeight_px = navigationArea.bottomRect.height

    hilog.info(0x0000, TAG, 'the width is ' + WindowUtils.windowWidth_px + '  ' + WindowUtils.windowHeight_px + '  ' +
    WindowUtils.topAvoidAreaHeight_px + '  ' + WindowUtils.navigationIndicatorHeight_px);

    // 监听窗口尺寸、状态栏高度、以及导航条的高度并更新
    try {
      WindowUtils.window.on('windowSizeChange',(data)=>{
        hilog.info(0x0000, TAG, 'on windowSizeChange, the width is ' + data.width + ', the height is ' + data.height);
        WindowUtils.windowWidth_px = data.width
        WindowUtils.windowHeight_px = data.height
        this.updateBreakpoint(data.width)
        AppStorage.setOrCreate('windowSizeChanged',Date.now())
      })

      WindowUtils.window.on('avoidAreaChange', (data) => {
        if (data.type == window.AvoidAreaType.TYPE_SYSTEM) {
          let topRectHeight = data.area.topRect.height;
          hilog.info(0x0000, TAG, 'on avoidAreaChange, the top avoid area height is ' + topRectHeight);
          WindowUtils.topAvoidAreaHeight_px = topRectHeight;
        } else if (data.type == window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR) {
          let bottomRectHeight = data.area.bottomRect.height;
          hilog.info(0x0000, TAG, 'on avoidAreaChange, the navigation indicator height is ' + bottomRectHeight);
          WindowUtils.navigationIndicatorHeight_px = bottomRectHeight;
        }
      })
    }catch (exception) {
      hilog.error(0x0000, TAG, `register failed. code: ${exception.code}, message: ${exception.message}`);
    }

    //************************* 一镜到底截止******************************************//




    windowStage.loadContent('pages/HomePage', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });



  }


  // 一镜到底相关补充的方法定义

  updateBreakpoint(width:number){
    let windowWidthVp = width / (display.getDefaultDisplaySync().densityDPI / 160)
    let newBreakPoint:string= ''
    if (windowWidthVp < 400) {
      newBreakPoint = 'xs'
    }
    else if (windowWidthVp < 600) {
        newBreakPoint = 'sm'
    }
    else if (windowWidthVp < 800) {
      newBreakPoint = 'md'
    }
    else {
      newBreakPoint = 'lg'
    }

    if (this.currentBreakPoint !== newBreakPoint) {
      this.currentBreakPoint = newBreakPoint
      // 使用状态变量记录当前断点值
      AppStorage.setOrCreate('currentBreakpoint',this.currentBreakPoint)
    }
  }


  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}