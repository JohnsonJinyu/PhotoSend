# PhotoSend 项目快速参考指南

## 📁 文件位置一览表

### 核心 PTP/IP 模块

| 文件 | 位置 | 行数 | 主要职责 |
|------|------|------|---------|
| **PtpConnectionManager.ets** | `entry/src/main/ets/ptpip/` | 1159 | TCP 连接 + 会话管理 |
| **PtpClient.ets** | `entry/src/main/ets/ptpip/` | 456 | 高层 API (扫描、下载) |
| **PtpConstants.ets** | `entry/src/main/ets/ptpip/` | 219 | 协议常量定义 |
| **PtpTypes.ets** | `entry/src/main/ets/ptpip/` | 145 | 数据结构定义 |
| **PtpCompatLayer.ets** | `entry/src/main/ets/ptpip/` | ? | 相机兼容性处理 |
| **index.ets** | `entry/src/main/ets/ptpip/` | ? | 统一导出 |

### UI 页面

| 页面 | 位置 | 功能 |
|------|------|------|
| **HomePage.ets** | `entry/src/main/ets/pages/` | 应用主页，底部标签栏 |
| **CameraPage/** | `entry/src/main/ets/pages/CameraPage/` | 相机连接和照片浏览 |
| **PhoneLocalPhotos/** | `entry/src/main/ets/pages/PhoneLocalPhotos/` | 手机本地照片 |
| **MinePage/** | `entry/src/main/ets/pages/MinePage/` | 我的页面（用户信息） |
| **CamPhotoPreAndDownload/** | `entry/src/main/ets/pages/` | 照片预览和下载 |
| **RemoteControl/** | `entry/src/main/ets/pages/` | 相机远程控制 |

### 工具和服务

| 文件 | 位置 | 用途 |
|------|------|------|
| **CameraUtils.ets** | `entry/src/main/ets/utils/` | 单例模式，相机服务 |
| **PtpConnectionManager.ets** | `entry/src/main/ets/utils/` | 连接管理辅助类 |
| **CameraUtils.ets** | `entry/src/main/ets/utils/` | 动画工具 |
| **CreateLocalDir.ets** | `entry/src/main/ets/utils/tools/` | 创建本地目录 |

### 组件和自定义

| 文件 | 位置 | 用途 |
|------|------|------|
| **CameraControlDialog/** | `entry/src/main/ets/components/` | 相机控制对话框 |
| **CustomTransition/** | `entry/src/main/ets/` | 自定义转场动画 |

### 配置文件

| 文件 | 用途 |
|------|------|
| **oh-package.json5** | 项目依赖配置 |
| **build-profile.json5** | 编译配置 |
| **hvigorfile.ts** | Hvigor 构建脚本 |
| **code-linter.json5** | 代码检查配置 |

### 文档

| 文件 | 内容 |
|------|------|
| **PROJECT_OVERVIEW.md** | 项目总体概览（本创建） |
| **ARCHITECTURE.md** | 系统架构和技术细节（本创建） |
| **README_PTP_IMPLEMENTATION.md** | PTP/IP 实现指南 |
| **QUICK_START.md** | 快速开始 |
| **PTPIP_USAGE_GUIDE.md** | PTP/IP 使用指南 |
| **REFACTOR_SUMMARY.md** | 重构总结 |
| **CLEANUP_GUIDE.md** | 清理指南 |

---

## 🚀 常用操作速查表

### 添加新页面

```typescript
// 1. 创建页面文件：entry/src/main/ets/pages/NewPage/NewPage.ets

@Entry
@Component
struct NewPage {
  build() {
    Column() {
      // UI 代码
    }
  }
}

// 2. 在 HomePage.ets 中注册
// 在 TabContent 中添加新标签页

// 3. 配置转场动画（如需要）
// 在 HomePage.ets 的 allowedCustomTransitionFromPageName 中添加
```

### 连接相机

```typescript
// 方法 1：使用 CameraUtils（推荐）
import { CameraUtils } from '../utils/CameraUtils';

const cameraUtils = CameraUtils.getInstance();
const connected = await cameraUtils.connectCamera('192.168.1.100');

// 方法 2：直接使用 PtpClient
import { PtpClient } from '../ptpip/PtpClient';

const client = new PtpClient();
const connected = await client.connect('192.168.1.100', 15740);
```

### 扫描照片

```typescript
import { CameraUtils } from '../utils/CameraUtils';

const cameraUtils = CameraUtils.getInstance();

// 设置进度回调
cameraUtils.setScanProgressCallback((current: number, total: number) => {
  console.log(`扫描进度: ${current}/${total}`);
});

// 扫描照片
const photos = await cameraUtils.getPhotoList();
console.log(`找到 ${photos.length} 张照片`);

// 获取照片列表
photos.forEach(photo => {
  console.log(`${photo.filename} - ${photo.size} bytes - ${photo.captureDate}`);
});
```

### 下载照片

```typescript
import { CameraUtils } from '../utils/CameraUtils';

const cameraUtils = CameraUtils.getInstance();

// 设置下载进度回调
cameraUtils.setDownloadProgressCallback((progress) => {
  console.log(`下载进度: ${progress.current}/${progress.total} (${progress.percentage}%)`);
});

// 下载照片
const photo = photos[0]; // 获取第一张照片
const savePath = '/data/PhotoSend/' + photo.filename;
const success = await cameraUtils.downloadPhoto(photo.objectHandle, savePath);

if (success) {
  console.log('下载完成');
}
```

### 获取缩略图

```typescript
import { CameraUtils } from '../utils/CameraUtils';

const cameraUtils = CameraUtils.getInstance();
const photo = photos[0];

const thumbnailBuffer = await cameraUtils.getThumbnail(photo.objectHandle);
if (thumbnailBuffer) {
  // 转换为 Image 显示
  const imageData = new Uint8Array(thumbnailBuffer);
  // 在 UI 中显示缩略图
}
```

### 断开相机连接

```typescript
import { CameraUtils } from '../utils/CameraUtils';

const cameraUtils = CameraUtils.getInstance();
await cameraUtils.disconnectCamera();
console.log('已断开相机连接');
```

### 监听连接状态

```typescript
@State cameraConnected: boolean = false;
@State connectionMessage: string = '';

async aboutToAppear() {
  // 在页面显示时检查连接状态
  const cameraUtils = CameraUtils.getInstance();
  
  // 设置断开连接回调
  ptpConnectionManager.setOnDisconnect(() => {
    this.cameraConnected = false;
    this.connectionMessage = '相机已断开连接';
  });
}
```

---

## 🔧 调试和故障排除

### 查看连接日志

```typescript
// PtpConnectionManager 会输出详细日志
// 查看 logcat 过滤 "PtpConnectionManager"

// 示例输出：
// I/PtpConnectionManager: 【PtpConnectionManager】开始连接 PTP/IP 设备：192.168.1.100:15740
// I/PtpConnectionManager: [STEP 1] 创建 TCP Socket...
// I/PtpConnectionManager: [STEP 2] 连接到设备...
// I/PtpConnectionManager: [STEP 3] 发送握手包...
// ...
```

### 常见问题

| 问题 | 原因 | 解决方案 |
|------|------|---------|
| 无法连接相机 | IP 地址错误 | 检查相机 IP，确保在同一网络 |
| 连接超时 | 防火墙或网络问题 | 检查防火墙，尝试 ping 相机 |
| 获取照片列表为空 | 相机没有照片 | 检查相机存储中是否有照片 |
| 下载速度慢 | WiFi 网络差 | 靠近相机或检查信号强度 |
| 应用崩溃 | 内存不足 | 关闭其他应用，清理缓存 |
| 无权限访问存储 | 未授予文件权限 | 检查应用权限设置 |

### 启用详细日志

```typescript
// 在 PtpConnectionManager.ets 顶部修改
const TAG = 'PtpConnectionManager';
const DEBUG_MODE = true; // 改为 true

// 输出会更详细，可能影响性能
```

---

## 📊 对象模型速查

### PtpDeviceInfo (设备信息)

```typescript
interface PtpDeviceInfo {
  standardVersion: number;           // PTP 标准版本
  vendorExtensionId: number;        // 厂商扩展 ID
  vendorExtensionVersion: number;   // 厂商扩展版本
  vendorExtensionDesc: string;      // 厂商扩展描述
  functionalMode: number;           // 功能模式
  operationsSupported: number[];    // 支持的操作
  eventsSupported: number[];        // 支持的事件
  devicePropertiesSupported: number[]; // 支持的设备属性
  captureFormats: number[];         // 捕获格式
  imageFormats: number[];           // 图像格式
  manufacturer: string;             // 制造商（如 "NIKON"）
  model: string;                    // 模型（如 "Z fc"）
  deviceVersion: string;            // 设备版本
  serialNumber: string;             // 序列号
}
```

### PhotoMeta (照片元数据)

```typescript
interface PhotoMeta {
  filename: string;                 // 文件名（如 "DSC0001.JPG"）
  size: number;                     // 文件大小（字节）
  captureDate: Date;                // 拍摄日期
  modificationDate: Date;           // 修改日期
  objectHandle: number;             // 对象句柄（用于下载）
  objectFormat: number;             // 对象格式码
}
```

### PtpStorageInfo (存储信息)

```typescript
interface PtpStorageInfo {
  storageType: number;              // 存储类型
  filesystemType: number;           // 文件系统类型
  accessCapability: number;         // 访问能力
  maxCapacity: number;              // 最大容量（字节）
  freeSpaceInBytes: number;         // 可用空间（字节）
  freeSpaceInImages: number;        // 可用空间（图像数）
  storageDescription: string;       // 存储描述
  volumeLabel: string;              // 卷标
}
```

---

## 🎯 PTP 操作码快速查询

### 常用操作码

| 操作 | 代码 | 用途 |
|------|------|------|
| GetDeviceInfo | 0x1001 | 获取相机信息 |
| OpenSession | 0x1002 | 打开会话 |
| CloseSession | 0x1003 | 关闭会话 |
| GetStorageIDs | 0x1004 | 获取存储 ID |
| GetStorageInfo | 0x1005 | 获取存储信息 |
| GetNumObjects | 0x1006 | 获取对象数量 |
| GetObjectHandles | 0x1007 | 获取对象句柄列表 |
| GetObjectInfo | 0x1008 | 获取对象信息 |
| GetObject | 0x1009 | 下载完整照片 |
| GetThumb | 0x100A | 获取缩略图 |
| DeleteObject | 0x100B | 删除对象 |

### 尼康扩展操作码

| 操作 | 代码 | 用途 |
|------|------|------|
| Nikon_GetPreview | 0x90C2 | 获取预览 |
| Nikon_StartLiveView | 0x90C3 | 开始实时取景 |
| Nikon_EndLiveView | 0x90C4 | 结束实时取景 |
| Nikon_GetDevicePropDesc | 0x90C5 | 获取设备属性描述 |
| Nikon_GetDevicePropValue | 0x90C6 | 获取设备属性值 |
| Nikon_SetDevicePropValue | 0x90C7 | 设置设备属性值 |

---

## 📝 代码示例汇总

### 完整的连接和下载流程

```typescript
// 导入所需模块
import { CameraUtils } from '../utils/CameraUtils';
import type { PhotoMeta } from '../ptpip/PtpTypes';

@Entry
@Component
struct CameraDownloadPage {
  @State cameraIp: string = '192.168.1.100';
  @State photos: PhotoMeta[] = [];
  @State isConnecting: boolean = false;
  @State downloadProgress: number = 0;

  async connectCamera() {
    this.isConnecting = true;
    const cameraUtils = CameraUtils.getInstance();
    
    try {
      // 连接相机
      const connected = await cameraUtils.connectCamera(this.cameraIp);
      if (!connected) {
        console.error('连接失败');
        return;
      }
      
      console.log('连接成功，开始扫描照片...');
      
      // 设置进度回调
      cameraUtils.setScanProgressCallback((current, total) => {
        console.log(`扫描进度: ${current}/${total}`);
      });
      
      // 扫描照片
      this.photos = await cameraUtils.getPhotoList();
      console.log(`找到 ${this.photos.length} 张照片`);
      
    } catch (error) {
      console.error('错误:', error);
    } finally {
      this.isConnecting = false;
    }
  }

  async downloadPhoto(photo: PhotoMeta) {
    const cameraUtils = CameraUtils.getInstance();
    const savePath = `/data/PhotoSend/${photo.filename}`;
    
    try {
      // 设置进度回调
      cameraUtils.setDownloadProgressCallback((progress) => {
        this.downloadProgress = progress.percentage;
      });
      
      // 下载
      const success = await cameraUtils.downloadPhoto(photo.objectHandle, savePath);
      if (success) {
        console.log('下载完成:', savePath);
      }
    } catch (error) {
      console.error('下载错误:', error);
    }
  }

  disconnectCamera() {
    const cameraUtils = CameraUtils.getInstance();
    cameraUtils.disconnectCamera();
  }

  build() {
    Column() {
      TextInput({ text: this.cameraIp })
        .onChange((value) => { this.cameraIp = value; })
        .margin({ bottom: 10 })
      
      Button('连接相机')
        .onClick(() => this.connectCamera())
        .enabled(!this.isConnecting)
      
      List() {
        ForEach(this.photos, (photo: PhotoMeta) => {
          ListItem() {
            Column() {
              Text(photo.filename)
              Text(`${(photo.size / 1024 / 1024).toFixed(2)} MB`)
              Text(photo.captureDate.toString())
              
              if (this.downloadProgress > 0) {
                Progress({ value: this.downloadProgress, total: 100 })
              }
              
              Button('下载')
                .onClick(() => this.downloadPhoto(photo))
            }
          }
        })
      }
      
      Button('断开连接')
        .onClick(() => this.disconnectCamera())
    }
    .padding(20)
  }
}
```

---

## 🔗 相关资源链接

### 官方文档
- [HarmonyOS 网络编程](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/)
- [PTP 标准文档](https://en.wikipedia.org/wiki/Picture_Transfer_Protocol)

### 相机厂商文档
- [尼康 PTP/IP 实现](https://www.nikonusa.com/)
- [佳能 EOS PTP/IP](https://www.canon.com/)

### 项目文档
- 见本项目根目录的各 markdown 文件

---

## 📞 获取帮助

### 查看现有文档
- `PROJECT_OVERVIEW.md` - 项目总体概览
- `ARCHITECTURE.md` - 系统架构
- `README_PTP_IMPLEMENTATION.md` - 实现细节
- `QUICK_START.md` - 快速开始

### 检查日志
```bash
# 从 HarmonyOS 设备查看日志
hdc shell hilog | grep PtpConnectionManager
```

### 调试技巧
1. 在 PtpConnectionManager.ets 中启用详细日志
2. 使用 HarmonyOS DevEco Studio 的调试器
3. 检查网络连接和防火墙设置
4. 验证相机 IP 地址和端口

---

最后更新：2026 年 3 月 10 日

**提示**: 这是快速参考指南。详细信息请查看对应的详细文档。

