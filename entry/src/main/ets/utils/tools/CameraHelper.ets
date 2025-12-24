// CameraHelper.ets
import nativeCamera from 'libentry.so';

import { ParamOptions } from 'ets/types/types';

const instanceCallbackMap = new WeakMap<CameraHelper, (params: ParamOptions) => void>();

export class CameraHelper {
  private static instance: CameraHelper;
  private isoOptions: string[] = [];
  private isIsoOptionsUpdated = false;
  onIsoOptionsUpdate?: (options: string[]) => void;

  private instanceId: string = Math.random().toString(36).substr(2, 9); // 生成唯一ID

  private constructor() {
    console.info( 'CameraHelper', `实例创建，ID: ${this.instanceId}`);
    this.registerCallback();
  }

  static getInstance(): CameraHelper {
    if (!CameraHelper.instance) {
      CameraHelper.instance = new CameraHelper();
    }
    console.info( 'CameraHelper', `获取实例，ID: ${CameraHelper.instance.instanceId}`);

    return CameraHelper.instance;
  }

  private handleParamCallback(params: ParamOptions) {
    console.log("C++推送参数: " + JSON.stringify(params));
    if (Array.isArray(params.iso) && params.iso.every((value) => typeof value ==='string')) {
      this.updateIsoOptions(params.iso);
      this.isIsoOptionsUpdated = true;
      console.log('isoOptions 数据已更新')
    } else {
      console.error('C++推送的ISO参数格式不正确');
    }
  }

  private registerCallback() {
    const callback = (params: ParamOptions) => {
      const helper = instanceCallbackMap.get(this);
      console.info( 'CameraHelper', `C++回调触发，helper存在: ${!!helper}`); // 若为false则映射失效
      if (helper) {
        helper(params);
      }
    };
    instanceCallbackMap.set(this, this.handleParamCallback.bind(this));
    nativeCamera.RegisterParamCallback(callback);
  }

  getIsoOptions(): string[] {
    return this.isoOptions;
  }

  // 新增方法，用于更新IsoOptions
  updateIsoOptions(options: string[]) {
    this.isoOptions = options;
    this.onIsoOptionsUpdate?.(options);
  }
}