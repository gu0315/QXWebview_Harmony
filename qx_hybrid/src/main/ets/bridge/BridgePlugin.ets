/*
 * 插件接口与基类。对应 Android IBridgePlugin / QXBasePlugin 的执行契约。
 */

import { BridgeCallback, BridgeHost } from './BridgeTypes';

/** 所有原生插件实现此接口。 */
export interface IBridgePlugin {
  /** 插件名,对应 JS 侧的 plugin 字段。 */
  readonly name: string;

  /**
   * 处理一次调用。
   * @returns true 表示该 action 被此插件识别并已处理(即使异步);false 表示未知 action,
   *          由桥统一回 STATUS_NOT_FOUND(与 Android execute 返回值语义一致)。
   */
  execute(host: BridgeHost, action: string | undefined,
    params: object | undefined, callback: BridgeCallback): boolean;

  /** 页面销毁时释放资源(蓝牙、定位监听等)。对应 Android Destroyable。 */
  onDestroy?(): void;
}

/** 便捷基类:子类用 action 名到方法的表来分发。 */
export abstract class BasePlugin implements IBridgePlugin {
  abstract readonly name: string;

  abstract execute(host: BridgeHost, action: string | undefined,
    params: object | undefined, callback: BridgeCallback): boolean;

  onDestroy(): void {
  }

  /** 从 params 中安全读取字符串字段。 */
  protected str(params: object | undefined, key: string): string | undefined {
    if (!params) {
      return undefined;
    }
    const v: object | undefined = (params as Record<string, object>)[key];
    return typeof v === 'string' ? v as string : undefined;
  }

  /** 从 params 中安全读取数值字段。 */
  protected num(params: object | undefined, key: string): number | undefined {
    if (!params) {
      return undefined;
    }
    const v: object | undefined = (params as Record<string, object>)[key];
    return typeof v === 'number' ? v as number : undefined;
  }

  /** 从 params 中安全读取布尔字段。 */
  protected bool(params: object | undefined, key: string): boolean | undefined {
    if (!params) {
      return undefined;
    }
    const v: object | undefined = (params as Record<string, object>)[key];
    return typeof v === 'boolean' ? v as boolean : undefined;
  }
}
