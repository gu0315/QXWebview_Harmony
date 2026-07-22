/*
 * QXHostBridgePlugin —— 宿主桥。对应 Android QXHostBridgePlugin。
 *
 * H5 通过 `JDBridge.callNative("QXHostBridgePlugin", {action:<方法名>, params})` 调用宿主 App 的
 * 自定义方法,由集成方实现的 QXHostBridgeDelegate 处理并返回**裸数据**(不套 {code,message,data} 信封)。
 *
 * 线上 H5(fr-home-charge-web)已知会调:
 *   getUserInfo -> 期望返回 { phone, token?, list: [{ vin, mac }] }
 */

import { BasePlugin } from '../bridge/BridgePlugin';
import { BridgeCallback, BridgeHost } from '../bridge/BridgeTypes';
import { QXHostBridgeDelegate } from '../bridge/HostDelegate';

export class QXHostBridgePlugin extends BasePlugin {
  static readonly NAME: string = 'QXHostBridgePlugin';
  readonly name: string = QXHostBridgePlugin.NAME;

  private delegate: QXHostBridgeDelegate | null;

  constructor(delegate: QXHostBridgeDelegate | null) {
    super();
    this.delegate = delegate;
  }

  execute(host: BridgeHost, action: string | undefined,
    params: object | undefined, callback: BridgeCallback): boolean {
    if (!action) {
      return false;
    }
    const del: QXHostBridgeDelegate | null = this.delegate;
    if (!del) {
      callback.onError(`QXHostBridgePlugin 未设置宿主代理,无法处理方法: ${action}`);
      return true;
    }
    // 全部方法(含 openPage)转交宿主处理,成功回裸数据,失败回错误信息。
    del.onCustomMethod(action, params,
      (data: Object): void => callback.onSuccess(data),
      (message: string): void => callback.onError(message));
    return true;
  }
}
