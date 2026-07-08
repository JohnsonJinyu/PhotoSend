# PTP/IP 会话建立排查结论（Nikon Zf）

## 当前结论

截至 **2026-03-14 08:29** 的最新日志，问题已经进入 **“会话前置条件 / Nikon 专有会话建立条件”** 排查阶段。

结合最新现场观察：
- 手机连接 Nikon Zf 热点后
- **官方 App 很快连接成功**
- 但切回 PhotoSend 时，**相机热点关闭**

当前最合理的主结论：

1. **TCP 命令连接正常**
2. **`Init_Command_Request / Init_Command_Ack` 握手稳定成功**
3. **`OpenSession` 在多种封装、多个客户端身份下都被 Nikon Zf 静默忽略**
4. **官方 App 已能证明普通 Wi‑Fi/TCP 层不是当前主因**
5. **热点在官方 App 成功后关闭，强烈指向 Nikon 专有状态切换 / 单客户端独占 / 会话保持机制**
6. `15741` 事件连接仍是独立问题，但已不是当前日志里的首个失败点

因此，后续排查重点应从“基础包格式”进一步转向：
- Nikon Zf 的 **会话前置条件**
- Nikon Wi‑Fi 模式下是否存在 **专有身份/配对/控制权限门槛**
- 官方 App 是否先完成了 **application mode / 状态保持 / 单客户端占用**

---

## 已验证通过的事项

### 1. 命令连接层
- 能稳定连接 `192.168.1.1:15740`
- `tcpSocket.connect()` 成功
- 命令连接可写

### 2. PTP/IP 初始握手层
- `Init_Command_Request` 已发送成功
- `Init_Command_Ack` 能稳定返回
- 返回包长度稳定为 `56` 字节
- `Connection Number` 可正确解析，且会递增变化（如 `1 / 2 / 4 / 5`）

### 3. 已排除的若干简单原因
- 不是热点未连接
- 不是命令 TCP 不通
- 不是 `Init_Command_Ack` 分段读取失败
- 不是单纯的 `Session ID / Connection Number` 混淆
- 不是 `OpenSession` 的 `TransactionID != 0`
- 不是仅仅 `PTP/IP OperationRequest` 与 raw PTP container 二选一错误
- 不是仅仅普通 `deviceName` 文本变体（`Nikon / MobileDevice / AndroidPhone / 空字符串`）

---

## 已做过且已验证“仍失败”的实验

### 实验 A：`OpenSession` 使用 PTP/IP `OperationRequest`
- 格式：`22` 字节
- `dataPhase = 3`
- `tid = 0`
- 结果：**5 秒内 0 字节响应**

### 实验 B：`OpenSession` 使用 raw PTP command container
- 格式：`16` 字节
- `tid = 0`
- 在全新命令连接上单独尝试
- 结果：**5 秒内 0 字节响应**

### 实验 C：`OpenSession` 前预建事件连接
- 目标端口：`15741`
- 结果：重复得到 `2301115 / Operation in progress`
- 但始终无法进入真正可发送状态
- 未拿到 `Init_Event_Ack`

### 实验 D：事件连接重试
- 连续 5 次重试
- 结果：始终未真正建立成功

### 实验 E：`15740` 单通道 5-case 干净实验矩阵
- 完全绕开：
  - 手工 `15741`
  - `Init_Event_Request`
  - 自动重连
  - 复杂 fallback
- 仅保留 `15740 + 握手 + OpenSession`
- 覆盖 case：
  1. `nikon-fixed-ptpip`
  2. `nikon-fixed-raw`
  3. `mobile-device-ptpip`
  4. `android-phone-ptpip`
  5. `empty-name-ptpip`
- 结果：**全部在 5 秒内 0 字节响应**

---

## 现在最像什么问题

### 主线：Nikon Zf 的专有控制状态机未被 PhotoSend 满足
从日志和现场观察看，Nikon Zf 已经“接受连接”，但不接受 PhotoSend 的 `OpenSession`；而官方 App 却能很快成功，随后热点关闭。

这更像说明 Nikon Zf 并非只要求一个标准 PTP/IP 数据包，而是至少要求满足下面某一项：

1. **必须进入 Nikon 官方预期的 application mode / 控制模式**
2. **必须先经过某种应用身份确认 / 配对上下文**
3. **存在单客户端独占 / 官方 App 负责会话保持**
4. **当前热点模式允许握手，但控制会话必须由特定工作流触发**

### 次线：相机当前模式仍需现场核对
若官方 App 实际只进入浏览态，或机身模式并非远程控制模式，则仍可能是：
- 当前相机模式本身就不开放完整控制
- 不是 PhotoSend 包格式问题

### 并行次线：HarmonyOS `NetworkKit` / `15741`
端口 `15741` 的连接尝试此前总是返回：
- `2301115`
- `Operation in progress`

但最新一轮 5-case 单通道实验已经表明：
- 即便完全不触发 `15741`
- `OpenSession` 依旧被静默忽略

这说明：
- `15741` 仍然是独立故障点
- **但已经不是当前首个失败点**

---

## 当前不建议继续优先深挖的方向

以下方向已经不是最高优先级：

1. 继续只改 `OpenSession` 包长度
2. 继续只改 `TransactionID`
3. 继续只在同一条命令连接里切换 16/22 字节格式
4. 继续只调 `readBytes` 超时
5. 继续只调 `Connection Number` / `Session ID`
6. 继续只扩展普通 `deviceName` 变体
7. 继续把 `15741` 当作当前首因

这些都已经做过关键验证，收益开始明显下降。

---

## 建议的下一步排查主线

### 方向 1：确认官方 App 触发了什么状态切换
建议优先核对：
- 官方 App 成功后，热点是立即关闭还是延时关闭
- 官方 App 是否必须保持前台才能维持当前状态
- 相机端是否出现“已连接 / 控制中 / 被占用”提示
- 切回第三方 App 是否必然导致会话丢失

### 方向 2：确认 Nikon Zf 当前 Wi‑Fi 模式是否真的允许 PTP 会话
建议核对相机端：
- 当前是“仅热点浏览/传图模式”还是“远程控制/PTP 模式”
- 是否需要进入特定菜单后才开放完整控制
- 是否必须由 Nikon 官方 App 先激活控制会话
- 是否存在“允许握手但不允许控制”的热点模式

### 方向 3：继续模拟 Nikon 官方客户端上下文
后续若继续代码侧兼容，优先尝试：
- GUID 变化策略（固定 / 随机 / 更接近 Nikon 官方模式）
- 更严格对齐 Nikon 官方客户端的连接时序
- 保活 / 心跳 / 模式切换后的状态保持逻辑

### 方向 4：把 `15741` 保持为并行次线
建议继续记录：
- 每次 `15741` 连接是否都只返回 `2301115`
- 是否存在更长等待后成功的情况
- 是否必须在命令连接保持某种状态时才允许第二连接

但它不应继续压过“会话前置条件”主线。

---

## 当前阶段性结论（一句话）

**当前问题已从“基础 PTP/IP 握手问题”收敛为“官方工作流驱动的会话前置条件未满足”，而“官方 App 一成功、切回 PhotoSend 热点就关闭”的观察进一步指向 Nikon 专有状态机、单客户端独占与会话保持机制。**

建议后续回溯时优先参考：
- `docs/NIKON_ZF_FIELD_TRIAGE.md`
- `docs/PTPIP_DEBUG_TIMELINE.md`
- `NIKON_ZF_FIX_GUIDE.md`
- `entry/src/main/ets/ptpip/PtpConnectionManager.ets`
