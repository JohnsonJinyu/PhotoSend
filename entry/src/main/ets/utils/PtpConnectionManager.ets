/**
 * PTP 相机连接管理器 - 增强版
 * 支持自动检测、手动连接、保持连接三种场景
 */

import { CameraUtils } from './CameraUtils';

const TAG = 'PtpConnectionManager';
const DOMAIN = 0x00601;

/**
 * 连接状态枚举
 */
export enum ConnectionStatus {
  DISCONNECTED = 'disconnected',
  CONNECTING = 'connecting',
  CONNECTED = 'connected',
  CONNECTION_FAILED = 'connection_failed'
}

/**
 * 连接状态结果
 */
export interface ConnectionStateResult {
  state: boolean;
  message: string;
  status?: ConnectionStatus;
}

/**
 * 监听器类型
 */
export type ConnectionListener = (state: boolean, message: string) => void;

/**
 * PTP 相机连接管理器类 - 单例模式
 */
class PtpConnectionManagerClass {
  private static instance: PtpConnectionManagerClass | null = null;
  
  // 连接状态
  private isConnected: boolean = false;
  private connectionStatus: ConnectionStatus = ConnectionStatus.DISCONNECTED;
  private stateMessage: string = '未连接相机';
  
  // 监听器列表
  private listeners: Set<ConnectionListener> = new Set();
  
  // 配置信息
  private defaultIp: string = '192.168.1.1';
  private defaultPort: number = 15740;
  private autoReconnect: boolean = true;
  private reconnectInterval: number = 3000;
  private reconnectTimer: number = 0;
  
  // 私有构造函数（单例模式）
  private constructor() {
    console.info(TAG, 'PTP 相机连接管理器初始化');
  }

  /**
   * 获取单例实例
   */
  static getInstance(): PtpConnectionManagerClass {
    if (!PtpConnectionManagerClass.instance) {
      PtpConnectionManagerClass.instance = new PtpConnectionManagerClass();
    }
    return PtpConnectionManagerClass.instance;
  }

  /**
   * 设置默认相机 IP 和端口
   */
  setDefaultCamera(ip: string, port: number = 15740): void {
    this.defaultIp = ip;
    this.defaultPort = port;
    console.info(TAG, `设置默认相机：${ip}:${port}`);
  }

  /**
   * 添加监听器
   */
  addListener(listener: ConnectionListener): void {
    this.listeners.add(listener);
    console.info(TAG, `添加监听器，当前监听器数量：${this.listeners.size}`);
    
    // 立即通知一次当前状态
    listener(this.isConnected, this.stateMessage);
  }

  /**
   * 移除监听器
   */
  removeListener(listener: ConnectionListener): void {
    this.listeners.delete(listener);
    console.info(TAG, `移除监听器，当前监听器数量：${this.listeners.size}`);
  }

  /**
   * 通知所有监听器
   */
  private notifyListeners(state: boolean, message: string): void {
    this.listeners.forEach(listener => {
      try {
        listener(state, message);
      } catch {
        console.error(TAG, `通知监听器失败`);
      }
    });
  }

  /**
   * 更新连接状态
   */
  private updateConnectionState(connected: boolean, message: string, status?: ConnectionStatus): void {
    this.isConnected = connected;
    this.stateMessage = message;
    
    if (status) {
      this.connectionStatus = status;
    }
    
    console.info(TAG, `连接状态更新：${connected ? '已连接' : '未连接'}, ${message}`);
    this.notifyListeners(connected, message);
  }

  /**
   * 场景 1: App 启动时自动检测连接
   */
  async autoDetectAndConnect(): Promise<ConnectionStateResult> {
    console.info(TAG, '==========================================');
    console.info(TAG, '【PTP/IP】App 启动 - 开始自动检测并连接相机');
    console.info(TAG, '==========================================');
    
    try {
      this.updateConnectionState(false, '正在检测相机...', ConnectionStatus.CONNECTING);
      
      const connected = await this.connectCamera(this.defaultIp, this.defaultPort);
      
      if (connected) {
        console.info(TAG, '✅【PTP/IP】自动检测成功！相机已连接');
        this.updateConnectionState(true, '相机已连接', ConnectionStatus.CONNECTED);
        return { state: true, message: '相机已连接', status: ConnectionStatus.CONNECTED };
      } else {
        const failureMessage = CameraUtils.getLastConnectionFailureReason() || '相机端口可达，但 PTP 会话未建立';
        console.warn(TAG, `⚠️【PTP/IP】自动检测失败：${failureMessage}`);
        this.updateConnectionState(false, failureMessage, ConnectionStatus.CONNECTION_FAILED);

        if (this.autoReconnect) {
          console.info(TAG, '【PTP/IP】启动自动重连机制...');
          this.startAutoReconnect();
        }
        
        return { state: false, message: failureMessage, status: ConnectionStatus.CONNECTION_FAILED };
      }
    } catch {
      const errMsg = `【PTP/IP】自动检测失败`;
      console.error(TAG, `❌ ${errMsg}`);
      this.updateConnectionState(false, errMsg, ConnectionStatus.CONNECTION_FAILED);
      return { state: false, message: errMsg, status: ConnectionStatus.CONNECTION_FAILED };
    }
  }

  /**
   * 场景 2: 用户手动点击连接按钮
   */
  async manualConnect(ip?: string, port?: number): Promise<ConnectionStateResult> {
    console.info(TAG, '==========================================');
    console.info(TAG, '【PTP/IP】用户手动连接相机');
    console.info(TAG, `目标：${ip || this.defaultIp}:${port || this.defaultPort}`);
    console.info(TAG, '==========================================');
    
    try {
      this.updateConnectionState(false, '正在连接相机...', ConnectionStatus.CONNECTING);
      
      this.stopAutoReconnect();
      
      const targetIp = ip || this.defaultIp;
      const targetPort = port || this.defaultPort;
      
      console.info(TAG, `【PTP/IP】尝试连接：${targetIp}:${targetPort}`);
      const connected = await this.connectCamera(targetIp, targetPort);
      
      if (connected) {
        console.info(TAG, '✅【PTP/IP】手动连接成功！相机已连接');
        this.updateConnectionState(true, '相机已连接', ConnectionStatus.CONNECTED);
        return { state: true, message: '相机已连接', status: ConnectionStatus.CONNECTED };
      } else {
        const errorMsg = CameraUtils.getLastConnectionFailureReason() || '相机已接受连接，但 PTP 会话未建立';
        console.error(TAG, `❌【PTP/IP】手动连接失败：${errorMsg}`);
        this.updateConnectionState(false, errorMsg, ConnectionStatus.CONNECTION_FAILED);
        return { state: false, message: errorMsg, status: ConnectionStatus.CONNECTION_FAILED };
      }
    } catch {
      const errMsg = `【PTP/IP】手动连接失败`;
      console.error(TAG, `❌ ${errMsg}`);
      this.updateConnectionState(false, errMsg, ConnectionStatus.CONNECTION_FAILED);
      return { state: false, message: errMsg, status: ConnectionStatus.CONNECTION_FAILED };
    }
  }

  /**
   * 场景 3: 检查现有连接
   */
  checkExistingConnection(): ConnectionStateResult {
    console.info(TAG, '检查现有连接状态');
    
    const exists = CameraUtils.isCameraConnected();
    
    if (exists) {
      this.isConnected = true;
      this.connectionStatus = ConnectionStatus.CONNECTED;
      this.stateMessage = '相机已连接';
      
      console.info(TAG, '发现已存在的连接');
      this.notifyListeners(true, '相机已连接');
      
      return { state: true, message: '相机已连接', status: ConnectionStatus.CONNECTED };
    } else {
      this.isConnected = false;
      this.connectionStatus = ConnectionStatus.DISCONNECTED;
      this.stateMessage = '未连接相机';
      
      console.info(TAG, '未发现已存在的连接');
      this.notifyListeners(false, '未连接相机');
      
      return { state: false, message: '未连接相机', status: ConnectionStatus.DISCONNECTED };
    }
  }

  /**
   * 连接相机的核心方法
   */
  private async connectCamera(ip: string, port: number): Promise<boolean> {
    try {
      console.info(TAG, `【PTP/IP】开始连接相机：${ip}:${port}`);
      console.info(TAG, `【PTP/IP】使用纯 ArkTS 实现，不依赖 libgphoto2`);
      
      const connected = await CameraUtils.connectCamera(ip, port);
      
      if (connected) {
        console.info(TAG, `✅【PTP/IP】相机连接成功！协议栈：PTP over IP/TCP`);
        return true;
      } else {
        console.error(TAG, `❌【PTP/IP】相机连接失败`);
        return false;
      }
    } catch {
      console.error(TAG, `❌【PTP/IP】连接异常`);
      return false;
    }
  }

  /**
   * 断开连接
   */
  async disconnect(): Promise<void> {
    console.info(TAG, '断开相机连接');
    
    this.stopAutoReconnect();
    
    try {
      await CameraUtils.disconnectCamera();
      
      this.isConnected = false;
      this.connectionStatus = ConnectionStatus.DISCONNECTED;
      this.stateMessage = '已断开连接';
      
      console.info(TAG, '相机已断开');
      this.notifyListeners(false, '已断开连接');
    } catch {
      console.error(TAG, `断开连接异常`);
    }
  }

  /**
   * 获取当前连接状态
   */
  getCurrentState(): ConnectionStateResult {
    return {
      state: this.isConnected,
      message: this.stateMessage,
      status: this.connectionStatus
    };
  }

  /**
   * 检查是否已连接
   */
  isCameraConnected(): boolean {
    return this.isConnected && CameraUtils.isCameraConnected();
  }

  /**
   * 启动自动重连
   */
  private startAutoReconnect(): void {
    if (!this.autoReconnect || this.reconnectTimer > 0) {
      return;
    }
    
    console.info(TAG, `启动自动重连，间隔：${this.reconnectInterval}ms`);
    
    this.reconnectTimer = setInterval(async () => {
      if (!this.isConnected) {
        console.info(TAG, '尝试自动重连...');
        const result = await this.manualConnect();
        
        if (result.state) {
          this.stopAutoReconnect();
        }
      }
    }, this.reconnectInterval);
  }

  /**
   * 停止自动重连
   */
  private stopAutoReconnect(): void {
    if (this.reconnectTimer > 0) {
      clearInterval(this.reconnectTimer);
      this.reconnectTimer = 0;
      console.info(TAG, '停止自动重连');
    }
  }

  /**
   * 设置是否自动重连
   */
  setAutoReconnect(enabled: boolean): void {
    this.autoReconnect = enabled;
    console.info(TAG, `自动重连已${enabled ? '启用' : '禁用'}`);
    
    if (!enabled) {
      this.stopAutoReconnect();
    } else if (!this.isConnected) {
      this.startAutoReconnect();
    }
  }

  /**
   * 清理资源
   */
  async dispose(): Promise<void> {
    console.info(TAG, '清理连接管理器资源');
    
    this.stopAutoReconnect();
    this.listeners.clear();
    
    await this.disconnect();
  }
}

// 导出单例实例
export const PtpConnectionManager = PtpConnectionManagerClass.getInstance();
