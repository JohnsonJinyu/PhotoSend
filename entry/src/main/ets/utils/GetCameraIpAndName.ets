import socket from '@ohos.net.socket';
import connection from '@ohos.net.connection';
import promptAction from '@ohos.promptAction';
import wifiManager from '@ohos.enterprise.wifiManager';
import { BusinessError } from '@kit.BasicServicesKit';
import  TextDecoder  from '@ohos.util'; // 导入鸿蒙的TextDecoder

const TARGET_PORT = 15740; // 目标端口（PTPIP默认端口）
const CONNECT_TIMEOUT = 5000; // 超时时间（毫秒）
const CONCURRENT_LIMIT = 5; // 并发扫描数量（避免过多连接导致系统限制）

let localIP = '' //本机IP
let cameraIP = '' // camera IP address
let cameraName = ''


/**
 * 尼康相机信息实体类
 */
interface NikonCameraInfo {
  model: string; // 型号（如"Nikon Z7 II"）
  ip: string;    // IP地址（如"192.168.1.1"）
  port: number;  // 端口（默认15740）
}


export default class LanScanner {
  // 获取本机IP地址，解析局域网网段（如192.168.1.）

  // 常见相机IP的最后一段（可根据品牌补充，如佳能、索尼常用1或100）
  //const candidateLastParts = [1, 100, 101, 254];


  // PTP协议常量（参考PTP/IP规范）
  private static readonly PTP_OPCODE_GET_DEVICE_INFO = 0x1001; // 获取设备信息命令
  private static readonly PTP_RESPONSE_OK = 0x2001; // 命令成功响应
  private static readonly PTP_PACKET_TYPE_COMMAND = 0x0002; // 命令包类型
  private static readonly PTP_PACKET_TYPE_RESPONSE = 0x0003; // 响应包类型

  /**
   * 获取本机所在网段（如192.168.1.）
   * 手机连接相机热点时，通常只有一个IPv4地址，直接提取即可
   */
  public async getLocalSubnet(): Promise<string | null> {
    try {
      // 1. 获取默认网络句柄（相机热点网络）
      const netHandle = await connection.getDefaultNet();
      if (netHandle.netId === 0) {
        console.error('未连接到任何网络');
        return null;
      }

      // 2. 获取该网络的属性（含IP地址）
      const connProps = await connection.getConnectionProperties(netHandle);
      if (!connProps.linkAddresses || connProps.linkAddresses.length === 0) {
        console.error('未获取到IP地址信息');
        return null;
      }

      // 3. 提取第一个IPv4地址（热点场景下通常只有一个）
      let ipv4: string | null = null;
      for (const addr of connProps.linkAddresses) {
        if (addr.address.family === 1) { // family=1 是IPv4
          ipv4 = addr.address.address;
          break; // 找到第一个即退出
        }
      }

      if (!ipv4) {
        console.error('未找到IPv4地址');
        return null;
      }

      // 4. 保存本机IP并提取网段（前三位）
      localIP = ipv4;
      const ipParts = ipv4.split('.');
      if (ipParts.length !== 4) { // 校验IP格式
        console.error('IP地址格式错误:', ipv4);
        return null;
      }
      const subnet = `${ipParts[0]}.${ipParts[1]}.${ipParts[2]}.`;
      cameraIP = `${subnet}1`
      console.log(`本机IP: ${localIP}，网段: ${subnet},相机IP：${cameraIP}`);

      // 返回相机IP
      return cameraIP;

    } catch (err) {
      console.error('获取网段失败:', JSON.stringify(err));
      return null;
    }
  }

  /**
   * 通过PTP/IP获取相机名称
   * @param cameraIP 相机IP地址
   * @returns 相机名称（品牌+型号）或null
   */

  public async getCameraName(cameraIP:string):Promise<string|null>{
    let tcpSocket:socket.TCPSocket | null = null
    try {
      // 1、创建TCP socket并连接相机
      tcpSocket = socket.constructTCPSocketInstance()
      let camAddr:socket.NetAddress= {
        address: cameraIP,
        port:TARGET_PORT
      }
      let tcpConnectOptions:socket.TCPConnectOptions={
        address:camAddr,
        timeout: CONNECT_TIMEOUT
      }

      // 关键修改：等待连接成功（替换原回调式connect）
      await this.connectSocket(tcpSocket, camAddr); // 这里会等待连接完成，成功后才继续



      //2、发送PTP初始化命令（简化版握手）
      const intBuffer = this.constructInitCommand();
      await tcpSocket.send({data:intBuffer})

      //3、接受初始化响应（验证连接有效性）
      const initResponse = await this.receiveData(tcpSocket)
      if (!this.verifyInitResponse(initResponse)) {
        console.error('相机初始化响应验证失败');
        return null;
      }

      // 4. 发送获取设备信息命令
      const cmdBuffer = this.constructGetDeviceInfoCommand();
      await tcpSocket.send({ data: cmdBuffer });


      // 5. 接收设备信息响应
      const deviceInfoResponse = await this.receiveData(tcpSocket);
      const cameraName = this.parseDeviceInfo(deviceInfoResponse);


      console.log('cameraName:',cameraName);
      return cameraName || '未知相机';






    }catch (err) {
      // 关键：打印错误码、错误描述，而非stringify
      const businessErr = err as BusinessError;
      console.error(`获取相机名称失败：错误码=${businessErr.code}，描述=${businessErr.message}`);
      // 同时打印原始错误，辅助排查
      console.error(`原始错误信息:`, businessErr);
      return null;
    }finally {
      // 确保连接关闭
      if (tcpSocket) {
        await tcpSocket.close();
        console.log('已关闭与相机的连接');
      }
    }

    return cameraName
  }



  /**
   * 构造PTP初始化命令（PTP/IP握手包）
   */
  constructInitCommand(): ArrayBuffer {
    // 标准PTP/IP INIT_CMD包长度：24字节（必须严格匹配）
    const buffer = new ArrayBuffer(24);
    const view = new DataView(buffer);

    // 1. 包类型：INIT_CMD（0x0001，Uint16，大端）- 索引0-1（2字节）
    view.setUint16(0, 0x0001, false);
    // 2. 包总长度：24字节（Uint32，大端）- 索引2-5（4字节）
    view.setUint32(2, 24, false);
    // 3. PTP版本号：1.0（0x0100，Uint16，大端）- 索引6-7（2字节）
    view.setUint16(6, 0x0100, false);
    // 4. 操作码：INIT_CMD（0x0001，Uint16，大端）- 索引8-9（2字节）
    view.setUint16(8, 0x0001, false);
    // 5. 会话ID：初始会话为0（Uint32，大端）- 索引10-13（4字节）
    view.setUint32(10, 0x00000000, false);
    // 6. 最大数据包大小：16KB（0x4000，Uint32，大端）- 索引14-17（4字节）
    view.setUint32(14, 0x4000, false);
    // 7. 设备GUID（随机值，2个Uint32，共8字节）- 索引18-21、22-25？不！22+4=26超24，需调整：
    // 正确分布：将“最大数据包大小”改为索引12-15，腾出空间给GUID
    // 重新对齐后，确保最后一个字段索引+4=24：
    view.setUint32(12, 0x4000, false); // 修正：最大数据包大小移到12-15（4字节）
    view.setUint32(16, Math.floor(Math.random() * 0xFFFFFFFF), false); // GUID1：16-19（4字节）
    view.setUint32(20, Math.floor(Math.random() * 0xFFFFFFFF), false); // GUID2：20-23（4字节）

    // 验证：最后一个字段索引20 + 4 = 24，刚好填满24字节
    return buffer;
  }



  /**
   * 验证初始化响应
   */
  private verifyInitResponse(data: ArrayBuffer): boolean {
    if (data.byteLength < 10) return false;
    const view = new DataView(data);
    // 验证响应类型为INIT_ACK (0x0002)
    return view.getUint16(0, false) === 0x0002;
  }


  /**
   * 构造获取设备信息的PTP命令
   */
  private constructGetDeviceInfoCommand(): ArrayBuffer {
    const buffer = new ArrayBuffer(12);
    const view = new DataView(buffer);

    // 包类型：命令包 (0x0002)
    view.setUint16(0, LanScanner.PTP_PACKET_TYPE_COMMAND, false);
    // 包长度
    view.setUint32(2, 12, false);
    // 事务ID（唯一标识，可递增）
    view.setUint32(6, Date.now() % 0xFFFFFFFF, false);
    // 操作码：获取设备信息
    view.setUint16(10, LanScanner.PTP_OPCODE_GET_DEVICE_INFO, false);

    return buffer;
  }



  /**
   * 从socket接收数据（处理分块）
   */
  private async receiveData(tcpSocket: socket.TCPSocket): Promise<ArrayBuffer> {
    return new Promise((resolve, reject) => {
      const chunks: Uint8Array[] = [];
      let totalExpectedLength = 0;

      tcpSocket.on('message', (data) => {
        const chunk = new Uint8Array(data.message);
        chunks.push(chunk);
        console.log(`收到相机数据：${chunk.length}字节，累计：${chunks.reduce((s,c)=>s+c.length,0)}字节`);

        // 1. 先读包总长度（PTP包第2-5字节，4字节大端）
        if (totalExpectedLength === 0 && chunks.reduce((s,c)=>s+c.length,0) >= 4) {
          const tempBuffer = new Uint8Array(chunks.reduce((s,c)=>s+c.length,0));
          totalExpectedLength = new DataView(tempBuffer.buffer).getUint32(2, false);
          console.log(`解析出预期数据长度：${totalExpectedLength}字节`);
        }

        // 2. 只要累计长度 >= 预期长度，就认为数据完整（无论长度大小）
        const currentTotal = chunks.reduce((s,c)=>s+c.length,0);
        if (totalExpectedLength > 0 && currentTotal >= totalExpectedLength) {
          const finalBuffer = new Uint8Array(totalExpectedLength);
          let offset = 0;
          chunks.forEach(c => {
            const copyLen = Math.min(c.length, totalExpectedLength - offset);
            finalBuffer.set(c.subarray(0, copyLen), offset);
            offset += copyLen;
          });
          console.log(`接收完整数据：${finalBuffer.length}字节`);
          resolve(finalBuffer.buffer);
          tcpSocket.off('message');
        }
      });

      tcpSocket.on('error', (err) => {
        console.error('接收数据错误:', err);
        reject(err);
      });
      setTimeout(() => {
        reject(new Error(`接收数据超时（${CONNECT_TIMEOUT}ms）`));
      }, CONNECT_TIMEOUT);
    });
  }


  /**
   * 解析设备信息响应，提取相机名称
   */
  private parseDeviceInfo(data: ArrayBuffer): string | null {
    try {
      const view = new DataView(data);
      // 验证响应类型和状态
      if (view.getUint16(0, false) !== LanScanner.PTP_PACKET_TYPE_RESPONSE) {
        console.error('不是响应包');
        return null;
      }
      if (view.getUint16(10, false) !== LanScanner.PTP_RESPONSE_OK) {
        console.error('命令执行失败');
        return null;
      }

      // 设备信息从响应包的第12字节开始
      let offset = 12;

      // 跳过标准版本、厂商扩展版本等固定字段（各4字节）
      offset += 4; // 标准版本
      offset += 4; // 厂商扩展版本
      offset += 4; // 厂商ID
      offset += 4; // 产品ID
      offset += 4; // 设备版本
      offset += 4; // 序列号

      // 读取厂商名称（null结尾的UTF-8字符串）
      const manufacturer = this.readNullTerminatedString(data, offset);
      offset += manufacturer.length + 1; // +1跳过null终止符

      // 读取模型名称（相机型号）
      const model = this.readNullTerminatedString(data, offset);

      // 组合品牌+型号作为相机名称
      return `${manufacturer} ${model}`.trim() || null;

    } catch (e) {
      console.error('解析设备信息失败:', e);
      return null;
    }
  }


  /**
   * 读取以null结尾的UTF-8字符串
   */
  private readNullTerminatedString(buffer: ArrayBuffer, offset: number): string {
    const bytes = new Uint8Array(buffer);
    let end = offset;
    // 找到null终止符
    while (end < bytes.length && bytes[end] !== 0) {
      end++;
    }
    // 解码UTF-8字符串
    //return new TextDecoder.TextDecoder('utf-8').decode(bytes.subarray(offset, end));
    return TextDecoder.TextDecoder.create('utf-8').decodeToString(bytes.subarray(offset, end));
  }

  /**
   * 封装 TCP 连接为 Promise，确保连接成功后再返回
   */
  private async connectSocket(tcpSocket: socket.TCPSocket, camAddr: socket.NetAddress): Promise<void> {
    return new Promise((resolve, reject) => {
      const tcpConnectOptions: socket.TCPConnectOptions = {
        address: camAddr,
        timeout: CONNECT_TIMEOUT // 使用定义的超时时间
      };
      // 执行连接
      tcpSocket.connect(tcpConnectOptions, (err: BusinessError) => {
        if (err) {
          console.error(`连接相机 ${camAddr.address}:${camAddr.port} 失败:`, err);
          reject(err); // 连接失败，通过 Promise 抛出错误
          return;
        }
        console.log(`已成功连接到相机 ${camAddr.address}:${camAddr.port}`);
        resolve(); // 连接成功，继续后续操作
      });
    });
  }






  /**
   * 通过mDNS发现尼康相机并获取型号
   * @param timeout 超时时间（毫秒）
   * @returns 相机信息或null
   */
  async discoverNikonByMDNS(timeout: number = 5000): Promise<NikonCameraInfo | null>{


    return null
  }













}