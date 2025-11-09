import nativeCamera from 'libentry.so';
import { BusinessError } from '@ohos.base';

// 仅保留两种连接状态
export type ConnectionState = 'connected' | 'disconnected';

// 状态变化监听器类型
export type ConnectionListener = (state: boolean, message: string) => void;

//  显式声明状态结果接口（解决对象字面量报错）
export interface ConnectionStateResult {
  state: boolean;
  message: string;
}



class CamConnectionManager {
  // 单例实例
  private static instance: CamConnectionManager|null =null;

  // 核心状态管理
  private state: boolean = false;
  private stateMessage: string = '未连接相机';


  // 新增：存储相机厂商和型号
  private cameraManufacturer: string = 'Nikon';
  private cameraModel: string = 'Zf';


  // 监听器列表（存储各页面的回调）
  private listeners: ConnectionListener[] = [];

  // 连接状态检查定时器（参考RemoteControl的定时器逻辑）
  private connectionCheckTimer: number = -1;

  // 私有构造函数：禁止外部实例化
  private constructor() {}

  // 获取全局唯一实例
  static getInstance(): CamConnectionManager {
    if (!CamConnectionManager.instance) {
      CamConnectionManager.instance = new CamConnectionManager();
    }
    return CamConnectionManager.instance;
  }

  // 新增：更新相机厂商和型号的方法
  updateCameraInfo(manufacturer: string, model: string) {
    this.cameraManufacturer = manufacturer;
    this.cameraModel = model;
  }

  // 新增：获取拼接后的相机名称（厂商 + 型号，带空格）
  getCameraFullName(): string {
    return `${this.cameraManufacturer} ${this.cameraModel}`;
  }



  // 手动连接相机（核心方法，参考RemoteControl的连接逻辑）
  async connectCamera(): Promise<boolean> {
    // 已连接状态直接返回
    if (this.state === true) {
      this.stateMessage = '已连接相机';
      this.notifyListeners();
      return true;
    }

    // 连接中提示（不改变状态，仅更新消息）
    this.stateMessage = '正在连接相机...';
    this.notifyListeners();

    try {
      // 调用底层连接接口（与RemoteControl保持一致）
      const isConnected = await nativeCamera.ConnectCamera(camConnectionManager.getCameraFullName(),'ptpip:192.168.1.1:15740');

      if (isConnected) {
        // 连接成功：更新状态并启动监测
        this.state = true;
        this.stateMessage = '相机连接成功';
        this.startConnectionCheck(); // 启动自动监测
        this.notifyListeners();
        return true;
      } else {
        // 连接失败：维持未连接状态
        this.state = false;
        this.stateMessage = '连接失败：相机无响应';
        this.notifyListeners();
        return false;
      }
    } catch (error) {
      // 连接异常处理
      const err = error as BusinessError;
      this.state = false;
      this.stateMessage = `连接出错：${err.message || '未知错误'}`;
      this.notifyListeners();
      return false;
    }
  }

  // 启动连接状态自动监测（参考RemoteControl的定时器逻辑）
  private startConnectionCheck() {
    // 先停止已有定时器，避免重复
    this.stopConnectionCheck();

    // 每3秒检查一次连接状态（与RemoteControl监测频率一致）
    this.connectionCheckTimer = setInterval(async () => {
      try {
        // 调用底层检查接口（与RemoteControl保持一致）
        const isAlive = nativeCamera.IsCameraConnected();

        if (!isAlive) {
          // 连接中断：更新状态并停止监测
          this.state = false;
          this.stateMessage = '连接已中断';
          this.stopConnectionCheck();
          this.notifyListeners();
        }
      } catch (error) {
        // 监测失败：视为连接中断
        this.state = false;
        this.stateMessage = '连接监测失败';
        this.stopConnectionCheck();
        this.notifyListeners();
      }
    }, 3000);
  }





  // 停止连接监测
  private stopConnectionCheck() {
    if (this.connectionCheckTimer !== -1) {
      clearInterval(this.connectionCheckTimer);
      this.connectionCheckTimer = -1;
    }
  }

  // 通知所有页面状态变化
  private notifyListeners() {
    this.listeners.forEach(listener => {
      listener(this.state, this.stateMessage);
    });
  }

  // 供页面注册状态监听器
  addListener(listener: ConnectionListener) {
    if (!this.listeners.includes(listener)) {
      this.listeners.push(listener);
    }
  }

  // 供页面移除监听器（避免内存泄漏）
  removeListener(listener: ConnectionListener) {
    this.listeners = this.listeners.filter(l => l !== listener);
  }

  // 供页面获取当前状态
  getCurrentState(): ConnectionStateResult {
    return {
      state: this.state,
      message: this.stateMessage
    };
  }

  // 销毁方法（可选，应用退出时调用）
  destroy() {
    this.stopConnectionCheck();
    this.listeners = [];
    CamConnectionManager.instance = null;
  }
}

// 导出全局实例
export const camConnectionManager = CamConnectionManager.getInstance();