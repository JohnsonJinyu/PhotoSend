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
 * 相机状态信息接口，包含电量、参数、存储等信息
 */
interface CameraStatus {
  /** 是否成功获取信息 */
  isSuccess: boolean;

  /** 电量状态（如"Full"、"50%"、"Low"） */
  batteryLevel: string;

  /** 光圈值（如"2.8"、"5.6"、"Auto"） */
  aperture: string;

  /** 快门速度（如"1/1000"、"0.001"、"Auto"） */
  shutter: string;

  /** ISO值（如"400"、"800"、"Auto"） */
  iso: string;

  /** 曝光补偿（如"0.3"、"-1.0"，单位EV） */
  exposureCompensation: string;

  /** 白平衡模式（如"Auto"、"Daylight"、"Tungsten"） */
  whiteBalance: string;

  /** 拍摄模式（如"Program"、"Aperture Priority"、"Manual"） */
  captureMode: string;

  /** 剩余存储空间（单位：字节，大整数） */
  freeSpaceBytes: bigint;

  /** 剩余可拍摄张数 */
  remainingPictures: number;

  /** 曝光模式 */
  exposureProgram: string;

  /** 对焦模式*/
  focusMode: string;

  /** 测光模式 */
  exposureMeterMode: string;
}


/**
 * 相机配置参数项接口，包含参数名称、显示名称、类型、当前值及可选值列表
 */
interface ConfigItem {
  /** 参数名（如"aperture"、"shutter-speed"） */
  name: string;

  /** 参数显示名称（如"Aperture"、"Shutter Speed"） */
  label: string;

  /** 参数类型（如"choice"表示选项类型、"text"表示文本类型、"range"表示范围类型） */
  type: string;

  /** 参数当前值（如"f/5.6"、"1/100"） */
  current: string;

  /** 参数可选值列表（仅类型为"choice"时有效，如["f/2.8", "f/4", "f/5.6"]） */
  choices: string[];
}

/**
 * 获取相机所有配置参数（包含参数名、显示名、类型、当前值及可选值）
 * @returns 配置参数列表，每个元素为符合ConfigItem接口的对象
 */
export const GetCameraConfig: () => ConfigItem[];

/**
 * 获取所有可用相机列表
 * @returns 可用相机列表，每个元素为"型号|路径"格式的字符串
 */
export const GetAvailableCameras: () => string[];


/**
 * 获取相机的状态信息（电量、参数、存储等）
 * @returns 相机状态信息对象（CameraStatus），包含各类属性
 */
export const GetCameraStatus: () => CameraStatus;

/**
 * 设置 gphoto2 插件目录（相机驱动和端口驱动）
 * @param camlibDir 相机驱动目录
 * @param iolibDir 端口驱动目录
 * @returns 设置成功返回 true
 */
export const SetGPhotoLibDirs: (camlibDir: string) => boolean;


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
export const GetPreview: () => ArrayBuffer;

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


export const IsCameraConnected: () => boolean


/**
 * 获取指定相机参数的可选值列表（从配置树缓存中读取，避免重复通信）
 * @param paramName 参数名（需与相机配置树中的节点名一致，如"f-number"=光圈、"shutterspeed"=快门、"iso"=ISO）
 * @returns 参数的可选值列表（如光圈返回["f/2.8", "f/4", "f/5.6"]，无可选值或参数不存在时返回空数组）
 */
export const GetParamOptions: (paramName: string) => string[];


export const RegisterParamCallback: () => null;