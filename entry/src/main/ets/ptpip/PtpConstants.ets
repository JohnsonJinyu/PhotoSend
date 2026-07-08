/**
 * PTP/IP 协议常量定义
 * 基于 CIPA DC-X005-2005 标准和 gPhoto2 PTP/IP 文档
 */

// ======================== PTP 操作码 (Operation Codes) ========================
export enum PtpOperationCode {
  // 通用命令
  GetDeviceInfo = 0x1001,
  OpenSession = 0x1002,
  CloseSession = 0x1003,
  GetStorageIDs = 0x1004,
  GetStorageInfo = 0x1005,
  GetNumObjects = 0x1006,
  GetObjectHandles = 0x1007,
  GetObjectInfo = 0x1008,
  GetObject = 0x1009,
  GetThumb = 0x100A,
  DeleteObject = 0x100B,
  SendObjectInfo = 0x100C,
  SendObject = 0x100D,
  
  // 尼康扩展命令
  Nikon_GetPreview = 0x90C2,
  Nikon_StartLiveView = 0x90C3,
  Nikon_EndLiveView = 0x90C4,
  Nikon_GetDevicePropDesc = 0x90C5,
  Nikon_GetDevicePropValue = 0x90C6,
  Nikon_SetDevicePropValue = 0x90C7,
}

// ======================== PTP 响应码 (Response Codes) ========================
export enum PtpResponseCode {
  Undefined = 0x2000,
  OK = 0x2001,
  GeneralError = 0x2002,
  SessionNotOpen = 0x2003,
  InvalidTransactionID = 0x2004,
  IncompleteTransfer = 0x2005,
  InvalidStorageId = 0x2006,
  InvalidObjectHandle = 0x2007,
  DevicePropNotSupported = 0x2008,
  InvalidObjectFormatCode = 0x2009,
  ObjectWriteProtected = 0x200A,
  StorageReadOnly = 0x200B,
  AccessDenied = 0x200C,
  NoThumbnailPresent = 0x200D,
  SelfTestFailed = 0x2011,
  PartialDeletion = 0x2012,
  StoreNotAvailable = 0x2013,
  SpecificationByFormatUnsupported = 0x2014,
  NoValidObjectInfo = 0x2015,
  InvalidCodeFormat = 0x2016,
  UnknownVendorCode = 0x2017,
  CaptureAlreadyTerminated = 0x2018,
  DeviceBusy = 0x2019,
  InvalidParentObject = 0x201A,
  InvalidDevicePropFormat = 0x201B,
  InvalidDevicePropValue = 0x201C,
  InvalidParameter = 0x201D,
  SessionAlreadyOpened = 0x201E,
  TransactionCancelled = 0x201F,
}

// ======================== PTP 对象格式代码 (Object Format Codes) ========================
export enum PtpObjectFormatCode {
  Undefined = 0x3000,
  Association = 0x3001,  // 文件夹/目录
  Script = 0x3002,
  Executable = 0x3003,
  Text = 0x3004,
  HTML = 0x3005,
  DPOF = 0x3006,
  AIFF = 0x3007,
  WAV = 0x3008,
  MP3 = 0x3009,
  AVI = 0x300A,
  MPEG = 0x300B,
  ASF = 0x300C,
  QT = 0x300D,
  
  // 图像格式
  EXIF_JPEG = 0x3801,
  TIFF_EP = 0x3802,
  FlashPix = 0x3803,
  BMP = 0x3804,
  CIFF = 0x3805,
  GIF = 0x3807,
  JFIF = 0x3808,
  PCD = 0x3809,
  PICT = 0x380A,
  PNG = 0x380B,
  TIFF = 0x380D,
  TIFF_IT = 0x380E,
  JP2 = 0x380F,
  JPEG2000 = 0x3810,
  
  // 尼康 RAW 格式
  Nikon_NEF = 0xB101,
  Nikon_NRW = 0xB102,
}

// ======================== PTP 存储类型 (Storage Types) ========================
export enum PtpStorageType {
  FixedROM = 0x0001,
  RemovableROM = 0x0002,
  FixedRAM = 0x0003,
  RemovableRAM = 0x0004,
}

// ======================== PTP 文件系统类型 (Filesystem Types) ========================
export enum PtpFilesystemType {
  GenericFlat = 0x0001,
  GenericHierarchical = 0x0002,
  DCF = 0x0003,  // Design rule for Camera File system
}

// ======================== PTP 访问保护类型 (Access Protection) ========================
export enum PtpAccessProtectionType {
  NoProtection = 0x0000,
  ReadOnly = 0x0001,
  ReadWrite = 0x0002,
}

// ======================== PTP 数据类型 (Data Types) ========================
export enum PtpDataType {
  UNDEF = 0x0000,
  INT8 = 0x0001,
  UINT8 = 0x0002,
  INT16 = 0x0003,
  UINT16 = 0x0004,
  INT32 = 0x0005,
  UINT32 = 0x0006,
  INT64 = 0x0007,
  UINT64 = 0x0008,
  INT128 = 0x0009,
  UINT128 = 0x000A,
  AINT8 = 0x4001,
  AUINT8 = 0x4002,
  AINT16 = 0x4003,
  AUINT16 = 0x4004,
  AINT32 = 0x4005,
  AUINT32 = 0x4006,
  AINT64 = 0x4007,
  AUINT64 = 0x4008,
  AINT128 = 0x4009,
  AUINT128 = 0x400A,
  STRING = 0xFFFF,
}

// ======================== PTP 设备属性代码 (Device Properties) ========================
export enum PtpDevicePropertyCode {
  Undefined = 0x5000,
  BatteryLevel = 0x5001,
  FunctionalMode = 0x5002,
  ImageSize = 0x5003,
  CompressionSetting = 0x5004,
  WhiteBalance = 0x5005,
  RGBGain = 0x5006,
  FNumber = 0x5007,
  FocalLength = 0x5008,
  FocusDistance = 0x5009,
  FocusMode = 0x500A,
  ExposureMeteringMode = 0x500B,
  FlashMode = 0x500C,
  ExposureTime = 0x500D,
  ExposureProgramMode = 0x500E,
  ExposureIndex = 0x500F,
  ExposureBiasCompensation = 0x5010,
  DateTime = 0x5011,
  CaptureDelay = 0x5012,
  StillCaptureMode = 0x5013,
  Contrast = 0x5014,
  Sharpness = 0x5015,
  DigitalZoom = 0x5016,
  EffectMode = 0x5017,
  Orientation = 0x5018,
}

// ======================== PTP/IP 特定常量 ========================
export const PTP_IP_DEFAULT_PORT = 15740;
export const PTP_IP_COMMAND_PHASE = 1;
export const PTP_IP_DATA_PHASE = 2;
export const PTP_IP_RESPONSE_PHASE = 3;

// ======================== PTP/IP 包类型 ========================
export enum PtpIpPacketType {
  InitCommandRequest = 1,
  InitCommandAck = 2,
  InitEventRequest = 3,
  InitEventAck = 4,
  InitFail = 5,
  OperationRequest = 6,
  OperationResponse = 7,
  Event = 8,
  StartDataPacket = 9,
  DataPacket = 10,
  CancelTransaction = 11,
  EndDataPacket = 12,
}

// ======================== 尼康相机型号映射 ========================
export const NIKON_CAMERA_MODELS: Record<string, string> = {
  'Nikon Zf': 'Nikon Zf',
  'Nikon Z9': 'Nikon Z9',
  'Nikon Z8': 'Nikon Z8',
  'Nikon Z7II': 'Nikon Z7 II',
  'Nikon Z6II': 'Nikon Z6 II',
  'Nikon Z7': 'Nikon Z7',
  'Nikon Z6': 'Nikon Z6',
  'Nikon Z5': 'Nikon Z5',
  'Nikon Z50': 'Nikon Z50',
  'Nikon Zfc': 'Nikon Zfc',
};

// ======================== 照片文件扩展名过滤 ========================
export const SUPPORTED_PHOTO_EXTENSIONS = [
  '.jpg', '.jpeg', '.JPG', '.JPEG',
  '.nef', '.NEF',  // Nikon RAW
  '.nrw', '.NRW',  // Nikon RAW
  '.png', '.PNG',
];
