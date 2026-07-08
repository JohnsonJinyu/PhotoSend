# PTP/IP 调试时间线（Nikon Zf）

> 目的：记录每一轮关键实验、对应日志、观察结果、结论与下一步，便于后续回溯。

---

## 环境背景
- 项目：`PhotoSend`
- 机型：`Nikon Zf`
- 手机：`HUAWEI Pura 80 Pro+`
- 热点目标：`192.168.1.1:15740`
- 事件端口：`15741`
- 当前实现：`entry/src/main/ets/ptpip/PtpConnectionManager.ets`

---

## 2026-03-10 ~ 2026-03-13 早期阶段

### 阶段目标
先打通基础 PTP/IP 链路：
- TCP 连接
- `Init_Command_Request`
- `Init_Command_Ack`

### 关键进展
- 命令 TCP 连接成功
- `Init_Command_Ack` 可返回
- `Connection Number` 可解析
- 包读取从“硬编码长度”改成“头 + 体”动态读取

### 阶段结论
基础握手已被打通，问题从“连不上/读不到握手包”转向“握手后无法打开会话”。

---

## 2026-03-13 22:25 左右
日志：`HiLog-...-1773411980395.txt`

### 实验
- `OpenSession` 使用 `PTP/IP OperationRequest`
- 事件连接放在失败恢复路径中

### 观察
- `Init_Command_Ack` 稳定成功
- `OpenSession` 发送 `22` 字节后，5 秒内 `0` 字节响应
- 事件连接进入 `2301115 / Operation in progress`
- 随后 `writeDataToEventSocket` 返回 `2301107 / Socket not connected`

### 结论
- 第一次 `OpenSession` 的失败独立于事件连接
- 事件 socket 之前存在“假成功”判定

### 下一步
- 修正事件连接判定
- 增加 `OpenSession` 数据包细粒度日志

---

## 2026-03-13 22:39 左右
用户贴出日志片段

### 实验
- 记录 `OpenSession` 的 `dataPhase`
- 保留事件连接可写性探测

### 关键日志
- `[buildCommandPacket] op=0x1002, tid=1, dataPhase=3, totalLength=22`
- `OpenSession` 仍然 `0` 字节超时
- 事件连接探测持续 `Socket not connected`

### 结论
- 单纯 `dataPhase=3` 不能保证 Nikon Zf 接受 `OpenSession`
- 事件连接问题被进一步证实，但不是首个失败点

### 下一步
- 尝试 raw PTP command container 兼容路径

---

## 2026-03-13 22:46 左右
用户贴出日志片段

### 实验
- `OpenSession` 先走 `PTP/IP OperationRequest`
- 超时后在同一命令连接里回退到 raw `16` 字节容器

### 观察
- `22` 字节路径超时
- `16` 字节 raw 路径也超时
- 事件连接仍未真正建立

### 阶段结论
- 不能只盯着 22 字节包封装
- 但同一连接里的第二种格式测试存在污染风险，尚不能完全否定 raw 路径

### 下一步
- 让两种 `OpenSession` 封装在独立的新鲜命令连接上测试

---

## 2026-03-13 22:53 左右
用户贴出日志片段

### 实验
- `OpenSession` 前先尝试建立事件连接
- 事件连接改为真实 connect 重试，不再“sleep 后假成功”

### 观察
- `15741` 连续 5 次：`2301115 / Operation in progress`
- 最终：`事件连接重试耗尽`
- 即便事件连接前置，也未能解锁 `OpenSession`

### 结论
- 事件连接前置没有直接解决问题
- `15741` 连接行为本身就是一个独立故障点

### 下一步
- 检查 `OpenSession` 公共字段，重点验证 `TransactionID=0`

---

## 2026-03-13 22:56 左右
用户贴出日志片段

### 实验
- 将 `OpenSession` 的 `TransactionID` 固定为 `0`
- 同时保留 `PTP/IP` 与 raw 两条路径

### 观察
- `[buildCommandPacket] op=0x1002, tid=0, dataPhase=3, totalLength=22`
- `[buildRawCommandPacket] op=0x1002, tid=0, totalLength=16`
- 两条路径均在 5 秒内 `0` 字节超时
- `15741` 仍无法建立

### 结论
- `TransactionID != 0` 已被排除为首因
- “同一连接污染”仍未完全排除

### 下一步
- raw 路径改为优先使用
- raw 失败后重建命令连接并重新握手，再测 `PTP/IP OperationRequest`

---

## 2026-03-13 23:03 左右
用户贴出日志片段

### 实验
- **raw `OpenSession` 先试**
- 若 raw 超时，则：
  - 重建命令连接
  - 重新握手
  - 再试 `PTP/IP OperationRequest`

### 关键日志
- `raw OpenSession（tid=0）`：无响应
- `reconnectCommandChannel`：成功重建命令连接
- 新连接重新握手成功，`Connection Number=4`
- `PTP/IP OperationRequest（tid=0）`：仍无响应
- 事件连接 `15741`：5 次均 `2301115 / Operation in progress`

### 当前最强结论
1. raw 路径在**新鲜连接**上也失败
2. `PTP/IP OperationRequest` 在**新鲜连接**上也失败
3. 事件连接依旧未真正建立
4. 问题已进入：
   - **Nikon Zf 会话建立前置条件**
   - **HarmonyOS `NetworkKit` 事件 socket 行为**
   的联合排查阶段

### 当前不再优先的方向
- 单纯再改 `TransactionID`
- 单纯再改 `22/16` 字节封装
- 单纯再改 `Session ID / Connection Number`
- 单纯延长读取超时

### 后续建议实验矩阵
| 实验方向 | 目的 | 状态 |
|---|---|---|
| Nikon 设备名称变体 | 验证客户端身份门槛 | 待做 |
| GUID 变体 / 随机 GUID | 验证身份/配对关联 | 待做 |
| 相机端 Wi‑Fi / 远程控制模式核对 | 验证是否真的开放 PTP 会话 | 待做 |
| `15741` 连接模型替代实现 | 排除 `NetworkKit` 行为差异 | 待做 |
| 模拟 Nikon 官方连接顺序 | 验证是否存在 SnapBridge 式前置条件 | 待做 |

---

## 2026-03-14 08:29 左右
日志：`HiLog-...-1773448182170.txt`

### 实验
- 启用**最小会话实验模式**，完全绕开：
  - 手工 `15741`
  - `Init_Event_Request`
  - 自动重连
  - 复杂 fallback
- 仅使用 `15740` 命令通道，执行 5 组单变量实验矩阵：
  1. `nikon-fixed-ptpip`
  2. `nikon-fixed-raw`
  3. `mobile-device-ptpip`
  4. `android-phone-ptpip`
  5. `empty-name-ptpip`
- 每个非首 case 都在**全新命令连接**上重新握手后再测 `OpenSession`

### 关键观察
- `15740` TCP 连接稳定成功
- 每轮 `Init_Command_Ack` 都稳定返回，`Connection Number` 递增（`1 -> 5`）
- 5 个 case 的 `OpenSession` 全部都在 5 秒内 `0` 字节响应：
  - `PTP/IP OperationRequest`：超时
  - raw `16` 字节容器：超时
  - `deviceName=Nikon / MobileDevice / AndroidPhone / <empty>`：全部超时
- 最终 UI / 日志统一提示：
  - `已连接到相机端口并完成握手，但所有 15740 单通道 OpenSession 实验均未获得有效响应`

### 新增结论
1. **`15741` 不是本轮首个阻塞点**，因为本轮完全未参与失败链路
2. **`OpenSession` 的 22/16 字节封装不是高优先级方向**，因为两条路径在新鲜连接上都失败
3. **简单客户端名称变体不是高优先级方向**，因为 `Nikon / MobileDevice / AndroidPhone / 空字符串` 全部无响应
4. 问题进一步收敛为：
   - **Nikon Zf 会话建立前置条件 / 模式门槛**
   - **Nikon 专有身份 / 配对 / 控制授权上下文**

### 当前应下调优先级的方向
- 继续只改 `15741` 时序
- 继续只改 `OpenSession` 包长度
- 继续只改 `TransactionID`
- 继续只扩展普通 `deviceName` 字符串组合

### 下一步建议
- 优先核对相机端：
  - 当前 Wi‑Fi 模式是否真的是远程控制/PTP 模式
  - 是否需要 Nikon 官方 App 先激活控制会话
  - 是否存在“允许握手、不允许控制”的热点模式
- 代码侧若继续实验，优先做：
  - **更贴近 Nikon 官方客户端的 GUID / 时序 / 配对上下文模拟**
  - 而不是继续只在 `OpenSession` 封装层打转

---

## 2026-03-14 现场对照实验
用户现场反馈

### 观察
- 手机先连接 Nikon Zf 热点
- Nikon 官方 App **很快连接成功**
- 切回 PhotoSend 时，**相机热点关闭**

### 新增判断
1. **普通 Wi‑Fi / TCP 层不是当前主因**
   - 因为官方 App 已可快速完成连接
2. **官方 App 很可能触发了 Nikon 专有状态切换**
   - 更像进入某种 application mode / 控制态 / 独占会话
3. **热点关闭** 强烈提示：
   - 官方 App 负责维持当前会话
   - 或 Nikon Zf 当前工作流存在单客户端独占 / 状态保持要求
4. 这进一步解释了为什么：
   - PhotoSend 可以完成握手
   - 但 `OpenSession` 在多轮实验里都被静默忽略

### 对排查优先级的影响
- **上调优先级**：
  - Nikon 官方工作流 / application mode
  - 专有初始化 / 授权上下文
  - 单客户端独占 / 会话保持
- **下调优先级**：
  - 普通 Wi‑Fi 是否连通
  - `15740` 端口是否正确
  - 单纯 `OpenSession` 封装细节

### 下一步
- 按 `docs/NIKON_ZF_FIELD_TRIAGE.md` 继续记录：
  - 热点是立即关闭还是延时关闭
  - 官方 App 是否必须保持前台
  - 切回 PhotoSend 前后，相机端是否出现“已连接/控制中/被占用”提示

---

## 当前阶段性判断

**已进入“会话前置条件排查”阶段。**

也就是说，当前更像：
- Nikon Zf 愿意接受基础握手
- 但不愿意为当前客户端开放真正的 PTP 会话
- 同时 HarmonyOS 上的 `15741` 事件连接也未被成功建立
- 且最新证据表明：**即便完全绕开 `15741`，`OpenSession` 依旧被静默忽略**

这份时间线应与以下文档配合阅读：
- `docs/PTPIP_SESSION_TRIAGE.md`
- `NIKON_ZF_FIX_GUIDE.md`
- `docs/DOCUMENTATION_INDEX.md`
