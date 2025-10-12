// 1. 定义类型（不变）
export interface CameraInfo {
  name: string;
  path: string;
}

export interface PhotoPath {
  folder: string;
  name: string;
}

// 2. 关键：导入 C++ 编译的原生模块（模块名与 NAPI_MODULE 一致，即 "entry"）
// 注意：导入路径需根据项目配置调整，若为共享库，可能是 '@ohos/shared_library(entry)'
import NativeCameraModule from 'libentry.so';


// 3. 绑定原生函数 + 类型注解（替换原孤立声明）
// 用 "!" 断言非 undefined（前提是原生模块正确加载），或保留 "| undefined"
export const GetCameraList: (() => CameraInfo[]) | undefined = NativeCameraModule.GetCameraList;
export const ConnectCamera: ((cameraPath: string) => boolean) | undefined = NativeCameraModule.ConnectCamera;
export const SetCameraParameter: ((paramName: string, paramValue: string) => boolean) | undefined = NativeCameraModule.SetCameraParameter;
export const TakePhoto: (() => PhotoPath) | undefined = NativeCameraModule.TakePhoto;
export const GetPreview: (() => string) | undefined = NativeCameraModule.GetPreview;
export const DownloadPhoto: ((folder: string, name: string) => string) | undefined = NativeCameraModule.DownloadPhoto;
export const DisconnectCamera: (() => boolean) | undefined = NativeCameraModule.DisconnectCamera;