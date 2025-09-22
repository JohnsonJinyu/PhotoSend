/**
 *  全局类型定义中心
 *  1、类型聚合平台
 *  -承担统一管理自定义类型（如接口、联合类型、枚举替代类型）的职责
 *  -集中定义跨组件/模块共享的数据结构
 *  2、类型安全基石
 *  -通过标准化接口定义，确保不同模块间数据交互的规范性
 *  -避免重复定义导致的不一致问题，提升代码可维护性
 * */
import { Type } from '@ohos.arkui.StateManagement'


// 基础类型定义
type DevicesStatus = `online` | `offline` | `error`

interface Dimension {
  width: number;
  height: number;
}