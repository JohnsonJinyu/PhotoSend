// CreateLocalDirUtil.ets
import fs from '@ohos.file.fs';
import log from '@ohos.hilog';
import fileUri from '@ohos.file.fileuri';
import picker from '@ohos.file.picker';
import { BusinessError } from '@ohos.base';
import { common } from '@kit.AbilityKit';
// 导入用户当前的 StorageUtil（路径需根据项目结构调整）
import { StorageUtil } from './StorageUtil';

const TAG = 'CreateLocalDir';
const DOMAIN = 0x00201;
const DIR_URI_KEY = 'app_download_dir_uri'; // 存储目录 URI 的键（固定，用于读写）

export class CreateLocalDirUtil {
  /**
   * 核心方法：创建或获取应用专属下载目录（不重复创建，路径一致）
   * @param context - UIAbilityContext（必须传入，用于初始化 StorageUtil 和文件选择器）
   * @returns 目录的绝对路径（string）
   */
  public static async createOrGetDir(context: common.UIAbilityContext): Promise<string> {
    if (!context) throw new Error('请传入有效的 UIAbilityContext');

    // 1. 初始化 StorageUtil（用户的 StorageUtil 需先 init 才能读写）
    const storageUtil = StorageUtil.getInstance();
    await storageUtil.init(context); // 关键：传入 context 初始化 Preferences

    // 2. 读取已保存的目录 URI（优先使用缓存，避免重复创建）
    const savedDirUri = await storageUtil.getString(DIR_URI_KEY);
    if (savedDirUri) {
      try {
        // 用 fileuri 解析 URI 为路径（确保路径有效性）
        const dirPath = new fileUri.FileUri(savedDirUri).path;
        if (dirPath && await fs.access(dirPath)) { // 验证路径是否存在
          log.info(DOMAIN, TAG, `使用已保存的目录路径：${dirPath}`);
          return dirPath;
        }
      } catch (error) {
        // 路径无效（如目录被删除），继续创建新目录
        log.warn(DOMAIN, TAG, `已保存的 URI 无效，将重新创建：${savedDirUri}`);
      }
    }

    // 3. 若 URI 不存在/无效，通过文件选择器创建新目录
    try {
      const documentPicker = new picker.DocumentViewPicker(context);
      const saveOptions = new picker.DocumentSaveOptions();
      saveOptions.pickerMode = picker.DocumentPickerMode.DOWNLOAD; // 固定下载目录模式

      // 调用系统文件选择器，让用户确认创建目录（仅首次需要）
      const uris = await documentPicker.save(saveOptions);
      if (!uris || uris.length === 0) throw new Error('用户取消创建目录');

      // 4. 处理目录 URI（获取完整目录 URI，而非文件 URI）
      const fileUriObj = new fileUri.FileUri(uris[0]);
      const dirUri = fileUriObj.getFullDirectoryUri(); // 关键：获取目录的持久化 URI

      // 5. 保存 URI 到 Preferences（供下次直接使用）
      await storageUtil.setString(DIR_URI_KEY, dirUri);
      log.info(DOMAIN, TAG, `目录创建成功，已保存 URI：${dirUri}`);

      // 6. 解析 URI 为路径并返回
      const dirPath = new fileUri.FileUri(dirUri).path;
      if (!dirPath) throw new Error('解析目录路径失败');
      return dirPath;
    } catch (error) {
      const err = error as BusinessError;
      log.error(DOMAIN, TAG, `目录操作失败：${err.code} - ${err.message}`);
      throw new Error(`创建/获取目录失败：${err.message}`);
    }
  }
}