import { ErrorEvent, MessageEvent, MessageEvents, ThreadWorkerGlobalScope, worker } from '@kit.ArkTS';
import nativeCamera from 'libentry.so'
import { fileIo } from '@kit.CoreFileKit';


// 获取Worker全局作用域
const workerPort: ThreadWorkerGlobalScope = worker.workerPort;

// --- 消息结构更新 ---
// 主线程 → Worker：传递 3 个参数（含沙箱临时路径）
interface DownloadTaskMessage {
  folder: string;
  name: string;
  tempFilePath: string; // 新增：沙箱临时文件路径
}

// Worker → 主线程：成功消息（仅返回路径，不携带二进制数据）
interface DownloadSuccessMessage {
  type: 'downloadSuccess';
  name: string;
  tempFilePath: string; // 告知主线程文件保存位置
}

// Worker → 主线程：失败消息
interface DownloadFailureMessage {
  type: 'error';
  message: string;
  name?: string;
}

type WorkerResponseMessage = DownloadSuccessMessage | DownloadFailureMessage;

/**
 * Defines the event handler to be called when the worker thread receives a message sent by the host thread.
 * The event handler is executed in the worker thread.
 *@description 处理主线程发送的消息
 * @param event message data
 */
workerPort.onmessage =  (event: MessageEvent<DownloadTaskMessage>) => {

  const folder = event.data.folder
  const name = event.data.name
  const tempFilePath = event.data.tempFilePath
  console.log(`Worker: 开始下载图片到沙箱 -> 相机路径: ${folder}/${name}, 沙箱路径: ${tempFilePath}`);

  try {
    // --- 调用修改后的 C++ 接口（传递 3 个参数，返回布尔值）---
    const isSuccess: boolean = nativeCamera.DownloadPhoto(folder, name, tempFilePath);

    if (isSuccess) {
      console.log(`Worker: 下载成功，文件已写入沙箱: ${tempFilePath}`);
      const successMsg: DownloadSuccessMessage = {
        type: 'downloadSuccess',
        name: name,
        tempFilePath: tempFilePath
      };
      workerPort.postMessage(successMsg);
    } else {
      throw new Error(`C++ 接口返回失败，未写入沙箱文件: ${tempFilePath}`);
    }

  } catch (error) {
    const errorMsg = error instanceof Error ? error.message : String(error);
    console.error(`Worker: 下载失败: ${errorMsg}`);
    const failureMsg: DownloadFailureMessage = {
      type: 'error',
      message: errorMsg,
      name: name
    };
    workerPort.postMessage(failureMsg);
  }
};

/**
 * Defines the event handler to be called when the worker receives a message that cannot be deserialized.
 * The event handler is executed in the worker thread.
 *@description 处理消息反序列化失败
 * @param event message data
 */
workerPort.onmessageerror = (event: MessageEvents) => {
  console.error(`Worker: 消息解析失败: ${event.data}`);
  const failureMsg: DownloadFailureMessage = {
    type: 'error',
    message: '收到无法解析的消息'
    // name 未知
  };
  workerPort.postMessage(failureMsg);
};


/**
 * Defines the event handler to be called when an exception occurs during worker execution.
 * The event handler is executed in the worker thread.
 *@description 处理Worker内部异常
 * @param event error message
 */
workerPort.onerror = (event: ErrorEvent) => {
  console.error(`Worker: 严重错误 - 消息: ${event.message}, 行号: ${event.lineno}`);
  const errorMsg: DownloadFailureMessage = {
    type: 'error',
    message: `Worker内部错误: ${event.message} (行号: ${event.lineno})`
  };
  workerPort.postMessage(errorMsg);
};