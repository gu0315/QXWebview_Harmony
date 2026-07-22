/*
 * QXWebView —— 承载 H5 的 Web 容器组件。对应 Android JDWebView / QXWebViewActivity。
 *
 * 用法(集成方):
 *   QXWebView({ url: 'https://.../index.html', delegate: myHostDelegate })
 *
 * 组件负责:
 *   1. 创建 Web 组件并配置(JS 开启、DOM 存储等);
 *   2. 通过 javaScriptProxy 把 JDBridge 以 window.XWebView 注入(方法名 _callNative);
 *   3. 注册全部插件;
 *   4. 转发页面生命周期给 QXLifecyclePlugin。
 */

import { webview } from '@kit.ArkWeb';
import { common, abilityAccessCtrl, Permissions } from '@kit.AbilityKit';
import { JDBridge } from '../bridge/JDBridge';
import { BridgeHost, BridgeCallback } from '../bridge/BridgeTypes';
import { QXHostDelegate, QXHostBridgeDelegate } from '../bridge/HostDelegate';
import { StorageUtil } from '../utils/StorageUtil';
import { QXBasePlugin } from '../plugins/QXBasePlugin';
import { QXBlePlugin } from '../plugins/QXBlePlugin';
import { QXLifecyclePlugin } from '../plugins/QXLifecyclePlugin';
import { SystemInfoPlugin } from '../plugins/SystemInfoPlugin';
import { QXHostBridgePlugin } from '../plugins/QXHostBridgePlugin';

/** BridgeHost 的类实现(ArkTS 要求带方法的接口用类实现,不能用对象字面量)。 */
class WebViewBridgeHost implements BridgeHost {
  private controller: webview.WebviewController;
  bridge: JDBridge | null = null;

  constructor(controller: webview.WebviewController) {
    this.controller = controller;
  }

  runJavaScript(script: string): void {
    this.controller.runJavaScript(script).catch(() => {
      // 页面未就绪时忽略。
    });
  }

  getController(): webview.WebviewController {
    return this.controller;
  }

  dispatchEvent(eventName: string, detail?: Object): void {
    this.bridge?.dispatchEvent(eventName, detail);
  }

  callJS(pluginName: string, params?: Object): void {
    this.bridge?.callJS(pluginName, params);
  }
}

@Component
export struct QXWebView {
  /** 要加载的 H5 地址。 */
  url: string = '';
  /** 宿主页面代理(返回/关闭/打开新页/导航栏)。可选。 */
  delegate: QXHostDelegate | null = null;
  /** 宿主桥代理(处理 H5 的自定义方法,如 getUserInfo 返回 phone/vin/mac)。可选。 */
  hostBridgeDelegate: QXHostBridgeDelegate | null = null;
  /** 扫码实现(需 Scan Kit,真机),可选注入。 */
  scanHandler?: (cb: BridgeCallback) => void;

  private controller: webview.WebviewController = new webview.WebviewController();
  private bridge: JDBridge | null = null;
  private lifecyclePlugin: QXLifecyclePlugin = new QXLifecyclePlugin();
  private storage: StorageUtil = new StorageUtil();

  aboutToAppear(): void {
    const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;

    // 运行时申请 user_grant 权限(定位/蓝牙/相机)。HAR 声明的权限不会自动生效,
    // 必须在运行时向用户申请,否则 H5 调 location/BLE/扫码会失败。
    this.requestRuntimePermissions(context);

    // BridgeHost:插件通过它执行 JS。ArkTS 不允许对象字面量实现带方法的接口,故用类。
    const host: WebViewBridgeHost = new WebViewBridgeHost(this.controller);
    const bridge: JDBridge = new JDBridge(host);
    host.bridge = bridge;
    this.bridge = bridge;
    this.lifecyclePlugin.attachBridge(bridge);

    // 注册插件(与 Android QXBridgePluginRegister.registerAllPlugins 对齐)。
    const basePlugin: QXBasePlugin = new QXBasePlugin(context, this.storage, this.delegate);
    if (this.scanHandler) {
      basePlugin.setScanHandler(this.scanHandler);
    }
    bridge.registerPlugin(basePlugin);
    bridge.registerPlugin(new QXBlePlugin(context));
    bridge.registerPlugin(this.lifecyclePlugin);
    bridge.registerPlugin(new SystemInfoPlugin());
    bridge.registerPlugin(new QXHostBridgePlugin(this.hostBridgeDelegate));

    // 初始化本地存储。
    this.storage.init(context);

    this.lifecyclePlugin.notifyState('onCreate');
  }

  /** 运行时申请定位/蓝牙/相机权限。首次加载时弹窗;已授权则静默返回。 */
  private requestRuntimePermissions(context: common.UIAbilityContext): void {
    const perms: Array<Permissions> = [
      'ohos.permission.APPROXIMATELY_LOCATION',
      'ohos.permission.LOCATION',
      'ohos.permission.ACCESS_BLUETOOTH',
      'ohos.permission.CAMERA'
    ];
    try {
      const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
      atManager.requestPermissionsFromUser(context, perms).catch(() => {
        // 用户拒绝或申请异常:忽略,由各功能被调用时再自行处理失败。
      });
    } catch (e) {
      // 忽略
    }
  }

  onPageShow(): void {
    this.lifecyclePlugin.notifyState('onShow');
  }

  onPageHide(): void {
    this.lifecyclePlugin.notifyState('onHide');
  }

  aboutToDisappear(): void {
    this.lifecyclePlugin.notifyState('onDestroy');
    this.bridge?.destroy();
  }

  build() {
    Web({ src: this.url, controller: this.controller })
      .javaScriptAccess(true)
      .domStorageAccess(true)
      .fileAccess(true)
      .mixedMode(MixedMode.All)
      .javaScriptProxy({
        object: {
          // 暴露给 JS 的方法。JS 调用:window.XWebView._callNative(jsonStr)
          _callNative: (objStr: string): void => {
            this.bridge?._callNative(objStr);
          }
        },
        name: JDBridge.JS_NAME,
        methodList: ['_callNative'],
        controller: this.controller
      })
      .width('100%')
      .height('100%')
  }
}
