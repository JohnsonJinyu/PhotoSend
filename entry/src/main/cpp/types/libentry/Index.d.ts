/**
 * 相机设备信息接口，包含相机名称和路径
 */
interface CameraDevice {
  /** 相机型号名称（如"Nikon D850"） */
  name: string;
  /** 相机连接路径（如"usb:001,005"） */
  path: string;
}

/**
 * 照片存储路径信息接口
 */
interface PhotoPathInfo {
  /** 照片所在文件夹路径 */
  folder: string;
  /** 照片文件名 */
  name: string;
}



/**
 * 设置 gphoto2 插件目录（相机驱动和端口驱动）
 * @param camlibDir 相机驱动目录
 * @param iolibDir 端口驱动目录
 * @returns 设置成功返回 true
 */
export const SetGPhotoLibDirs: (camlibDir: string, iolibDir: string) => boolean;



/**
 * 连接指定相机
 * @param cameraName 相机型号名称
 * @param cameraPath 相机连接路径
 * @returns 连接成功返回true，否则返回false
 */
export const ConnectCamera: (cameraName: string, cameraPath: string) => boolean;

/**
 * 设置相机参数（如光圈、快门、ISO等）
 * @param paramName 参数名称（如"aperture"表示光圈，"shutter-speed"表示快门）
 * @param paramValue 参数值（如"f/5.6"表示光圈值，"1/100"表示快门速度）
 * @returns 设置成功返回true，否则返回false
 */
export const SetCameraParameter: (paramName: string, paramValue: string) => boolean;

/**
 * 控制相机拍照
 * @returns 照片在相机内的存储路径信息，包含文件夹和文件名
 */
export const TakePhoto: () => PhotoPathInfo;

/**
 * 获取相机实时预览画面
 * @returns Base64编码的预览图像数据字符串
 */
export const GetPreview: () => Uint8Array;

/**
 * 从相机下载照片
 * @param folder 照片所在文件夹路径
 * @param name 照片文件名
 * @returns 照片的二进制数据（ArrayBuffer）
 */

export const DownloadPhoto: (folder: string, name: string) => ArrayBuffer;

/**
 * 断开与相机的连接
 * @returns 断开成功返回true
 */
export const Disconnect: () => boolean;


export const IsCameraConnected:()=>boolean