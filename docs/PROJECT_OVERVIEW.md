# PhotoSend 项目代码梳理

## 📋 项目概述

**项目名称**: PhotoSend  
**包名**: com.lingyu.photosend  
**版本**: 1.0.0  
**开发平台**: HarmonyOS / OpenHarmony  
**开发语言**: ArkTS / TypeScript

### 项目目标
通过 WiFi 连接相机（支持尼康 ZF 等），使用 **PTP/IP 协议**实现相机照片的浏览和下载功能。替代了之前的 libgphoto2 C++ 库，改为 100% 纯 ArkTS 实现。

---

## 🏗️ 项目结构

```
PhotoSend (根目录)
├── AppScope/                           # 应用全局配置
│   ├── app.json5                       # 应用清单
│   └── resources/
│       └── base/
│           ├── element/               # UI 元素资源
│           └── media/                 # 媒体资源（图片、图标等）
│
├── entry/                              # 主应用模块
│   ├── src/main/
│   │   ├── ets/                        # 核心代码目录
│   │   │   ├── ptpip/                  # ★ PTP/IP 协议核心模块
│   │   │   ├── pages/                  # UI 页面
│   │   │   ├── components/             # 自定义组件
│   │   │   ├── utils/                  # 工具类
│   │   │   ├── common/                 # 公共资源（常量等）
│   │   │   ├── workers/                # 后台任务
│   │   │   ├── entryability/           # 应用入口
│   │   │   ├── CustomTransition/       # 自定义转场动画
│   │   │   └── types/                  # 类型定义
│   │   ├── cpp/                        # C++ 代码
│   │   └── resources/                  # 应用资源
│   │       ├── base/
│   │       ├── dark/                   # 深色主题资源
│   │       └── rawfile/                # 原始文件
│   ├── build/                          # 编译输出
│   │   └── outputs/
│   │       └── default/
│   │           └── PhotoSend-default-unsigned.app  # 输出的 APP 文件
│   └── libs/                           # 原生库 (arm64-v8a)
│       └── arm64-v8a/                  # ★ 相机驱动库集合
│           ├── libgphoto2.so           # 原始库（已不使用）
│           ├── canon.so / nikon.so     # 相机厂商驱动
│           └── ... 30+ 个库文件
│
├── oh_modules/                         # HarmonyOS 模块依赖
│   └── @ohos/
│       ├── hamock/                     # Mock 测试框架
│       └── hypium/                     # 测试框架
│
├── hvigor/                             # Hvigor 构建配置
├── build-profile.json5                 # 项目编译配置
├── oh-package.json5                    # 项目依赖清单
├── REFACTOR_SUMMARY.md                 # 重构总结
├── PTPIP_USAGE_GUIDE.md                # PTP/IP 使用指南
└── CLEANUP_GUIDE.md                    # 清理指南

```

---

## 🔧 核心模块详解

### 1. **PTP/IP 协议模块** (`entry/src/main/ets/ptpip/`)

这是项目的核心，完全使用 ArkTS 实现 PTP/IP 协议。

#### 关键文件：

##### **PtpConstants.ets** (常量定义)
- **PTP 操作码** (PtpOperationCode)
  - `GetDeviceInfo` (0x1001) - 获取设备信息
  - `OpenSession` (0x1002) - 打开会话
  - `GetStorageIDs` (0x1004) - 获取存储 ID
  - `GetObjectHandles` (0x1007) - 获取对象句柄（照片列表）
  - `GetObjectInfo` (0x1008) - 获取对象信息
  - `GetObject` (0x1009) - 下载完整照片
  - `GetThumb` (0x100A) - 获取缩略图
  - `Nikon_*` - 尼康扩展命令

- **PTP 响应码** (PtpResponseCode)
  - `OK` (0x2001) - 成功
  - `SessionNotOpen` (0x2003) - 会话未打开
  - `InvalidStorageId` (0x2006) - 无效存储 ID
  - 等等...

- **PTP 数据格式代码** (PtpObjectFormatCode)
  - `Undefined` (0x3000)
  - `Association` (0x3001) - 文件夹
  - `JPEG` (0x3801)
  - `NEF` (0xB018) - 尼康 RAW 格式
  - 等等...

##### **PtpTypes.ets** (数据结构)
定义了与 PTP/IP 协议相关的数据结构：
```typescript
interface PtpDeviceInfo {
  standardVersion: number;
  vendorExtensionId: number;
  manufacturer: string;      // 例：NIKON
  model: string;             // 例：NIKON Z fc
  deviceVersion: string;     // 固件版本
  serialNumber: string;      // 序列号
  imageFormats: number[];    // 支持的图像格式
  // ... 其他字段
}

interface PtpStorageInfo {
  storageType: number;
  filesystemType: number;
  maxCapacity: number;       // 总容量
  freeSpaceInBytes: number;  // 可用空间
  storageDescription: string;
  // ... 其他字段
}

interface PtpObjectInfo {
  objectHandle: number;      // 对象句柄（唯一标识照片）
  storageId: number;
  objectFormat: number;      // 格式代码
  protectionStatus: number;
  objectCompressedSize: number;  // 文件大小
  filename: string;          // 文件名
  captureDate: number;       // 拍摄日期（Unix 时间戳）
  modificationDate: number;  // 修改日期
}

interface PhotoMeta {
  filename: string;
  size: number;
  captureDate: Date;
  modificationDate: Date;
  objectHandle: number;
  objectFormat: number;
}
```

##### **PtpConnectionManager.ets** (连接管理) - 核心类 (1159 行)

**职责**：
- TCP Socket 连接管理（命令连接 + 事件连接）
- PTP/IP 握手流程（Init_Command_Request/Ack 等）
- 会话管理（OpenSession / CloseSession）
- PTP 命令发送与响应接收
- 数据包编码与解码

**关键方法**：
```typescript
// 建立 TCP 连接
async connect(ip: string, port: number): Promise<boolean>

// 执行 PTP 命令
async executePtpCommand(command: PtpCommand): Promise<PtpResponse>

// 打开会话
async openSession(sessionId: number): Promise<boolean>

// 关闭会话
async closeSession(): Promise<void>

// 断开连接
async disconnect(): Promise<void>

// 获取连接状态
getState(): ConnectionState

// 获取会话 ID
getSessionId(): number
```

**连接流程**：
```
1. 创建 TCP Socket
2. 连接到设备 IP:15740
3. 发送 Init_Command_Request (握手)
4. 接收 Init_Command_Ack (获取 Session ID)
5. 发送 Init_Event_Request (事件连接初始化)
6. 接收 Init_Event_Ack
7. 打开 PTP 会话
8. 准备接收命令
```

##### **PtpClient.ets** (高层 API) - 456 行

**职责**：
- 提供易用的高层接口
- 扫描相机上的照片
- 下载照片和缩略图
- 进度回调机制

**关键方法**：
```typescript
// 连接相机
async connect(ip: string, port?: number): Promise<boolean>

// 断开连接
async disconnect(): Promise<void>

// 扫描所有照片
async scanPhotos(): Promise<PhotoMeta[]>

// 下载完整照片
async downloadPhoto(objectHandle: number, savePath: string): Promise<boolean>

// 下载缩略图
async downloadThumbnail(objectHandle: number): Promise<ArrayBuffer | null>

// 设置扫描进度回调
setScanProgressCallback(callback: (current: number, total: number) => void)

// 设置下载进度回调
setDownloadProgressCallback(callback: (progress: DownloadProgressData) => void)

// 获取缓存的照片元数据
getCachedPhotoMetas(): PhotoMeta[]
```

**工作流程**：
```
1. 连接设备
2. 获取设备信息
3. 获取存储 ID 列表
4. 对每个存储：
   - 获取对象数量
   - 遍历对象句柄
   - 获取对象信息
   - 筛选照片（JPEG、NEF、CR2 等）
5. 返回照片元数据列表
```

##### **PtpCompatLayer.ets** (兼容性层)

处理不同相机厂商的 PTP/IP 实现差异：
- 尼康、佳能、索尼等特殊命令
- 数据格式差异
- 响应格式差异

##### **index.ets** (统一导出)
```typescript
export { PtpConnectionManager, ConnectionState } from './PtpConnectionManager';
export { PtpClient } from './PtpClient';
export type { PtpDeviceInfo, PtpStorageInfo, PtpObjectInfo, PhotoMeta } from './PtpTypes';
export { PtpOperationCode, PtpResponseCode, PtpObjectFormatCode } from './PtpConstants';
```

---

### 2. **页面模块** (`entry/src/main/ets/pages/`)

#### HomePage.ets (主页)
- 使用 `Tabs` 组件实现底部标签栏
- 包含三个主要标签页
- 管理应用存储路径创建
- 集成自定义转场动画

#### CameraPage/ (相机页面)
- **CameraPage.ets** - 相机连接和照片浏览
  - 输入相机 IP 地址
  - 连接相机
  - 显示照片网格
  - 照片预览
  
- **CameraPagePreview.ets** - 预览模式

#### PhoneLocalPhotos/ (手机本地照片)
- 浏览手机本地照片
- 照片分类展示
- 照片管理

#### MinePage/ (我的页面)
- 用户信息
- 设置
- 关于应用

#### CamPhotoPreAndDownload/ (相机照片预览和下载)
- 相机照片详情预览
- 下载功能
- 进度显示

#### RemoteControl/ (远程控制)
- 相机远程控制功能

---

### 3. **自定义组件** (`entry/src/main/ets/components/`)

#### CameraControlDialog/ (相机控制对话框)
- 相机连接对话框
- 控制选项界面

---

### 4. **工具类** (`entry/src/main/ets/utils/`)

#### **CameraUtils.ets** (相机工具类 - 单例模式)
```typescript
export class CameraUtils {
  private static instance: CameraUtils | null = null;
  private ptpClient: PtpClient;
  
  static getInstance(): CameraUtils
  
  // 相机操作方法
  async connectCamera(ip: string): Promise<boolean>
  async disconnectCamera(): Promise<void>
  async getPhotoList(): Promise<PhotoMeta[]>
  async downloadPhoto(...): Promise<boolean>
  async getThumbnail(...): Promise<ArrayBuffer>
}
```

#### animation/ (动画工具)
- 动画效果定义

#### tools/ (工具函数集)
- **CreateLocalDir** - 创建本地目录
- 其他工具函数

#### **PtpConnectionManager.ets** (utils 中的版本)
- 辅助连接管理

---

### 5. **应用入口** (`entry/src/main/ets/entryability/`)

#### EntryAbility.ets
- 应用启动入口
- 生命周期管理
- 权限申请

---

### 6. **类型定义和常量** (`entry/src/main/ets/`)

#### common/constants/ (常量定义)
- 应用级别常量
- UI 相关常量
- 业务逻辑常量

#### types/ (类型定义)
- TypeScript 类型定义
- 接口定义

---

## 🔄 主要工作流程

### 连接相机流程
```
用户输入相机 IP → 点击连接
  ↓
CameraUtils.connectCamera(ip)
  ↓
PtpClient.connect(ip)
  ↓
PtpConnectionManager.connect(ip)
  ↓
TCP Socket 连接 → PTP/IP 握手 → 打开会话
  ↓
获取设备信息 → 获取存储 ID
  ↓
连接成功，更新 UI
```

### 扫描照片流程
```
连接成功后
  ↓
PtpClient.scanPhotos()
  ↓
遍历每个存储
  ↓
获取对象数量
  ↓
遍历所有对象句柄
  ↓
获取对象信息
  ↓
筛选照片（JPEG、NEF、CR2 等）
  ↓
构建 PhotoMeta 对象
  ↓
更新 UI 进度回调
  ↓
返回所有照片元数据
```

### 下载照片流程
```
用户选择照片
  ↓
PtpClient.downloadPhoto(objectHandle, savePath)
  ↓
PtpConnectionManager.executePtpCommand(GetObject)
  ↓
接收二进制数据
  ↓
写入本地文件系统
  ↓
触发进度回调
  ↓
下载完成
```

---

## 🏛️ 架构设计

### 分层架构

```
┌─────────────────────────────────┐
│      UI 层                       │
│  (Pages & Components)           │
└────────────┬────────────────────┘
             ↓
┌─────────────────────────────────┐
│      业务逻辑层                  │
│  CameraUtils (单例)             │
│  PtpClient (高层 API)           │
└────────────┬────────────────────┘
             ↓
┌─────────────────────────────────┐
│      协议层                      │
│  PtpConnectionManager           │
│  PtpConstants, PtpTypes         │
│  PtpCompatLayer                 │
└────────────┬────────────────────┘
             ↓
┌─────────────────────────────────┐
│      网络层                      │
│  TCP Socket (@kit.NetworkKit)   │
└─────────────────────────────────┘
```

### 设计模式

1. **单例模式** - CameraUtils
2. **适配器模式** - PtpCompatLayer (处理不同相机)
3. **观察者模式** - 进度回调
4. **状态模式** - ConnectionState (连接状态管理)

---

## 📦 依赖管理

### 外部依赖

```json
{
  "dependencies": {
    "libentry.so": "file:./src/main/cpp/types/libentry"
  },
  "devDependencies": {
    "@ohos/hypium": "1.0.24",      // 测试框架
    "@ohos/hamock": "1.0.0"        // Mock 框架
  }
}
```

### HarmonyOS 系统 API

- **@kit.NetworkKit** - TCP Socket 网络连接
- **@ohos.file.fs** - 文件系统操作
- **@kit.AbilityKit** - 应用能力框架
- **@ohos.data.preferences** - 数据存储

### 原生库 (libs/arm64-v8a/)

虽然现在使用纯 ArkTS 实现，但仍保留了 30+ 个原生库文件（可能用于其他功能或向后兼容）。

---

## 🎯 关键特性

### ✅ 已实现
- PTP/IP 协议完整实现
- 相机连接 (TCP Socket)
- 会话管理
- 照片扫描和元数据读取
- 照片下载（完整+缩略图）
- 进度显示
- 相机兼容性处理（尼康、佳能等）
- 文件系统操作
- 自定义 UI 动画

### 🔄 可扩展功能
- 相机远程控制
- 实时预览
- 批量下载
- 照片编辑上传
- 相机固件升级

---

## 📝 重要文档

1. **README_PTP_IMPLEMENTATION.md** - PTP/IP 详细实现指南
2. **QUICK_START.md** - 快速开始指南
3. **PTPIP_USAGE_GUIDE.md** - PTP/IP 使用指南
4. **REFACTOR_SUMMARY.md** - 重构总结
5. **CLEANUP_GUIDE.md** - 清理指南

---

## 🚀 开发建议

### 编码规范
- 使用 ArkTS 编写所有新代码
- 避免引入 C++ 依赖
- 遵循 HarmonyOS 最佳实践

### 性能优化
- 使用 Worker 线程处理大文件下载
- 实现缓存机制减少网络请求
- 优化内存使用（避免一次性加载全部照片）

### 测试
- 使用 Hypium 测试框架编写单元测试
- 测试 PTP/IP 协议实现
- 测试不同相机厂商的兼容性

### 错误处理
- 实现完善的异常处理
- 提供用户友好的错误提示
- 记录详细的日志便于调试

---

## 📊 项目统计

- **总行数**: 约 3000+ 行 ArkTS 代码
- **核心模块**: PtpConnectionManager (1159 行)
- **页面数量**: 6+ 个主要页面
- **支持相机**: 尼康、佳能、索尼等主流相机
- **原生库**: 30+ 个预编译库文件

---

## 🔗 相关标准和文档

- **PTP/IP 标准**: CIPA DC-X005-2005
- **gPhoto2 文档**: https://gphoto.sourceforge.io/
- **HarmonyOS 网络 API**: @kit.NetworkKit
- **相机 PTP/IP 实现**:
  - 尼康相机 PTP/IP 扩展
  - 佳能 EOS PTP/IP
  - 索尼 α 相机网络控制

---

最后更新：2026 年 3 月 10 日  
项目版本：1.0.0  
状态：✅ 活跃开发中

