/**
 * PTP/IP 连接管理器
 * 负责建立 TCP 连接、会话管理、命令发送与接收
 */

import { socket } from '@kit.NetworkKit';
import {
  PtpOperationCode,
  PtpResponseCode,
  PtpIpPacketType,
  PTP_IP_DEFAULT_PORT,
  PTP_IP_COMMAND_PHASE,
  PTP_IP_DATA_PHASE,
  PTP_IP_RESPONSE_PHASE
} from './PtpConstants';
import type { PtpDeviceInfo, PtpStorageId, PtpStorageInfo, PtpObjectHandle, PtpObjectInfo } from './PtpTypes';
import type { BusinessError } from '@ohos.base';

const TAG = 'PtpConnectionManager';
const DOMAIN = 0x00301;

/**
 * PTP/IP 连接状态
 */
export enum ConnectionState {
  Disconnected = 0,
  Connecting = 1,
  Connected = 2,
  SessionOpened = 3,
}

/**
 * PTP 命令包结构
 */
interface PtpCommand {
  code: number;
  transactionId: number;
  parameters: number[];
}

/**
 * PTP 响应包结构
 */
interface PtpResponse {
  code: number;
  transactionId: number;
  parameters: number[];
}

interface ClientIdentityProfile {
  label: string;
  deviceName: string;
  guid: number[];
}

interface SessionExperimentCase {
  label: string;
  profileIndex: number;
  transportMode: CommandTransportMode;
  reuseCurrentConnection?: boolean;
}

type CommandTransportMode = 'ptpip' | 'raw';

/**
 * Socket 消息事件数据类型
 */
interface SocketMessageEvent {
  message: ArrayBuffer;
}

/**
 * PTP/IP 连接管理器类
 */
export class PtpConnectionManager {
  private tcpSocket: socket.TCPSocket | null = null;  // 命令连接（端口 15740）
  private eventSocket: socket.TCPSocket | null = null;  // 事件连接（端口 15741）
  private connectionState: ConnectionState = ConnectionState.Disconnected;
  private currentTransactionId: number = 0;
  private sessionId: number = 0;
  private connectionNumber: number = 0;
  private simpleGphoto2StyleSessionExperiment: boolean = true;
  private lastFailureReason: string = '';
  private readonly clientProfiles: ClientIdentityProfile[] = [
    {
      label: 'nikon-fixed',
      deviceName: 'Nikon',
      guid: [0x33, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
    },
    {
      label: 'mobile-device',
      deviceName: 'MobileDevice',
      guid: [0x10, 0x32, 0x54, 0x76, 0x98, 0xba, 0xdc, 0xfe, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88]
    },
    {
      label: 'android-phone',
      deviceName: 'AndroidPhone',
      guid: [0x42, 0x6f, 0x19, 0x87, 0xaa, 0x55, 0xcc, 0x33, 0x90, 0x10, 0xde, 0xad, 0xbe, 0xef, 0x12, 0x34]
    },
    {
      label: 'empty-name',
      deviceName: '',
      guid: [0xfe, 0xdc, 0xba, 0x98, 0x76, 0x54, 0x32, 0x10, 0x08, 0x07, 0x06, 0x05, 0x04, 0x03, 0x02, 0x01]
    }
  ];
  private readonly simpleSessionExperimentCases: SessionExperimentCase[] = [
    { label: 'nikon-fixed-ptpip', profileIndex: 0, transportMode: 'ptpip', reuseCurrentConnection: true },
    { label: 'nikon-fixed-raw', profileIndex: 0, transportMode: 'raw' },
    { label: 'mobile-device-ptpip', profileIndex: 1, transportMode: 'ptpip' },
    { label: 'android-phone-ptpip', profileIndex: 2, transportMode: 'ptpip' },
    { label: 'empty-name-ptpip', profileIndex: 3, transportMode: 'ptpip' }
  ];
  private activeClientProfileIndex: number = 0;
  private commandTransportMode: CommandTransportMode = 'ptpip';
  private commandReadBuffer: Uint8Array = new Uint8Array(0);
  private eventReadBuffer: Uint8Array = new Uint8Array(0);

  // 连接信息
  private ipAddress: string = '';
  private port: number = PTP_IP_DEFAULT_PORT;
  
  // 事件监听器
  private onDisconnectCallback?: () => void;

  // 事件连接初始化标志
  private eventConnectionInitialized: boolean = false;

  /**
   * 获取当前连接状态
   */
  getState(): ConnectionState {
    return this.connectionState;
  }

  getLastFailureReason(): string {
    return this.lastFailureReason;
  }

  /**
   * 设置断开连接回调
   */
  setOnDisconnect(callback: () => void): void {
    this.onDisconnectCallback = callback;
  }

  /**
   * 连接到 PTP/IP 设备
   * @param ip 设备 IP地址
   * @param port 端口号（默认 15740）
   */
  async connect(ip: string, port: number = PTP_IP_DEFAULT_PORT): Promise<boolean> {
    try {
      console.info(TAG, `\n==========================================`);
      console.info(TAG, `【PtpConnectionManager】开始连接 PTP/IP 设备：${ip}:${port}`);
      console.info(TAG, `使用 HarmonyOS NetworkKit TCP Socket`);
      console.info(TAG, `==========================================`);
      
      this.ipAddress = ip;
      this.port = port;
      this.connectionState = ConnectionState.Connecting;
      this.currentTransactionId = 0;
      this.sessionId = 0;
      this.connectionNumber = 0;
      this.commandReadBuffer = new Uint8Array(0);
      this.eventReadBuffer = new Uint8Array(0);
      this.eventConnectionInitialized = false;
      this.activeClientProfileIndex = 0;
      this.lastFailureReason = '';

      console.info(TAG, `[STEP 1] 创建 TCP Socket...`);
      // 创建 TCP Socket
      this.tcpSocket = socket.constructTCPSocketInstance();
      
      if (!this.tcpSocket) {
        console.error(TAG, `❌【STEP 1 失败】创建 TCP Socket 失败`);
        return false;
      }
      
      console.info(TAG, `✅【STEP 1 成功】TCP Socket 创建成功`);
      console.info(TAG, `[STEP 2] 开始 TCP 连接到 ${ip}:${port}...`);
      
      // 发起连接
      console.info(TAG, `[STEP 2] 调用 connectToHost...`);
      await this.connectToHost(ip, port);
      
      console.info(TAG, `✅【STEP 2 成功】TCP 连接建立成功！状态：${this.connectionState}`);
      console.info(TAG, `[STEP 2 完成] 设置 connectionState = Connected`);
      this.connectionState = ConnectionState.Connected;
      
      // STEP 3: 短暂等待相机准备（某些相机需要一点时间）
      console.info(TAG, `\n[STEP 3] 等待相机准备就绪...`);
      console.info(TAG, `[STEP 3] 开始休眠 200ms`);
      await this.sleep(200);
      console.info(TAG, `✅【STEP 3 完成】相机已准备就绪，继续 STEP 4`);
      
      // STEP 4: PTP/IP 协议握手（发送 Init_Command_Request）
      console.info(TAG, `\n==========================================`);
      console.info(TAG, `[STEP 4] PTP/IP 握手：发送 Init_Command_Request...`);
      console.info(TAG, `[STEP 4] 当前连接状态：${this.connectionState}`);
      console.info(TAG, `[STEP 4] TCP Socket 状态：${this.tcpSocket ? '正常' : 'null'}`);
      console.info(TAG, `[STEP 4] 调用 sendInitCommandRequest()`);
      
      const handshakeSuccess = await this.sendInitCommandRequest();
      
      console.info(TAG, `[STEP 4 返回] sendInitCommandRequest 结果：${handshakeSuccess ? '成功 ✅' : '失败 ❌'}`);
      
      if (handshakeSuccess) {
        console.info(TAG, `✅【STEP 4 成功】PTP/IP 握手完成，相机已接受连接`);
      } else {
        this.lastFailureReason = '已连接到相机端口，但 Init_Command 握手失败';
        console.error(TAG, `❌【STEP 4 失败】PTP/IP 握手失败`);
        console.error(TAG, `❌ 相机拒绝了我们的连接请求`);
        console.error(TAG, `💡 提示：Nikon 相机可能需要特定的设备标识`);
        await this.disconnect();
        return false;
      }
      
      console.info(TAG, `\n✅【PtpConnectionManager】TCP 命令连接阶段完成`);
      console.info(TAG, `[connect] 跳过初始事件连接，先保持命令连接稳定；待 OpenSession 成功后再尝试建立事件连接`);

      console.info(TAG, `\n✅【PtpConnectionManager】握手完成，准备打开 PTP 会话`);
      console.info(TAG, `==========================================`);
      return true;
    } catch (error) {
      if (!this.lastFailureReason) {
        this.lastFailureReason = '无法连接到相机端口 15740';
      }
      console.error(TAG, `\n❌【PtpConnectionManager】连接失败：${JSON.stringify(error)}`);
      console.error(TAG, `错误堆栈：${(error as Error).stack}`);
      await this.disconnect();
      this.connectionState = ConnectionState.Disconnected;
      return false;
    }
  }

  /**
   * 实际执行 TCP 连接
   */
  private connectToHost(ip: string, port: number): Promise<void> {
    return new Promise((resolve, reject) => {
      if (!this.tcpSocket) {
        console.error(TAG, `❌【connectToHost】TCP Socket 未初始化`);
        reject(new Error('TCP Socket 未初始化'));
        return;
      }
      
      console.info(TAG, `[connectToHost] 构建连接参数：IP=${ip}, Port=${port}`);
      
      // 按照官方文档构建 NetAddress 和 TCPConnectOptions
      const netAddress: socket.NetAddress = {
        address: ip,
        port: port
      };
      
      console.info(TAG, `[connectToHost] NetAddress: ${JSON.stringify(netAddress)}`);
      
      const tcpConnectOptions: socket.TCPConnectOptions = {
        address: netAddress
      };
      
      console.info(TAG, `[connectToHost] TCPConnectOptions: ${JSON.stringify(tcpConnectOptions)}`);
      console.info(TAG, `[connectToHost] 调用 tcpSocket.connect...`);
      
      // 使用官方文档的 connect 方法，带回调函数
      this.tcpSocket.connect(tcpConnectOptions, (err) => {
        if (err) {
          console.error(TAG, `❌【connectToHost】TCP 连接错误：${JSON.stringify(err)}`);
          reject(err);
        } else {
          console.info(TAG, `✅【connectToHost】TCP 连接成功`);
          resolve();
        }
      });
    });
  }

  /**
   * 建立事件连接（端口 15741）
   * PTP/IP 需要两个连接：命令连接（15740）和事件连接（15741）
   */
  private async connectEventConnection(): Promise<boolean> {
    try {
      console.info(TAG, `【connectEventConnection】开始建立事件连接...`);
      this.eventConnectionInitialized = false;

      if (this.eventSocket) {
        try {
          await this.eventSocket.close();
        } catch {
        }
        this.eventSocket = null;
      }

      this.eventReadBuffer = new Uint8Array(0);

      const eventPort = this.port + 1;
      console.info(TAG, `[connectEventConnection] 连接到 ${this.ipAddress}:${eventPort}`);
      console.info(TAG, `[connectEventConnection] 等待 500ms 确保命令连接稳定...`);
      await this.sleep(500);

      const connected = await this.connectEventToHost(this.ipAddress, eventPort);
      if (!connected || !this.eventSocket) {
        console.warn(TAG, `⚠️【connectEventConnection】事件 Socket 未能真正建立`);
        return false;
      }

      console.info(TAG, `✅【connectEventConnection】事件连接建立成功`);
      await this.sleep(200);

      const initialized = await this.sendInitEventRequest();
      this.eventConnectionInitialized = initialized;
      if (initialized) {
        console.info(TAG, `✅【connectEventConnection】事件连接初始化完成`);
      } else {
        console.warn(TAG, `⚠️【connectEventConnection】事件连接已建立，但 Init_Event_Request 未完成`);
      }
      return initialized;
    } catch (error) {
      console.error(TAG, `❌【connectEventConnection】建立事件连接失败：${JSON.stringify(error)}`);
      console.warn(TAG, `⚠️【connectEventConnection】事件连接失败，但将继续尝试连接`);
      return false;
    }
  }

  /**
   * 实际执行事件连接（带重试）
   */
  private async connectEventToHost(ip: string, port: number): Promise<boolean> {
    const maxAttempts = 5;

    for (let attempt = 1; attempt <= maxAttempts; attempt++) {
      if (this.eventSocket) {
        try {
          await this.eventSocket.close();
        } catch {
        }
      }

      this.eventSocket = socket.constructTCPSocketInstance();
      if (!this.eventSocket) {
        console.error(TAG, `❌【connectEventToHost】创建事件 Socket 失败`);
        return false;
      }

      const netAddress: socket.NetAddress = {
        address: ip,
        port: port
      };

      const tcpConnectOptions: socket.TCPConnectOptions = {
        address: netAddress,
        timeout: 1500
      };

      try {
        await new Promise<void>((resolve, reject) => {
          if (!this.eventSocket) {
            reject(new Error('事件 Socket 未初始化'));
            return;
          }

          this.eventSocket.connect(tcpConnectOptions, (err: BusinessError) => {
            if (err) {
              reject(err);
              return;
            }
            resolve();
          });
        });

        console.info(TAG, `✅【connectEventToHost】事件连接成功（尝试 ${attempt}/${maxAttempts}）`);
        return true;
      } catch (error) {
        const businessError = error as BusinessError;
        console.warn(TAG, `⚠️【connectEventToHost】事件连接尝试 ${attempt}/${maxAttempts} 失败：${JSON.stringify(businessError)}`);

        if (attempt >= maxAttempts) {
          console.error(TAG, `❌【connectEventToHost】事件连接重试耗尽`);
          return false;
        }

        await this.sleep(400 * attempt);
      }
    }

    return false;
  }

  /**
   * 发送 Init_Event_Request
   */
  private async sendInitEventRequest(): Promise<boolean> {
    try {
      console.info(TAG, `[sendInitEventRequest] 发送 Init_Event_Request...`);

      if (!this.eventSocket) {
        console.error(TAG, `❌【sendInitEventRequest】事件 Socket 未初始化`);
        return false;
      }

      // Init_Event_Request 包结构：
      // - 4 bytes: length (12)
      // - 4 bytes: type (3 = Init_Event_Request)
      // - 4 bytes: Connection Number
      const totalLength = 12;
      const buffer = new ArrayBuffer(totalLength);
      const view = new DataView(buffer);
      let offset = 0;
      
      view.setUint32(offset, totalLength, true);
      offset += 4;
      view.setUint32(offset, PtpIpPacketType.InitEventRequest, true);
      offset += 4;
      view.setUint32(offset, this.connectionNumber, true);
      offset += 4;

      console.info(TAG, `[sendInitEventRequest] 发送 Init_Event_Request 包，长度：${totalLength} 字节，Connection Number=${this.connectionNumber}`);

      await this.writeDataToEventSocket(buffer);
      console.info(TAG, `[sendInitEventRequest] 等待 Init_Event_Ack...`);
      
      const ackBuffer = await this.readBytesFromEventSocket(8);
      const ackView = new DataView(ackBuffer);
      const ackLength = ackView.getUint32(0, true);
      const ackType = ackView.getUint32(4, true);
      
      console.info(TAG, `[sendInitEventRequest] 收到响应：length=${ackLength}, type=${ackType}`);
      
      if (ackType === PtpIpPacketType.InitEventAck) {
        console.info(TAG, `✅【sendInitEventRequest】收到 Init_Event_Ack，事件连接建立成功`);
        return true;
      }

      console.warn(TAG, `⚠️【sendInitEventRequest】未知响应类型：${ackType}`);
      return false;
    } catch (error) {
      console.error(TAG, `❌【sendInitEventRequest】异常：${JSON.stringify(error)}`);
      console.warn(TAG, `⚠️【sendInitEventRequest】事件连接失败，但将继续尝试连接`);
      return false;
    }
  }

  /**
   * 通过命令连接发送 Init_Event_Request
   * 某些相机（如 Nikon）要求在发送 OpenSession 之前必须先发送 Init_Event_Request
   */
  private async sendInitEventRequestViaCommandConnection(): Promise<boolean> {
    try {
      console.info(TAG, `[sendInitEventRequestViaCommandConnection] 发送 Init_Event_Request...`);
      
      // Init_Event_Request 包结构：
      // - 4 bytes: length (12)
      // - 4 bytes: type (3 = Init_Event_Request)
      // - 4 bytes: Connection Number
      const totalLength = 12;
      const buffer = new ArrayBuffer(totalLength);
      const view = new DataView(buffer);
      let offset = 0;
      
      // Length
      view.setUint32(offset, totalLength, true);
      offset += 4;
      
      // Type = 3 (Init_Event_Request)
      view.setUint32(offset, PtpIpPacketType.InitEventRequest, true);
      offset += 4;
      
      // Connection Number（来自 Init_Command_Ack）
      view.setUint32(offset, this.connectionNumber, true);
      offset += 4;

      console.info(TAG, `[sendInitEventRequestViaCommandConnection] 发送 Init_Event_Request 包，长度：${totalLength} 字节，Connection Number=${this.connectionNumber}`);

      // 通过命令连接发送
      await this.writeData(buffer);
      
      console.info(TAG, `[sendInitEventRequestViaCommandConnection] 等待 Init_Event_Ack...`);
      
      try {
        const ackBuffer = await this.readBytesWithTimeout(8, 500);
        const ackView = new DataView(ackBuffer);
        
        const ackLength = ackView.getUint32(0, true);
        const ackType = ackView.getUint32(4, true);
        
        console.info(TAG, `[sendInitEventRequestViaCommandConnection] 收到响应：length=${ackLength}, type=${ackType}`);
        
        if (ackType === PtpIpPacketType.InitEventAck) {
          console.info(TAG, `✅【sendInitEventRequestViaCommandConnection】收到 Init_Event_Ack`);
          return true;
        }

        console.warn(TAG, `⚠️【sendInitEventRequestViaCommandConnection】未收到标准 Init_Event_Ack，继续执行`);
        return false;
      } catch {
        console.warn(TAG, `⚠️【sendInitEventRequestViaCommandConnection】未收到 Init_Event_Ack，但继续执行`);
        return false;
      }
    } catch (error) {
      console.error(TAG, `❌【sendInitEventRequestViaCommandConnection】异常：${JSON.stringify(error)}`);
      console.warn(TAG, `⚠️【sendInitEventRequestViaCommandConnection】Init_Event_Request 失败，但继续执行`);
      return false;
    }
  }

  /**
   * 打开 PTP 会话
   * @param sessionId 会话 ID
   */
  async openSession(sessionId: number): Promise<boolean> {
    try {
      console.info(TAG, `【PtpConnectionManager】==========================================`);
      console.info(TAG, `【PtpConnectionManager】打开 PTP 会话 (ID=${sessionId})`);
      console.info(TAG, `【PtpConnectionManager】==========================================`);
      
      this.sessionId = sessionId;
      this.currentTransactionId = 0;
      this.commandTransportMode = 'raw';
      this.eventConnectionInitialized = false;

      if (this.simpleGphoto2StyleSessionExperiment) {
        console.info(TAG, `【PtpConnectionManager】启用最小会话实验模式：仅使用 15740 命令通道，跳过手工 15741 / Init_Event_Request / 复杂回退，改为干净的身份与封装实验矩阵`);
        return await this.executeSimpleSessionExperiment(sessionId);
      }

      const attemptOpenSessionWithCurrentProfile = async (): Promise<PtpResponse | null> => {
        const profile = this.getCurrentClientProfile();
        console.info(TAG, `【PtpConnectionManager】本轮 OpenSession 使用客户端身份：${profile.label}, deviceName=${profile.deviceName === '' ? '<empty>' : profile.deviceName}`);

        const commandEventReady = await this.sendInitEventRequestViaCommandConnection();
        if (commandEventReady) {
          console.info(TAG, `✅【PtpConnectionManager】命令通道 Init_Event_Request 预热成功`);
        } else {
          console.warn(TAG, `⚠️【PtpConnectionManager】命令通道 Init_Event_Request 未确认成功，继续尝试 OpenSession`);
        }

        const openSessionTransactionId = 0;

        const tryRawOpenSession = async (): Promise<PtpResponse> => {
          console.warn(TAG, `⚠️ 【PtpConnectionManager】优先尝试 raw PTP 容器格式的 OpenSession（tid=${openSessionTransactionId}）...`);
          const response = await this.sendRawCommandWithTransaction(PtpOperationCode.OpenSession, openSessionTransactionId, [sessionId]);
          this.commandTransportMode = 'raw';
          return response;
        };

        const tryOpenSession = async (): Promise<PtpResponse> => {
          console.info(TAG, `【PtpConnectionManager】尝试 PTP/IP OperationRequest 格式的 OpenSession (0x1002), tid=${openSessionTransactionId}...`);
          this.commandTransportMode = 'ptpip';
          return await this.sendPtpIpCommandWithTransaction(PtpOperationCode.OpenSession, openSessionTransactionId, [sessionId]);
        };

        try {
          return await tryRawOpenSession();
        } catch (rawError) {
          console.warn(TAG, `⚠️ 【PtpConnectionManager】raw OpenSession 未收到响应，重建命令连接后再尝试 PTP/IP OperationRequest：${JSON.stringify(rawError)}`);

          const reconnected = await this.reconnectCommandChannel();
          if (!reconnected) {
            console.warn(TAG, `⚠️ 【PtpConnectionManager】兼容模式切换前重建命令连接失败`);
            return null;
          }

          const reconnectedEventReady = await this.sendInitEventRequestViaCommandConnection();
          if (reconnectedEventReady) {
            console.info(TAG, `✅【PtpConnectionManager】重建命令连接后 Init_Event_Request 预热成功`);
          }

          try {
            return await tryOpenSession();
          } catch (wrappedError) {
            console.warn(TAG, `⚠️ 【PtpConnectionManager】PTP/IP OperationRequest 也未收到响应，再尝试事件连接恢复：${JSON.stringify(wrappedError)}`);

            const eventReady = await this.connectEventConnection();
            if (!eventReady) {
              console.warn(TAG, `⚠️ 【PtpConnectionManager】事件连接未真正就绪，当前客户端身份可能仍不满足 Nikon 会话条件`);
              return null;
            }

            console.info(TAG, `✅ 【PtpConnectionManager】事件连接已就绪，回到 raw OpenSession 重试`);
            this.commandTransportMode = 'raw';
            return await this.sendRawCommandWithTransaction(PtpOperationCode.OpenSession, openSessionTransactionId, [sessionId]);
          }
        }
      };

      let response: PtpResponse | null = await attemptOpenSessionWithCurrentProfile();
      while (!response && await this.tryNextClientProfile()) {
        response = await attemptOpenSessionWithCurrentProfile();
      }

      if (!response) {
        console.warn(TAG, `⚠️【PtpConnectionManager】所有 Nikon 客户端身份策略均未打开会话`);
        return false;
      }

      if (response.code === PtpResponseCode.OK) {
        this.connectionState = ConnectionState.SessionOpened;
        this.lastFailureReason = '';
        console.info(TAG, `✅ 【PtpConnectionManager】PTP 会话打开成功！状态：${this.connectionState}`);
        console.info(TAG, `【PtpConnectionManager】准备发送 PTP 命令...`);

        if (!this.eventSocket || !this.eventConnectionInitialized) {
          try {
            console.info(TAG, `【PtpConnectionManager】OpenSession 成功，开始延后建立事件连接...`);
            const eventReady = await this.connectEventConnection();
            if (!eventReady) {
              console.warn(TAG, `⚠️ 【PtpConnectionManager】事件连接仍未就绪，继续使用命令连接`);
            }
          } catch (eventError) {
            console.warn(TAG, `⚠️ 【PtpConnectionManager】事件连接建立失败，继续使用命令连接：${JSON.stringify(eventError)}`);
          }
        }
        return true;
      } else {
        this.lastFailureReason = `相机已接受连接，但 OpenSession 返回错误码 0x${response.code.toString(16)}`;
        console.error(TAG, `❌ 【PtpConnectionManager】打开会话失败，响应码：0x${response.code.toString(16)}`);
        return false;
      }
    } catch (error) {
      if (!this.lastFailureReason) {
        this.lastFailureReason = '相机已接受连接，但 OpenSession 阶段发生异常';
      }
      console.error(TAG, `❌ 【PtpConnectionManager】打开会话异常：${JSON.stringify(error)}`);
      return false;
    }
  }

  /**
   * 关闭 PTP 会话
   */
  async closeSession(): Promise<void> {
    try {
      if (this.connectionState === ConnectionState.SessionOpened) {
        console.info(TAG, '关闭 PTP 会话');
        await this.sendCommand(PtpOperationCode.CloseSession, []);
      }
    } catch (error) {
      console.error(TAG, `关闭会话异常：${JSON.stringify(error)}`);
    } finally {
      this.connectionState = ConnectionState.Connected;
    }
  }

  /**
   * 断开连接
   */
  async disconnect(): Promise<void> {
    try {
      console.info(TAG, '断开 PTP/IP 连接');
      
      // 先关闭会话
      await this.closeSession();
      
      // 关闭 TCP 连接
      if (this.tcpSocket) {
        await this.tcpSocket.close();
        this.tcpSocket = null;
      }

      if (this.eventSocket) {
        await this.eventSocket.close();
        this.eventSocket = null;
      }

      this.connectionState = ConnectionState.Disconnected;
      this.currentTransactionId = 0;
      this.sessionId = 0;
      this.connectionNumber = 0;
      this.commandTransportMode = 'ptpip';
      this.commandReadBuffer = new Uint8Array(0);
      this.eventReadBuffer = new Uint8Array(0);

      // 调用断开回调
      if (this.onDisconnectCallback) {
        this.onDisconnectCallback();
      }
      
      console.info(TAG, '连接已断开');
    } catch (error) {
      console.error(TAG, `断开连接异常：${JSON.stringify(error)}`);
    }
  }

  /**
   * 获取设备信息
   */
  async getDeviceInfo(): Promise<PtpDeviceInfo | null> {
    try {
      const response = await this.sendCommand(PtpOperationCode.GetDeviceInfo, []);
      
      if (response.code !== PtpResponseCode.OK) {
        console.error(TAG, `获取设备信息失败：${response.code}`);
        return null;
      }
      
      // 解析设备信息数据
      // TODO: 实现具体的解析逻辑
      return {} as PtpDeviceInfo;
    } catch (error) {
      console.error(TAG, `获取设备信息异常：${JSON.stringify(error)}`);
      return null;
    }
  }

  /**
   * 发送 PTP 命令并等待响应
   * @param operationCode 操作码
   * @param parameters 参数列表
   */
  async sendCommand(operationCode: number, parameters: number[]): Promise<PtpResponse> {
    // 检查连接状态 - OpenSession 命令可以在 Connected 状态下发送
    if (!this.tcpSocket) {
      throw new Error('未连接到 PTP/IP 设备');
    }
    
    // 除了 OpenSession 外，其他命令需要 SessionOpened 状态
    if (operationCode !== PtpOperationCode.OpenSession && 
        this.connectionState !== ConnectionState.SessionOpened) {
      throw new Error('PTP 会话未打开');
    }
    
    // 生成事务 ID
    const transactionId = operationCode === PtpOperationCode.OpenSession
      ? 0
      : ++this.currentTransactionId;

    console.debug(TAG, `发送命令：code=0x${operationCode.toString(16)}, tid=${transactionId}, mode=${this.commandTransportMode}`);

    const response = this.commandTransportMode === 'raw'
      ? await this.sendRawCommandWithTransaction(operationCode, transactionId, parameters)
      : await this.sendPtpIpCommandWithTransaction(operationCode, transactionId, parameters);

    console.debug(TAG, `收到响应：code=0x${response.code.toString(16)}, tid=${response.transactionId}`);

    return response;
  }

  private async sendPtpIpCommandWithTransaction(operationCode: number, transactionId: number, parameters: number[]): Promise<PtpResponse> {
    const commandBuffer = this.buildCommandPacket(operationCode, transactionId, parameters);
    await this.writeData(commandBuffer);
    return await this.readResponse();
  }

  private async sendRawCommand(operationCode: number, parameters: number[]): Promise<PtpResponse> {
    const transactionId = operationCode === PtpOperationCode.OpenSession
      ? 0
      : ++this.currentTransactionId;
    return await this.sendRawCommandWithTransaction(operationCode, transactionId, parameters);
  }

  private async sendRawCommandWithTransaction(operationCode: number, transactionId: number, parameters: number[]): Promise<PtpResponse> {
    const commandBuffer = this.buildRawCommandPacket(operationCode, transactionId, parameters);
    await this.writeData(commandBuffer);
    return await this.readRawResponse();
  }

  private buildRawCommandPacket(operationCode: number, transactionId: number, parameters: number[]): ArrayBuffer {
    const parameterCount = Math.min(parameters.length, 5);
    const totalLength = 12 + (parameterCount * 4);
    const buffer = new ArrayBuffer(totalLength);
    const view = new DataView(buffer);
    let offset = 0;

    view.setUint32(offset, totalLength, true);
    offset += 4;
    view.setUint16(offset, 1, true);
    offset += 2;
    view.setUint16(offset, operationCode, true);
    offset += 2;
    view.setUint32(offset, transactionId, true);
    offset += 4;

    for (let i = 0; i < parameterCount; i++) {
      view.setUint32(offset, parameters[i], true);
      offset += 4;
    }

    console.info(TAG, `[buildRawCommandPacket] op=0x${operationCode.toString(16)}, tid=${transactionId}, totalLength=${totalLength}`);
    console.debug(TAG, `[buildRawCommandPacket] hex=${this.formatHexPreview(buffer)}`);
    return buffer;
  }

  private async readRawResponse(): Promise<PtpResponse> {
    console.info(TAG, `[readRawResponse] 开始读取 raw PTP 响应...`);
    const headerBuffer = await this.readBytes(12);
    const headerView = new DataView(headerBuffer);
    const length = headerView.getUint32(0, true);
    const containerType = headerView.getUint16(4, true);
    const code = headerView.getUint16(6, true);
    const transactionId = headerView.getUint32(8, true);

    console.info(TAG, `[readRawResponse] 包解析：length=${length}, containerType=${containerType}, code=0x${code.toString(16)}, tid=${transactionId}`);

    if (containerType !== 3) {
      throw new Error(`未处理的 raw 响应容器类型：${containerType}`);
    }

    const remainingLength = length - 12;
    const remainingBuffer = remainingLength > 0 ? await this.readBytes(remainingLength) : new ArrayBuffer(0);
    const view = new DataView(remainingBuffer);
    let offset = 0;
    const parameters: number[] = [];
    const paramCount = Math.floor(remainingBuffer.byteLength / 4);
    for (let i = 0; i < paramCount && i < 5; i++) {
      parameters.push(view.getUint32(offset, true));
      offset += 4;
    }

    return {
      code,
      transactionId,
      parameters
    };
  }

  /**
   * 获取数据阶段信息
   */
  private getDataPhaseInfo(operationCode: number): number {
    const hasIncomingDataPhase: boolean = operationCode === PtpOperationCode.GetDeviceInfo ||
      operationCode === PtpOperationCode.GetObject ||
      operationCode === PtpOperationCode.GetThumb ||
      operationCode === PtpOperationCode.GetObjectHandles ||
      operationCode === PtpOperationCode.GetObjectInfo ||
      operationCode === PtpOperationCode.GetStorageIDs ||
      operationCode === PtpOperationCode.GetStorageInfo ||
      operationCode === PtpOperationCode.GetNumObjects;

    if (hasIncomingDataPhase) {
      return PTP_IP_DATA_PHASE;
    }

    const hasOutgoingDataPhase: boolean = operationCode === PtpOperationCode.SendObjectInfo ||
      operationCode === PtpOperationCode.SendObject ||
      operationCode === PtpOperationCode.Nikon_SetDevicePropValue;

    if (hasOutgoingDataPhase) {
      return PTP_IP_COMMAND_PHASE;
    }

    return PTP_IP_RESPONSE_PHASE;
  }

  private formatHexPreview(buffer: ArrayBuffer, maxBytes: number = 24): string {
    const bytes = new Uint8Array(buffer);
    const end = Math.min(bytes.length, maxBytes);
    return Array.from(bytes.slice(0, end)).map((value: number): string => value.toString(16).padStart(2, '0')).join(' ');
  }

  /**
   * 构建PTP 命令包
   */
  private buildCommandPacket(operationCode: number, transactionId: number, parameters: number[]): ArrayBuffer {
    // 标准 PTP/IP OperationRequest 包格式：
    // - PacketLength (4 bytes)
    // - PacketType (4 bytes) = 6 (OperationRequest)
    // - DataPhaseInfo (4 bytes) = 1/2/3
    // - OperationCode (2 bytes)
    // - TransactionID (4 bytes)
    // - Parameters (0-5 * 4 bytes)
    
    const parameterCount = Math.min(parameters.length, 5);
    const totalLength = 18 + (parameterCount * 4);

    const buffer = new ArrayBuffer(totalLength);
    const view = new DataView(buffer);
    let offset = 0;
    
    view.setUint32(offset, totalLength, true);
    offset += 4;

    view.setUint32(offset, PtpIpPacketType.OperationRequest, true);
    offset += 4;

    const dataPhaseInfo: number = this.getDataPhaseInfo(operationCode);
    view.setUint32(offset, dataPhaseInfo, true);
    offset += 4;

    view.setUint16(offset, operationCode, true);
    offset += 2;

    view.setUint32(offset, transactionId, true);
    offset += 4;
    
    for (let i = 0; i < parameterCount; i++) {
      view.setUint32(offset, parameters[i], true);
      offset += 4;
    }

    console.info(TAG, `[buildCommandPacket] op=0x${operationCode.toString(16)}, tid=${transactionId}, dataPhase=${dataPhaseInfo}, totalLength=${totalLength}`);
    console.debug(TAG, `[buildCommandPacket] hex=${this.formatHexPreview(buffer)}`);

    return buffer;
  }

  /**
   * 写入数据到 Socket
   */
  private writeData(buffer: ArrayBuffer): Promise<void> {
    return new Promise((resolve, reject) => {
      if (!this.tcpSocket) {
        console.error(TAG, `[writeData] ❌ TCP Socket 未初始化`);
        reject(new Error('TCP Socket 未初始化'));
        return;
      }
      
      const data: Uint8Array = new Uint8Array(buffer);
      console.info(TAG, `[writeData] 准备发送 ${data.length} 字节`);
      console.debug(TAG, `[writeData] 数据预览 (前 16 字节): ${Array.from(data.slice(0, 16)).map(b => b.toString(16).padStart(2, '0')).join(' ')}`);
      
      // 使用官方文档的 send 方法，带回调函数
      // 注意：HarmonyOS send 方法需要正确的参数格式
      try {
        this.tcpSocket.send({ data: data.buffer }, (err: Error) => {
          if (err) {
            console.error(TAG, `❌【writeData】写入数据错误：${JSON.stringify(err)}`);
            console.error(TAG, `❌【writeData】错误详情：${err.name} - ${err.message}`);
            reject(err);
          } else {
            console.info(TAG, `✅【writeData】数据发送成功`);
            resolve();
          }
        });
      } catch {
        console.error(TAG, `❌【writeData】send 方法异常`);
        reject(new Error('send 方法执行失败'));
      }
    });
  }

  /**
   * 写入数据到事件 Socket
   */
  private writeDataToEventSocket(buffer: ArrayBuffer): Promise<void> {
    return new Promise((resolve, reject) => {
      if (!this.eventSocket) {
        console.error(TAG, `[writeDataToEventSocket] ❌ 事件 Socket 未初始化`);
        reject(new Error('事件 Socket 未初始化'));
        return;
      }
      
      const data: Uint8Array = new Uint8Array(buffer);
      console.info(TAG, `[writeDataToEventSocket] 准备发送 ${data.length} 字节`);
      console.debug(TAG, `[writeDataToEventSocket] 数据预览 (前 16 字节): ${Array.from(data.slice(0, 16)).map(b => b.toString(16).padStart(2, '0')).join(' ')}`);
      
      try {
        this.eventSocket.send({ data: data.buffer }, (err: Error) => {
          if (err) {
            console.error(TAG, `❌【writeDataToEventSocket】写入数据错误：${JSON.stringify(err)}`);
            reject(err);
          } else {
            console.info(TAG, `✅【writeDataToEventSocket】数据发送成功`);
            resolve();
          }
        });
      } catch {
        console.error(TAG, `❌【writeDataToEventSocket】send 方法异常`);
        reject(new Error('send 方法执行失败'));
      }
    });
  }

  /**
   * 读取响应
   */
  private async readResponse(): Promise<PtpResponse> {
    if (!this.tcpSocket) {
      console.error(TAG, `[readResponse] TCP Socket 未初始化`);
      throw new Error('TCP Socket 未初始化');
    }
    
    console.info(TAG, `[readResponse] 开始读取响应...`);
    console.info(TAG, `[readResponse] 读取 8 字节 PTP/IP 包头...`);
    const headerBuffer = await this.readBytes(8);
    console.info(TAG, `[readResponse] 收到包头：${headerBuffer.byteLength} 字节`);
    
    const headerView = new DataView(headerBuffer);
    const length = headerView.getUint32(0, true);
    const packetType = headerView.getUint32(4, true);

    console.info(TAG, `[readResponse] 包解析：length=${length}, packetType=${packetType}`);

    if (length < 8) {
      throw new Error(`非法响应长度：${length}`);
    }

    const remainingLength = length - 8;
    console.info(TAG, `[readResponse] 还需要读取 ${remainingLength} 字节...`);
    const remainingBuffer = remainingLength > 0 ? await this.readBytes(remainingLength) : new ArrayBuffer(0);
    console.info(TAG, `[readResponse] 收到包体：${remainingBuffer.byteLength} 字节`);
    
    return this.parseResponse(packetType, remainingBuffer);
  }

  /**
   * 解析 OperationResponse 包
   */
  private parseResponse(packetType: number, data: ArrayBuffer): PtpResponse {
    if (packetType !== PtpIpPacketType.OperationResponse) {
      throw new Error(`未处理的响应包类型：${packetType}`);
    }

    const view = new DataView(data);
    let offset = 0;
    const code = view.getUint16(offset, true);
    offset += 2;

    const transactionId = view.getUint32(offset, true);
    offset += 4;
    
    const parameters: number[] = [];
    const remainingBytes = data.byteLength - offset;
    const paramCount = Math.floor(remainingBytes / 4);
    
    for (let i = 0; i < paramCount && i < 5; i++) {
      parameters.push(view.getUint32(offset, true));
      offset += 4;
    }
    
    return {
      code: code,
      transactionId: transactionId,
      parameters: parameters
    };
  }

  /**
   * 从 Socket 读取指定长度的字节
   * 使用消息订阅方式接收数据
   */
  private readBytes(length: number): Promise<ArrayBuffer> {
    return this.readExactBytesFromSocket(this.tcpSocket, 'command', length, 5000, 'readBytes');
  }

  /**
   * 从事件 Socket 读取指定长度的字节
   */
  private readBytesFromEventSocket(length: number): Promise<ArrayBuffer> {
    return this.readExactBytesFromSocket(this.eventSocket, 'event', length, 5000, 'readBytesFromEventSocket');
  }

  /**
   * 读取数据块（用于照片、缩略图等大数据）
   */
  async readDataPacket(): Promise<ArrayBuffer> {
    if (!this.tcpSocket) {
      throw new Error('TCP Socket 未初始化');
    }

    const chunks: ArrayBuffer[] = [];
    let totalReceived = 0;
    let expectedTotal = 0;

    while (true) {
      // 读取包头（8 字节）
      const headerBuffer = await this.readBytes(8);
      const headerView = new DataView(headerBuffer);
      
      let offset = 0;
      const packetLength = headerView.getUint32(offset, true);
      offset += 4;
      
      const packetType = headerView.getUint32(offset, true);
      offset += 4;

      // 如果是第一个包，记录总长度
      if (expectedTotal === 0 && packetType === PtpIpPacketType.StartDataPacket) {
        // StartDataPacket 包含 TransactionID(4) + TotalDataLength(8)
        const remainingHeader = await this.readBytes(packetLength - 8);
        const remainingView = new DataView(remainingHeader);
        expectedTotal = remainingView.getUint32(4, true);
        continue;
      }

      // 读取数据内容
      const dataLength = packetLength - 8;
      if (dataLength > 0) {
        const dataBuffer = await this.readBytes(dataLength);
        
        if (packetType === PtpIpPacketType.DataPacket) {
          chunks.push(dataBuffer);
          totalReceived += dataBuffer.byteLength;
        }
      }

      // 检查是否结束
      if (packetType === PtpIpPacketType.EndDataPacket || totalReceived >= expectedTotal) {
        break;
      }
    }

    // 合并所有数据块
    return this.mergeArrayBuffers(chunks);
  }

  /**
   * 合并多个 ArrayBuffer
   */
  private mergeArrayBuffers(buffers: ArrayBuffer[]): ArrayBuffer {
    const totalLength = buffers.reduce((sum, buf) => sum + buf.byteLength, 0);
    const result = new Uint8Array(totalLength);
    let offset = 0;
    
    for (const buffer of buffers) {
      result.set(new Uint8Array(buffer), offset);
      offset += buffer.byteLength;
    }
    
    return result.buffer;
  }

  private appendUint8Array(base: Uint8Array, addition: Uint8Array): Uint8Array {
    if (base.byteLength === 0) {
      return addition.slice();
    }

    const result = new Uint8Array(base.byteLength + addition.byteLength);
    result.set(base, 0);
    result.set(addition, base.byteLength);
    return result;
  }

  private cloneArrayBuffer(data: Uint8Array): ArrayBuffer {
    const result = new Uint8Array(data.byteLength);
    result.set(data);
    return result.buffer as ArrayBuffer;
  }

  private getSocketReadBuffer(bufferType: 'command' | 'event'): Uint8Array {
    return bufferType === 'command' ? this.commandReadBuffer : this.eventReadBuffer;
  }

  private setSocketReadBuffer(bufferType: 'command' | 'event', data: Uint8Array): void {
    if (bufferType === 'command') {
      this.commandReadBuffer = data;
    } else {
      this.eventReadBuffer = data;
    }
  }

  private readExactBytesFromSocket(
    socketInstance: socket.TCPSocket | null,
    bufferType: 'command' | 'event',
    length: number,
    timeoutMs: number,
    logLabel: string
  ): Promise<ArrayBuffer> {
    return new Promise((resolve, reject) => {
      if (!socketInstance) {
        console.error(TAG, `[${logLabel}] ❌ Socket 未初始化`);
        reject(new Error('Socket 未初始化'));
        return;
      }

      let buffered = this.getSocketReadBuffer(bufferType);
      if (buffered.byteLength >= length) {
        const result = buffered.slice(0, length);
        const remaining = buffered.slice(length);
        this.setSocketReadBuffer(bufferType, remaining);
        console.info(TAG, `[${logLabel}] ✅ 直接从缓存读取 ${length} 字节，剩余缓存 ${remaining.byteLength} 字节`);
        resolve(this.cloneArrayBuffer(result));
        return;
      }

      console.info(TAG, `[${logLabel}] 开始读取 ${length} 字节，当前缓存 ${buffered.byteLength} 字节...`);

      let settled = false;
      let timeoutId: number = -1;

      const cleanup = () => {
        socketInstance.off('message', messageHandler);
        if (timeoutId >= 0) {
          clearTimeout(timeoutId);
        }
      };

      const tryResolve = () => {
        if (settled || buffered.byteLength < length) {
          return;
        }

        settled = true;
        const result = buffered.slice(0, length);
        const remaining = buffered.slice(length);
        this.setSocketReadBuffer(bufferType, remaining);
        cleanup();
        console.info(TAG, `[${logLabel}] ✅ 成功读取 ${length} 字节，剩余缓存 ${remaining.byteLength} 字节`);
        resolve(this.cloneArrayBuffer(result));
      };

      const messageHandler = (value: SocketMessageEvent) => {
        const chunk = new Uint8Array(value.message);
        buffered = this.appendUint8Array(buffered, chunk);
        console.debug(TAG, `[${logLabel}] 收到数据块：${chunk.byteLength} 字节，缓存累计：${buffered.byteLength}/${length}`);
        tryResolve();
      };

      socketInstance.on('message', messageHandler);
      console.info(TAG, `[${logLabel}] 已订阅 message 事件，等待数据...`);
      tryResolve();

      timeoutId = setTimeout(() => {
        if (settled) {
          return;
        }

        cleanup();
        this.setSocketReadBuffer(bufferType, buffered);
        console.error(TAG, `[${logLabel}] ❌ 读取超时：期望${length}字节，当前缓存${buffered.byteLength}字节`);
        reject(new Error(`读取数据超时：期望${length}字节，当前缓存${buffered.byteLength}字节`));
      }, timeoutMs);
    });
  }

  /**
   * 从 Socket 读取指定长度的字节（带超时，用于清空缓冲区）
   * @param length 要读取的长度
   * @param timeoutMs 超时时间（毫秒）
   */
  private readBytesWithTimeout(length: number, timeoutMs: number): Promise<ArrayBuffer> {
    return this.readExactBytesFromSocket(this.tcpSocket, 'command', length, timeoutMs, 'readBytesWithTimeout');
  }

  /**
   * PTP/IP 协议握手：发送 Init_Command_Request
   * 这是 PTP/IP 特有的初始化流程，在 TCP 连接后必须先发送这个包
   * 关键点：让相机认为连接的是智能移动设备（手机/平板），而不是计算机
   */
  private async sendInitCommandRequest(): Promise<boolean> {
    try {
      if (!this.tcpSocket || this.connectionState !== ConnectionState.Connected) {
        console.error(TAG, `[sendInitCommandRequest] ❌ TCP 未连接`);
        console.error(TAG, `[sendInitCommandRequest] tcpSocket: ${this.tcpSocket ? '已初始化' : '未初始化'}`);
        console.error(TAG, `[sendInitCommandRequest] connectionState: ${this.connectionState}`);
        return false;
      }
      
      console.info(TAG, `[sendInitCommandRequest] ✅ 开始构造 Init_Command_Request 包（模拟智能设备）...`);
      const profile = this.getCurrentClientProfile();
      console.info(TAG, `[sendInitCommandRequest] 当前客户端身份：${profile.label}, deviceName=${profile.deviceName === '' ? '<empty>' : profile.deviceName}`);

      const guid: number[] = profile.guid;
      const deviceName = profile.deviceName;

      // 构建包结构：
      // - 4 bytes: length
      // - 4 bytes: type (1 = Init_Command_Request)
      // - 16 bytes: GUID
      // - xx bytes: device name (ASCII + null terminator)
      // - 4 bytes: protocol version (0x00010000)
      const nameLength = deviceName.length + 1; // ASCII + null terminator
      const protocolVersion = 0x00010000;
      const totalLength = 4 + 4 + 16 + nameLength + 4;

      const buffer = new ArrayBuffer(totalLength);
      const view = new DataView(buffer);
      let offset = 0;
      
      // Length (little-endian)
      view.setUint32(offset, totalLength, true);
      offset += 4;
      console.debug(TAG, `[sendInitCommandRequest] 包长度：${totalLength} 字节`);
      
      // Type = 1 (Init_Command_Request)
      view.setUint32(offset, PtpIpPacketType.InitCommandRequest, true);
      offset += 4;
      console.debug(TAG, `[sendInitCommandRequest] 包类型：1 (Init_Command_Request)`);
      
      // GUID (16 bytes)
      for (let i = 0; i < 16; i++) {
        view.setUint8(offset + i, guid[i]);
      }
      offset += 16;
      console.debug(TAG, `[sendInitCommandRequest] GUID: ${guid.map(b => b.toString(16).padStart(2, '0')).join('')}`);
      
      // Device name as ASCII (每个字符 1 字节) + null terminator
      for (let i = 0; i < deviceName.length; i++) {
        const charCode = deviceName.charCodeAt(i);
        view.setUint8(offset, charCode);
        offset += 1;
      }
      // Null terminator
      view.setUint8(offset, 0);
      offset += 1;

      // ProtocolVersion
      view.setUint32(offset, protocolVersion, true);
      offset += 4;
      console.debug(TAG, `[sendInitCommandRequest] ProtocolVersion=0x${protocolVersion.toString(16)}`);

      console.info(TAG, `[sendInitCommandRequest] 发送 Init_Command_Request 包，总长度：${totalLength} 字节`);
      
      // 发送包
      console.info(TAG, `[sendInitCommandRequest] 开始发送数据...`);
      await this.writeData(buffer);
      console.info(TAG, `[sendInitCommandRequest] ✅ 数据发送成功，等待 Init_Command_Ack...`);
      
      // 等待响应（Init_Command_Ack，类型 2）
      console.info(TAG, `[sendInitCommandRequest] 开始读取响应...`);
      
      // 【关键修复】改进的包读取逻辑
      // 第一步：先读取包头（8 字节）来获得包长度
      console.info(TAG, `[sendInitCommandRequest] 第一步：读取包头（8字节）...`);
      const headerBuffer = await this.readBytes(8);
      const headerView = new DataView(headerBuffer);

      const ackLength = headerView.getUint32(0, true);
      const ackType = headerView.getUint32(4, true);

      console.info(TAG, `[sendInitCommandRequest] 包头解析：length=${ackLength}, type=${ackType}`);

      if (ackLength < 8) {
        console.error(TAG, `❌【sendInitCommandRequest】非法响应长度：${ackLength}`);
        return false;
      }

      // 第二步：如果包长度 > 8，继续读取剩余部分
      let ackBuffer: ArrayBuffer;
      let finalAckLength = ackLength;

      if (ackLength > 8) {
        const remainingLength = ackLength - 8;
        console.info(TAG, `[sendInitCommandRequest] 第二步：读取包体（${remainingLength}字节）...`);
        const remainingBuffer = await this.readBytes(remainingLength);

        // 合并包头和包体
        const totalBuffer = new Uint8Array(ackLength);
        totalBuffer.set(new Uint8Array(headerBuffer), 0);
        totalBuffer.set(new Uint8Array(remainingBuffer), 8);
        ackBuffer = totalBuffer.buffer as ArrayBuffer;
        finalAckLength = ackLength;

        console.info(TAG, `[sendInitCommandRequest] ✅ 完整 Init_Command_Ack 包接收：${ackLength} 字节`);
      } else {
        ackBuffer = headerBuffer as ArrayBuffer;
        finalAckLength = 8;
      }

      const ackView = new DataView(ackBuffer);
      
      if (ackType === 2) {
        if (finalAckLength < 12) {
          console.error(TAG, `❌【sendInitCommandRequest】Init_Command_Ack 不完整：${finalAckLength} 字节，无法解析 Connection Number`);
          return false;
        }

        console.info(TAG, `✅【sendInitCommandRequest】收到 Init_Command_Ack，握手成功！`);
        console.info(TAG, `✅ Nikon ZF 相机已接受连接`);

        let connectionNumber = ackView.getUint32(8, true);
        console.info(TAG, `【sendInitCommandRequest】Connection Number(偏移8)=${connectionNumber}`);

        if (connectionNumber === 0 && finalAckLength >= 12) {
          const tailConnectionNumber = ackView.getUint32(finalAckLength - 4, true);
          if (tailConnectionNumber !== 0) {
            console.warn(TAG, `⚠️【sendInitCommandRequest】偏移8的 Connection Number 为 0，改用尾部字段 ${tailConnectionNumber}`);
            connectionNumber = tailConnectionNumber;
          }
        }

        if (connectionNumber === 0) {
          console.warn(TAG, `⚠️【sendInitCommandRequest】未解析到有效 Connection Number，回退使用默认值 1`);
          connectionNumber = 1;
        }

        console.info(TAG, `【sendInitCommandRequest】相机返回的 Connection Number: ${connectionNumber}`);

        // 保存 Connection Number，供 Init_Event_Request 使用
        this.connectionNumber = connectionNumber;
        this.sessionId = 0;

        console.info(TAG, `✅【sendInitCommandRequest】握手完成，Connection Number=${connectionNumber}`);
        console.info(TAG, `【sendInitCommandRequest】命令连接已稳定；OpenSession 将使用本地固定 PTP Session ID，事件连接将使用 Connection Number`);

        return true;
      } else if (ackType === PtpIpPacketType.InitFail) {
        // Init_Fail
        console.error(TAG, `❌【sendInitCommandRequest】握手失败 (Init_Fail, type=5)`);
        console.error(TAG, `❌ Nikon 相机拒绝了连接请求`);
        console.error(TAG, `❌ 当前设备名称：Nikon`);
        console.error(TAG, `💡 故障排查建议：`);
        console.error(TAG, `   1. 确保相机已启用 WiFi 和 PTP/IP`);
        console.error(TAG, `   2. 确保手机和相机在同一 WiFi 网络`);
        console.error(TAG, `   3. 尝试在相机上重新启用 PTP/IP 功能`);
        console.error(TAG, `   4. 重启相机的 WiFi 模块`);
        return false;
      } else {
        console.error(TAG, `❌【sendInitCommandRequest】未知响应类型：${ackType}`);
        console.error(TAG, `❌ 期望收到 type=2 (Init_Command_Ack) 或 type=5 (Init_Fail)`);
        console.error(TAG, `❌ 诊断信息：`);
        console.error(TAG, `   - 响应包长度: ${finalAckLength} 字节`);
        console.error(TAG, `   - 响应类型字段: ${ackType}`);
        console.error(TAG, `   - 响应长度字段: ${ackLength}`);
        console.error(TAG, `💡 这可能表示：`);
        console.error(TAG, `   1. 相机使用了非标准的 PTP/IP 协议`);
        console.error(TAG, `   2. 网络数据损坏`);
        console.error(TAG, `   3. 相机固件版本不兼容`);
        return false;
      }
    } catch (error) {
      console.error(TAG, `❌【sendInitCommandRequest】异常：${JSON.stringify(error)}`);
      console.error(TAG, `❌ 错误堆栈：${(error as Error).stack}`);
      return false;
    }
  }

  private sleep(ms: number): Promise<void> {
    return new Promise((resolve: () => void) => {
      setTimeout((): void => {
        resolve();
      }, ms);
    });
  }

  getSessionId(): number {
    return this.sessionId === 0 ? 1 : this.sessionId;
  }

  getConnectionNumber(): number {
    return this.connectionNumber;
  }

  isConnected(): boolean {
    return this.connectionState === ConnectionState.SessionOpened;
  }

  private async executeSimpleSessionExperiment(sessionId: number): Promise<boolean> {
    const totalCases = this.simpleSessionExperimentCases.length;
    const openSessionTransactionId = 0;

    for (let index = 0; index < totalCases; index++) {
      const experimentCase = this.simpleSessionExperimentCases[index];
      this.activeClientProfileIndex = experimentCase.profileIndex;
      const profile = this.getCurrentClientProfile();
      const casePrefix = `【PtpConnectionManager】[Case ${index + 1}/${totalCases}] ${experimentCase.label}`;

      if (experimentCase.reuseCurrentConnection) {
        console.info(TAG, `${casePrefix}：复用当前已握手的 15740 命令连接`);
      } else {
        console.info(TAG, `${casePrefix}：重建新的 15740 命令连接并重新握手`);
        const reconnected = await this.reconnectCommandChannel();
        if (!reconnected) {
          console.warn(TAG, `${casePrefix}：无法完成重建连接或重新握手，继续下一个实验`);
          continue;
        }
      }

      this.commandTransportMode = experimentCase.transportMode;
      console.info(TAG, `${casePrefix}：客户端身份=${profile.label}, deviceName=${profile.deviceName === '' ? '<empty>' : profile.deviceName}, transport=${experimentCase.transportMode}, Connection Number=${this.connectionNumber}`);

      try {
        const response = experimentCase.transportMode === 'raw'
          ? await this.sendRawCommandWithTransaction(PtpOperationCode.OpenSession, openSessionTransactionId, [sessionId])
          : await this.sendPtpIpCommandWithTransaction(PtpOperationCode.OpenSession, openSessionTransactionId, [sessionId]);

        if (response.code === PtpResponseCode.OK) {
          this.connectionState = ConnectionState.SessionOpened;
          this.lastFailureReason = '';
          console.info(TAG, `✅ ${casePrefix}：OpenSession 成功；本轮不主动建立事件连接`);
          return true;
        }

        console.warn(TAG, `${casePrefix}：OpenSession 收到非 OK 响应码 0x${response.code.toString(16)}`);
      } catch (error) {
        console.warn(TAG, `${casePrefix}：OpenSession 未收到有效响应：${JSON.stringify(error)}`);
      }
    }

    this.lastFailureReason = '已连接到相机端口并完成握手，但所有 15740 单通道 OpenSession 实验均未获得有效响应';
    console.error(TAG, `❌ 【PtpConnectionManager】${this.lastFailureReason}`);
    return false;
  }

  private async reconnectCommandChannel(): Promise<boolean> {
    try {
      console.info(TAG, `【reconnectCommandChannel】重建命令连接用于兼容模式切换...`);

      if (this.eventSocket) {
        try {
          await this.eventSocket.close();
        } catch {
        }
        this.eventSocket = null;
      }

      if (this.tcpSocket) {
        try {
          await this.tcpSocket.close();
        } catch {
        }
        this.tcpSocket = null;
      }

      this.commandReadBuffer = new Uint8Array(0);
      this.eventReadBuffer = new Uint8Array(0);
      this.connectionState = ConnectionState.Connecting;
      this.currentTransactionId = 0;
      this.sessionId = 0;
      this.connectionNumber = 0;
      this.eventConnectionInitialized = false;
      this.commandTransportMode = 'ptpip';

      this.tcpSocket = socket.constructTCPSocketInstance();
      if (!this.tcpSocket) {
        console.error(TAG, `❌【reconnectCommandChannel】创建命令 Socket 失败`);
        return false;
      }

      await this.connectToHost(this.ipAddress, this.port);
      this.connectionState = ConnectionState.Connected;
      await this.sleep(200);
      const handshakeSuccess = await this.sendInitCommandRequest();
      if (!handshakeSuccess) {
        const profile = this.getCurrentClientProfile();
        this.lastFailureReason = `重建 15740 命令连接后握手失败：${profile.label}`;
      }
      return handshakeSuccess;
    } catch (error) {
      this.lastFailureReason = '重建 15740 命令连接失败';
      console.error(TAG, `❌【reconnectCommandChannel】重建命令连接失败：${JSON.stringify(error)}`);
      return false;
    }
  }

  private getCurrentClientProfile(): ClientIdentityProfile {
    return this.clientProfiles[this.activeClientProfileIndex];
  }

  private async tryNextClientProfile(): Promise<boolean> {
    if (this.activeClientProfileIndex >= this.clientProfiles.length - 1) {
      return false;
    }

    this.activeClientProfileIndex += 1;
    const profile = this.getCurrentClientProfile();
    console.warn(TAG, `⚠️【tryNextClientProfile】切换到下一个 Nikon 客户端身份：${profile.label}, deviceName=${profile.deviceName === '' ? '<empty>' : profile.deviceName}`);
    return await this.reconnectCommandChannel();
  }
}

// 导出单例实例
export const ptpConnectionManager = new PtpConnectionManager();
