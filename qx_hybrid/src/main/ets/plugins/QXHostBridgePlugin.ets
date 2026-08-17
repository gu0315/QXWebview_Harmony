/*
 * QXHostBridgePlugin —— 宿主桥。对应 Android com/jd/plugins/QXHostBridgePlugin.kt。
 *
 * H5 通过 `JDBridge.callNative("QXHostBridgePlugin", {action:<方法名>, params})` 调用宿主 App 的能力:
 *   - action === 'openPage' 走专用入口 onOpenPage(url|pageName, params);
 *   - 其余 action 全部转交 onCustomMethod。
 *
 * 与 Android 一致的细节:
 *   - 宿主返回 null / 未返回时,回 { success:true };
 *   - 未实现 delegate -> 1005 unsupported 信封;openPage 缺 url -> 1000 invalidParams 信封;
 *   - 成功回**裸数据**(不套 code/message 信封)。
 *
 * 线上 H5(fr-home-charge-web)已知会调:
 *   getUserInfo -> 期望返回 { phone, token?, list: [{ vin, mac }] }
 */

import { BasePlugin } from '../bridge/BridgePlugin';
import { BridgeCallback, BridgeHost } from '../bridge/BridgeTypes';
import { QXHostBridgeDelegate } from '../bridge/HostDelegate';
import { QXBridgeError } from '../bridge/QXBridgeError';

const METHOD_OPEN_PAGE: string = 'openPage';

interface SuccessAck {
  success: boolean;
}

const ACK_SUCCESS: SuccessAck = { success: true };

export class QXHostBridgePlugin extends BasePlugin {
  static readonly NAME: string = 'QXHostBridgePlugin';
  readonly name: string = QXHostBridgePlugin.NAME;

  private delegate: QXHostBridgeDelegate | null;

  constructor(delegate: QXHostBridgeDelegate | null) {
    super();
    this.delegate = delegate;
  }

  setDelegate(delegate: QXHostBridgeDelegate | null): void {
    this.delegate = delegate;
  }

  execute(host: BridgeHost, action: string | undefined,
    params: object | undefined, callback: BridgeCallback): boolean {
    const method: string = action ?? '';
    const del: QXHostBridgeDelegate | null = this.delegate;
    if (!del) {
      callback.onError(QXBridgeError.unsupported('宿主 APP 未实现 delegate'));
      return true;
    }

    const resolve = (data: Object): void => callback.onSuccess(data ?? ACK_SUCCESS);
    const reject = (message: string): void => callback.onError(QXBridgeError.failure(message));

    if (method === METHOD_OPEN_PAGE) {
      const url: string = (this.str(params, 'url') ?? this.str(params, 'pageName') ?? '').trim();
      if (url.length === 0) {
        callback.onError(QXBridgeError.invalidParams('缺少 url/pageName 参数'));
        return true;
      }
      const pageParams: object | undefined = this.obj(params, 'params');
      if (del.onOpenPage) {
        del.onOpenPage(url, pageParams, resolve, reject);
      } else {
        // 宿主没单独实现 openPage 时退回自定义方法通道,保持行为可用。
        del.onCustomMethod(METHOD_OPEN_PAGE, params, resolve, reject);
      }
      return true;
    }

    del.onCustomMethod(method, params, resolve, reject);
    return true;
  }
}
