/*
 * QXLifecyclePlugin —— 页面生命周期订阅。对应 Android QXLifecyclePlugin。
 * action:subscribe / unsubscribe / getPageLifecycleState
 * 事件:通过 CustomEvent 'onPageLifecycle' 派发给 H5。
 */

import { BasePlugin } from '../bridge/BridgePlugin';
import { BridgeCallback, BridgeHost } from '../bridge/BridgeTypes';
import { JDBridge } from '../bridge/JDBridge';

export type PageLifecycleState = 'onShow' | 'onHide' | 'onCreate' | 'onDestroy';

interface SubscribeResult {
  subscribed: boolean;
}

interface StateResult {
  state: string;
}

export class QXLifecyclePlugin extends BasePlugin {
  static readonly NAME: string = 'QXLifecyclePlugin';
  static readonly EVENT_NAME: string = 'onPageLifecycle';
  readonly name: string = QXLifecyclePlugin.NAME;

  private subscribed: boolean = false;
  private currentState: PageLifecycleState = 'onCreate';
  private bridge: JDBridge | null = null;

  /** 由容器创建时注入 bridge,用于派发事件。 */
  attachBridge(bridge: JDBridge): void {
    this.bridge = bridge;
  }

  /** 容器在页面生命周期变化时调用,广播给已订阅的 H5。 */
  notifyState(state: PageLifecycleState): void {
    this.currentState = state;
    if (this.subscribed && this.bridge) {
      const detail: StateResult = { state: state };
      this.bridge.dispatchEvent(QXLifecyclePlugin.EVENT_NAME, detail);
    }
  }

  execute(host: BridgeHost, action: string | undefined,
    params: object | undefined, callback: BridgeCallback): boolean {
    switch (action) {
      case 'subscribe': {
        this.subscribed = true;
        const r: SubscribeResult = { subscribed: true };
        callback.onSuccess(r);
        return true;
      }
      case 'unsubscribe': {
        this.subscribed = false;
        const r: SubscribeResult = { subscribed: false };
        callback.onSuccess(r);
        return true;
      }
      case 'getPageLifecycleState': {
        const r: StateResult = { state: this.currentState };
        callback.onSuccess(r);
        return true;
      }
      default:
        return false;
    }
  }
}
