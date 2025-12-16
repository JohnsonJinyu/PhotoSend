// ExifReader.ets
import native from 'libentry.so'; // 编译后的native库

export interface ExifInfo {
  orientation: number;  // 方向值：1-8
  width: number;        // 图片宽度
  height: number;       // 图片高度
  make: string;         // 制造商
  model: string;        // 相机型号
}

export class ExifReader{

  /**
   * 获取图片的EXIF方向信息
   * EXIF Orientation值说明：
   * 1 = 正常（无旋转）
   * 2 = 水平翻转
   * 3 = 旋转180度
   * 4 = 垂直翻转
   * 5 = 顺时针90度 + 水平翻转
   * 6 = 顺时针90度（最常见）
   * 7 = 顺时针90度 + 垂直翻转
   * 8 = 逆时针90度
   * @param filePath 图片文件路径
   * @returns 方向值（1-8），失败返回1
   */
  static getOrientation(filePath: string): number {
    try {
      if (!filePath || filePath.length === 0) {
        return 1;
      }

      const orientation = native.GetImageOrientationNapi(filePath);

      // 确保返回值在有效范围内
      if (orientation >= 1 && orientation <= 8) {
        return orientation;
      } else {
        console.warn(`无效的方向值: ${orientation}，使用默认值1`);
        return 1;
      }
    } catch (error) {
      console.error('读取EXIF方向失败:', error);
      return 1;
    }
  }





  /**
   * 获取完整的EXIF信息
   * @param filePath 图片文件路径
   * @returns EXIF信息对象
   */
  static getExifInfo(filePath: string): ExifInfo {
    const defaultInfo: ExifInfo = {
      orientation: 1,
      width: 0,
      height: 0,
      make: '',
      model: ''
    };

    try {
      if (!filePath || filePath.length === 0) {
        return defaultInfo;
      }

      const exifInfo = native.GetImageExifInfoNapi(filePath);

      if (!exifInfo) {
        return defaultInfo;
      }

      return {
        orientation: exifInfo.orientation || 1,
        width: exifInfo.width || 0,
        height: exifInfo.height || 0,
        make: exifInfo.make || '',
        model: exifInfo.model || ''
      };
    } catch (error) {
      console.error('读取EXIF信息失败:', error);
      return defaultInfo;
    }
  }

  /**
   * 根据方向值获取旋转角度
   * @param orientation EXIF方向值
   * @returns 需要旋转的角度（度）
   */
  static getRotationAngle(orientation: number): number {
    switch (orientation) {
      case 1: return 0;      // 正常
      case 2: return 0;      // 水平翻转（ArkTS不支持翻转，保持原样）
      case 3: return 180;    // 旋转180度
      case 4: return 180;    // 垂直翻转（转换为180度）
      case 5: return 90;     // 顺时针90度 + 水平翻转
      case 6: return 90;     // 顺时针90度（最常见）
      case 7: return -90;    // 逆时针90度 + 垂直翻转
      case 8: return -90;    // 逆时针90度
      default: return 0;
    }
  }


  /**
   * 检查是否需要旋转（方向值为5-8）
   */
  static needsRotation(orientation: number): boolean {
    return orientation >= 5 && orientation <= 8;
  }

  /**
   * 判断是否为竖图（需要旋转90或270度）
   */
  static isPortrait(orientation: number): boolean {
    return orientation === 6 || orientation === 8;
  }

}