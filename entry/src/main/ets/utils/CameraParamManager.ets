// CameraParamManager.ets
import nativeCamera from 'libentry.so'
/**
 * 相机参数管理
 * */
// 相机参数选项接口
export interface ParamOption {
  name: string;       // 参数名（如"aperture"）
  label: string;      // 显示名称（如"光圈"）
  currentValue: string; // 当前值
  options: string[];  // 可选值列表
  isEditable: boolean; // 是否可编辑
}

export class CameraParamManager {

  private paramRefreshTimer: number = -1; // 参数刷新定时器

  private isConnected: boolean = false;
  private params: Map<string, ParamOption> = new Map();
  private listeners: Array<() => void> = [];

  constructor() {
    this.initDefaultParams();
  }

  // 初始化默认参数（未连接时显示）
  private initDefaultParams() {
    const defaultParams: ParamOption[] = [
      { name: 'aperture', label: '光圈', currentValue: 'NA', options: [], isEditable: false },
      { name: 'shutter', label: '快门', currentValue: 'NA', options: [], isEditable: false },
      { name: 'iso', label: 'ISO', currentValue: 'NA', options: [], isEditable: false },
      { name: 'exposureCompensation', label: '曝光补偿', currentValue: 'NA', options: [], isEditable: false },
      { name: 'whiteBalance', label: '白平衡', currentValue: 'NA', options: [], isEditable: false },
      { name: 'exposureMeterMode', label: '测光模式', currentValue: 'NA', options: [], isEditable: false },
      { name: 'focusMode', label: '对焦模式', currentValue: 'NA', options: [], isEditable: false },
      { name: 'exposureProgram', label: '曝光模式', currentValue: 'NA', options: [], isEditable: false },
    ];

    defaultParams.forEach(param => this.params.set(param.name, param));
  }

  // 更新连接状态时，启动/停止参数定时刷新
  updateConnectionStatus(connected: boolean) {
    this.isConnected = connected;
    if (connected) {
      this.refreshAllParams(); // 立即刷新一次
      this.startParamRefreshTimer(); // 启动定时刷新
    } else {
      this.stopParamRefreshTimer(); // 停止定时刷新
      this.initDefaultParams();
      this.notifyListeners();
    }
  }

  // 启动参数定时刷新（每2秒一次）
  private startParamRefreshTimer() {
    // 避免重复启动
    if (this.paramRefreshTimer === -1) {
      this.paramRefreshTimer = setInterval(() => {
        this.refreshAllParams();
      }, 1000); // 2秒刷新一次
    }
  }


  // 停止参数定时刷新
  private stopParamRefreshTimer() {
    if (this.paramRefreshTimer !== -1) {
      clearInterval(this.paramRefreshTimer);
      this.paramRefreshTimer = -1;
    }
  }

  // 从相机刷新所有参数
  async refreshAllParams() {
    try {
      const status = nativeCamera.GetCameraStatus(); // 调用底层接口获取相机状态
      // 打印从底层获取的原始参数
      console.log('从相机获取的原始参数:', JSON.stringify(status));
      if (status.isSuccess) {
        // 更新当前值
        this.updateParamCurrentValue('aperture', status.aperture);
        this.updateParamCurrentValue('shutter', status.shutter);
        this.updateParamCurrentValue('iso', status.iso);
        this.updateParamCurrentValue('exposureCompensation', status.exposureCompensation);
        this.updateParamCurrentValue('whiteBalance', status.whiteBalance);
        this.updateParamCurrentValue('exposureMeterMode', status.exposureMeterMode);
        this.updateParamCurrentValue('focusMode', status.focusMode);
        this.updateParamCurrentValue('exposureProgram', status.exposureProgram); // 同步曝光模式

        // 刷新可选值（实际应从相机接口获取，这里模拟）
        console.log('CameraParamManager: 参数更新完成，准备通知UI');
        await this.refreshParamOptions();
        this.notifyListeners();
        console.log('CameraParamManager: 已通知所有 listeners');
        //console.log('参数更新成功，当前参数:', JSON.stringify(Array.from(this.params.values())));
      }
    } catch (error) {
      console.error('刷新参数失败:', error);
    }
  }

  // 刷新参数可选值（实际项目中需调用相机接口获取）
  private async refreshParamOptions() {
    // 从C++层获取真实可选值（替换模拟数据）
    const apertureOpts = await nativeCamera.GetParamOptions('f-number'); // 光圈
    const shutterOpts = await nativeCamera.GetParamOptions('shutterspeed'); // 快门
    const isoOpts = await nativeCamera.GetParamOptions('iso'); // ISO
    const wbOpts = await nativeCamera.GetParamOptions('whitebalance'); // 白平衡
    const evOpts = await nativeCamera.GetParamOptions('exposurecompensation'); // 曝光补偿

    // 更新参数可选值
    this.updateParamOptions('aperture', apertureOpts);
    this.updateParamOptions('shutter', shutterOpts);
    this.updateParamOptions('iso', isoOpts);
    this.updateParamOptions('whiteBalance', wbOpts);
    this.updateParamOptions('exposureCompensation', evOpts);

    this.params.forEach(param => param.isEditable = true);
  }

  // 更新参数当前值
  // 更新参数当前值
  private updateParamCurrentValue(paramName: string, value: string) {
    // 先获取参数对象，判断是否存在
    const targetParam = this.params.get(paramName);
    if (targetParam) { // 存在则赋值
      targetParam.currentValue = value;
    }
  }

  // 更新参数可选值
  private updateParamOptions(paramName: string, options: string[]) {
    // 先获取参数对象，判断是否存在
    const targetParam = this.params.get(paramName);
    if (targetParam) { // 存在则赋值
      targetParam.options = options;
    }
  }

  // 设置相机参数并同步
  async setParameter(paramName: string, value: string): Promise<boolean> {
    if (!this.isConnected) return false;
    const success = nativeCamera.SetCameraParameter(paramName, value);
    if (success) {
      this.updateParamCurrentValue(paramName, value);
      this.notifyListeners();
    }
    return success;
  }

  // 暴露给UI的方法
  getParams(): ParamOption[] {
    return Array.from(this.params.values());
  }

  getIsConnected(): boolean {
    return this.isConnected;
  }

  // 监听机制
  addListener(listener: () => void) {
    this.listeners.push(listener);
  }

  removeListener(listener: () => void) {
    this.listeners = this.listeners.filter(l => l !== listener);
  }

  private notifyListeners() {
    this.listeners.forEach(listener => listener());
  }
}

// 单例实例
export const cameraParamManager = new CameraParamManager();