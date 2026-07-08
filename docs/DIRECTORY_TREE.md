# PhotoSend 项目目录树状图 (详细版)

## 完整项目结构

```
PhotoSend/
│
├── 📄 oh-package.json5                    # 项目依赖配置文件
├── 📄 build-profile.json5                 # 项目编译配置
├── 📄 build-profile.json5.backup          # 编译配置备份
├── 📄 code-linter.json5                   # 代码检查规则
├── 📄 local.properties                    # 本地配置
├── 📄 hvigorfile.ts                       # Hvigor 构建脚本
├── 📄 oh-package-lock.json5               # 依赖锁定文件
│
├── 📋 PROJECT_OVERVIEW.md                 # [新] 项目总体概览
├── 📋 ARCHITECTURE.md                     # [新] 系统架构文档
├── 📋 QUICK_REFERENCE.md                  # [新] 快速参考指南
├── 📋 REFACTOR_SUMMARY.md                 # 重构总结
├── 📋 PTPIP_USAGE_GUIDE.md                # PTP/IP 使用指南
├── 📋 CLEANUP_GUIDE.md                    # 清理指南
│
├── 📁 AppScope/                           # 应用全局配置
│   ├── 📄 app.json5                       # 应用清单 (包名、版本、权限等)
│   └── 📁 resources/
│       └── 📁 base/
│           ├── 📁 element/                # 元素资源 (字符串、颜色等)
│           └── 📁 media/                  # 媒体资源 (图片、图标)
│
├── 📁 entry/                              # 主应用模块
│   ├── 📄 oh-package.json5                # 模块依赖配置
│   ├── 📄 oh-package-lock.json5           # 依赖锁定
│   ├── 📄 hvigorfile.ts                   # 模块构建脚本
│   ├── 📄 build-profile.json5             # 模块编译配置
│   ├── 📄 obfuscation-rules.txt           # 代码混淆规则
│   ├── 📄 readme.md                       # 模块说明
│   │
│   ├── 📁 src/main/
│   │   │
│   │   ├── 📄 module.json5                # 模块清单
│   │   │
│   │   ├── 📁 ets/                        # ★ 核心代码目录
│   │   │   │
│   │   │   ├── 📁 ptpip/                  # ★★★ PTP/IP 协议核心模块 (CORE)
│   │   │   │   ├── 📄 PtpConnectionManager.ets    # [1159 行] 连接管理器 ⭐
│   │   │   │   │                          # 职责: TCP 连接、会话管理、命令发送
│   │   │   │   ├── 📄 PtpClient.ets               # [456 行] 高层 API ⭐
│   │   │   │   │                          # 职责: 扫描、下载、进度管理
│   │   │   │   ├── 📄 PtpConstants.ets            # [219 行] 协议常量
│   │   │   │   │                          # 操作码、响应码、格式码、数据类型
│   │   │   │   ├── 📄 PtpTypes.ets                # [145 行] 数据结构
│   │   │   │   │                          # PtpDeviceInfo, PhotoMeta, 等
│   │   │   │   ├── 📄 PtpCompatLayer.ets         # 兼容性处理
│   │   │   │   │                          # 处理尼康、佳能、索尼差异
│   │   │   │   ├── 📄 index.ets                   # 统一导出文件
│   │   │   │   ├── 📋 README_PTP_IMPLEMENTATION.md
│   │   │   │   └── 📋 QUICK_START.md
│   │   │   │
│   │   │   ├── 📁 pages/                  # UI 页面
│   │   │   │   ├── 📄 HomePage.ets                # 主页 (底部标签栏)
│   │   │   │   │
│   │   │   │   ├── 📁 CameraPage/                 # 相机页面
│   │   │   │   │   ├── 📄 CameraPage.ets         # 相机连接和照片浏览
│   │   │   │   │   └── 📄 CameraPagePreview.ets  # 预览模式
│   │   │   │   │
│   │   │   │   ├── 📁 PhoneLocalPhotos/          # 手机本地照片页面
│   │   │   │   │   ├── 📄 PhoneLocalPhotos.ets
│   │   │   │   │   └── 📄 ...
│   │   │   │   │
│   │   │   │   ├── 📁 MinePage/                   # 我的页面
│   │   │   │   │   ├── 📄 MinePage.ets
│   │   │   │   │   └── 📄 MinePagePreview.ets
│   │   │   │   │
│   │   │   │   ├── 📁 CamPhotoPreAndDownload/    # 相机照片预览和下载
│   │   │   │   │   └── 📄 ...
│   │   │   │   │
│   │   │   │   ├── 📁 RemoteControl/             # 远程控制页面
│   │   │   │   │   └── 📄 ...
│   │   │   │   │
│   │   │   │   └── 📄 RemoteTest.ets             # 测试页面
│   │   │   │
│   │   │   ├── 📁 components/             # 自定义组件
│   │   │   │   └── 📁 CameraControlDialog/       # 相机控制对话框
│   │   │   │       └── 📄 ...
│   │   │   │
│   │   │   ├── 📁 utils/                  # 工具和服务
│   │   │   │   ├── 📄 CameraUtils.ets            # 相机工具 (单例模式) ⭐
│   │   │   │   │                          # 与 PtpClient 交互的中间层
│   │   │   │   ├── 📄 PtpConnectionManager.ets   # 连接管理辅助
│   │   │   │   │
│   │   │   │   ├── 📁 animation/                 # 动画工具
│   │   │   │   │   └── 📄 ...
│   │   │   │   │
│   │   │   │   └── 📁 tools/                     # 工具函数集
│   │   │   │       ├── 📄 CreateLocalDir.ets    # 创建本地目录
│   │   │   │       └── 📄 ...
│   │   │   │
│   │   │   ├── 📁 common/                 # 公共资源
│   │   │   │   └── 📁 constants/                 # 应用级常量
│   │   │   │       └── 📄 ...
│   │   │   │
│   │   │   ├── 📁 CustomTransition/       # 自定义转场动画
│   │   │   │   └── 📄 CustomNavigationUtils.ets
│   │   │   │
│   │   │   ├── 📁 workers/                # 后台任务
│   │   │   │   └── 📄 ...
│   │   │   │
│   │   │   ├── 📁 types/                  # TypeScript 类型定义
│   │   │   │   └── 📄 ...
│   │   │   │
│   │   │   ├── 📁 entryability/           # 应用入口
│   │   │   │   └── 📄 EntryAbility.ets    # 应用生命周期管理
│   │   │   │
│   │   │   ├── 📁 entrybackupability/     # 备用入口
│   │   │   │   └── 📄 ...
│   │   │   │
│   │   │   └── 📁 NodeContainer/          # 节点容器
│   │   │       └── 📄 ...
│   │   │
│   │   ├── 📁 cpp/                        # C++ 代码
│   │   │   └── 📁 types/
│   │   │       └── 📄 libentry (原生库绑定)
│   │   │
│   │   └── 📁 resources/                  # 应用资源
│   │       ├── 📁 base/
│   │       │   ├── 📁 element/            # UI 元素 (字符串、颜色等)
│   │       │   │   ├── 📄 string.json5    # 字符串资源
│   │       │   │   ├── 📄 color.json5     # 颜色资源
│   │       │   │   └── 📄 ...
│   │       │   └── 📁 media/              # 图片、图标等
│   │       │       ├── 📄 ic_launcher.svg
│   │       │       ├── 📄 bg_*.png
│   │       │       └── 📄 ...
│   │       ├── 📁 dark/                   # 深色主题资源
│   │       │   └── 📄 ...
│   │       └── 📁 rawfile/                # 原始文件 (JSON 配置等)
│   │           └── 📄 ...
│   │
│   ├── 📁 build/                          # 编译输出
│   │   ├── 📁 config/
│   │   │   └── 📄 buildConfig.json        # 编译配置信息
│   │   └── 📁 default/
│   │       ├── 📁 cache/                  # 编译缓存
│   │       ├── 📁 generated/              # 生成的代码
│   │       ├── 📁 intermediates/          # 中间文件
│   │       ├── 📁 outputs/
│   │       │   ├── 📄 pac.json            # PAC 信息
│   │       │   ├── 📄 pack.info           # 打包信息
│   │       │   └── 📦 PhotoSend-default-unsigned.app  # ⭐ 输出的 APP 文件
│   │       └── 📄 ...
│   │
│   └── 📁 libs/                           # 原生库集合 (arm64-v8a)
│       └── 📁 arm64-v8a/
│           ├── 📄 libgphoto2.so                   # gphoto2 主库 (已废弃)
│           ├── 📄 libgphoto2_port.so              # gphoto2 端口库
│           │
│           ├── 📄 cannon.so                       # 佳能驱动
│           ├── 📄 nikon.so                        # 尼康驱动
│           ├── 📄 pentax.so                       # 宾得驱动
│           ├── 📄 sony.so                         # 索尼驱动 (可能)
│           │
│           ├── 📄 libcrypto.so, libcrypto.so.1.1 # OpenSSL
│           ├── 📄 libcurl.so, libcurl.so.4       # cURL 网络库
│           ├── 📄 libssl.so, libssl.so.1.1       # SSL 库
│           ├── 📄 libusb-1.0.so                  # USB 库
│           ├── 📄 libxml2.so                     # XML 库
│           ├── 📄 libz.so                        # 压缩库
│           │
│           ├── 📄 libjpeg.so, libturbojpeg.so   # JPEG 编码
│           ├── 📄 libpng.so                      # PNG 编码
│           ├── 📄 libraw.so                      # RAW 格式处理
│           ├── 📄 libexif.so                     # EXIF 元数据
│           │
│           ├── 📄 libltdl.so                     # 动态加载库
│           ├── 📄 libltdl.so.7                   # 动态加载库 (版本)
│           │
│           ├── 📄 ax203.so                       # 设备驱动
│           ├── 📄 digigr8.so
│           ├── 📄 dimagev.so
│           ├── 📄 directory.so
│           ├── 📄 disk.so
│           ├── 📄 jl2005*.so
│           ├── 📄 kodak_dc240.so
│           ├── 📄 lumix.so
│           ├── 📄 mars.so
│           ├── 📄 ptp2.so
│           ├── 📄 ptpip.so                       # ★ PTP/IP 驱动 (已被 ArkTS 实现替代)
│           ├── 📄 quicktake1x0.so
│           ├── 📄 ricoh_g3.so
│           ├── 📄 sierra.so
│           ├── 📄 sonix.so
│           ├── 📄 sq905.so
│           ├── 📄 st2205.so
│           ├── 📄 topfield.so
│           ├── 📄 tp6801.so
│           ├── 📄 usb1.so
│           ├── 📄 usbdiskdirect.so
│           └── 📄 usbscsi.so
│
├── 📁 oh_modules/                         # HarmonyOS 模块依赖
│   ├── 📁 libentry.so/
│   │   ├── 📄 Index.d.ts                  # TypeScript 类型定义
│   │   └── 📄 oh-package.json5
│   │
│   └── 📁 @ohos/
│       ├── 📁 hamock/                     # Mock 测试框架
│       │   ├── 📄 ...
│       │   └── 📄 package.json
│       │
│       └── 📁 hypium/                     # 单元测试框架
│           ├── 📄 ...
│           └── 📄 package.json
│
└── 📁 hvigor/                             # Hvigor 构建系统
    └── 📄 hvigor-config.json5             # Hvigor 配置
```

---

## 📊 目录说明

### 1️⃣ **根目录层** 
包含项目全局配置文件和文档

### 2️⃣ **AppScope 层**
应用全局资源和配置

### 3️⃣ **entry 层 - 核心应用模块**

#### entry/src/main/ets/ - 代码核心
- **ptpip/** - ★★★ PTP/IP 协议实现 (项目核心)
  - 1159 行代码主要集中在 PtpConnectionManager.ets
  - 处理所有网络通信、会话管理、命令发送
  
- **pages/** - UI 页面 (6+ 个主要页面)
  - HomePage 主容器
  - CameraPage 相机功能
  - 其他页面
  
- **utils/** - 辅助工具
  - CameraUtils 单例服务类
  - 其他工具函数
  
- **components/** - 自定义组件
  
- **entryability/** - 应用入口

#### entry/src/main/resources/ - 资源文件
- 字符串、颜色、图标等

#### entry/libs/arm64-v8a/ - 原生库
- 30+ 个预编译库文件
- **注意**: 大多数已被 ArkTS 实现替代，但保留以备向后兼容

### 4️⃣ **oh_modules 层**
外部依赖模块

### 5️⃣ **build/ 层**
编译输出产物

---

## 🎯 关键文件速查

### 最重要的文件 (按重要性排序)

| 重要性 | 文件 | 行数 | 位置 |
|--------|------|------|------|
| ⭐⭐⭐ | PtpConnectionManager.ets | 1159 | entry/src/main/ets/ptpip/ |
| ⭐⭐⭐ | PtpClient.ets | 456 | entry/src/main/ets/ptpip/ |
| ⭐⭐ | CameraUtils.ets | ? | entry/src/main/ets/utils/ |
| ⭐⭐ | HomePage.ets | 214 | entry/src/main/ets/pages/ |
| ⭐ | PtpConstants.ets | 219 | entry/src/main/ets/ptpip/ |
| ⭐ | PtpTypes.ets | 145 | entry/src/main/ets/ptpip/ |

---

## 📦 包体积分析

```
PhotoSend-default-unsigned.app
├── ArkTS 代码                  ~ 500 KB
├── UI 资源 (图片、字符串)      ~ 1 MB
├── 原生库 (libs/)              ~ 50 MB (可选)
│   ├── libgphoto2.so          ~ 2 MB
│   ├── libcurl.so             ~ 1 MB
│   ├── 其他库                 ~ 47 MB
│
└── 其他资源                    ~ 1-2 MB

总计: ~52-53 MB (含原生库)
      ~2-3 MB (仅 ArkTS 实现，无原生库)
```

---

## 🔄 代码流向概览

```
用户界面
  ↓
HomePage (页面容器)
  ↓
CameraPage (相机页面)
  ↓
CameraUtils.getInstance() (单例服务)
  ↓
PtpClient (高层 API)
  ↓
PtpConnectionManager (协议实现)
  ↓
@kit.NetworkKit (TCP Socket)
  ↓
相机设备 (WiFi)
```

---

## 🛠️ 开发工作流

```
开发新功能
  ↓
修改 entry/src/main/ets 中的相关文件
  ↓
使用 HarmonyOS DevEco Studio 编译
  ↓
输出到 entry/build/default/outputs/
  ↓
生成 PhotoSend-default-unsigned.app
  ↓
部署到设备或模拟器
  ↓
测试和调试
```

---

## 📝 文档说明

本项目包含以下文档:

| 文档 | 位置 | 内容 |
|------|------|------|
| PROJECT_OVERVIEW.md | 根目录 | [新] 项目总体概览 |
| ARCHITECTURE.md | 根目录 | [新] 系统架构详解 |
| QUICK_REFERENCE.md | 根目录 | [新] 快速参考指南 |
| REFACTOR_SUMMARY.md | 根目录 | 重构总结 |
| PTPIP_USAGE_GUIDE.md | 根目录 | PTP/IP 使用指南 |
| CLEANUP_GUIDE.md | 根目录 | 清理指南 |
| README_PTP_IMPLEMENTATION.md | ptpip/ | PTP/IP 实现指南 |
| QUICK_START.md | ptpip/ | 快速开始 |

---

最后更新：2026 年 3 月 10 日

**说明**: 
- ⭐ 表示重要等级
- 📄 表示文件
- 📁 表示目录
- 📋 表示文档
- 📦 表示应用包
- ★ 表示核心模块

