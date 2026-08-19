/*
 * WebDebug —— H5 的 DevTools 调试开关。
 *
 * webview.WebviewController.setWebDebuggingAccess 必须在**任何 Web 组件创建之前**调用,
 * 否则不生效。SDK 在 QXWebView.aboutToAppear(早于 build 里的 Web())里调一次,
 * 集成方不需要在自己的 UIAbility 里写任何代码。
 *
 * 默认策略:跟随包的 debug 属性 —— debug 包开、release 包关。
 * 开启后网页内部状态可被外部检查和修改,所以正式包必须是关的。
 * 集成方要覆盖默认(例如想在 release 包临时排查),在第一个 QXWebView 出现前调
 * QXWebDebug.setEnabled(true)。
 *
 * 用法(调试):
 *   hdc shell "cat /proc/net/unix | grep devtools"      # 拿 webview_devtools_remote_<pid>
 *   hdc fport tcp:9222 localabstract:webview_devtools_remote_<pid>
 *   Chrome 打开 chrome://inspect#devices,Configure 里加 localhost:9222
 */

import { webview } from '@kit.ArkWeb';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DEBUG_DOMAIN: number = 0x00B2;
const DEBUG_TAG: string = 'QXWebDebug';

export class QXWebDebug {
  /** 只生效一次:Web 组件建好之后再调也没用,重复调用没有意义。 */
  private static applied: boolean = false;
  /** 集成方是否显式指定过。没指定就跟随包的 debug 属性。 */
  private static hasOverride: boolean = false;
  private static overrideValue: boolean = false;

  /**
   * 显式指定开关,覆盖「debug 包才开」的默认策略。
   * 必须在第一个 QXWebView 出现之前调用(例如 UIAbility.onCreate),之后调用无效。
   */
  static setEnabled(enabled: boolean): void {
    QXWebDebug.hasOverride = true;
    QXWebDebug.overrideValue = enabled;
  }

  /** SDK 内部调用。幂等,多个 QXWebView 只会真正生效第一次。 */
  static applyOnce(context: common.UIAbilityContext): void {
    if (QXWebDebug.applied) {
      return;
    }
    QXWebDebug.applied = true;

    let enabled: boolean = false;
    if (QXWebDebug.hasOverride) {
      enabled = QXWebDebug.overrideValue;
    } else {
      try {
        enabled = context.applicationInfo.debug;
      } catch (e) {
        // 取不到就按 release 处理,宁可关着。
        enabled = false;
      }
    }

    try {
      webview.WebviewController.setWebDebuggingAccess(enabled);
      hilog.info(DEBUG_DOMAIN, DEBUG_TAG, 'setWebDebuggingAccess(%{public}s)', `${enabled}`);
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      hilog.warn(DEBUG_DOMAIN, DEBUG_TAG, 'setWebDebuggingAccess 失败: %{public}s', `${e.code} ${e.message}`);
    }
  }
}
