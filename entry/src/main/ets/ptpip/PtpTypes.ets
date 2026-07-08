/**
 * PTP/IP 协议数据结构定义
 */

import { PtpDataType, PtpObjectFormatCode } from './PtpConstants';

/**
 * PTP 设备信息结构
 */
export interface PtpDeviceInfo {
  standardVersion: number;
  vendorExtensionId: number;
  vendorExtensionVersion: number;
  vendorExtensionDesc: string;
  functionalMode: number;
  operationsSupported: number[];
  eventsSupported: number[];
  devicePropertiesSupported: number[];
  captureFormats: number[];
  imageFormats: number[];
  manufacturer: string;
  model: string;
  deviceVersion: string;
  serialNumber: string;
}

/**
 * PTP 存储 ID
 */
export interface PtpStorageId {
  storageId: number;
}

/**
 * PTP 存储信息结构
 */
export interface PtpStorageInfo {
  storageType: number;
  filesystemType: number;
  accessCapability: number;
  maxCapacity: number;
  freeSpaceInBytes: number;
  freeSpaceInImages: number;
  storageDescription: string;
  volumeLabel: string;
}

/**
 * PTP 对象句柄（照片 ID）
 */
export interface PtpObjectHandle {
  handle: number;
}

/**
 * PTP 对象信息结构（照片元数据）
 */
export interface PtpObjectInfo {
  storageId: number;
  objectFormatCode: number;
  protectionStatus: number;
  objectCompressedSize: number;
  thumbFormatCode: number;
  thumbCompressedSize: number;
  thumbPixWidth: number;
  thumbPixHeight: number;
  imagePixWidth: number;
  imagePixHeight: number;
  imageBitDepth: number;
  parentObject: number;
  associationType: number;
  associationDesc: number;
  sequenceNumber: number;
  filename: string;
  dateTimeCreated: string;
  dateTimeModified: string;
  keywords: string;
}

/**
 * PTP 对象数据（照片二进制数据）
 */
export interface PtpObjectData {
  data: ArrayBuffer;
  length: number;
}

/**
 * PTP 缩略图数据
 */
export interface PtpThumbnailData {
  data: ArrayBuffer;
  format: number;
  size: number;
}

/**
 * PTP 设备属性描述
 */
export interface PtpDevicePropDesc {
  devicePropertyCode: number;
  dataType: number;
  getSet: number;
  factoryDefaultValue: number | string;
  currentValue: number | string;
  formFlag: number;
  form: number | string;
}

/**
 * PTP 事件结构
 */
export interface PtpEvent {
  code: number;
  transactionId: number;
  parameter1: number;
  parameter2: number;
  parameter3: number;
}

/**
 * 照片元数据（应用层使用）
 */
export interface PhotoMeta {
  objectId: number;        // PTP 对象 ID
  storageId: number;       // 存储 ID
  filename: string;        // 文件名
  fileSize: number;        // 文件大小（字节）
  width: number;           // 宽度（像素）
  height: number;          // 高度（像素）
  format: number;          // 格式代码
  dateTime: string;        // 拍摄时间
  thumbAvailable: boolean; // 是否有缩略图
}

/**
 * 下载进度数据
 */
export interface DownloadProgressData {
  fileName: string;
  currentProgress: number;  // 0.0 - 1.0
  totalSize: number;
  downloadedSize: number;
}
