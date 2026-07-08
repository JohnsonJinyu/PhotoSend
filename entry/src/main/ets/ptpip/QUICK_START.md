# PTP/IP 相机连接快速开始指南

## 项目目标

使用纯 ArkTS 实现 PTP/IP 协议，替代 libgphoto2，连接尼康 ZF 等相机，实现 WiFi 照片浏览和下载。

## 核心优势

✅ **无 C++ 依赖** - 100% ArkTS 实现，编译快、体积小
✅ **高性能** - 直接使用 HarmonyOS NetworkKit TCP Socket
✅ **易维护** - 代码完全可控，易于调试和扩展
✅ **标准协议** - 基于 CIPA DC-X005-2005 标准

## 文件结构

```
entry/src/main/ets/
├── ptpip/                          # PTP/IP 协议核心模块
│   ├── PtpConstants.ets           # 协议常量定义
│   ├── PtpTypes.ets               # 数据结构定义
│   ├── PtpConnectionManager.ets   # 连接管理器
│   ├── PtpClient.ets              # 高层客户端 API
│   ├── index.ets                  # 统一导出
│   └── README_PTP_IMPLEMENTATION.md  # 实现指南
├── utils/
│   └── CameraUtils.ets            # 相机工具类（单例）
└── pages/
    └── CamPhotoPreAndDownload/
        └── CamPhotoPrePagePTP.ets # 示例页面
```

## 快速上手

### 1. 连接相机

```typescript
import { CameraUtils } from '../utils/CameraUtils';

// 连接到尼康相机（默认 IP: 192.168.1.1, 端口：15740）
const connected = await CameraUtils.connectCamera('192.168.1.1');
if (connected) {
  console.log('相机连接成功!');
}
```

### 2. 扫描照片列表

```typescript
// 启动异步扫描
await CameraUtils.startAsyncScan();

// 等待扫描完成（轮询检查）
setTimeout(() => {
  const totalCount = CameraUtils.getPhotoTotalCount();
  console.log(`共找到 ${totalCount} 张照片`);
}, 5000);
```

### 3. 分页加载照片

```typescript
// 获取第 1 页，每页 20 张
const photos = CameraUtils.getPhotoMetaList(0, 20);

photos.forEach(photo => {
  console.log(`文件名：${photo.filename}`);
  console.log(`大小：${photo.fileSize} bytes`);
  console.log(`分辨率：${photo.width} x ${photo.height}`);
});
```

### 4. 下载照片

```typescript
import { fileIo } from '@kit.IO.FileIOKit';

// 下载到应用专属目录
const savePath = `${this.appStoragePath}/DSC_0001.JPG`;
const success = await CameraUtils.downloadPhoto(photo.objectId, savePath);

if (success) {
  console.log('下载成功!');
}
```

### 5. 获取缩略图

```typescript
// 获取缩略图数据（ArrayBuffer）
const thumbData = await CameraUtils.getThumbnail(photo.objectId);

if (thumbData) {
  // 可以显示为 Image 组件
  const imageSource = { data: thumbData };
}
```

### 6. 断开连接

```typescript
await CameraUtils.disconnectCamera();
```

## 完整示例

```typescript
import { CameraUtils } from '../utils/CameraUtils';
import type { PhotoMeta } from '../ptpip/PtpTypes';

@Entry
@Component
struct MyCameraPage {
  @State photoList: PhotoMeta[] = [];
  @State isConnected: boolean = false;

  async aboutToAppear() {
    // 1. 连接相机
    const connected = await CameraUtils.connectCamera('192.168.1.1');
    if (!connected) return;
    
    this.isConnected = true;
    
    // 2. 扫描照片
    await CameraUtils.startAsyncScan();
    
    // 3. 等待扫描完成后加载
    setTimeout(async () => {
      const count = CameraUtils.getPhotoTotalCount();
      const photos = CameraUtils.getPhotoMetaList(0, 20);
      this.photoList = photos;
    }, 5000);
  }

  build() {
    Column() {
      Text(this.isConnected ? '已连接相机' : '未连接')
      
      List() {
        ForEach(this.photoList, (photo: PhotoMeta) => {
          ListItem() {
            Row() {
              Text(photo.filename)
              Button('下载')
                .onClick(() => {
                  CameraUtils.downloadPhoto(photo.objectId, '/path/to/save.jpg');
                })
            }
          }
        })
      }
    }
  }
}
```

## API 参考

### CameraUtils 方法

| 方法 | 参数 | 返回值 | 说明 |
|------|------|--------|------|
| `connectCamera` | ip: string, port: number | Promise<boolean> | 连接相机 |
| `disconnectCamera` | - | Promise<void> | 断开连接 |
| `isCameraConnected` | - | boolean | 检查连接状态 |
| `startAsyncScan` | - | Promise<boolean> | 异步扫描照片 |
| `getPhotoTotalCount` | - | number | 获取照片总数 |
| `getPhotoMetaList` | pageIndex: number, pageSize: number | PhotoMeta[] | 分页获取照片 |
| `downloadPhoto` | objectId: number, savePath: string | Promise<boolean> | 下载照片 |
| `getThumbnail` | objectId: number | Promise<ArrayBuffer\|null> | 获取缩略图 |

### PhotoMeta 结构

```typescript
interface PhotoMeta {
  objectId: number;        // PTP 对象 ID
  storageId: number;       // 存储 ID
  filename: string;        // 文件名
  fileSize: number;        // 文件大小（字节）
  width: number;           // 宽度（像素）
  height: number;          // 高度（像素）
  format: number;          // 格式代码
  dateTime: string;        // 拍摄时间
  thumbAvailable: boolean; // 是否有缩略图
}
```

## 常见问题

### Q1: 相机 IP 不是 192.168.1.1 怎么办？

在相机菜单中查看 WiFi 设置，找到当前分配的 IP地址。有些相机可能使用 DHCP 自动获取 IP。

### Q2: 连接超时如何处理？

增加超时时间或重试机制:

```typescript
// 修改超时时间（需要修改 PtpConnectionManager）
ptpConnectionManager.setConnectionTimeout(10000); // 10 秒
```

### Q3: 如何知道扫描是否完成？

轮询检查:

```typescript
const checkScanComplete = setInterval(() => {
  const count = CameraUtils.getPhotoTotalCount();
  if (count > 0) {
    clearInterval(checkScanComplete);
    console.log('扫描完成');
  }
}, 1000);
```

### Q4: 下载大文件很慢怎么办？

添加进度回调:

```typescript
ptpClient.setOnDownloadProgress((progress) => {
  console.log(`下载进度：${Math.round(progress.currentProgress * 100)}%`);
});
```

### Q5: 支持哪些相机型号？

所有支持 PTP/IP 协议的尼康相机:
- Nikon Zf ✓
- Nikon Z9 ✓
- Nikon Z8 ✓
- Nikon Z7II / Z6II ✓
- Nikon Z7 / Z6 / Z5 ✓
- Nikon Z50 / Zfc ✓

## 调试技巧

### 1. 启用详细日志

在 `PtpConnectionManager.ets` 中添加:

```typescript
console.info(TAG, `发送命令：0x${operationCode.toString(16)}, TID=${transactionId}`);
console.info(TAG, `响应码：0x${response.code.toString(16)}`);
console.info(TAG, `数据长度：${data.byteLength} bytes`);
```

### 2. 使用 Wireshark 抓包

在 PC 上安装 Wireshark，过滤条件:
```
tcp.port == 15740
```

对比正常工作的官方客户端和你的实现。

### 3. 错误码查询

常见错误码:
- `0x2001` - OK ✓
- `0x2002` - General Error ✗
- `0x2019` - Device Busy (相机正忙)
- `0x201E` - Session Already Opened

## 性能优化建议

1. **缩略图缓存**: 下载的缩略图保存到本地缓存
2. **分页加载**: 避免一次性加载所有照片
3. **并发控制**: 同时下载不超过 3 张照片
4. **连接保持**: 复用 TCP 连接，避免频繁重连

## 下一步开发计划

1. ✅ 基础协议框架
2. ✅ 连接管理
3. ✅ 照片浏览
4. 🔄 完善数据解析（需根据实际相机调整）
5. 🔄 文件保存（使用 HarmonyOS FileIO）
6. 🔄 UI 集成
7. 🔄 清理 C++ 代码

## 参考资料

- [CIPA DC-X005-2005 官方文档](https://cipa.jp/std/documents/e/DC-X005.pdf)
- [ptp.js 源码](https://github.com/feklee/ptp.js)
- [gPhoto2 PTP/IP 文档](http://gphoto.org/doc/ptpip.php)

---

祝你开发顺利！📷✨
