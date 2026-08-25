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
 *     // 系统返回键:先让 H5 逐级后退,到根页再返回 false 交系统关闭本页。
 *     onBackPress(): boolean { return this.webController.onBackPress(); }
 *     build() { QXWebView({ url: ..., webController: this.webController }) }
 *   }
 */

import { webview } from '@kit.ArkWeb';
import { QXLifecyclePlugin } from '../plugins/QXLifecyclePlugin';
import { BridgeHost } from '../bridge/BridgeTypes';

export class QXWebViewController {
  private lifecycle: QXLifecyclePlugin | null = null;
  private host: BridgeHost | null = null;

  /** 由 QXWebView 在 aboutToAppear 时调用,集成方无需关心。 */
  attach(lifecycle: QXLifecyclePlugin, host: BridgeHost): void {
    this.lifecycle = lifecycle;
    this.host = host;
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

  /**
   * 承载页面 onBackPress 时调用。对齐 Android QXWebViewActivity 的返回键处理:
   * WebView 还有前进/后退历史(H5 内部多级页面)时,后退一级并「消费」本次返回(return true);
   * 已到 H5 根页则「不消费」(return false),交系统默认逻辑关闭本承载页(等价 Android finish)。
   *
   * @returns true=已在 H5 内后退一级;false=已到根,交系统关闭本页。
   */
  onBackPress(): boolean {
    const controller: webview.WebviewController | undefined = this.host?.getController();
    if (!controller) {
      return false;
    }
    try {
      if (controller.accessBackward()) {
        controller.backward();
        return true;
      }
    } catch (e) {
      // 页面尚未加载完成时 accessBackward 会抛错,按「无历史」处理,交系统关闭。
    }
    return false;
  }
}
