/*
 * qx-hybrid HAR 对外入口。集成方仅从这里 import。
 * 例:import { QXWebView, QXHostDelegate } from 'qx-hybrid';
 */

// 容器组件
export { QXWebView } from './src/main/ets/components/QXWebView';
export { QXWebViewController } from './src/main/ets/components/QXWebViewController';

// 零承载页接入:SDK 自带的命名路由承载页 + 全局配置。
// 宿主启动时 QXWebRegistry.configure(...) 登记一次业务能力,之后
// router.pushNamedRoute({ name: QX_WEB_PAGE_ROUTE_NAME, params: { url } }) 即可打开,
// 生命周期与系统返回键全在 SDK 内处理,无需宿主写 onBackPress/onPageShow。
// (此处的 export 同时触发命名路由注册。)
export { QXWebPage, QX_WEB_PAGE_ROUTE_NAME } from './src/main/ets/pages/QXWebPage';
export { QXWebRegistry, QXWebPageConfig } from './src/main/ets/pages/QXWebRegistry';

// H5 调试开关(默认 debug 包自动开启,需要覆盖默认策略时才用)
export { QXWebDebug } from './src/main/ets/utils/WebDebug';

// 宿主代理与相关类型
export { QXHostDelegate, OpenWebViewOptions, QXNavigationBarStyle,
  parseNavigationBarStyle, navigationBarStyleJsValue,
  QXHostBridgeDelegate, HostMethodResolve, HostMethodReject } from './src/main/ets/bridge/HostDelegate';

// 桥类型(供高级用法/自定义插件)
export { BridgeRequest, BridgeResponse, BridgeCallback, BridgeHost } from './src/main/ets/bridge/BridgeTypes';
export { IBridgePlugin, BasePlugin } from './src/main/ets/bridge/BridgePlugin';
export { JDBridge } from './src/main/ets/bridge/JDBridge';
export { QXBridgeError, QXBridgeErrorCode } from './src/main/ets/bridge/QXBridgeError';
export { PageResultCenter } from './src/main/ets/bridge/PageResultCenter';

// 插件(如需单独复用)
export { QXBasePlugin } from './src/main/ets/plugins/QXBasePlugin';
export { QXBlePlugin } from './src/main/ets/plugins/QXBlePlugin';
export { QXBLEventType, QXBleErrorCode, bleErrorMessage } from './src/main/ets/plugins/QXBleDefine';
export { QXLifecyclePlugin, PageLifecycleType, PageLifecycleState } from './src/main/ets/plugins/QXLifecyclePlugin';
export { SystemInfoPlugin, DeviceInfoResult, collectDeviceInfo } from './src/main/ets/plugins/SystemInfoPlugin';
export { QXHostBridgePlugin } from './src/main/ets/plugins/QXHostBridgePlugin';
