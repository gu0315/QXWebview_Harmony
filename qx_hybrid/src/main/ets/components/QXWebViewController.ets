/*
 * QXWebView 的对外控制器。
 *
 * 存在的原因:ArkUI 里 onPageShow / onPageHide 只在 @Entry 组件上触发,嵌套的 QXWebView 收不到。
 * 承载页面(@Entry)需持有一个 QXWebViewController 传给 QXWebView,并在自己的
 * onPageShow / onPageHide 里转调,H5 才能收到与 Android QXWebViewActivity 一致的
 * pageWillShow / pageShow / pageWillHide / pageHide 事件。
 *
 * 用法:
 *   @Entry @Component struct WebPage {
 *     private webController: QXWebViewController = new QXWebViewController();
 *     onPageShow(): void { this.webController.onPageShow(); }
 *     onPageHide(): void { this.webController.onPageHide(); }
 *     build() { QXWebView({ url: ..., webController: this.webController }) }
 *   }
 */

import { QXLifecyclePlugin } from '../plugins/QXLifecyclePlugin';

export class QXWebViewController {
  private lifecycle: QXLifecyclePlugin | null = null;

  /** 由 QXWebView 在 aboutToAppear 时调用,集成方无需关心。 */
  attach(lifecycle: QXLifecyclePlugin): void {
    this.lifecycle = lifecycle;
  }

  /** 承载页面 onPageShow 时调用。 */
  onPageShow(): void {
    this.lifecycle?.notifyState('pageWillShow', 'onPageShow');
    this.lifecycle?.notifyState('pageShow', 'onPageShow');
  }

  /** 承载页面 onPageHide 时调用。 */
  onPageHide(): void {
    this.lifecycle?.notifyState('pageWillHide', 'onPageHide');
    this.lifecycle?.notifyState('pageHide', 'onPageHide');
  }
}
