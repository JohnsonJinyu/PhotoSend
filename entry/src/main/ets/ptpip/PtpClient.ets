/**
 * PTP 客户端 - 高层 API 封装
 * 提供照片浏览、下载等高级功能
 */

import { ptpConnectionManager, ConnectionState } from './PtpConnectionManager';
import { 
  PtpOperationCode, 
  PtpResponseCode, 
  PtpObjectFormatCode,
  SUPPORTED_PHOTO_EXTENSIONS 
} from './PtpConstants';
import type { PhotoMeta, PtpObjectInfo, DownloadProgressData } from './PtpTypes';
import fs from '@ohos.file.fs';

const TAG = 'PtpClient';
const DOMAIN = 0x00302;

/**
 * PTP 客户端类
 */
export class PtpClient {
  private isConnected: boolean = false;
  private storageIds: number[] = [];
  private cachedPhotoMetas: PhotoMeta[] = [];
  private scanProgressCurrent: number = 0;
  private scanProgressTotal: number = 0;
  private isScanning: boolean = false;
  private lastConnectionFailureReason: string = '';

  // 回调函数
  private onScanProgressCallback?: (current: number, total: number) => void;
  private onDownloadProgressCallback?: (progress: DownloadProgressData) => void;

  /**
   * 连接相机
   * @param ip 相机 IP地址
   * @param port 端口号（默认 15740）
   */
  async connect(ip: string, port: number = 15740): Promise<boolean> {
    try {
      console.info(TAG, `==========================================`);
      console.info(TAG, `【PtpClient】开始连接相机：${ip}:${port}`);
      console.info(TAG, `【PtpClient】使用 PTP/IP 协议 (CIPA DC-X005-2005)`);
      console.info(TAG, `==========================================`);
      this.lastConnectionFailureReason = '';

      // 建立 TCP 连接
      console.info(TAG, `【PtpClient】步骤 1: 建立 TCP Socket 连接...`);
      const connected = await ptpConnectionManager.connect(ip, port);
      
      console.info(TAG, `【PtpClient】connect() 返回，结果：${connected ? '成功' : '失败'}`);
      
      if (!connected) {
        this.lastConnectionFailureReason = ptpConnectionManager.getLastFailureReason() || '无法连接到相机端口 15740';
        console.error(TAG, `❌ 【PtpClient】TCP 连接失败：${this.lastConnectionFailureReason}`);
        return false;
      }
      console.info(TAG, `✅ 【PtpClient】TCP 连接成功：${ip}:${port}`);
      
      // 打开 PTP 会话
      console.info(TAG, `【PtpClient】步骤 2: 打开 PTP 会话...`);
      
      // PTP Session ID 由客户端自行选择，首次会话固定使用 1
      // Init_Command_Ack 返回的是连接级编号，不应直接复用于 OpenSession
      const sessionId = 1;
      console.info(TAG, `【PtpClient】准备调用 openSession(${sessionId})，握手 Connection Number=${ptpConnectionManager.getConnectionNumber()}...`);
      const sessionOpened = await ptpConnectionManager.openSession(sessionId);
      console.info(TAG, `【PtpClient】openSession 返回，结果：${sessionOpened ? '成功' : '失败'}`);
      
      if (!sessionOpened) {
        this.lastConnectionFailureReason = ptpConnectionManager.getLastFailureReason() || '相机已接受连接，但 PTP 会话打开失败';
        console.error(TAG, `❌ 【PtpClient】PTP 会话打开失败：${this.lastConnectionFailureReason}`);
        await ptpConnectionManager.disconnect();
        return false;
      }
      console.info(TAG, `✅ 【PtpClient】PTP 会话已打开 (ID=${sessionId})`);
      
      this.isConnected = true;
      this.lastConnectionFailureReason = '';
      console.info(TAG, `✅ 【PtpClient】相机连接成功！`);
      
      // 获取存储 ID 列表
      console.info(TAG, `【PtpClient】步骤 3: 获取存储 ID 列表...`);
      await this.getStorageIds();
      
      console.info(TAG, `==========================================`);
      console.info(TAG, `【PtpClient】连接流程完成，准备扫描照片`);
      console.info(TAG, `==========================================`);
      
      return true;
    } catch (error) {
      this.lastConnectionFailureReason = ptpConnectionManager.getLastFailureReason() || '连接过程中发生未分类异常';
      console.error(TAG, `❌ 【PtpClient】连接异常：${JSON.stringify(error)}`);
      return false;
    }
  }

  getLastConnectionFailureReason(): string {
    return this.lastConnectionFailureReason;
  }

  /**
   * 断开连接
   */
  async disconnect(): Promise<void> {
    try {
      console.info(TAG, `【PtpClient】断开相机连接`);
      this.isConnected = false;
      this.storageIds = [];
      this.cachedPhotoMetas = [];
      await ptpConnectionManager.disconnect();
      console.info(TAG, `✅ 【PtpClient】已断开连接`);
    } catch (error) {
      console.error(TAG, `❌ 【PtpClient】断开连接异常：${JSON.stringify(error)}`);
    }
  }

  /**
   * 获取存储 ID 列表
   */
  private async getStorageIds(): Promise<void> {
    try {
      const response = await ptpConnectionManager.sendCommand(PtpOperationCode.GetStorageIDs, []);
      
      if (response.code !== PtpResponseCode.OK) {
        console.error(TAG, `获取存储 ID 失败：${response.code}`);
        return;
      }
      
      // TODO: 解析响应中的存储 ID 数组
      // 这里简化处理，实际需要根据 PTP 协议格式解析
      
      console.info(TAG, `获取到 ${this.storageIds.length} 个存储`);
    } catch (error) {
      console.error(TAG, `获取存储 ID 异常：${JSON.stringify(error)}`);
    }
  }

  /**
   * 异步扫描照片
   */
  async startAsyncScan(): Promise<boolean> {
    if (!this.isConnected) {
      console.error(TAG, '未连接相机');
      return false;
    }
    
    if (this.isScanning) {
      console.warn(TAG, '正在扫描中');
      return false;
    }
    
    this.isScanning = true;
    this.scanProgressCurrent = 0;
    this.scanProgressTotal = 0;
    
    // 在后台线程执行扫描
    this.performScan();
    
    return true;
  }

  /**
   * 执行扫描（内部方法）
   */
  private async performScan(): Promise<void> {
    try {
      console.info(TAG, '开始扫描照片');
      
      const photoHandles: number[] = [];
      
      // 遍历所有存储
      for (const storageId of this.storageIds) {
        try {
          // 获取对象句柄
          const handles = await this.getObjectHandles(storageId);
          photoHandles.push(...handles);
        } catch (error) {
          console.error(TAG, `获取存储 ${storageId} 的对象失败：${JSON.stringify(error)}`);
        }
      }
      
      this.scanProgressTotal = photoHandles.length;
      console.info(TAG, `找到 ${photoHandles.length} 个对象`);
      
      // 获取每个对象的元信息
      const photoMetas: PhotoMeta[] = [];
      
      for (let i = 0; i < photoHandles.length; i++) {
        const handle = photoHandles[i];
        
        try {
          // 获取对象信息
          const objectInfo = await this.getObjectInfo(handle);
          
          if (objectInfo && this.isPhotoFile(objectInfo.filename)) {
            const meta: PhotoMeta = {
              objectId: handle,
              storageId: objectInfo.storageId,
              filename: objectInfo.filename,
              fileSize: objectInfo.objectCompressedSize,
              width: objectInfo.imagePixWidth,
              height: objectInfo.imagePixHeight,
              format: objectInfo.objectFormatCode,
              dateTime: objectInfo.dateTimeCreated,
              thumbAvailable: objectInfo.thumbCompressedSize > 0
            };
            
            photoMetas.push(meta);
          }
        } catch (error) {
          console.error(TAG, `获取对象 ${handle} 信息失败：${JSON.stringify(error)}`);
        }
        
        // 更新进度
        this.scanProgressCurrent = i + 1;
        if (this.onScanProgressCallback) {
          this.onScanProgressCallback(this.scanProgressCurrent, this.scanProgressTotal);
        }
        
        // 每 100 个对象记录一次日志
        if (i % 100 === 0 || i === photoHandles.length - 1) {
          console.info(TAG, `扫描进度：${i + 1}/${photoHandles.length}`);
        }
      }
      
      // 缓存结果
      this.cachedPhotoMetas = photoMetas;
      this.isScanning = false;
      
      console.info(TAG, `扫描完成，共 ${photoMetas.length} 张照片`);
    } catch (error) {
      console.error(TAG, `扫描异常：${JSON.stringify(error)}`);
      this.isScanning = false;
    }
  }

  /**
   * 获取对象句柄列表
   */
  private async getObjectHandles(storageId: number): Promise<number[]> {
    const response = await ptpConnectionManager.sendCommand(
      PtpOperationCode.GetObjectHandles, 
      [storageId, 0, 0]  // 0xFFFFFFFF, 0x00000000 = 所有对象
    );
    
    if (response.code !== PtpResponseCode.OK) {
      throw new Error(`GetObjectHandles 失败：${response.code}`);
    }
    
    // TODO: 解析响应中的句柄数组
    // 简化实现，返回空数组
    return [];
  }

  /**
   * 获取对象信息
   */
  private async getObjectInfo(handle: number): Promise<PtpObjectInfo | null> {
    const response = await ptpConnectionManager.sendCommand(
      PtpOperationCode.GetObjectInfo,
      [handle]
    );
    
    if (response.code !== PtpResponseCode.OK) {
      throw new Error(`GetObjectInfo 失败：${response.code}`);
    }
    
    // TODO: 解析对象信息
    // 简化实现，返回 null
    return null;
  }

  /**
   * 判断是否为照片文件
   */
  private isPhotoFile(filename: string): boolean {
    const lowerFilename = filename.toLowerCase();
    return SUPPORTED_PHOTO_EXTENSIONS.some(ext => lowerFilename.endsWith(ext));
  }

  /**
   * 获取照片总数
   */
  getPhotoTotalCount(): number {
    return this.cachedPhotoMetas.length;
  }

  /**
   * 分页获取照片元信息
   * @param pageIndex 页码（从 0 开始）
   * @param pageSize 每页大小
   */
  getPhotoMetaList(pageIndex: number, pageSize: number): PhotoMeta[] {
    const startIndex = pageIndex * pageSize;
    const endIndex = Math.min(startIndex + pageSize, this.cachedPhotoMetas.length);
    
    if (startIndex >= this.cachedPhotoMetas.length) {
      return [];
    }
    
    return this.cachedPhotoMetas.slice(startIndex, endIndex);
  }

  /**
   * 下载照片
   * @param objectId 对象 ID
   * @param savePath 保存路径
   */
  async downloadPhoto(objectId: number, savePath: string): Promise<boolean> {
    if (!this.isConnected) {
      console.error(TAG, '未连接相机');
      return false;
    }
    
    try {
      console.info(TAG, `开始下载照片：objectId=${objectId}, savePath=${savePath}`);
      
      // 1. 发送 GetObject 命令
      const response = await ptpConnectionManager.sendCommand(
        PtpOperationCode.GetObject,
        [objectId]
      );
      
      if (response.code !== PtpResponseCode.OK) {
        console.error(TAG, `GetObject 命令失败：${response.code}`);
        return false;
      }
      
      // 2. 读取照片数据（DataBlock 流式传输）
      const photoData = await ptpConnectionManager.readDataPacket();
      
      if (!photoData || photoData.byteLength === 0) {
        console.error(TAG, '照片数据为空');
        return false;
      }
      
      console.info(TAG, `收到照片数据：${photoData.byteLength} bytes`);
      
      // 3. 验证 JPEG 格式
      const uint8Data = new Uint8Array(photoData);
      if (uint8Data.length < 2 || uint8Data[0] !== 0xFF || uint8Data[1] !== 0xD8) {
        console.error(TAG, '不是有效的 JPEG 数据');
        return false;
      }
      
      // 4. 保存到文件
      try {
        // 使用 fileIo 保存文件
        const saveSuccess = await this.saveToFile(savePath, photoData);
        if (!saveSuccess) {
          console.error(TAG, '保存文件失败');
          return false;
        }
        
        console.info(TAG, `下载完成：${savePath}, ${photoData.byteLength} bytes`);
        
        // 5. 调用进度回调（如果有）
        if (this.onDownloadProgressCallback) {
          this.onDownloadProgressCallback({
            fileName: savePath.split('/').pop() || '',
            currentProgress: 1.0,
            totalSize: photoData.byteLength,
            downloadedSize: photoData.byteLength
          });
        }
        
        return true;
      } catch (ioError) {
        console.error(TAG, `文件 IO 错误：${JSON.stringify(ioError)}`);
        return false;
      }
    } catch (error) {
      console.error(TAG, `下载异常：${JSON.stringify(error)}`);
      return false;
    }
  }

  /**
   * 获取缩略图
   * @param objectId 对象 ID
   */
  async getThumbnail(objectId: number): Promise<ArrayBuffer | null> {
    if (!this.isConnected) {
      console.error(TAG, '未连接相机');
      return null;
    }
    
    try {
      console.info(TAG, `获取缩略图：objectId=${objectId}`);
      
      // 发送 GetThumb 命令
      const response = await ptpConnectionManager.sendCommand(
        PtpOperationCode.GetThumb,
        [objectId]
      );
      
      if (response.code !== PtpResponseCode.OK) {
        console.error(TAG, `获取缩略图失败：${response.code}`);
        return null;
      }
      
      // TODO: 读取缩略图数据
      return null;
    } catch (error) {
      console.error(TAG, `获取缩略图异常：${JSON.stringify(error)}`);
      return null;
    }
  }

  /**
   * 设置扫描进度回调
   */
  setOnScanProgress(callback: (current: number, total: number) => void): void {
    this.onScanProgressCallback = callback;
  }

  /**
   * 设置下载进度回调
   */
  setOnDownloadProgress(callback: (progress: DownloadProgressData) => void): void {
    this.onDownloadProgressCallback = callback;
  }

  /**
   * 保存文件到本地
   */
  private async saveToFile(filePath: string, data: ArrayBuffer): Promise<boolean> {
    try {
      const file = fs.openSync(filePath, 0o1400); // 0o1400 = O_WRONLY | O_CREAT
      
      if (!file.fd) {
        return false;
      }
      
      fs.writeSync(file.fd, data);
      fs.closeSync(file);
      
      return true;
    } catch {
      console.error(TAG, `保存文件失败`);
      return false;
    }
  }

  /**
   * 检查是否已连接
   */
  checkConnection(): boolean {
    return this.isConnected && ptpConnectionManager.isConnected();
  }

  /**
   * 清除缓存
   */
  clearCache(): void {
    this.cachedPhotoMetas = [];
    this.scanProgressCurrent = 0;
    this.scanProgressTotal = 0;
  }
}

// 导出单例实例
export const ptpClient = new PtpClient();
