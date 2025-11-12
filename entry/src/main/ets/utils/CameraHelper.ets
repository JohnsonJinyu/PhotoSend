// CameraHelper.ets
import nativeCamera from 'libentry.so';

interface ParamOptions {
  iso: string[];
  shutterspeed?: string[];
}

export class CameraHelper {
  private static instance: CameraHelper;
  private isoOptions: string[] = [];
  onIsoOptionsUpdate?: (options: string[]) => void;

/*  private constructor() {
    this.registerCallback();
  }

  static getInstance(): CameraHelper {
    if (!this.instance) {
      this.instance = new CameraHelper();
    }
    return this.instance;
  }

  private registerCallback() {
    const that = this;
    nativeCamera.RegisterParamCallback((params: ParamOptions) => {
      console.log("C++推送参数: " + JSON.stringify(params));
      if (params.iso) {
        that.isoOptions = params.iso;
        that.onIsoOptionsUpdate?.(that.isoOptions);
      }
    });
  }*/

  getIsoOptions(): string[] {
    return this.isoOptions;
  }
}