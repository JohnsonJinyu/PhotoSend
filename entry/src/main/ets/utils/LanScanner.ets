import socket from '@ohos.net.socket';
import connection from '@ohos.net.connection';
import promptAction from '@ohos.promptAction';
import wifiManager from '@ohos.enterprise.wifiManager';


const TARGET_PORT = 55740; // 目标端口（PTPIP默认端口）
const CONNECT_TIMEOUT = 200; // 超时时间（毫秒）
const CONCURRENT_LIMIT = 5; // 并发扫描数量（避免过多连接导致系统限制）

let localIP = '' //本机IP
let cameraIP = '' // camera IP address


export default class LanScanner {
  // 获取本机IP地址，解析局域网网段（如192.168.1.）

  // 常见相机IP的最后一段（可根据品牌补充，如佳能、索尼常用1或100）
  //const candidateLastParts = [1, 100, 101, 254];


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
}