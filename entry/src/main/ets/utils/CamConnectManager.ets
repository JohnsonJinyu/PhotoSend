import nativeCamera from 'libentry.so';
import { BusinessError } from '@ohos.base';
import { ErrorEvent, MessageEvent, worker } from '@kit.ArkTS';

// 仅保留两种连接状态
export type ConnectionState = 'connected' | 'disconnected';

// 状态变化监听器类型
export type ConnectionListener = (state: boolean, message: string) => void;

//  显式声明状态结果接口（解决对象字面量报错）
export interface ConnectionStateResult {
  state: boolean;
  message: string;
}

// ======================== 主线程与Worker的消息协议 ========================
// 消息类型枚举（明确双方通信的指令）
export enum CheckMsgType {
  START_CHECK = 'start_check', // 主线程→Worker：启动检测
  STOP_CHECK = 'stop_check', // 主线程→Worker：停止检测
  PAUSE_CHECK = 'pause_check', // 主线程→Worker：暂停检测
  RESUME_CHECK = 'resume_check', // 主线程→Worker：恢复检测
  CHECK_RESULT = 'check_result', // Worker→主线程：检测结果
  ERROR = 'error' // Worker→主线程：检测错误
}

// 消息体结构（统一格式，方便解析）
export interface CheckMessage {
  type: CheckMsgType;
  data?: boolean | string; // 附加数据（如检测结果、错误信息）
}


// Worker内部状态（控制检测逻辑）
export interface WorkerInnerState {
  isChecking: boolean; // 是否正在执行检测（定时器是否运行）
  isPaused: boolean; // 是否被暂停（锁状态）
  checkTimer: number; // 检测定时器ID
}


class CamConnectionManager {
  // 单例实例
  private static instance: CamConnectionManager | null = null;
  // 核心状态管理
  private state: boolean = false;
  private stateMessage: string = '未连接，请检查是否连接相机WiFi';
  // 新增：存储相机厂商和型号
  private cameraManufacturer: string = 'Nikon';
  private cameraModel: string = 'Zf';
  // 监听器列表（存储各页面的回调）
  private listeners: ConnectionListener[] = [];
  // 连接状态检查定时器（参考RemoteControl的定时器逻辑）
  private connectionCheckTimer: number = -1;
  // worker 相关
  private checkWorker: worker.ThreadWorker | null = null
  private isWorkerReady: boolean = false // worker是否初始化完成

  // 私有构造函数：禁止外部实例化
  private constructor() {
    this.initWorker()
  }

  // ======================== Worker初始化与通信 ========================
  // 初始化检测worker
  private initWorker() {
    try {
      // 创建Worker（路径根据项目结构调整，确保能找到文件）
      this.checkWorker = new worker.ThreadWorker('../workers/CheckConnection')

      // 监听Worker 发送的消息（检测结果/错误）
      this.checkWorker.onmessage = (e: MessageEvent<CheckMessage>) => {
        this.handleWorkerMessage(e.data)
      }

      // 监听worker错误
      this.checkWorker.onerror = (err: ErrorEvent) => {
        console.error(`连接检测Worker错误：${err.message}（行号：${err.lineno}）`)
        this.stateMessage = `检测服务异常：${err.message}`;
        this.notifyListeners();
      }

      this.isWorkerReady = true
      console.log(`连接检测Worker初始化成功`)
    } catch (error) {
      const err = error as BusinessError;
      console.error(`创建检测Worker失败：${err.message}`);
      this.stateMessage = `检测服务初始化失败`;
      this.notifyListeners();
    }
  }

  // 处理worker发送的消息
  private handleWorkerMessage(msg: CheckMessage) {
    console.log(`主线程收到 Worker 消息: ${msg.type}, 数据: ${msg.data}`);
    switch (msg.type) {
      case CheckMsgType.CHECK_RESULT:
        const isConnected = msg.data as boolean;
        // 直接根据 Worker 传来的状态更新自身状态
        if (isConnected !== this.state) {
          this.state = isConnected;
          this.stateMessage = isConnected ? '相机已连接' : '未连接，请检查是否连接相机WiFi';
          if (!isConnected) {
            this.stopConnectionCheck();
          }
          this.notifyListeners(); // 通知所有UI监听器
        }
        break;
      case CheckMsgType.ERROR:
        // 如果收到错误，强制更新为未连接状态
        if (this.state) {
          this.state = false;
          this.stateMessage = `检测错误: ${msg.data}`;
          this.notifyListeners();
        }
        break;
    }
  }

  // 向worker发送消息，通用方法
  private sendWorkerMessage(msg: CheckMessage) {
    if (!this.checkWorker || !this.isWorkerReady) {
      console.warn(`Worker未就绪，无法发送消息`)
      return
    }
    this.checkWorker.postMessage(msg)
  }

  // ======================== 检测控制方法（对外/内部调用） ========================
  // 启动连接检测（替代原startConnectionCheck）
  /**
   * 启动连接检测
   * 通知 Worker 开始其内部的检测循环
   */
  public startConnectionCheck() {
    if (this.isWorkerReady) {
      this.sendWorkerMessage({ type: CheckMsgType.START_CHECK });
      console.log('已通知 Worker 启动检测');
    }
  }


  /**
   * 停止连接检测
   * 通知 Worker 停止其内部的检测循环
   */
  public stopConnectionCheck() {
    if (this.isWorkerReady) {
      this.sendWorkerMessage({ type: CheckMsgType.STOP_CHECK });
      console.log('已通知 Worker 停止检测');
    }
  }

  // 暂停检测（对外暴露，供UI/其他操作调用）
  public pauseCheck() {
    if (this.isWorkerReady) {
      this.sendWorkerMessage({ type: CheckMsgType.PAUSE_CHECK });
      console.log(`主线程通知Worker暂停检测`);
    }
  }

  // 恢复检测（对外暴露，供UI/其他操作调用）
  public resumeCheck() {
    if (this.isWorkerReady && this.state) { // 仅连接状态下恢复
      this.sendWorkerMessage({ type: CheckMsgType.RESUME_CHECK });
      console.log(`主线程通知Worker恢复检测`);
    }
  }



  // ======================== 原有核心逻辑修改（加入锁控制） ========================
  /**
   * 手动连接相机
   * 连接成功后，启动 Worker 检测
   */
  async connectCamera(): Promise<boolean> {
    if (this.state === true) {
      this.notifyListeners();
      return true;
    }

    this.stateMessage = '正在连接相机...';
    this.notifyListeners();

    try {
      const cameraFullName = this.getCameraFullName();
      // 注意：这里的 ConnectCamera 是一个异步操作，假设它会等待连接结果
      const isConnected = await nativeCamera.ConnectCamera(cameraFullName, 'ptpip:192.168.1.1:15740');

      if (isConnected) {
        // 连接成功后，启动 Worker 进行持续检测
        this.startConnectionCheck();
      } else {
        this.stateMessage = '连接失败：相机无响应';
      }
      // 状态会由 Worker 的第一次检测结果来更新，这里可以不用手动设置
      // 但为了UI能更快地得到反馈，可以先手动设置，后续 Worker 会进行确认
      this.state = isConnected;
      this.notifyListeners();
      return isConnected;
    } catch (error) {
      const err = error as BusinessError;
      this.state = false;
      this.stateMessage = `连接出错：${err.message || '未知错误'}`;
      this.notifyListeners();
      return false;
    }
  }

  // ======================== 其他方法 ========================


  // 新增：更新相机厂商和型号的方法
  updateCameraInfo(manufacturer: string, model: string) {
    this.cameraManufacturer = manufacturer;
    this.cameraModel = model;
  }

  // 新增：获取拼接后的相机名称（厂商 + 型号，带空格）
  getCameraFullName(): string {
    return `${this.cameraManufacturer} ${this.cameraModel}`;
  }

  // 获取全局唯一实例
  static getInstance(): CamConnectionManager {
    if (!CamConnectionManager.instance) {
      CamConnectionManager.instance = new CamConnectionManager();
    }
    return CamConnectionManager.instance;
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