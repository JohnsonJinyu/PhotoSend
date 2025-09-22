/**
 * 相机状态管理类 - 负责管理所有相机相关的状态数据
 * 使用@Tracked装饰器实现状态与UI的自动绑定
 */
export class CameraStateManager {
  // 连接状态：@Tracked装饰器标记该状态变化时会触发UI更新
  @Track isConnected: boolean = false;

  // 相机信息对象：存储当前连接的相机详细信息
  @Track cameraInfo: CameraInfo | null = null;

  // 当前连接模式：蓝牙/WiFi-AP/WiFi-STA
  @Track connectionMode: ConnectionMode = 'WiFi-AP';

  /**
   * 更新连接状态方法
   * @param status 新的连接状态（true=已连接，false=未连接）
   */
  updateConnectionStatus(status: boolean): void {
    // 更新状态时会自动触发依赖该状态的UI组件重新渲染
    this.isConnected = status;
  }
}