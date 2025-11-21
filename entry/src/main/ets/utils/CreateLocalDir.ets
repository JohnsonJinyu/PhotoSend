// CreateLocalDir.ets
import fs from '@ohos.file.fs';
import environment from '@ohos.file.environment';
import log from '@ohos.hilog';

const TAG = 'CreateLocalDir';
const DOMAIN = 0x00201;

/**
 * 文件目录操作工具类（适配 HarmonyOS API 20，无 fs.path 依赖）
 */
export class CreateLocalDirUtil {

  /**
   * 检查并创建公共Download目录下的指定名称目录（API 20 兼容版）
   * @param label - 要创建的目录名称（自定义，如 "MyAppFiles"）
   * @returns Promise<string> - 返回创建或已存在的目录绝对路径
   * @throws {Error} - 目录路径获取失败、创建失败时抛出异常
   */
  public static async checkAndCreateDir(label: string): Promise<string> {
    // 校验 label 合法性
    if (!label || label.trim() === '') {
      throw new Error("目录名称 label 不能为空");
    }
    const targetDirName = label.trim();

    try {
      // 1. API 20 中通过 environment.getUserDownloadDir() 获取公共下载目录（无硬编码）
      const publicDownloadDir = environment.getUserDownloadDir();
      if (!publicDownloadDir) {
        throw new Error("获取公共Download目录失败");
      }
      log.info(DOMAIN, TAG, `公共Download目录: ${publicDownloadDir}`);

      // 2. 手动拼接目标目录路径（API 20 无 fs.path，直接用 '/' 拼接，系统自动适配）
      // 处理公共目录路径末尾是否带 '/'，避免重复拼接
      const targetDirPath = publicDownloadDir.endsWith('/')
        ? `${publicDownloadDir}${targetDirName}`
        : `${publicDownloadDir}/${targetDirName}`;
      log.info(DOMAIN, TAG, `目标目录路径: ${targetDirPath}`);

      // 3. 检查目录是否存在，不存在则创建（API 20 兼容）
      try {
        // API 20 中 fs.statSync 直接接收路径字符串
        const dirStat = fs.statSync(targetDirPath);
        if (dirStat.isDirectory()) {
          log.info(DOMAIN, TAG, `目录已存在: ${targetDirPath}`);
          return targetDirPath;
        } else {
          log.error(DOMAIN, TAG, `路径存在但非目录: ${targetDirPath}`);
          throw new Error(`路径存在但非目录，无法创建: ${targetDirPath}`);
        }
      } catch (err) {
        // 捕获 stat 失败（目录不存在或权限问题），尝试创建目录
        log.info(DOMAIN, TAG, `目录不存在，尝试创建: ${targetDirPath}`);
        // API 20 中 fs.mkdirSync 第二个参数为 boolean（true 表示递归创建）
        fs.mkdirSync(targetDirPath, true);
        log.info(DOMAIN, TAG, `目录创建成功: ${targetDirPath}`);
        return targetDirPath;
      }

    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      log.error(DOMAIN, TAG, `目录操作失败: ${errorMsg}`);
      throw new Error(errorMsg); // 抛出标准 Error，方便调用方处理
    }
  }
}