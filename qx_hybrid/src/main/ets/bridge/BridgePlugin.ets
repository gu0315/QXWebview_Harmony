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

  /** 从 params 中原样读取任意类型字段(对象/数组/数字/字符串…)。 */
  protected raw(params: object | undefined, key: string): Object | undefined {
    if (!params) {
      return undefined;
    }
    const v: Object | undefined = (params as Record<string, Object>)[key];
    return v === null ? undefined : v;
  }

  /** 从 params 中读取对象字段(如 query / params 子对象)。 */
  protected obj(params: object | undefined, key: string): object | undefined {
    const v: Object | undefined = this.raw(params, key);
    return (v !== undefined && typeof v === 'object' && !Array.isArray(v)) ? v as object : undefined;
  }

  /**
   * 把可能是 Boolean / "true"|"false" 字符串 / 数字的值归一为三态 Boolean。
   * 对应 Android QXLocationManager.coerceBoolean —— H5 常把布尔序列化成字符串。
   */
  protected coerceBool(params: object | undefined, key: string): boolean | undefined {
    const v: Object | undefined = this.raw(params, key);
    if (v === undefined) {
      return undefined;
    }
    if (typeof v === 'boolean') {
      return v as boolean;
    }
    if (typeof v === 'number') {
      return (v as number) !== 0;
    }
    if (typeof v === 'string') {
      const s: string = (v as string).trim().toLowerCase();
      if (s === 'true' || s === '1') {
        return true;
      }
      if (s === 'false' || s === '0') {
        return false;
      }
    }
    return undefined;
  }

  /**
   * 读取数值,兼容 H5 传字符串的情况(如 openMap 的 latitude:"31.23")。
   * 对应 Android 的 optString(...).toDoubleOrNull()。
   */
  protected numLoose(params: object | undefined, key: string): number | undefined {
    const v: Object | undefined = this.raw(params, key);
    if (typeof v === 'number') {
      return v as number;
    }
    if (typeof v === 'string') {
      const s: string = (v as string).trim();
      if (s.length === 0) {
        return undefined;
      }
      const n: number = Number.parseFloat(s);
      return Number.isNaN(n) ? undefined : n;
    }
    return undefined;
  }

  /** 读取字符串数组字段(如 chooseImage 的 sourceType)。 */
  protected strArray(params: object | undefined, key: string): string[] | undefined {
    const v: Object | undefined = this.raw(params, key);
    if (!Array.isArray(v)) {
      return undefined;
    }
    const out: string[] = [];
    (v as Array<Object>).forEach((item: Object) => {
      if (typeof item === 'string' && (item as string).trim().length > 0) {
        out.push((item as string).trim().toLowerCase());
      }
    });
    return out;
  }
}
