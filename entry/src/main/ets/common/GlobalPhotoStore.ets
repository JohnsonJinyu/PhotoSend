//GlobalPhotoStore.ets
import { ImageInfo } from "../pages/PhoneLocalPhotos/LocalPhotoDataSource";

// 全局存储图片列表，供列表页和详情页共享
export class GlobalPhotoStore {
  private static instance: GlobalPhotoStore;
  private _imageList: ImageInfo[] = [];

  // 单例模式，确保全局只有一个实例
  public static getInstance(): GlobalPhotoStore {
    if (!GlobalPhotoStore.instance) {
      GlobalPhotoStore.instance = new GlobalPhotoStore();
    }
    return GlobalPhotoStore.instance;
  }

  // 设置图片列表
  setImageList(list: ImageInfo[]): void {
    this._imageList = list;
  }

  // 获取图片列表
  getImageList(): ImageInfo[] {
    return this._imageList;
  }
}