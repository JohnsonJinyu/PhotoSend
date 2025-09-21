import wifiManager from '@ohos.wifiManager';
import http from '@ohos.net.http';
import socket from '@ohos.net.socket';
import { BusinessError } from '@ohos.base';

/**
 * 连接模式类型定义
 */
type ConnectionMode = 'Bluetooth' | 'WiFi-AP' | 'WiFi-STA';


interface ResultObj{
  success:boolean;
  ip:string|null;
}


/**
 * Nikon相机工具类，封装与相机交互的底层逻辑
 * 功能模块：
 * 1. 设备识别模块 - 检测并识别Nikon相机
 * 2. 连接管理模块 - 处理与相机的连接/断连状态检测
 * 3. 功能执行模块 - 提供相机控制功能
 * 4. 通用工具模块 - 提供辅助功能
 */
export class NikonCameraKitUtil {
  /** 尼康相机AP模式下的默认IP（主流型号通用） */
  private static readonly NIKON_AP_DEFAULT_IPS: string[] = ['192.168.1.1', '192.168.0.1'];
  /** 尼康相机开放的特征端口（控制+HTTP服务） */
  private static readonly NIKON_FEATURE_PORTS: number[] = [5573, 80];
  /** 尼康相机HTTP信息接口（不同型号可能有差异，需兼容） */
  private static readonly NIKON_INFO_ENDPOINTS: string[] = [
    '/nikon_camera_info.json', // 新型号标准接口
    '/camera_info.xml',        // 旧型号兼容接口
    '/'                        //  fallback：解析首页HTML
  ];

  /** 当前连接的相机IP */
  private currentCameraIp: string | null = null;
  /** 当前连接模式 */
  private currentConnectionMode: ConnectionMode | null = null;

  /**
   * 设备识别：检测是否是Nikon相机（基于当前系统连接状态）
   * @param connectionMode 连接模式
   * @returns 是否为Nikon相机
   */
  public async detectCameraDevice(connectionMode: ConnectionMode): Promise<boolean> {
    let isNikonDevice = false;

    try {
      switch (connectionMode) {
        case 'Bluetooth':
          isNikonDevice = await this.detectBluetoothMode();
          break;
        case 'WiFi-AP':
          isNikonDevice = await this.detectWiFiAPMode();
          break;
        case 'WiFi-STA':
          isNikonDevice = await this.detectWiFiSTAMode();
          break;
        default:
          console.error(`不支持的连接模式: ${connectionMode}`);
          return false;
      }

      // 更新连接状态
      if (isNikonDevice) {
        this.currentConnectionMode = connectionMode;
      } else {
        if (this.currentConnectionMode === connectionMode) {
          this.currentConnectionMode = null;
          this.currentCameraIp = null;
        }
      }

      return isNikonDevice;
    } catch (err) {
      const error = err as BusinessError;
      console.error(`设备检测失败: ${error.code} - ${error.message}`);
      return false;
    }
  }

  /**
   * 连接状态检查：检查是否已连接到Nikon相机
   * @param connectionMode 连接模式
   * @returns 是否连接成功
   */
  public async checkConnectionStatus(connectionMode: ConnectionMode): Promise<boolean> {
    try {
      return await this.detectCameraDevice(connectionMode);
    } catch (err) {
      const error = err as BusinessError;
      console.error(`连接状态检查失败: ${error.code} - ${error.message}`);
      return false;
    }
  }

  /**
   * 连接管理：断开与Nikon相机的连接（仅更新状态，实际断开由系统管理）
   * @returns 是否成功更新状态
   */
  public disconnectFromCamera(): boolean {
    this.currentConnectionMode = null;
    this.currentCameraIp = null;
    return true;
  }

  /**
   * 功能执行：拍摄照片
   * @returns 拍摄是否成功
   */
  public async takePhoto(): Promise<boolean> {
    if (!this.currentCameraIp || !this.currentConnectionMode) {
      console.error('未连接到相机，无法执行拍摄');
      return false;
    }

    try {
      // 通过HTTP接口触发拍摄（兼容尼康相机API）
      const url = `http://${this.currentCameraIp}/nikon/take_photo`;
      const httpRequest = http.createHttp();

      const response = await httpRequest.request(url, {
        method: http.RequestMethod.POST,
        connectTimeout: 5000,
        readTimeout: 10000
      });

      httpRequest.destroy();
      return response.responseCode === 200;
    } catch (err) {
      const error = err as BusinessError;
      console.error(`拍摄失败: ${error.code} - ${error.message}`);
      return false;
    }
  }

  /**
   * WiFi-AP模式下检测是否为尼康相机
   * @returns 验证结果（true=是尼康相机，false=不是）
   */
  private async detectWiFiAPMode(): Promise<boolean> {
    try {
      // 步骤1：检查当前WiFi是否处于AP连接状态
      const isApConnected = await this.checkWifiApConnectionStatus();
      if (!isApConnected) {
        console.log('WiFi-AP模式：未连接到相机热点');
        return false;
      }

      // 步骤2：检测尼康特征端口
      const portCheckResult = await this.checkNikonFeaturePorts();
      if (!portCheckResult.success) {
        console.log('WiFi-AP模式：未检测到尼康特征端口');
        return false;
      }

      // 记录检测到的相机IP
      this.currentCameraIp = portCheckResult.ip;

      // 步骤3：通过HTTP接口验证设备身份
      const isNikonDevice = await this.verifyNikonIdentityByHttp();
      return isNikonDevice;

    } catch (err) {
      const error = err as BusinessError;
      console.error(`WiFi-AP模式检测失败：${error.code} - ${error.message}`);
      return false;
    }
  }

  /**
   * 蓝牙模式下检测是否为尼康相机
   * @returns 验证结果
   */
  private async detectBluetoothMode(): Promise<boolean> {
    try {
      console.log('蓝牙模式检测：检查是否连接到尼康设备');
      // 实际项目中应添加蓝牙设备检测逻辑
      return false;
    } catch (err) {
      const error = err as BusinessError;
      console.error(`蓝牙模式检测失败：${error.code} - ${error.message}`);
      return false;
    }
  }

  /**
   * WiFi-STA模式下检测是否为尼康相机
   * @returns 验证结果
   */
  private async detectWiFiSTAMode(): Promise<boolean> {
    try {
      console.log('WiFi-STA模式检测：开始扫描局域网内尼康设备');

      // 步骤1：获取当前网络信息
      const wifiInfo = await wifiManager.getLinkedInfo();
      if (!wifiInfo) {
        console.log('未连接到WiFi网络');
        return false;
      }

      // 步骤2：解析本地IP，生成可能的网段
      const localIp = this.intToIp(wifiInfo.ipAddress);
      const subnet = localIp.substring(0, localIp.lastIndexOf('.'));

      // 步骤3：扫描同一网段的常见相机IP（简化版）
      const candidateIps: string[] = [
        `${subnet}.1`,   // 常见网关IP
        `${subnet}.100`, // 常见设备IP
        `${subnet}.101`  // 常见设备IP
      ];

      // 合并默认IP和网段内IP进行检测
      const allIps: string[] = NikonCameraKitUtil.NIKON_AP_DEFAULT_IPS.concat(candidateIps);

      // 步骤4：检测这些IP上的尼康特征端口
      for (const ip of allIps) {
        for (const port of NikonCameraKitUtil.NIKON_FEATURE_PORTS) {
          const isOpen = await this.checkTcpPort(ip, port);
          if (isOpen) {
            this.currentCameraIp = ip;
            // 验证设备身份
            const isNikonDevice = await this.verifyNikonIdentityByHttp();
            if (isNikonDevice) {
              return true;
            }
          }
        }
      }

      return false;
    } catch (err) {
      const error = err as BusinessError;
      console.error(`WiFi-STA模式检测失败：${error.code} - ${error.message}`);
      return false;
    }
  }

  /**
   * 检查当前是否连接到相机热点（而非路由器）
   * @returns 检查结果
   */
  private async checkWifiApConnectionStatus(): Promise<boolean> {
    try {
      // 获取当前WiFi连接信息（API 20兼容）
      const wifiInfo = await wifiManager.getLinkedInfo();
      if (!wifiInfo || !wifiInfo.ssid) {
        return false; // 未连接WiFi
      }

      // 检查SSID是否可能是尼康相机（通常包含Nikon字样）
      const ssid = wifiInfo.ssid.toLowerCase();
      const isNikonSsid = ssid.includes('nikon') ||
      ssid.includes('尼康') ||
      ssid.includes('dslr') ||
      ssid.includes('coolpix');

      if (!isNikonSsid) {
        return false;
      }

      // 检查手机IP是否在尼康相机常见网段
      const phoneIp = this.intToIp(wifiInfo.ipAddress);
      const isInNikonSubnet = phoneIp.startsWith('192.168.1.') ||
      phoneIp.startsWith('192.168.0.');

      return isInNikonSubnet;
    } catch (err) {
      const error = err as BusinessError;
      console.error(`检查WiFi连接状态失败：${error.code} - ${error.message}`);
      return false;
    }
  }

  /**
   * 检测尼康特征端口（5573控制端口或80 HTTP端口）
   * @returns 检测结果及找到的IP
   */
  private async checkNikonFeaturePorts(): Promise<ResultObj> {
    // 并发检测所有IP和端口组合，提高效率
    const promises: Promise<boolean>[] = NikonCameraKitUtil.NIKON_AP_DEFAULT_IPS.flatMap(ip =>
    NikonCameraKitUtil.NIKON_FEATURE_PORTS.map(port => this.checkTcpPort(ip, port))
    );

    const results = await Promise.all(promises);

    // 查找第一个开放的端口对应的IP
    for (let i = 0; i < results.length; i++) {
      if (results[i]) {
        const ipIndex = Math.floor(i / NikonCameraKitUtil.NIKON_FEATURE_PORTS.length);
        return { success: true, ip: NikonCameraKitUtil.NIKON_AP_DEFAULT_IPS[ipIndex] };
      }
    }

    return { success: false, ip: null };
  }

  /**
   * 通过HTTP接口验证设备身份
   * @returns 验证结果
   */
  private async verifyNikonIdentityByHttp(): Promise<boolean> {
    if (!this.currentCameraIp) {
      return false;
    }

    // 遍历信息接口，确保兼容性
    for (const endpoint of NikonCameraKitUtil.NIKON_INFO_ENDPOINTS) {
      const url = `http://${this.currentCameraIp}${endpoint}`;
      const isNikon = await this.sendHttpIdentityCheck(url);
      if (isNikon) {
        console.log(`WiFi-AP模式：HTTP验证通过，确认是尼康相机`);
        return true;
      }
    }

    return false;
  }

  /**
   * 辅助工具：检测TCP端口是否开放
   * @param ip 目标IP地址
   * @param port 目标端口
   * @param timeout 超时时间(ms)
   * @returns 端口是否开放
   */
  private async checkTcpPort(ip: string, port: number, timeout: number = 3000): Promise<boolean> {
    return new Promise((resolve) => {
      const tcpSocket = socket.constructTCPSocketInstance();
      let isConnected = false;

      // 构建符合TCPConnectOptions类型的参数
      const connectOptions: socket.TCPConnectOptions = {
        address: {
          address: ip,  // IP地址字符串
          port: port    // 端口号
        }
      };

      // 超时处理
      const timer = setTimeout(() => {
        if (!isConnected) {
          tcpSocket.close().catch((err: BusinessError) => {
            console.error(`关闭socket失败: ${err.code} - ${err.message}`);
          });
          resolve(false);
        }
      }, timeout);

      // 连接成功回调
      tcpSocket.on('connect', () => {
        isConnected = true;
        clearTimeout(timer);
        tcpSocket.close().catch((err: BusinessError) => {
          console.error(`关闭socket失败: ${err.code} - ${err.message}`);
        });
        resolve(true);
      });

      // 连接失败回调
      tcpSocket.on('error', (err: BusinessError) => {
        clearTimeout(timer);
        tcpSocket.close().catch((closeErr: BusinessError) => {
          console.error(`关闭socket失败: ${closeErr.code} - ${closeErr.message}`);
        });
        console.error(`连接错误: ${err.code} - ${err.message}`);
        resolve(false);
      });

      // 发起连接
      try {
        tcpSocket.connect(connectOptions);
      } catch (err) {
        const error = err as BusinessError;
        clearTimeout(timer);
        console.error(`发起连接失败: ${error.code} - ${error.message}`);
        resolve(false);
      }
    });
  }


  /**
   * 辅助工具：发送HTTP请求验证设备身份
   * @param url 请求URL
   * @returns 验证结果
   */
  private async sendHttpIdentityCheck(url: string): Promise<boolean> {
    const httpRequest = http.createHttp();
    try {
      const response = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        connectTimeout: 5000,
        readTimeout: 5000
      });

      // 只处理200状态码的响应
      if (response.responseCode !== 200) {
        return false;
      }

      // 响应内容转为字符串（可能是JSON或HTML/XML）
      const responseText = response.result?.toString().toLowerCase() || '';

      // 验证逻辑：包含尼康制造商标识
      const nikonIdentifiers: string[] = ['nikon', '尼康', 'nikon corporation', 'coolpix', 'd3', 'd5', 'd7'];
      return nikonIdentifiers.some(identifier => responseText.includes(identifier));
    } catch {
      return false;
    } finally {
      httpRequest.destroy(); // 销毁请求，避免内存泄漏
    }
  }

  /**
   * 辅助工具：将整数IP转换为字符串格式
   * @param ipInt 整数形式的IP地址
   * @returns 字符串形式的IP地址
   */
  private intToIp(ipInt: number): string {
    return `${(ipInt >>> 24) & 0xFF}.${(ipInt >>> 16) & 0xFF}.${(ipInt >>> 8) & 0xFF}.${ipInt & 0xFF}`;
  }
}
