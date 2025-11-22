import { ErrorEvent, MessageEvent, MessageEvents, ThreadWorkerGlobalScope, worker } from '@kit.ArkTS';
import nativeCamera from 'libentry.so'
import { fileIo } from '@kit.CoreFileKit';


// 获取Worker全局作用域
const workerPort: ThreadWorkerGlobalScope = worker.workerPort;

// --- 定义消息结构 ---

// 1. 主线程 -> Worker：下载任务消息
interface DownloadTaskMessage {
  folder: string;
  name: string;
}

// 2. Worker -> 主线程：下载成功消息
interface DownloadSuccessMessage {
  type: 'downloadSuccess';
  name: string;
  imageBuffer: ArrayBuffer;
}

// 3. Worker -> 主线程：下载失败消息
interface DownloadFailureMessage {
  type: 'error';
  message: string;
  name?: string; // 文件名可能不存在，比如在onerror中
}


/**
 * Defines the event handler to be called when the worker thread receives a message sent by the host thread.
 * The event handler is executed in the worker thread.
 *@description 处理主线程发送的消息
 * @param event message data
 */
workerPort.onmessage =  (event: MessageEvent<DownloadTaskMessage>) => {
  // 现在 event.data 有了明确的类型 DownloadTaskMessage
  const taskData = event.data;
  const folder = taskData.folder;
  const name = taskData.name;

  console.log(`Worker: 开始下载图片: ${name} from ${folder}`);

  try {
    // 1. 调用原生接口下载照片（耗时操作）
    const imageBuffer = nativeCamera.DownloadPhoto(folder, name);

    if (!imageBuffer || imageBuffer.byteLength === 0) {
      throw new Error('下载失败，返回的图片数据为空');
    }

    console.log(`Worker: 下载成功，数据大小: ${imageBuffer.byteLength} bytes`);

    // 2. 向主线程发送“下载成功”消息
    const successMsg: DownloadSuccessMessage = {
      type: 'downloadSuccess',
      name: name,
      imageBuffer: imageBuffer
    };
    workerPort.postMessage(successMsg);

  } catch (error) {
    // 3. 处理下载过程中的已知错误
    const errorMsg = error instanceof Error ? error.message : String(error);
    console.error(`Worker: 下载失败: ${errorMsg}`);

    const failureMsg: DownloadFailureMessage = {
      type: 'error',
      message: errorMsg,
      name: name // 这里可以明确知道是哪个文件下载失败
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
  console.error(`Worker: 发生严重错误 - 消息: ${event.message}, 行号: ${event.lineno}`);

  // 构造一个错误消息发送给主线程
  const errorMsg: DownloadFailureMessage = {
    type: 'error',
    message: `Worker内部错误: ${event.message} (行号: ${event.lineno})`
    // 在这种情况下，无法确定是哪个文件导致的错误，所以name字段省略
  };
  workerPort.postMessage(errorMsg);
};