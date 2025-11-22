//cam_connect_type.ets 仅仅类型定义，无任何业务逻辑

// 消息类型枚举
// 消息类型枚举（明确双方通信的指令）
export enum CheckMsgType {
  START_CHECK = 'start_check', // 主线程→Worker：启动检测
  STOP_CHECK = 'stop_check', // 主线程→Worker：停止检测
  PAUSE_CHECK = 'pause_check', // 主线程→Worker：暂停检测
  RESUME_CHECK = 'resume_check', // 主线程→Worker：恢复检测
  CHECK_RESULT = 'check_result', // Worker→主线程：检测结果
  ERROR = 'error' // Worker→主线程：检测错误
}

// 消息体结构
export interface CheckMessage {
  type: CheckMsgType;
  data?: boolean | string;
}

//  显式声明状态结果接口（解决对象字面量报错）
export interface ConnectionStateResult {
  state: boolean;
  message: string;
}
