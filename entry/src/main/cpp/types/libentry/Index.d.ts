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
 * 照片元信息接口（用于懒加载优化）
 */
interface PhotoMeta {
  /** 照片在相机中的文件夹路径（如"/DCIM/100NIKON"） */
  folder: string;

  /** 照片文件名（如"DSC_0001.NEF"） */
  filename: string;

  /** 文件大小（单位：字节，可选） */
  size?: number;
}

/**
 * 回调函数接收的参数类型，包含参数的可选值
 */
interface ParamOptions {
  iso: string[];
  shutterspeed?: string[];
  // 这里可以根据实际情况添加其他可能的参数
}

/**
 * 缩略图信息接口，包含照片在相机中的路径、文件名及缩略图二进制数据
 */
interface ThumbnailInfo {
  /** 照片在相机中的文件夹路径（如"/DCIM/100NIKON"） */
  folder: string;

  /** 照片文件名（如"DSC_0001.NEF"） */
  filename: string;

  /** 缩略图二进制数据（ArrayBuffer格式） */
  thumbnail: ArrayBuffer;
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
 * @param tempFilePath 临时文件路径（沙箱路径）
 * @returns 照片的二进制数据（ArrayBuffer）
 */
export const DownloadPhoto: (folder: string, name: string, tempFilePath: string) => boolean;

/**
 * 断开与相机的连接
 * @returns 断开成功返回true
 */
export const Disconnect: () => boolean;

/**
 * 检查相机是否已连接
 * @returns 已连接返回true，否则返回false
 */
export const IsCameraConnected: () => boolean;

/**
 * 获取指定相机参数的可选值列表（从配置树缓存中读取，避免重复通信）
 * @param paramName 参数名（需与相机配置树中的节点名一致，如"f-number"=光圈、"shutterspeed"=快门、"iso"=ISO）
 * @returns 参数的可选值列表（如光圈返回["f/2.8", "f/4", "f/5.6"]，无可选值或参数不存在时返回空数组）
 */
export const GetParamOptions: (paramName: string) => string[];

/**
 * 注册参数回调函数
 * @param callback 回调函数，接收一个ParamOptions类型的参数
 */
export const RegisterParamCallback: (callback: (params: ParamOptions) => void) => void;


/**
 * 获取相机内照片的总数
 * @returns 照片总数（整数）
 * @description 此函数仅扫描相机中的照片文件并计数，不下载任何缩略图数据，因此速度很快。
 *              用于实现懒加载和分页功能。
 * @example
* const total = GetPhotoTotalCount();
 * console.log(`相机内共有 ${total} 张照片`);
 */
export const GetPhotoTotalCount: () => number;

/**
 * 分页获取照片元信息（不包含缩略图）
 * @param pageIndex 页码，从0开始
 * @param pageSize 每页大小
 * @returns 照片元信息列表（PhotoMeta数组）
 * @description 此函数返回指定页码的照片元信息（文件夹、文件名等），不包含缩略图数据。
 *              用于实现懒加载，先显示文件名，再按需加载缩略图。
 * @example
* const page1 = GetPhotoMetaList(0, 20); // 获取第1页，每页20张
 * const page2 = GetPhotoMetaList(1, 20); // 获取第2页，每页20张
 */
export const GetPhotoMetaList: (pageIndex: number, pageSize: number) => PhotoMeta[];

/**
 * 异步下载单张照片的缩略图
 * @param folder 照片所在文件夹路径
 * @param filename 照片文件名
 * @param callback 回调函数，用于接收异步结果
 *   - 第一个参数：错误信息（成功时为null，失败时为错误描述字符串）
 *   - 第二个参数：缩略图二进制数据（成功时为ArrayBuffer，失败时为null）
 * @description 此函数用于按需加载单张照片的缩略图，优化大量照片时的加载性能。
 *              建议在用户滚动到可见区域时调用此函数。
 * @example
* DownloadSingleThumbnail(
 *   "/DCIM/100NIKON",
 *   "DSC_0001.NEF",
 *   (err, buffer) => {
 *     if (err) {
 *       console.error("下载缩略图失败:", err);
 *     } else {
 *       console.log("缩略图数据:", buffer);
 *       // 将buffer转换为PixelMap显示
 *     }
 *   }
 * );
 */
export const DownloadSingleThumbnail: (
  folder: string,
  filename: string,
  callback: (err: string | null, buffer: ArrayBuffer | null) => void
) => void;

/**
 * 清理照片缓存
 * @description 清理已缓存的照片文件列表和元信息。
 *              在相机断开连接或需要重新扫描时调用此函数。
 * @returns void
 * @example
* ClearPhotoCache(); // 清理缓存，下次调用GetPhotoTotalCount会重新扫描
 */
export const ClearPhotoCache: () => void;



/**
 *  @description 获取Raw照片的方向
 * */
export const GetImageOrientationNapi: (filePath: string) => number;


/**
 *  @description 获取Raw照片的Exif信息
 * */
export const GetImageExifInfoNapi: (filePath: string) => {
  orientation: number;
  width: number;
  height: number;
  make: string;
  model: string;
};

/**
 * @description 获取RAW照片的EXIF方向
 * @param filePath RAW文件路径（如 .NEF）
 * @returns EXIF方向值 (1-8)，失败返回1
 */
export const GetRawImageOrientationNapi: (filePath: string) => number;

/**
 * @description 获取RAW照片的完整EXIF信息
 * @param filePath RAW文件路径（如 .NEF）
 * @returns EXIF信息对象
 */
export const GetRawImageExifInfoNapi: (filePath: string) => {
  orientation: number;
  width: number;
  height: number;
  make: string;
  model: string;
};