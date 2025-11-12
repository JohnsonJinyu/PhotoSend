// CameraHelper.ets
import nativeCamera from 'libentry.so';

import { ParamOptions } from 'ets/types';

const instanceCallbackMap = new WeakMap<CameraHelper, (params: ParamOptions) => void>();

export class CameraHelper {
  private static instance: CameraHelper;
  private isoOptions: string[] = [];
  onIsoOptionsUpdate?: (options: string[]) => void;

  private constructor() {
    this.registerCallback();
  }

  static getInstance(): CameraHelper {
    if (!CameraHelper.instance) {
      CameraHelper.instance = new CameraHelper();
    }
    return CameraHelper.instance;
  }

  private handleParamCallback(params: ParamOptions) {
    console.log("C++推送参数: " + JSON.stringify(params));
    if (params.iso) {
      this.updateIsoOptions(params.iso);
    }
  }

  private registerCallback() {
    const callback = (params: ParamOptions) => {
      const helper = instanceCallbackMap.get(this);
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