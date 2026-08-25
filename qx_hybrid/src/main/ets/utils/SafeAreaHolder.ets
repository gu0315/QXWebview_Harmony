/*
 * 状态栏 / 底部导航条安全区高度的进程内缓存(单位:物理像素 px)。
 *
 * 为什么需要:H5 首屏在 onLaunch 就调 getSystemInfo 取 statusBarHeight 来垫头部返回按钮,
 * 而沉浸式全屏(window.setWindowLayoutFullScreen)是异步生效的。用户直接深链到某个页面时,
 * getWindowAvoidArea(TYPE_SYSTEM) 可能还没就绪、返回 0,statusBarHeight=0 会把 H5 的默认值
 * 覆盖成 0 → 顶部返回按钮顶进状态栏里,位置错乱。
 *
 * 对应 Android SystemInfoHandler 的 `if (topInset == 0) getStatusBarHeight()` 兜底。
 * 这里由 QXWebView 在窗口就绪 / avoidAreaChange 时写入最近一次有效值,SystemInfoPlugin
 * 读不到实时值(0)时回退到本缓存,保证 statusBarHeight 不会异常返回 0。
 */
export class SafeAreaHolder {
  private static statusBarHeightPx: number = 0;
  private static navBarHeightPx: number = 0;
  /** 当前 QXWebView 是否处于沉浸式布局。决定「测不到高度」时该不该兜底垫高。 */
  private static immersive: boolean = false;

  /** QXWebView 创建时登记本页是否沉浸式。 */
  static setImmersive(value: boolean): void {
    SafeAreaHolder.immersive = value;
  }

  /** 是否沉浸式。非沉浸式时系统已自动避让,statusBarHeight=0 是正确值,不可兜底。 */
  static isImmersive(): boolean {
    return SafeAreaHolder.immersive;
  }

  /** 写入状态栏高度(px)。只在拿到有效正值时更新,避免被 0 冲掉已缓存的好值。 */
  static updateStatusBarHeightPx(px: number): void {
    if (px > 0) {
      SafeAreaHolder.statusBarHeightPx = px;
    }
  }

  /** 写入底部导航条高度(px)。同样只在有效正值时更新。 */
  static updateNavBarHeightPx(px: number): void {
    if (px > 0) {
      SafeAreaHolder.navBarHeightPx = px;
    }
  }

  /** 最近一次有效的状态栏高度(px);从未测到则为 0。 */
  static getStatusBarHeightPx(): number {
    return SafeAreaHolder.statusBarHeightPx;
  }

  /** 最近一次有效的底部导航条高度(px);从未测到则为 0。 */
  static getNavBarHeightPx(): number {
    return SafeAreaHolder.navBarHeightPx;
  }
}
