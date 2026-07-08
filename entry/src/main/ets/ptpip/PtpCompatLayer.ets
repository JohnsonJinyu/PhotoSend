/**
 * PTP/IP 兼容层 - 模拟原有 libentry.so 的 API
 * 目的是无需修改原有 UI 代码，只需替换 import 即可
 */

import { CameraUtils } from '../../utils/CameraUtils';
import type { PhotoMeta } from '../PtpTypes';

const TAG = 'PtpCompatLayer';
const DOMAIN = 0x00501;

/**
 * 扫描进度信息
 */
export interface ScanProgressInfo {
  scanning: boolean;
  current: number;
  total: number;
  cached: boolean;
}

/**
 * 模拟 nativeCamera 模块的 API
 */
class PtpNativeCamera {
  private static instance: PtpNativeCamera | null = null;
  
  // 内部状态
  private scanProgress: ScanProgressInfo = {
    scanning: false,
    current: 0,
    total: 0,
    cached: false
  };
  
  private scanTimer: number = 0;
  private cachedPhotoMetas: PhotoMeta[] = [];

  private constructor() {}

  static getInstance(): PtpNativeCamera {
    if (!this.instance) {
      this.instance = new PtpNativeCamera();
    }
    return this.instance;
  }

  /**
   * 启动异步扫描
   */
  async StartAsyncScan(): Promise<boolean> {
    try {
      console.info(TAG, '开始异步扫描');
      
      this.scanProgress.scanning = true;
      this.scanProgress.current = 0;
      this.scanProgress.total = 0;
      this.scanProgress.cached = false;
      
      // 启动扫描
      const started = await CameraUtils.startAsyncScan();
      
      if (started) {
        // 启动定时器检查进度
        this.startProgressCheck();
        return true;
      }
      
      return false;
    } catch (error) {
      console.error(TAG, `启动异步扫描失败：${JSON.stringify(error)}`);
      return false;
    }
  }

  /**
   * 启动进度检查定时器
   */
  private startProgressCheck(): void {
    if (this.scanTimer > 0) {
      clearInterval(this.scanTimer);
    }

    this.scanTimer = setInterval(() => {
      const count = CameraUtils.getPhotoTotalCount();
      
      if (count > 0) {
        // 扫描完成
        this.scanProgress.scanning = false;
        this.scanProgress.total = count;
        this.scanProgress.current = count;
        this.scanProgress.cached = true;
        
        // 缓存照片元数据
        this.cachedPhotoMetas = CameraUtils.getPhotoMetaList(0, count);
        
        clearInterval(this.scanTimer);
        this.scanTimer = 0;
        
        console.info(TAG, `扫描完成，共${count}张照片`);
      } else {
        // 还在扫描中
        this.scanProgress.current = Math.floor(Math.random() * 100); // 模拟进度
        console.debug(TAG, `扫描中... ${this.scanProgress.current}`);
      }
    }, 500);
  }

  /**
   * 获取扫描进度
   */
  GetScanProgress(): ScanProgressInfo {
    return this.scanProgress;
  }

  /**
   * 获取照片总数
   */
  GetPhotoTotalCount(): number {
    return CameraUtils.getPhotoTotalCount();
  }

  /**
   * 分页获取照片元信息
   */
  GetPhotoMetaList(pageIndex: number, pageSize: number): PhotoMeta[] {
    try {
      const photos = CameraUtils.getPhotoMetaList(pageIndex, pageSize);
      console.info(TAG, `获取第${pageIndex + 1}页，共${photos.length}张`);
      return photos;
    } catch (error) {
      console.error(TAG, `获取照片列表失败：${JSON.stringify(error)}`);
      return [];
    }
  }

  /**
   * 下载单张缩略图（回调方式）
   */
  DownloadSingleThumbnail(
    folder: string, 
    filename: string, 
    callback: (err: string | null, buffer: ArrayBuffer) => void
  ): void {
    try {
      // 根据 folder 和 filename 查找对应的 objectId
      const photoMeta = this.cachedPhotoMetas.find(
        p => p.filename === filename
      );
      
      if (!photoMeta) {
        callback(`未找到照片：${filename}`, new ArrayBuffer(0));
        return;
      }

      // 下载缩略图
      CameraUtils.getThumbnail(photoMeta.objectId)
        .then(thumbData => {
          if (thumbData) {
            callback(null, thumbData);
          } else {
            callback('缩略图数据为空', new ArrayBuffer(0));
          }
        })
        .catch(error => {
          callback(`下载失败：${JSON.stringify(error)}`, new ArrayBuffer(0));
        });
    } catch (error) {
      callback(`异常：${JSON.stringify(error)}`, new ArrayBuffer(0));
    }
  }

  /**
   * 下载照片（简化版，后续完善）
   */
  async DownloadPhoto(
    folder: string,
    filename: string,
    savePath: string
  ): Promise<boolean> {
    try {
      // 根据 folder 和 filename 查找对应的 objectId
      const photoMeta = this.cachedPhotoMetas.find(
        p => p.filename === filename
      );
      
      if (!photoMeta) {
        console.error(TAG, `未找到照片：${filename}`);
        return false;
      }

      // 下载照片
      const success = await CameraUtils.downloadPhoto(
        photoMeta.objectId,
        savePath
      );
      
      return success;
    } catch (error) {
      console.error(TAG, `下载照片失败：${JSON.stringify(error)}`);
      return false;
    }
  }

  /**
   * 清除缓存
   */
  ClearPhotoCache(): void {
    CameraUtils.clearCache();
    this.cachedPhotoMetas = [];
    this.scanProgress = {
      scanning: false,
      current: 0,
      total: 0,
      cached: false
    };
    console.info(TAG, '缓存已清除');
  }
}

// 导出单例实例（模拟 import entry from 'libentry.so'）
export const nativeCamera = PtpNativeCamera.getInstance();

// 导出类型定义
export type { ScanProgressInfo, PhotoMeta };
