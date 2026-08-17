/*
 * 跨页面回传:挂起回调中心。对应 Android com/jd/plugins/PageResultCenter.kt。
 *
 * openWebView({forResult:true}) 打开新页面时把 callback 挂起;
 * 新页面调 closeWithResult(或被返回)时回传。用 pageId 索引,支持 A→B→C 多层嵌套互不串扰。
 */

import { BridgeCallback } from './BridgeTypes';

interface CancelledResult {
  cancelled: boolean;
}

const CANCELLED: CancelledResult = { cancelled: true };

export class PageResultCenter {
  private static callbacks: Map<string, BridgeCallback> = new Map();

  /** 生成一个新的回传 id(对应 Android 的 UUID.randomUUID)。 */
  static newPageId(): string {
    return `qxpage_${Date.now()}_${Math.floor(Math.random() * 1000000)}`;
  }

  /** 挂起打开方的 callback,等待新页面回传。 */
  static suspend(id: string, callback: BridgeCallback): void {
    PageResultCenter.callbacks.set(id, callback);
  }

  /** 不回调、仅丢弃(打开失败时清理)。 */
  static discard(id: string): void {
    PageResultCenter.callbacks.delete(id);
  }

  /** 新页面主动回传。 */
  static resolve(id: string, data: Object): void {
    const cb: BridgeCallback | undefined = PageResultCenter.callbacks.get(id);
    if (!cb) {
      return;
    }
    PageResultCenter.callbacks.delete(id);
    cb.onSuccess(data);
  }

  /** 被返回(未回传)的取消兜底 —— 回 {cancelled:true},与 Android 一致。 */
  static cancel(id: string): void {
    const cb: BridgeCallback | undefined = PageResultCenter.callbacks.get(id);
    if (!cb) {
      return;
    }
    PageResultCenter.callbacks.delete(id);
    cb.onSuccess(CANCELLED);
  }
}
