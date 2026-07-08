# PhotoSend 技术架构详解

## 🏗️ 系统架构图

```
┌────────────────────────────────────────────────────────────────┐
│                     UI 表现层                                   │
│ ┌─────────────┬──────────────┬─────────────┬─────────────────┐ │
│ │ HomePage    │ CameraPage   │PhoneLocal   │  MinePage       │ │
│ │ (底部标签)  │ (相机浏览)   │ Photos      │  (我的)          │ │
│ │             │              │ (本地照片)  │                  │ │
│ └────┬────────┴──────┬───────┴──────┬──────┴─────────┬────────┘ │
│      │                │              │                │          │
└──────┼────────────────┼──────────────┼────────────────┼──────────┘
       │                │              │                │
       ├─→ 自定义组件: CameraControlDialog, CustomTransition 动画
       │
┌──────┴────────────────────────────────────────────────────────┐
│                   业务逻辑层 (Service)                         │
│                                                                │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │  CameraUtils (单例) - 与 PTP 客户端交互                 │  │
│  │  • connectCamera()    → 连接相机                        │  │
│  │  • getPhotoList()     → 获取照片列表                    │  │
│  │  • downloadPhoto()    → 下载照片                        │  │
│  │  • getThumbnail()     → 获取缩略图                      │  │
│  └─────────────────────────────────────────────────────────┘  │
│                                                                │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │  PtpClient (API 层) - 高层协议接口                      │  │
│  │  • connect()          → 连接设备                        │  │
│  │  • scanPhotos()       → 扫描照片                        │  │
│  │  • downloadPhoto()    → 下载完整照片                    │  │
│  │  • downloadThumbnail()→ 下载缩略图                      │  │
│  │  • 进度回调机制                                         │  │
│  └─────────────────────────────────────────────────────────┘  │
│                                                                │
└───────┬──────────────────────────────────────────────────────┘
        │
┌───────┴──────────────────────────────────────────────────────┐
│              PTP/IP 协议层 (Protocol)                        │
│                                                               │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  PtpConnectionManager (核心 - 1159 行)               │   │
│  │  • TCP 连接管理                                      │   │
│  │  • PTP/IP 握手流程                                   │   │
│  │  • 会话管理 (OpenSession/CloseSession)               │   │
│  │  • 命令执行框架 (executePtpCommand)                  │   │
│  │  • 响应数据解析                                      │   │
│  └──────┬───────────────────────────────────────────────┘   │
│         │                                                      │
│  ┌──────┴───────────────────────────────────────────────┐   │
│  │  PtpConstants - 协议常量                             │   │
│  │  • PtpOperationCode (操作码)                         │   │
│  │  • PtpResponseCode (响应码)                          │   │
│  │  • PtpObjectFormatCode (格式码)                      │   │
│  │  • PtpIpPacketType (包类型)                          │   │
│  │  • 数据类型枚举                                      │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                               │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  PtpTypes - 数据结构定义                             │   │
│  │  • PtpDeviceInfo (设备信息)                          │   │
│  │  • PtpStorageInfo (存储信息)                         │   │
│  │  • PtpObjectInfo (对象信息)                          │   │
│  │  • PhotoMeta (照片元数据)                            │   │
│  │  • DownloadProgressData (进度数据)                   │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                               │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  PtpCompatLayer - 相机兼容性处理                     │   │
│  │  • 尼康扩展命令处理                                  │   │
│  │  • 佳能特殊格式支持                                  │   │
│  │  • 索尼相机适配                                      │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                               │
└───────┬──────────────────────────────────────────────────────┘
        │
┌───────┴──────────────────────────────────────────────────────┐
│               网络和文件系统层                               │
│                                                               │
│  ┌──────────────┐        ┌──────────────┐                  │
│  │  TCP Socket  │        │  文件系统    │                  │
│  │ (HarmonyOS   │        │  (@ohos.    │                  │
│  │  @kit.       │        │   file.fs)  │                  │
│  │  NetworkKit) │        │              │                  │
│  └──────────────┘        └──────────────┘                  │
│                                                               │
└──────────────────────────────────────────────────────────────┘
        │
┌───────┴──────────────────────────────────────────────────────┐
│                    相机设备 (Device)                         │
│                                                               │
│  • WiFi 连接相机 (尼康 Z fc, Z 6II 等)                      │
│  • TCP 15740 端口 (命令)                                     │
│  • TCP 15741 端口 (事件)                                     │
│                                                               │
└──────────────────────────────────────────────────────────────┘
```

---

## 📦 模块依赖关系

### 依赖流向

```
Pages & Components
    ↓
  CameraUtils (Singleton)
    ↓
  PtpClient
    ↓
  PtpConnectionManager
    ├→ PtpConstants
    ├→ PtpTypes
    ├→ PtpCompatLayer
    ├→ (@kit.NetworkKit) TCP Socket
    └→ (@ohos.file.fs) 文件系统
```

### 模块间通信

```
CameraPage
    ↓ 调用
CameraUtils.connectCamera(ip)
    ↓ 转发
PtpClient.connect(ip)
    ↓ 转发
PtpConnectionManager.connect(ip)
    ↓ 使用
@kit.NetworkKit.TCPSocket
    ↓
相机设备
    ↓ 响应
PtpConnectionManager
    ↓ 回调
PtpClient
    ↓ 回调
CameraUtils
    ↓ 更新
CameraPage UI
```

---

## 🔄 关键工作流程详解

### 流程 1: 连接设备

```
┌─ 用户输入 IP 地址 ─────────────┐
│                                 │
│ CameraPage 显示输入框           │
│ 用户点击"连接"按钮              │
│                                 │
└──────────────┬──────────────────┘
               │
       ┌───────v─────────┐
       │ CameraUtils     │
       │ connectCamera() │
       └───────┬─────────┘
               │
       ┌───────v──────────────────┐
       │ PtpClient.connect(ip)    │
       │                          │
       │ 1. 创建 TCP Socket       │
       │ 2. 连接到 ip:15740      │
       │ 3. 发送初始化包         │
       │ 4. 接收初始化响应       │
       │                          │
       └───────┬──────────────────┘
               │
       ┌───────v────────────────────────────┐
       │ PtpConnectionManager.connect()    │
       │                                    │
       │ ┌─ TCP 握手 ─────────────────────┐ │
       │ │ Init_Command_Request            │ │
       │ │     ↓ (发送)                    │ │
       │ │ Init_Command_Ack                │ │
       │ │     ← (接收，获取 Session ID) │ │
       │ │                                 │ │
       │ │ Init_Event_Request              │ │
       │ │     ↓ (发送)                    │ │
       │ │ Init_Event_Ack                  │ │
       │ │     ← (接收)                    │ │
       │ └─────────────────────────────────┘ │
       │                                    │
       │ 设置连接状态为 CONNECTED           │
       │ 保存 Session ID 和设备信息        │
       │                                    │
       └───────┬───────────────────────────┘
               │
       ┌───────v──────────┐
       │ OpenSession()    │
       │ 打开 PTP 会话    │
       └───────┬──────────┘
               │
       ┌───────v─────────┐
       │ GetDeviceInfo() │
       │ 获取设备信息    │
       └───────┬─────────┘
               │
       ┌───────v────────────┐
       │ GetStorageIDs()    │
       │ 获取存储 ID 列表  │
       └───────┬────────────┘
               │
       ┌───────v─────────┐
       │ 连接成功        │
       │ 返回 true       │
       └───────┬─────────┘
               │
       ┌───────v───────────────┐
       │ UI 更新               │
       │ 显示"已连接"状态      │
       │ 启用"扫描照片"按钮    │
       └───────────────────────┘
```

### 流程 2: 扫描照片

```
┌─ 用户点击"扫描照片" ─────────────────┐
│                                      │
│ CameraPage 触发扫描                  │
│                                      │
└──────────────┬───────────────────────┘
               │
       ┌───────v──────────────┐
       │ CameraUtils         │
       │ getPhotoList()      │
       └───────┬──────────────┘
               │
       ┌───────v──────────────────────────┐
       │ PtpClient.scanPhotos()          │
       │                                  │
       │ For each storageId:              │
       │   ├─ GetNumObjects()            │ 获取照片总数
       │   │   获取对象数量                 │
       │   │                              │
       │   └─ GetObjectHandles()         │ 获取所有对象句柄
       │       遍历每个对象:              │
       │       ├─ GetObjectInfo()        │ 获取对象信息
       │       │   (文件名、大小、日期等)  │
       │       │                          │
       │       └─ 筛选照片               │
       │           (JPEG, NEF, CR2等)    │
       │                                  │
       │ 触发进度回调:                    │
       │ onScanProgressCallback()        │ 例：30% (100/300)
       │                                  │
       │ 构建 PhotoMeta 对象:            │
       │ ├─ filename                    │
       │ ├─ size                        │
       │ ├─ captureDate                 │
       │ ├─ objectHandle                │
       │ └─ objectFormat                │
       │                                  │
       │ 返回 PhotoMeta[] 数组           │
       │                                  │
       └───────┬──────────────────────────┘
               │
       ┌───────v──────────────────┐
       │ CameraUtils 缓存结果    │
       │ cachedPhotoMetas[]      │
       └───────┬──────────────────┘
               │
       ┌───────v───────────────────┐
       │ UI 更新                   │
       │ 显示照片网格              │
       │ 更新进度条                │
       └───────────────────────────┘
```

### 流程 3: 下载照片

```
┌─ 用户选择照片并点击下载 ───────────┐
│                                    │
│ 获取照片的 objectHandle            │
│ 指定本地保存路径                   │
│                                    │
└──────────────┬────────────────────┘
               │
       ┌───────v──────────────────┐
       │ CameraUtils             │
       │ downloadPhoto()         │
       └───────┬──────────────────┘
               │
       ┌───────v─────────────────────────────┐
       │ PtpClient.downloadPhoto()           │
       │                                     │
       │ 1. 执行 GetObject 命令              │
       │    └─ objectHandle (对象 ID)       │
       │                                     │
       │ 2. 接收二进制数据                   │
       │    ├─ 接收响应头                   │
       │    ├─ 获取文件大小                 │
       │    └─ 循环接收数据包                │
       │        触发进度回调:                │
       │        onDownloadProgressCallback() │
       │        例：35% (3.5MB/10MB)        │
       │                                     │
       │ 3. 数据流转为 ArrayBuffer           │
       │                                     │
       │ 4. 返回 ArrayBuffer                 │
       │                                     │
       └───────┬─────────────────────────────┘
               │
       ┌───────v─────────────────────────┐
       │ 文件系统操作                     │
       │ (@ohos.file.fs)                │
       │                                 │
       │ 1. 创建文件                     │
       │    fs.createFile(savePath)      │
       │                                 │
       │ 2. 写入数据                     │
       │    fs.writeSync(fd, buffer)     │
       │                                 │
       │ 3. 关闭文件                     │
       │    fs.closeSync(fd)             │
       │                                 │
       └───────┬─────────────────────────┘
               │
       ┌───────v──────────────────┐
       │ UI 更新                  │
       │ 显示"下载完成"提示        │
       │ 显示本地文件位置          │
       └──────────────────────────┘
```

---

## 🔌 PTP/IP 协议实现细节

### PTP/IP 包结构

```
TCP 连接 -> Init_Command_Request
  ├─ PacketLength (4 bytes) - 包大小
  ├─ PacketType (4 bytes)   - 0x01 (Init_Command_Request)
  ├─ GUID (16 bytes)        - 客户端 GUID
  ├─ Name (variable)        - 客户端名称
  └─ ProtocolVersion (4 bytes) - 协议版本

←- Init_Command_Ack
  ├─ PacketLength (4 bytes) - 包大小
  ├─ PacketType (4 bytes)   - 0x02 (Init_Command_Ack)
  ├─ GUID (16 bytes)        - 设备 GUID
  ├─ Name (variable)        - 设备名称
  ├─ ProtocolVersion (4 bytes) - 协议版本
  └─ SessionID (4 bytes)    - ★ 关键：获取 Session ID
```

### PTP 命令包结构

```
Open_Session 示例:
  ├─ ContainerLength (4 bytes)    - 容器长度
  ├─ ContainerType (2 bytes)      - 0x0001 (命令)
  ├─ Code (2 bytes)               - 0x1002 (OpenSession)
  ├─ TransactionID (4 bytes)      - 事务 ID (递增)
  └─ Parameter1 (4 bytes)         - Session ID

GetDeviceInfo 示例:
  ├─ ContainerLength (4 bytes)    - 容器长度
  ├─ ContainerType (2 bytes)      - 0x0001 (命令)
  ├─ Code (2 bytes)               - 0x1001 (GetDeviceInfo)
  ├─ TransactionID (4 bytes)      - 事务 ID
  └─ (无参数)

GetObjectHandles 示例:
  ├─ ContainerLength (4 bytes)    - 容器长度
  ├─ ContainerType (2 bytes)      - 0x0001 (命令)
  ├─ Code (2 bytes)               - 0x1007 (GetObjectHandles)
  ├─ TransactionID (4 bytes)      - 事务 ID
  ├─ Parameter1 (4 bytes)         - StorageID
  ├─ Parameter2 (4 bytes)         - ObjectFormatCode (0=全部)
  └─ Parameter3 (4 bytes)         - Parent ObjectHandle (0=根)
```

### PTP 响应包结构

```
Response 包格式:
  ├─ ContainerLength (4 bytes)    - 容器长度
  ├─ ContainerType (2 bytes)      - 0x0003 (响应)
  ├─ Code (2 bytes)               - 响应码 (0x2001=OK)
  ├─ TransactionID (4 bytes)      - 对应的事务 ID
  └─ Parameter* (4 bytes each)    - 可变响应参数

GetDeviceInfo 响应 (Data 包):
  ├─ ContainerLength (4 bytes)    - 容器长度
  ├─ ContainerType (2 bytes)      - 0x0002 (数据)
  ├─ Code (2 bytes)               - 0x1001 (GetDeviceInfo)
  ├─ TransactionID (4 bytes)      - 事务 ID
  └─ Data (variable)              - 设备信息结构体
      ├─ StandardVersion (2)
      ├─ VendorExtensionID (4)
      ├─ VendorExtensionVersion (2)
      ├─ VendorExtensionDesc (string)
      ├─ Operations (uint16 array)
      ├─ Events (uint16 array)
      ├─ DeviceProperties (uint16 array)
      ├─ Manufacturer (string)
      ├─ Model (string)
      ├─ DeviceVersion (string)
      └─ SerialNumber (string)
```

### 事件系统

```
Event Connection (TCP 15741):

Init_Event_Request
  └─ 初始化事件连接

Init_Event_Ack
  └─ 确认事件连接

Event 包 (异步):
  ├─ PacketLength
  ├─ PacketType - 0x04 (Event)
  ├─ Code - 事件码 (如 0x4001 = CancelTransaction)
  ├─ TransactionID
  └─ Parameter* - 事件参数
```

---

## 💾 数据流示例

### 连接和获取设备信息的数据包序列

```
1. TCP 连接到 192.168.1.100:15740
   
2. 客户端 → 服务器 (Init_Command_Request)
   PacketLength: 0x000000A4
   PacketType: 0x00000001
   GUID: [16 bytes]
   Name: "PhotoSend Client"
   ProtocolVersion: 0x00010000

3. 服务器 → 客户端 (Init_Command_Ack)
   PacketLength: 0x000000A0
   PacketType: 0x00000002
   GUID: [16 bytes]
   Name: "NIKON Z fc"
   ProtocolVersion: 0x00010000
   SessionID: 0x00000001  ← 保存这个 ID！

4. 建立事件连接 (TCP 15741)
   Init_Event_Request
   Init_Event_Ack

5. 客户端 → 服务器 (OpenSession 命令)
   ContainerLength: 0x0000000C
   ContainerType: 0x0001
   Code: 0x1002 (OpenSession)
   TransactionID: 0x00000001
   Parameter1 (SessionID): 0x00000001

6. 服务器 → 客户端 (OpenSession 响应)
   ContainerLength: 0x0000000C
   ContainerType: 0x0003
   Code: 0x2001 (OK)
   TransactionID: 0x00000001

7. 客户端 → 服务器 (GetDeviceInfo 命令)
   ContainerLength: 0x00000008
   ContainerType: 0x0001
   Code: 0x1001 (GetDeviceInfo)
   TransactionID: 0x00000002

8. 服务器 → 客户端 (GetDeviceInfo 数据包)
   [包含设备信息结构体 - 数百字节]

9. 服务器 → 客户端 (GetDeviceInfo 响应)
   ContainerLength: 0x0000000C
   ContainerType: 0x0003
   Code: 0x2001 (OK)
   TransactionID: 0x00000002
```

---

## 🎯 技术栈总结

| 层级 | 技术 | 说明 |
|------|------|------|
| **UI 框架** | ArkUI | HarmonyOS 原生 UI 框架 |
| **语言** | ArkTS | TypeScript 方言 |
| **网络** | @kit.NetworkKit | TCP Socket |
| **文件系统** | @ohos.file.fs | 文件读写 |
| **数据存储** | @ohos.data.preferences | 偏好设置 |
| **应用框架** | @kit.AbilityKit | 应用生命周期 |
| **协议** | PTP/IP (CIPA DC-X005-2005) | 相机通信协议 |
| **测试** | @ohos/hypium | 单元测试框架 |
| **Mock** | @ohos/hamock | Mock 框架 |

---

## 📊 关键性能指标

| 指标 | 值 | 说明 |
|------|-----|------|
| **连接时间** | < 2秒 | TCP + PTP 握手 |
| **照片扫描速度** | ~100 张/秒 | 取决于相机响应 |
| **下载速度** | WiFi 限制 | 典型 1-10 MB/s |
| **内存占用** | < 50 MB | 不加载完整照片数据 |
| **包体积** | < 10 MB | 去除原生库后 |

---

## 🔐 错误处理策略

```
连接层错误:
  ├─ Socket 连接失败 → 显示"设备不可达"
  ├─ 握手失败 → 显示"设备不支持 PTP/IP"
  └─ 会话打开失败 → 显示"相机忙碌或不可用"

协议层错误:
  ├─ 无效 Session ID → 重新连接
  ├─ 无效存储 ID → 跳过该存储
  ├─ 无效对象句柄 → 跳过该照片
  └─ 设备繁忙 → 重试

下载层错误:
  ├─ 网络中断 → 提示重新下载
  ├─ 文件系统错误 → 显示存储空间不足
  └─ 权限拒绝 → 请求权限或更改目录
```

---

## 🚀 扩展点

### 可添加的功能

1. **实时预览** - Nikon_StartLiveView 命令
2. **远程控制** - 快门、光圈、ISO 控制
3. **批量操作** - 同时处理多个文件
4. **文件筛选** - 按日期、大小、格式筛选
5. **元数据编辑** - 修改照片信息
6. **多设备支持** - 同时连接多个相机
7. **蓝牙支持** - 扩展到蓝牙连接

### 优化方向

1. **缓存机制** - 缓存照片列表、缩略图
2. **后台下载** - Worker 线程处理
3. **增量扫描** - 只扫描新增照片
4. **内存优化** - 流式处理大文件
5. **网络优化** - 连接池、超时设置

---

最后更新：2026 年 3 月 10 日

