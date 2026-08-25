/*
 * QXWebPage(SDK 自带的命名路由承载页)的全局配置。
 *
 * 存在意义:命名路由页 QXWebPage 由 SDK 提供、内部已处理生命周期转调与系统返回键,
 * 宿主无需再写承载页。但「桥的业务能力」(getUserInfo / getToken / openPage 等)因宿主而异,
 * SDK 无法内置。宿主在 App 启动时(如 EntryAbility.onCreate)调用一次 QXWebRegistry.configure,
 * 把这些能力登记进来;之后所有 router.pushNamedRoute({ name: 'QXWebPage' }) 打开的页面都会复用。
 *
 * 典型用法(宿主一次性配置):
 *   QXWebRegistry.configure({
 *     hostBridgeDelegateProvider: () => new MyHostBridgeDelegate(),  // 每页取当前登录态
 *     scanHandler: (cb) => MyScanner.scan(cb)
 *   });
 */

import { QXHostBridgeDelegate } from '../bridge/HostDelegate';
import { BridgeCallback } from '../bridge/BridgeTypes';

/** 命名路由承载页的全局配置项。 */
export interface QXWebPageConfig {
  /**
   * 宿主桥代理实例。整个 App 共用一个、且能读到当前登录态时用它。
   * 若登录态会变、需要每次进页面重新构造,请改用 hostBridgeDelegateProvider。
   */
  hostBridgeDelegate?: QXHostBridgeDelegate;
  /** 宿主桥代理工厂:每次打开 QXWebPage 时调用,返回当次要用的代理(优先级高于 hostBridgeDelegate)。 */
  hostBridgeDelegateProvider?: () => QXHostBridgeDelegate;
  /** 扫码实现(需真机 Scan Kit)。不配则用 SDK 内置 ScanHelper。 */
  scanHandler?: (cb: BridgeCallback) => void;
  /** 沉浸式布局,默认 true。 */
  immersive?: boolean;
  /** 沉浸式下状态栏前景色,默认 '#000000'。 */
  statusBarContentColor?: string;
}

export class QXWebRegistry {
  private static config: QXWebPageConfig = {};

  /** 宿主启动时调用一次,登记 QXWebPage 需要的宿主能力。重复调用以最后一次为准。 */
  static configure(config: QXWebPageConfig): void {
    QXWebRegistry.config = config ?? {};
  }

  /** QXWebPage 内部读取配置。 */
  static getConfig(): QXWebPageConfig {
    return QXWebRegistry.config;
  }

  /** 解析本次要用的宿主桥代理:工厂优先,其次单例,都没有则 null。 */
  static resolveHostBridgeDelegate(): QXHostBridgeDelegate | null {
    const c: QXWebPageConfig = QXWebRegistry.config;
    if (c.hostBridgeDelegateProvider) {
      return c.hostBridgeDelegateProvider();
    }
    return c.hostBridgeDelegate ?? null;
  }
}
