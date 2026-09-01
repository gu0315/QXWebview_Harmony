/*
 * QXUIContextHolder —— 持有当前 QXWebView 所在的 UIContext。
 *
 * 为什么需要它:SDK 里弹系统对话框(地图选择面板等)必须有 UIContext,而工具类是静态的,
 * 只能反查。原先用 `window.getLastWindow(context).getUIContext()`,在只有一个窗口的
 * 调试 App 上没问题,**但宿主 App 往往有多个窗口**(自己的主窗、子窗、UIExtension 等),
 * getLastWindow 拿到的未必是当前前台那个 —— 弹窗会挂到看不见的窗口上:
 * 不报错、不回调,用户点了「毫无反应」,日志里也只停在最后一条正常输出上,极难排查。
 *
 * QXWebView 是 @Component,`this.getUIContext()` 拿到的一定是它自己所在的那个窗口,
 * 所以在 aboutToAppear 时存进来,MapHelper 之类优先取用,取不到再回退 getLastWindow。
 */

import { UIContext, window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';

export class QXUIContextHolder {
  private static current: UIContext | null = null;

  /** QXWebView.aboutToAppear 调用。多个 WebView 时后出现的覆盖先出现的,与「当前页」语义一致。 */
  static set(ui: UIContext | null): void {
    if (ui) {
      QXUIContextHolder.current = ui;
    }
  }

  /** QXWebView.aboutToDisappear 调用:只清掉自己存的那份,避免误清后来者。 */
  static clear(ui: UIContext | null): void {
    if (ui && QXUIContextHolder.current === ui) {
      QXUIContextHolder.current = null;
    }
  }

  static get(): UIContext | null {
    return QXUIContextHolder.current;
  }

  /**
   * 取 QXWebView 所在的那个窗口。
   *
   * 凡是要量状态栏/导航条高度、设沉浸式的地方都该用它,**别用 window.getLastWindow**:
   * 宿主 App 只要挂了悬浮窗(真机上见过 141x141 的 TestOverlayWindow),
   * getLastWindow 返回的就是那个悬浮窗 —— 量出来的安全区是悬浮窗的,不是页面的;
   * 沉浸式也会设到悬浮窗上。
   *
   * 拿不到登记的 UIContext(理论上不该发生)时才退回 getLastWindow。
   */
  static async getWindow(context: common.UIAbilityContext): Promise<window.Window> {
    const ui: UIContext | null = QXUIContextHolder.current;
    if (ui) {
      const name: string | undefined = ui.getWindowName();
      if (name !== undefined && name.length > 0) {
        try {
          return window.findWindow(name);
        } catch (e) {
          // 窗口已销毁等情况,落到下面的兜底。
        }
      }
    }
    return await window.getLastWindow(context);
  }
}
