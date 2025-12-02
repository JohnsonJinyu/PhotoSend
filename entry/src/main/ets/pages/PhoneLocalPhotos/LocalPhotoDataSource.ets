// LocalPhotoDataSource.ets
// LocalPhotoDataSource实现了IDataSource接口，用于管理listener监听，以及通知LazyForEach数据更新

import fs from '@ohos.file.fs';


// 导出图片模型
export interface ImageInfo{
  uri:string;
  name:string;
  modifyTime:number;
  dateStr:string;
}


export class LocalPhotoDataSource implements IDataSource{

  //私有变量：储存图片数据、监听器、文件路径
  private data:ImageInfo[]=[]
  private listeners:DataChangeListener[]=[]
  private appStoragePath:string=''


  // 构造函数：初始化路径
  constructor(initialPath:string='') {
    this.appStoragePath = initialPath
  }


  // --------------- 官方 IDataSource 必实现方法 ---------------
  // 1. 返回数据总数（UI层用于判断是否无数据）
  totalCount(): number {
    return this.data.length
  }

  // 2. 根据索引获取单个数据（LazyForEach 渲染时调用）
  getData(index: number): ImageInfo {
    if (index < 0 || index >= this.data.length) {
      throw new Error(`索引${index}超出数据范围`)
    }
    return this.data[index]
  }

  // 3. 注册数据变化监听器（官方要求：用于通知UI数据更新）
  registerDataChangeListener(listener: DataChangeListener): void {
    if (!this.listeners.includes(listener)) {
      this.listeners.push(listener);
    }
  }

  // 4. 注销数据变化监听器（官方要求：避免内存泄漏）
  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index = this.listeners.indexOf(listener);
    if (index !== -1) {
      this.listeners.splice(index, 1);
    }
  }

  // 👇 新增这行！用于外部获取完整图片数组（返回副本，避免源数据被修改）
  get dataList(): ImageInfo[] {
    return [...this.data]; // 解构赋值返回副本，安全无副作用
  }

  // --------------- 自定义数据操作方法（供UI层调用）---------------
  // 1. 更新文件路径（UI层路径变化时调用）
  updatePath(newPath: string): void {
    if (newPath !== this.appStoragePath) {
      this.appStoragePath = newPath;
    }
  }

  // 2. 加载/刷新图片数据（核心数据逻辑：读取文件、筛选、排序）
  async loadData(): Promise<void> {
    if (!this.appStoragePath) {
      this.data = [];
      this.notifyDataChanged(); // 通知UI路径为空
      return;
    }

    try {
      const imageFiles: ImageInfo[] = [];
      // 读取应用目录文件（纯数据操作，无UI）
      const fileList = await fs.listFile(this.appStoragePath);

      // 筛选图片文件（复用原逻辑）
      for (const fileName of fileList) {
        if (this.isImageFile(fileName)) {
          const filePath = `${this.appStoragePath}/${fileName}`;
          const stat = await fs.stat(filePath);
          const modifyTime = stat.mtime;
          const dateStr = this.formatDate(new Date(modifyTime));

          imageFiles.push({
            uri: `file://${filePath}`,
            name: fileName,
            modifyTime: modifyTime,
            dateStr: dateStr
          });
        }
      }

      // 按修改时间排序（纯数据排序）
      imageFiles.sort((a, b) => b.modifyTime - a.modifyTime);
      this.data = imageFiles;
    } catch (err) {
      console.error('数据层加载图片失败: ' + JSON.stringify(err));
      this.data = [];
      throw new Error(`数据加载失败: ${JSON.stringify(err)}`); // 抛出错误，让UI层处理提示
    } finally {
      this.notifyDataChanged(); // 无论成功失败，通知UI更新
    }
  }


  // --------------- 数据层辅助方法（纯工具逻辑）---------------
  private isImageFile(fileName: string): boolean {
    const imageExtensions = ['.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp'];
    const ext = fileName.substring(fileName.lastIndexOf('.')).toLowerCase();
    return imageExtensions.includes(ext);
  }

  private formatDate(date: Date): string {
    const year = date.getFullYear();
    const month = this.padZero(date.getMonth() + 1);
    const day = this.padZero(date.getDate());
    const hour = this.padZero(date.getHours());
    const minute = this.padZero(date.getMinutes());
    return `${year}-${month}-${day} ${hour}:${minute}`;
  }

  private padZero(num: number): string {
    return num < 10 ? '0' + num : num.toString();
  }

  // --------------- 通知UI数据变化（官方标准方式）---------------
  private notifyDataChanged(): void {
    this.listeners.forEach(listener => {
      listener.onDataReloaded(); // 通知UI：数据已全量更新
    });
  }

}