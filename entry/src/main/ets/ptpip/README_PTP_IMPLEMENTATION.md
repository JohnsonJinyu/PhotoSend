# PTP/IP 协议实现指南

## 概述

本项目已搭建完整的 PTP/IP 协议框架，但部分协议解析细节需要根据 CIPA DC-X005-2005 标准完善。本文档将指导你完成剩余工作。

## 已完成的核心功能

✅ **PTP/IP 协议常量定义** (`PtpConstants.ets`)
- 操作码、响应码、对象格式代码等
- 数据类型定义
- 尼康扩展命令

✅ **数据结构定义** (`PtpTypes.ets`)
- 设备信息、存储信息、对象信息等接口
- 照片元数据、下载进度等业务数据结构

✅ **连接管理器** (`PtpConnectionManager.ets`)
- TCP Socket 建立
- PTP 会话管理
- 命令发送与响应接收
- 事务 ID 管理

✅ **高层客户端 API** (`PtpClient.ets`)
- 相机连接/断开
- 异步照片扫描
- 分页加载
- 照片下载
- 缩略图获取

✅ **工具类** (`CameraUtils.ets`)
- 单例模式封装
- 便捷的相机管理接口

## 需要完善的部分

### 1. 二进制数据解析（关键）

#### 位置：`PtpConnectionManager.ets` - `parseResponse()` 方法

**任务**: 解析 PTP 响应包中的参数和数据

**参考**: 
- CIPA DC-X005-2005 标准第 5.3 节
- ptp.js 的 `parseDataPacket()` 函数

**示例代码**:
```typescript
private parseDeviceInfo(data: ArrayBuffer): PtpDeviceInfo {
  const view = new DataView(data);
  let offset = 0;
  
  // 读取标准版本 (UINT16)
  const standardVersion = view.getUint16(offset, true);
  offset += 2;
  
  // 读取厂商扩展 ID (UINT32)
  const vendorExtensionId = view.getUint32(offset, true);
  offset += 4;
  
  // ... 继续解析其他字段
  
  return {
    standardVersion,
    vendorExtensionId,
    // ...
  };
}
```

#### 位置：`PtpClient.ets` - `getObjectHandles()` 方法

**任务**: 解析 GetObjectHandles 返回的句柄数组

**协议格式**:
```
StorageID (4 bytes)
ObjectFormatCode (2 bytes)
AssociationType (2 bytes)
NumHandles (4 bytes)
Handles [NumHandles * 4 bytes]
```

**示例代码**:
```typescript
private async getObjectHandles(storageId: number): Promise<number[]> {
  const response = await this.sendCommand(
    PtpOperationCode.GetObjectHandles,
    [storageId, 0, 0]
  );
  
  // 从响应数据中解析句柄数组
  const data = await this.readData();  // 需要实现 DataBlock 读取
  const view = new DataView(data);
  
  const numHandles = view.getUint32(0, true);
  const handles: number[] = [];
  
  for (let i = 0; i < numHandles; i++) {
    const handle = view.getUint32(4 + i * 4, true);
    handles.push(handle);
  }
  
  return handles;
}
```

### 2. DataBlock 数据包读取

**位置**: `PtpConnectionManager.ets` - 添加新方法

**任务**: 处理大数据量的分块传输（如照片数据）

**参考**: gPhoto2 PTP/IP 文档的 "Data Transfer" 章节

**实现思路**:
```typescript
async readData(): Promise<ArrayBuffer> {
  // 1. 读取 StartDataPacket
  const header = await this.readBytes(12);
  
  // 2. 解析数据长度
  const totalLength = new DataView(header).getUint32(0, true);
  
  // 3. 循环读取所有 DataBlock
  const chunks: ArrayBuffer[] = [];
  let receivedBytes = 0;
  
  while (receivedBytes < totalLength) {
    const blockHeader = await this.readBytes(8);
    const blockType = new DataView(blockHeader).getUint16(4, true);
    const blockLength = new DataView(blockHeader).getUint32(0, true);
    
    if (blockType === PtpIpPacketType.DataBlock) {
      const data = await this.readBytes(blockLength - 8);
      chunks.push(data);
      receivedBytes += data.byteLength;
    } else if (blockType === PtpIpPacketType.EndOfBlock) {
      break;
    }
  }
  
  // 4. 合并所有数据块
  return this.mergeArrayBuffers(chunks);
}

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
```

### 3. 对象信息解析

**位置**: `PtpClient.ets` - `getObjectInfo()` 方法

**协议格式** (GetObjectInfo):
```
StorageID (4)
ObjectFormatCode (2)
ProtectionStatus (2)
ObjectCompressedSize (4)
ThumbFormatCode (2)
ThumbCompressedSize (4)
ThumbPixWidth (4)
ThumbPixHeight (4)
ImagePixWidth (4)
ImagePixHeight (4)
ImageBitDepth (4)
ParentObject (4)
AssociationType (2)
AssociationDesc (4)
SequenceNumber (4)
Filename (string)
DateTimeCreated (string)
DateTimeModified (string)
Keywords (string)
```

**字符串读取函数**:
```typescript
private readString(view: DataView, offset: { value: number }): string {
  const length = view.getUint16(offset.value, true);
  offset.value += 2;
  
  if (length <= 2) {
    return '';
  }
  
  const chars: string[] = [];
  for (let i = 0; i < length - 2; i++) {
    const charCode = view.getUint16(offset.value + i * 2, true);
    if (charCode !== 0) {
      chars.push(String.fromCharCode(charCode));
    }
  }
  
  offset.value += length;
  return chars.join('');
}
```

### 4. 文件保存

**位置**: `PtpClient.ets` - `downloadPhoto()` 方法

**任务**: 使用 HarmonyOS 文件 API 保存照片

**示例代码**:
```typescript
import { fileIo } from '@kit.IO.FileIOKit';

async downloadPhoto(objectId: number, savePath: string): Promise<boolean> {
  try {
    // 1. 发送 GetObject 命令
    const response = await this.sendCommand(PtpOperationCode.GetObject, [objectId]);
    
    if (response.code !== PtpResponseCode.OK) {
      return false;
    }
    
    // 2. 读取照片数据
    const photoData = await this.readData();
    
    // 3. 写入文件
    const file = fileIo.openSync(savePath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY);
    fileIo.writeSync(file.fd, photoData);
    fileIo.closeSync(file);
    
    return true;
  } catch (error) {
    console.error(TAG, `下载失败：${JSON.stringify(error)}`);
    return false;
  }
}
```

### 5. 缩略图数据处理

**位置**: `PtpClient.ets` - `getThumbnail()` 方法

**任务**: 将缩略图数据转换为 Image 组件可用的 Resource

**示例代码**:
```typescript
async getThumbnail(objectId: number): Promise<Resource | null> {
  try {
    const thumbData = await this.getThumbnailData(objectId);
    
    if (!thumbData) {
      return null;
    }
    
    // 创建临时文件
    const tempPath = `${this.cacheDir}/thumb_${objectId}.jpg`;
    await this.saveToFile(thumbData, tempPath);
    
    // 加载为 Resource
    return resourceManager.getMediaById(tempPath);
  } catch (error) {
    console.error(TAG, `获取缩略图失败：${JSON.stringify(error)}`);
    return null;
  }
}
```

## 调试建议

### 1. 使用 Wireshark 抓包分析

在 PC 上使用 Wireshark 抓取 PTP/IP 流量:
```
过滤条件：tcp.port == 15740
```

对比官方客户端和你的实现，查看:
- 命令序列是否正确
- 数据包格式是否匹配
- 响应内容是否符合预期

### 2. 日志输出

在关键位置添加详细日志:
```typescript
console.info(TAG, `发送命令：0x${operationCode.toString(16)}, TID=${transactionId}`);
console.info(TAG, `收到响应：0x${response.code.toString(16)}`);
console.info(TAG, `数据长度：${data.byteLength} bytes`);
```

### 3. 错误处理

完善的错误处理:
```typescript
if (response.code !== PtpResponseCode.OK) {
  const errorMsg = this.getErrorMessage(response.code);
  console.error(TAG, `PTP 错误：${errorMsg} (${response.code})`);
  throw new Error(errorMsg);
}
```

## 参考资源

### 协议文档
- [CIPA DC-X005-2005](https://cipa.jp/std/documents/e/DC-X005.pdf) - PTP/IP 官方标准
- [gPhoto2 PTP/IP](http://gphoto.org/doc/ptpip.php) - 简化版说明

### 开源实现
- [ptp.js](https://github.com/feklee/ptp.js) - JavaScript 实现（最清晰）
- [ptpip](https://github.com/mmattes/ptpip) - Python 实现

### 尼康相机默认 IP
- 大多数尼康相机：**192.168.1.1**
- 端口号：**15740**

## 下一步行动

1. **优先实现数据解析**: 先让 GetObjectHandles 和 GetObjectInfo 正常工作
2. **测试照片下载**: 确保能正确接收并保存 JPEG 文件
3. **优化性能**: 添加缓存机制、并发控制
4. **完善 UI**: 替换原有 Native 调用为纯 ArkTS 实现
5. **清理 C++ 代码**: 移除所有 libgphoto2 相关代码

## 常见问题

**Q: 连接超时怎么办？**
A: 增加超时时间到 10 秒，检查相机是否处于正确的传输模式

**Q: 响应码 0x2019 (DeviceBusy)?**
A: 相机正忙，稍等几秒后重试

**Q: 如何知道相机的 IP?**
A: 在相机 WiFi 设置中查看，或使用网络扫描工具

---

祝你开发顺利！如有问题，欢迎查阅上述参考资料。
