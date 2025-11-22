import fs from '@ohos.file.fs';
import log from '@ohos.hilog';
import fileUri from '@ohos.file.fileuri';
import picker from '@ohos.file.picker';
import { BusinessError } from '@ohos.base';
import { common } from '@kit.AbilityKit'; // 按华为文档正确导入Context

const TAG = 'CreateLocalDir';
const DOMAIN = 0x00201;

/**
 * 极简版：用DOWNLOAD模式创建应用专属空目录
 */
export class CreateLocalDirUtil {
  /**
   * 核心方法：创建Download/包名/空目录
   * @param context - 从页面获取的UIAbilityContext（按文档标准方式）
   * @returns 目录绝对路径
   */
  public static async createDownloadDir(context: common.UIAbilityContext): Promise<string> {
    if (!context) throw new Error('请传入正确的UIAbilityContext');

    try {
      // 1. 创建Picker实例（按文档要求传入context）
      const documentPicker = new picker.DocumentViewPicker(context);
      // 2. 配置DOWNLOAD模式（其他参数无需设置）
      const saveOptions = new picker.DocumentSaveOptions();
      saveOptions.pickerMode = picker.DocumentPickerMode.DOWNLOAD;

      // 3. 调用save触发目录创建（返回文件Uri，目录已自动生成）
      const uris = await documentPicker.save(saveOptions);
      if (!uris || uris.length === 0) throw new Error('创建目录失败');

      // 4. 从文件Uri解析出目录路径（极简处理，无需复杂辅助方法）
      const fileUriObj = new fileUri.FileUri(uris[0]);
      const dirUri = fileUriObj.getFullDirectoryUri(); // 直接拿目录Uri
      const dirPath = new fileUri.FileUri(dirUri).path; // 从目录Uri获取路径

      log.info(DOMAIN, TAG, `空目录创建成功：${dirPath}`);
      return dirPath;
    } catch (error) {
      const err = error as BusinessError;
      log.error(DOMAIN, TAG, `创建失败：${err.code}-${err.message}`);
      throw new Error(`目录创建失败：${err.message}`);
    }
  }
}