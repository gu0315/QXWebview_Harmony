/*
 * qx-hybrid HAR 对外入口。集成方仅从这里 import。
 * 例:import { QXWebView, QXHostDelegate } from 'qx-hybrid';
 */

// 容器组件
export { QXWebView } from './src/main/ets/components/QXWebView';

// 宿主代理与相关类型
export { QXHostDelegate, OpenWebViewOptions, NavigationBarStyle,
  QXHostBridgeDelegate, HostMethodResolve, HostMethodReject } from './src/main/ets/bridge/HostDelegate';

// 桥类型(供高级用法/自定义插件)
export { BridgeRequest, BridgeResponse, BridgeCallback, BridgeHost } from './src/main/ets/bridge/BridgeTypes';
export { IBridgePlugin, BasePlugin } from './src/main/ets/bridge/BridgePlugin';
export { JDBridge } from './src/main/ets/bridge/JDBridge';

// 插件(如需单独复用)
export { QXBasePlugin } from './src/main/ets/plugins/QXBasePlugin';
export { QXBlePlugin } from './src/main/ets/plugins/QXBlePlugin';
export { QXLifecyclePlugin } from './src/main/ets/plugins/QXLifecyclePlugin';
export { SystemInfoPlugin, collectDeviceInfo } from './src/main/ets/plugins/SystemInfoPlugin';
export { QXHostBridgePlugin } from './src/main/ets/plugins/QXHostBridgePlugin';
