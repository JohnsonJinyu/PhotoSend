/**
 * 相机设备管理工具类
 * 提供相机扫描、连接等便捷功能
 */

import { ptpClient, PtpClient } from '../ptpip/PtpClient';
import type { PhotoMeta } from '../ptpip/PtpTypes';

const TAG = 'CameraUtils';
const DOMAIN = 0x00303;

/**
 * 相机设备信息
 */
export interface CameraDeviceInfo {
  displayName: string;
  ipAddress: string;
  port: number;
  connectionType: 'WiFi-AP' | 'USB' | 'Unknown';
}

/**
 * 相机工具类 - 单例模式
 */
class CameraUtilsClass {
  private connectedCamera: string | null = null;
  
  /**
   * 扫描可用的相机（简化版：仅支持 WiFi 连接）
   * 实际项目中可以结合 mDNS/SSDP 等发现协议
   */
  async scanAvailableCameras(): Promise<CameraDeviceInfo[]> {
    console.info(TAG, '开始扫描可用相机');
    
    const cameras: CameraDeviceInfo[] = [];
    
    // 简化实现：返回预定义的尼康相机列表
    // 实际应该通过 mDNS 或用户手动输入 IP 来发现
    
    // 示例：假设相机 IP 为 192.168.1.1
    cameras.push({
      displayName: 'Nikon Zf (WiFi)',
      ipAddress: '192.168.1.1',
      port: 15740,
      connectionType: 'WiFi-AP'
    });
    
    console.info(TAG, `扫描到 ${cameras.length} 台相机`);
    return cameras;
  }

  /**
   * 连接相机
   * @param ip 相机 IP地址
   * @param port 端口号
   */
  async connectCamera(ip: string, port: number = 15740): Promise<boolean> {
    try {
      console.info(TAG, `【PTP/IP】CameraUtils - 开始连接相机：${ip}:${port}`);
      console.info(TAG, `【PTP/IP】使用纯 ArkTS 的 PTP/IP 协议，端口 ${port}`);
      
      const result = await ptpClient.connect(ip, port);
      
      if (result) {
        this.connectedCamera = ip;
        console.info(TAG, `✅ 【PTP/IP】CameraUtils - 相机连接成功：${ip}`);
        console.info(TAG, `【PTP/IP】准备启动异步扫描...`);
        
        // 启动异步扫描
        await ptpClient.startAsyncScan();
        console.info(TAG, `【PTP/IP】异步扫描已启动`);
      } else {
        console.error(TAG, `❌ 【PTP/IP】CameraUtils - 相机连接失败：${ptpClient.getLastConnectionFailureReason() || '未提供详细原因'}`);
      }
      
      return result;
    } catch (error) {
      console.error(TAG, `❌ 【PTP/IP】CameraUtils - 连接异常：${JSON.stringify(error)}`);
      return false;
    }
  }

  /**
   * 断开相机连接
   */
  async disconnectCamera(): Promise<void> {
    try {
      console.info(TAG, '【PTP/IP】CameraUtils - 断开相机连接');
      await ptpClient.disconnect();
      this.connectedCamera = null;
      console.info(TAG, '✅ 【PTP/IP】CameraUtils - 已断开连接');
    } catch (error) {
      console.error(TAG, `❌ 【PTP/IP】CameraUtils - 断开连接异常：${JSON.stringify(error)}`);
    }
  }

  /**
   * 检查是否已连接相机
   */
  isCameraConnected(): boolean {
    return this.connectedCamera !== null && ptpClient.checkConnection();
  }

  /**
   * 获取当前连接的相机 IP
   */
  getConnectedCameraIp(): string | null {
    return this.connectedCamera;
  }

  getLastConnectionFailureReason(): string {
    return ptpClient.getLastConnectionFailureReason();
  }

  /**
   * 快速连接测试（Ping 相机）
   */
  async quickConnectionTest(ip: string, port: number = 15740): Promise<boolean> {
    try {
      console.info(TAG, `快速连接测试：${ip}:${port}`);
      
      // 创建临时连接测试
      const tempClient = new PtpClient();
      const result = await tempClient.connect(ip, port);
      
      if (result) {
        await tempClient.disconnect();
        console.info(TAG, '连接测试成功');
        return true;
      }
      
      return false;
    } catch (error) {
      console.error(TAG, `连接测试失败：${JSON.stringify(error)}`);
      return false;
    }
  }

  /**
   * 获取照片总数
   */
  getPhotoTotalCount(): number {
    return ptpClient.getPhotoTotalCount();
  }

  /**
   * 分页获取照片元信息
   */
  getPhotoMetaList(pageIndex: number, pageSize: number): PhotoMeta[] {
    return ptpClient.getPhotoMetaList(pageIndex, pageSize);
  }

  /**
   * 下载照片
   * @param objectId 对象 ID
   * @param savePath 保存路径
   */
  async downloadPhoto(objectId: number, savePath: string): Promise<boolean> {
    return await ptpClient.downloadPhoto(objectId, savePath);
  }

  /**
   * 获取缩略图
   * @param objectId 对象 ID
   */
  async getThumbnail(objectId: number): Promise<ArrayBuffer | null> {
    return await ptpClient.getThumbnail(objectId);
  }

  /**
   * 清除缓存
   */
  clearCache(): void {
    ptpClient.clearCache();
  }
}

// 导出单例
export const CameraUtils = new CameraUtilsClass();
