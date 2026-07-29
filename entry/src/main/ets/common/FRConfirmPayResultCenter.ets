/*
 * FR 确认支付页的跨页面结果中心(宿主 Demo 用)。
 *
 * H5 通过 app://openFRConfirmPay 拉起原生确认支付页时,宿主桥代理先把 resolve 挂到这里,
 * 模拟支付页(FRConfirmPay)结束时调用 deliver 回传结果,再由这里回调给 H5。
 * 对应 Android 的 BridgeHostManager.pendingFRConfirmPayCompletion / deliverFRConfirmPayResult。
 */

/** (code, message, orderSeq) —— code: 0 成功 / 1 用户取消 / 2 失败 */
export type FRConfirmPayCallback = (code: string, message: string, orderSeq: string) => void;

export class FRConfirmPayResultCenter {
  private static pending: FRConfirmPayCallback | null = null;

  /**
   * 拉起确认支付页前登记回调。若上一次调用还挂着(页面异常未回传),
   * 先按失败结束,避免 H5 永远等不到。
   */
  static register(callback: FRConfirmPayCallback): void {
    const previous: FRConfirmPayCallback | null = FRConfirmPayResultCenter.pending;
    if (previous) {
      previous('2', '已被新的支付请求取代', '');
    }
    FRConfirmPayResultCenter.pending = callback;
  }

  /** 确认支付页结果回传入口,结果只会回调一次。 */
  static deliver(code: string, message: string, orderSeq: string): void {
    const callback: FRConfirmPayCallback | null = FRConfirmPayResultCenter.pending;
    FRConfirmPayResultCenter.pending = null;
    if (!callback) {
      return;
    }
    callback(code, message, orderSeq);
  }
}
