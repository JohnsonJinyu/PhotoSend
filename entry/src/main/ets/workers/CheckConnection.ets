import { ErrorEvent, MessageEvents, ThreadWorkerGlobalScope, worker } from '@kit.ArkTS';
import nativeCamera from 'libentry.so'
import { CheckMessage, CheckMsgType} from '../utils/tools/cam_connect_type'


const workerPort: ThreadWorkerGlobalScope = worker.workerPort;

let isPaused: boolean = false; // 区别于 stop（停止=清空定时器+重置状态）

// 检测间隔（5秒）
const CHECK_INTERVAL = 3000


// 用于存储上一次的检测结果，以判断状态是否发生变化
let lastCheckedState: boolean | null = null;

// 定时器ID
let checkTimer: number = -1;

//===============================核心检测函数=====================
/**
 * 核心检测函数
 * 1. 调用底层接口获取连接状态
 * 2. 与上一次状态对比，如果发生变化，则发送消息给主线程
 * 3. 更新上一次状态记录
 */
async function doCheck() {
  // 新增：如果是暂停状态，直接跳过检测（定时器不停止）
  if (isPaused) {
    console.log(`Worker 处于暂停状态，跳过本次检测`);
    return;
  }
  try {
    const rawState = nativeCamera.IsCameraConnected();
    const isConnected = typeof rawState === 'boolean' ? rawState : false;
    console.log(`Worker检测：底层返回=${rawState} → 处理后=${isConnected}，上一次=${lastCheckedState}`);

    if (isConnected !== lastCheckedState || lastCheckedState === null) {
      const resultMsg: CheckMessage = { type: CheckMsgType.CHECK_RESULT, data: isConnected };
      workerPort.postMessage(resultMsg);
      console.log(`Worker发送状态：${isConnected}`);
      lastCheckedState = isConnected;

      // 新增：检测到断开连接，自动停止检测（清空定时器+重置状态）
      if (!isConnected) {
        console.log(`Worker检测到断开，自动停止检测`);
        if (checkTimer !== -1) {
          clearInterval(checkTimer);
          checkTimer = -1;
          lastCheckedState = null;
        }
      }
    }
  } catch (error) {
    const err = error as Error;
    console.error(`Worker检测异常：${err.message}`);
    workerPort.postMessage({ type: CheckMsgType.ERROR, data: err.message });
    lastCheckedState = null;
  }
}

/**
 * Defines the event handler to be called when the worker thread receives a message sent by the host thread.
 * The event handler is executed in the worker thread.
 *@description 处理主线程消息
 * @param event message data
 */
workerPort.onmessage = (event: MessageEvents) => {
  const msg = event.data as CheckMessage;
  console.log(`Worker收到消息：${msg.type}`);

  switch (msg.type) {
    case CheckMsgType.START_CHECK:
      if (checkTimer === -1) {
        doCheck(); // 立即检测
        checkTimer = setInterval(doCheck, CHECK_INTERVAL);
        isPaused = false; // 启动时自动解除暂停
        console.log(`Worker启动检测，间隔=${CHECK_INTERVAL}ms`);
      }
      break;

    case CheckMsgType.STOP_CHECK:
      if (checkTimer !== -1) {
        clearInterval(checkTimer);
        checkTimer = -1;
        lastCheckedState = null;
        isPaused = false; // 停止时重置暂停状态
        console.log(`Worker停止检测`);
      }
      break;

    // 新增：暂停检测（保留定时器，仅跳过检测逻辑）
    case CheckMsgType.PAUSE_CHECK:
      isPaused = true;
      console.log(`Worker暂停检测`);
      break;

    // 新增：恢复检测（从暂停状态继续）
    case CheckMsgType.RESUME_CHECK:
      isPaused = false;
      doCheck(); // 恢复后立即执行一次检测
      console.log(`Worker恢复检测`);
      break;
  }
};

/**
 * Defines the event handler to be called when the worker receives a message that cannot be deserialized.
 * The event handler is executed in the worker thread.
 * @description worker异常处理
 * @param event message data
 */
workerPort.onmessageerror = (event: MessageEvents) => {
  console.error(`Worker消息解析失败：${event.data}`);
  const errorMsg: CheckMessage = {
    type: CheckMsgType.ERROR,
    data: `消息解析失败：${event.data}`
  };
  try {
    workerPort.postMessage(errorMsg);
  } catch (error) {

    console.error(`check connection woker error:${error}`)
  }

};

/**
 * Defines the event handler to be called when an exception occurs during worker execution.
 * The event handler is executed in the worker thread.
 *
 * @param event error message
 */
workerPort.onerror = (event: ErrorEvent) => {
  console.error(`Worker 内部异常: ${event.message} (行号: ${event.lineno})`);
  const errorMsg: CheckMessage = {
    type: CheckMsgType.ERROR,
    data: `Worker异常: ${event.message}`
  };
  try {
    workerPort.postMessage(errorMsg);
  } catch (error) {

    console.error(`check connection woker error:${error}`)
  }
};