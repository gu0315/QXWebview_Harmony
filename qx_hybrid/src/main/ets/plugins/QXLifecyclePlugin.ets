/*
 * QXLifecyclePlugin —— 页面生命周期订阅。对应 Android com/jd/plugins/QXLifecyclePlugin.kt。
 *
 * action:subscribePageLifecycle / unsubscribePageLifecycle / getPageLifecycleState
 *        (并保留 subscribe / unsubscribe 简写,与 Android 一致)
 *
 * 事件通道:**callJS**,不是 CustomEvent —— H5 侧是
 *   JDBridge.registerPlugin('QXLifecyclePlugin', (params) => { if (params.eventName === 'onPageLifecycle') ... })
 * 接收的,走 window.JDBridge._handleRequestFromNative。
 *
 * state 结构(与 Android buildState 完全一致):
 *   { eventName:'onPageLifecycle', type, nativeType, timestamp, url, isForeground }
 */

import { BasePlugin } from '../bridge/BridgePlugin';
import { BridgeCallback, BridgeHost } from '../bridge/BridgeTypes';
import { QXBridgeError } from '../bridge/QXBridgeError';

/**
 * H5 侧约定的生命周期阶段。与 Android QXWebViewActivity 派发的 type 一致。
 */
export type PageLifecycleType =
  'pageLoad' | 'pageWillShow' | 'pageShow' | 'pageWillHide' | 'pageHide' | 'pageDestroy' | 'unknown';

/** 派发给 H5 的生命周期状态。 */
export interface PageLifecycleState {
  eventName: string;
  /** 跨端统一的阶段名 */
  type: string;
  /** 原生侧的原始回调名(鸿蒙:aboutToAppear / onPageShow / onPageHide / aboutToDisappear) */
  nativeType: string;
  timestamp: number;
  url: string;
  isForeground: boolean;
}

interface SubscribeResult {
  subscribed: boolean;
  state: PageLifecycleState;
}

interface UnsubscribeResult {
  subscribed: boolean;
}

const EVENT_NAME: string = 'onPageLifecycle';

export class QXLifecyclePlugin extends BasePlugin {
  static readonly NAME: string = 'QXLifecyclePlugin';
  static readonly EVENT_NAME: string = EVENT_NAME;
  readonly name: string = QXLifecyclePlugin.NAME;

  private subscribed: boolean = false;
  private host: BridgeHost | null = null;
  private currentUrl: string = '';
  private latestState: PageLifecycleState = QXLifecyclePlugin.buildState('unknown', 'unknown', '');

  /** 由容器创建时注入,用于 callJS 推送事件。 */
  attachHost(host: BridgeHost): void {
    this.host = host;
  }

  /** 容器在页面 url 变化时同步,事件里会带上。 */
  setUrl(url: string): void {
    this.currentUrl = url ?? '';
  }

  /**
   * 容器在生命周期变化时调用。未订阅时只记录最新状态,不推送(与 Android dispatchPageLifecycle 一致)。
   * @param type 跨端阶段名
   * @param nativeType 鸿蒙原生回调名
   */
  notifyState(type: PageLifecycleType, nativeType: string): void {
    const state: PageLifecycleState = QXLifecyclePlugin.buildState(type, nativeType, this.currentUrl);
    this.latestState = state;
    if (!this.subscribed) {
      return;
    }
    this.host?.callJS(QXLifecyclePlugin.NAME, state);
  }

  execute(host: BridgeHost, action: string | undefined,
    params: object | undefined, callback: BridgeCallback): boolean {
    this.host = host;
    switch (action) {
      case 'subscribePageLifecycle':
      case 'subscribe': {
        this.subscribed = true;
        const r: SubscribeResult = { subscribed: true, state: this.latestState };
        callback.onSuccess(r);
        return true;
      }
      case 'unsubscribePageLifecycle':
      case 'unsubscribe': {
        this.subscribed = false;
        const r: UnsubscribeResult = { subscribed: false };
        callback.onSuccess(r);
        return true;
      }
      case 'getPageLifecycleState':
        callback.onSuccess(this.latestState);
        return true;
      default:
        // 与 Android 一致:本插件接管所有 action,未知操作回 1005 而不是「插件未找到」。
        callback.onError(QXBridgeError.unsupported(`未知生命周期操作: ${action ?? ''}`));
        return true;
    }
  }

  private static buildState(type: string, nativeType: string, url: string): PageLifecycleState {
    const state: PageLifecycleState = {
      eventName: EVENT_NAME,
      type: type,
      nativeType: nativeType,
      timestamp: Date.now(),
      url: url,
      isForeground: type === 'pageWillShow' || type === 'pageShow'
    };
    return state;
  }
}
