// StorageUtil.ets
import dataPreferences from '@ohos.data.preferences';
import { BusinessError } from '@ohos.base';
import { common } from '@kit.AbilityKit'; // 引入 UIAbilityContext

export class StorageUtil {
  private static instance: StorageUtil | null = null;
  private preferences: dataPreferences.Preferences | null = null;
  private readonly PREFERENCES_NAME = 'app_preferences';

  private constructor() {}

  public static getInstance(): StorageUtil {
    if (!StorageUtil.instance) {
      StorageUtil.instance = new StorageUtil();
    }
    return StorageUtil.instance;
  }

  /**
   * 初始化 Preferences。此方法必须在使用 put / get 前调用。
   * @param context UIAbilityContext
   */
  public async init(context: common.UIAbilityContext): Promise<void> {
    if (this.preferences) {
      return;
    }
    try {
      // 使用官方定义的 getPreferences 方法
      this.preferences = await dataPreferences.getPreferences(context, this.PREFERENCES_NAME);
    } catch (error) {
      const err = error as BusinessError;
      throw new Error(`初始化 Preferences 失败: ${err.message}`);
    }
  }

  /**
   * 存储字符串值 (使用官方的 put 方法)
   * @param key 键
   * @param value 值
   */
  public async setString(key: string, value: string): Promise<void> {
    if (!this.preferences) {
      throw new Error('Preferences 尚未初始化，请先调用 init 方法。');
    }
    try {
      // 修正：使用通用的 put 方法，它接受 string 类型的值
      await this.preferences.put(key, value);
      await this.preferences.flush();
    } catch (error) {
      const err = error as BusinessError;
      throw new Error(`存储数据失败 (key: ${key}): ${err.message}`);
    }
  }

  /**
   * 获取字符串值 (使用官方的 get 方法)
   * @param key 键
   * @param defaultValue 默认值
   * @returns 存储的字符串值或默认值
   */
  public async getString(key: string, defaultValue: string = ''): Promise<string> {
    if (!this.preferences) {
      throw new Error('Preferences 尚未初始化，请先调用 init 方法。');
    }
    try {
      // 修正：使用通用的 get 方法
      // get 方法返回的类型是 ValueType，需要确保它是 string 类型
      const value = await this.preferences.get(key, defaultValue);

      // 做一个类型检查，确保返回的是字符串，增强代码健壮性
      if (typeof value === 'string') {
        return value;
      } else {
        // 如果存储的不是字符串（例如被其他代码修改），则返回默认值
        return defaultValue;
      }
    } catch (error) {
      const err = error as BusinessError;
      throw new Error(`获取数据失败 (key: ${key}): ${err.message}`);
    }
  }
}