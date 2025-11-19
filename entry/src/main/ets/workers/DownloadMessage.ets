import { ErrorEvent, MessageEvents, ThreadWorkerGlobalScope, worker } from '@kit.ArkTS';
import nativeCamera from 'libentry.so'
import { fileIo } from '@kit.CoreFileKit';


// 获取Worker全局作用域
const workerPort: ThreadWorkerGlobalScope = worker.workerPort;

// 定义消息数据结构接口（主线程发送给Worker的数据）
interface DownloadMessage {
  folder: string;
  name: string;
  filesDir: string;
}

// 定义发送消息结构接口（Worker发送给主线程的数据）
interface PostMessageData {
  type: 'success' | 'error';
  message?: string;
  savePath?: string;
}

/**
 * Defines the event handler to be called when the worker thread receives a message sent by the host thread.
 * The event handler is executed in the worker thread.
 *@description 处理主线程发送的消息
 * @param event message data
 */
workerPort.onmessage = async (event: MessageEvents) => {
  // 解析消息数据（避免解构赋值，符合ArkTS规范）
  const data: DownloadMessage = event.data as DownloadMessage;
  const folder: string = data.folder;
  const name: string = data.name;
  const filesDir: string = data.filesDir;
  console.log(`worker 中的参数值分别为，folder:${folder}，name：${name}，fileDir：${filesDir}`);

  try {
    // 1. 调用原生接口下载照片（耗时操作）
    const imageBuffer = nativeCamera.DownloadPhoto(folder, name);
    if (!imageBuffer || imageBuffer.byteLength === 0) {
      const msg: PostMessageData = {
        type: 'error',
        message: '下载失败，图片数据为空！'
      };
      console.log(`下载失败，图片数据为空，图片名称：${name},图片地址:${folder}`);
      workerPort.postMessage(msg);
      return;
    }

    // 2、保存文件
    const saveDir: string = `${filesDir}/Pictures`;
    try {
      await fileIo.access(saveDir);
    } catch {
      fileIo.mkdirSync(saveDir);
    }

    const savePath: string = `${saveDir}/${name}`;
    const file = await fileIo.open(savePath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
    await fileIo.write(file.fd, new Uint8Array(imageBuffer));
    await fileIo.close(file.fd);

    // 3. 通知主线程成功
    const successMsg: PostMessageData = {
      type: 'success',
      savePath: savePath
    };
    workerPort.postMessage(successMsg);
  }catch (err){
    const error = err as BusinessError<number>;
    const errorMsg: PostMessageData = {
      type: 'error',
      message: `下载失败：${error.message || error.code}`
    };
    workerPort.postMessage(errorMsg);
  }
};

/**
 * Defines the event handler to be called when the worker receives a message that cannot be deserialized.
 * The event handler is executed in the worker thread.
 *@description 处理消息反序列化失败
 * @param event message data
 */
workerPort.onmessageerror = (event: MessageEvents) => {
  const errorMsg: PostMessageData = {
    type: 'error',
    message: `消息解析失败：${event.data}`
  };
  workerPort.postMessage(errorMsg);
};

/**
 * Defines the event handler to be called when an exception occurs during worker execution.
 * The event handler is executed in the worker thread.
 *@description 处理Worker内部异常
 * @param event error message
 */
workerPort.onerror = (event: ErrorEvent) => {
  const errorMsg: PostMessageData = {
    type: 'error',
    message: `Worker错误：${event.message}（行号：${event.lineno}）`
  };
  workerPort.postMessage(errorMsg);

};