// CameraPagePreview.ets
import { CameraPage } from '../CameraPage/CameraPage';
import { RemoteControl } from './RemoteControl';


// 预览专用组件，提供模拟的pageStack
@Preview
@Entry
@Component
struct RemoteControlPreview {
  // 模拟一个NavPathStack实例（仅用于预览）
  @Provide('pageStack') pageStack: NavPathStack = new NavPathStack();

  build() {
    // 渲染业务组件CameraPage，此时pageStack由预览包装器提供
    Column(){
      RemoteControl()
    }

  }
}