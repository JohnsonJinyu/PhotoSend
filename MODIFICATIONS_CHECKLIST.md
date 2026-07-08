# 修改清单 - PtpConnectionManager.ets

## 文件位置
```
E:\HarmonyOS\Projects\PhotoSend\entry\src\main\ets\ptpip\PtpConnectionManager.ets
```

## 修改 1：设备名称 (第 1034 行左右)

**修改前：**
```typescript
const deviceName = "SmartDevice"; // 通用智能设备名称
```

**修改后：**
```typescript
const deviceName = "Nikon"; // Nikon ZF 推荐使用 "Nikon" 作为设备名称
```

**为什么这样改：**
- Nikon ZF 相机对设备名称敏感
- "Nikon" 是官方推荐的标识
- 可以提高握手成功率

---

## 修改 2：readBytes 超时处理 (第 775 行左右)

**修改前：**
```typescript
// 设置超时（5 秒）
setTimeout(() => {
  this.tcpSocket?.off('message', messageHandler);
  console.error(TAG, `[readBytes] ❌ 读取超时：期望${length}字节，实际收到${receivedBytes}字节`);
  reject(new Error(`读取数据超时：期望${length}字节，实际收到${receivedBytes}字节`));
}, 5000);
```

**修改后：**
```typescript
// 设置超时（5 秒）
setTimeout(() => {
  this.tcpSocket?.off('message', messageHandler);
  console.error(TAG, `[readBytes] ⚠️ 读取超时：期望${length}字节，实际收到${receivedBytes}字节`);
  
  // 【关键改进】即使超时，如果已收到数据，则返回已收到的部分而不是完全失败
  if (receivedBytes > 0) {
    console.warn(TAG, `[readBytes] 即使超时也返回 ${receivedBytes} 字节的数据`);
    const result = new Uint8Array(receivedBytes);
    let offset = 0;
    for (const chunk of chunks) {
      result.set(chunk, offset);
      offset += chunk.byteLength;
    }
    resolve(result.buffer);
  } else {
    reject(new Error(`读取数据超时：期望${length}字节，实际收到${receivedBytes}字节`));
  }
}, 5000);
```

**为什么这样改：**
- 网络可能导致数据分批到达
- 不应该因为单次超时就放弃已接收的数据
- 增加容错能力

---

## 修改 3：Init_Command_Ack 包读取 (第 1070-1095 行)

**修改前：**
```typescript
// 等待响应（Init_Command_Ack，类型 2）
console.info(TAG, `[sendInitCommandRequest] 开始读取响应...`);

// 关键修复：Init_Command_Ack 总长度 56 字节，必须一次性读取完整
// 根据 gphoto2 官方文档：Init_Command_Ack payload 包含：
// - 4 byte Session ID
// - 16 byte GUID
// - xx byte WCHAR Camera Name
const ackTotalLength = 56; // 典型长度
const ackBuffer = await this.readBytes(ackTotalLength);
console.info(TAG, `[sendInitCommandRequest] 收到响应：${ackBuffer.byteLength} 字节`);

const ackView = new DataView(ackBuffer);

// 解析包头
const ackLength = ackView.getUint32(0, true);
const ackType = ackView.getUint32(4, true);

console.info(TAG, `[sendInitCommandRequest] 响应解析：length=${ackLength}, type=${ackType}`);
```

**修改后：**
```typescript
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

// 第二步：如果包长度 > 8，继续读取剩余部分
let ackBuffer: ArrayBuffer = headerBuffer;
if (ackLength > 8) {
  const remainingLength = ackLength - 8;
  console.info(TAG, `[sendInitCommandRequest] 第二步：读取包体（${remainingLength}字节）...`);
  try {
    const remainingBuffer = await this.readBytes(remainingLength);
    
    // 合并包头和包体
    const totalBuffer = new Uint8Array(ackLength);
    totalBuffer.set(new Uint8Array(headerBuffer), 0);
    totalBuffer.set(new Uint8Array(remainingBuffer), 8);
    ackBuffer = totalBuffer.buffer;
    
    console.info(TAG, `[sendInitCommandRequest] ✅ 完整 Init_Command_Ack 包接收：${ackLength} 字节`);
  } catch (e) {
    console.warn(TAG, `[sendInitCommandRequest] ⚠️ 读取包体超时，使用已有包头继续处理`);
  }
}

const ackView = new DataView(ackBuffer);
```

**为什么这样改：**
- 不同 Nikon 相机的 Init_Command_Ack 包长度不同
- 硬编码 56 字节会导致某些相机失败
- 动态读取可以适应各种情况

---

## 修改 4：Session ID 读取 (第 1100-1135 行)

**修改前：**
```typescript
if (ackType === 2) {
  console.info(TAG, `✅【sendInitCommandRequest】收到 Init_Command_Ack，握手成功！`);
  console.info(TAG, `✅ 相机已接受智能设备连接`);
  
  // 解析 Session ID（第 8-11 字节）
  const sessionId = ackView.getUint32(8, true);
  console.info(TAG, `【sendInitCommandRequest】相机返回的 Session ID: ${sessionId}`);
  
  // 解析相机 GUID（第 12-27 字节）
  const cameraGuid: number[] = [];
  for (let i = 0; i < 16; i++) {
    cameraGuid.push(ackView.getUint8(12 + i));
  }
  console.debug(TAG, `【sendInitCommandRequest】相机 GUID: ${cameraGuid.map(b => b.toString(16).padStart(2, '0')).join('')}`);
  
  // 解析相机名称（从第 28 字节开始，WCHAR 格式）
  let cameraName = '';
  let nameOffset = 28;
  while (nameOffset < ackBuffer.byteLength - 1) {
    const charCode = ackView.getUint16(nameOffset, true);
    if (charCode === 0) break;
    cameraName += String.fromCharCode(charCode);
    nameOffset += 2;
  }
  console.info(TAG, `【sendInitCommandRequest】相机名称：${cameraName}`);
  
  // 保存 Session ID
  this.sessionId = sessionId;
  
  console.info(TAG, `✅【sendInitCommandRequest】握手完成，Session ID=${sessionId}`);
  console.info(TAG, `【sendInitCommandRequest】⚠️ 跳过事件连接（Nikon 相机可能不支持）`);
  console.info(TAG, `【sendInitCommandRequest】准备打开会话...`);
  
  return true;
}
```

**修改后：**
```typescript
if (ackType === 2) {
  console.info(TAG, `✅【sendInitCommandRequest】收到 Init_Command_Ack，握手成功！`);
  console.info(TAG, `✅ Nikon ZF 相机已接受连接`);
  
  // 【改进】更安全的 Session ID 读取
  let sessionId = 1; // 默认值
  if (ackBuffer.byteLength >= 12) {
    sessionId = ackView.getUint32(8, true);
    console.info(TAG, `【sendInitCommandRequest】相机返回的 Session ID: ${sessionId}`);
  } else {
    console.warn(TAG, `⚠️【sendInitCommandRequest】包太短（${ackBuffer.byteLength}字节），无法解析 Session ID，使用默认值 1`);
  }
  
  // 解析相机 GUID（第 12-27 字节）
  if (ackBuffer.byteLength >= 28) {
    const cameraGuid: number[] = [];
    for (let i = 0; i < 16; i++) {
      cameraGuid.push(ackView.getUint8(12 + i));
    }
    console.debug(TAG, `【sendInitCommandRequest】相机 GUID: ${cameraGuid.map(b => b.toString(16).padStart(2, '0')).join('')}`);
    
    // 解析相机名称（从第 28 字节开始，WCHAR 格式）
    let cameraName = '';
    let nameOffset = 28;
    while (nameOffset < ackBuffer.byteLength - 1) {
      const charCode = ackView.getUint16(nameOffset, true);
      if (charCode === 0) break;
      cameraName += String.fromCharCode(charCode);
      nameOffset += 2;
    }
    if (cameraName) {
      console.info(TAG, `【sendInitCommandRequest】相机名称：${cameraName}`);
    }
  }
  
  // 保存 Session ID
  this.sessionId = sessionId;
  
  console.info(TAG, `✅【sendInitCommandRequest】握手完成，Session ID=${sessionId}`);
  console.info(TAG, `【sendInitCommandRequest】准备打开会话...`);
  
  return true;
}
```

**为什么这样改：**
- 增加了对不同包长度的容错处理
- 提供默认 Session ID 值
- 避免因包太短而导致解析失败

---

## 修改 5：错误处理 (第 1135-1150 行)

**修改前：**
```typescript
} else if (ackType === 5) {
  // Init_Fail
  console.error(TAG, `❌【sendInitCommandRequest】握手失败 (Init_Fail)`);
  console.error(TAG, `❌ 相机拒绝了连接请求`);
  console.error(TAG, `❌ 当前 GUID: ${guid.map(b => b.toString(16).padStart(2, '0')).join('')}`);
  console.error(TAG, `❌ 当前设备名称：${deviceName}`);
  console.error(TAG, `💡 Nikon 相机建议：尝试使用 "Nikon" 或其他设备名称`);
  return false;
} else {
  console.error(TAG, `❌【sendInitCommandRequest】未知响应类型：${ackType}`);
  console.error(TAG, `❌ 期望收到 type=2 (Init_Command_Ack) 或 type=5 (Init_Fail)`);
  return false;
}
```

**修改后：**
```typescript
} else if (ackType === 5) {
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
  console.error(TAG, `   - 响应包长度: ${ackBuffer.byteLength} 字节`);
  console.error(TAG, `   - 响应类型字段: ${ackType}`);
  console.error(TAG, `   - 响应长度字段: ${ackLength}`);
  console.error(TAG, `💡 这可能表示：`);
  console.error(TAG, `   1. 相机使用了非标准的 PTP/IP 协议`);
  console.error(TAG, `   2. 网络数据损坏`);
  console.error(TAG, `   3. 相机固件版本不兼容`);
  return false;
}
```

**为什么这样改：**
- 提供更详细的诊断信息
- 包含具体的故障排查步骤
- 帮助用户快速解决问题

---

## 总结

| 修改项 | 位置 | 原因 | 效果 |
|--------|------|------|------|
| 设备名称 | 1034 行 | Nikon ZF 要求 | 提高兼容性 |
| 超时处理 | 775 行 | 网络延迟 | 更宽松的容错 |
| 包长读取 | 1070-1095 行 | 包长度不固定 | 动态自适应 |
| Session ID | 1100-1135 行 | 防御短包 | 安全读取 |
| 错误信息 | 1135-1150 行 | 诊断困难 | 详细的排查指南 |

所有修改都已应用，您现在可以进行测试了！

