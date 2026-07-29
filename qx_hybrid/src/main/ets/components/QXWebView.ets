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
import { common, abilityAccessCtrl, Permissions, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
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
  private abilityContext: common.UIAbilityContext | null = null;

  aboutToAppear(): void {
    const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    this.abilityContext = context;

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

  /**
   * 拦截非 http/https 跳转。Web 组件只认 http(s),H5 直接 location.href 到 weixin://
   * 这类三方 scheme 会加载失败,必须在这里转成 startAbility 唤起。
   * 返回 true 表示本次加载已被拦截,Web 组件不再处理。
   */
  private handleUrlLoad(url: string): boolean {
    if (!url) {
      return false;
    }
    const lower: string = url.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://') ||
      lower.startsWith('about:') || lower.startsWith('data:') ||
      lower.startsWith('blob:') || lower.startsWith('javascript:')) {
      return false;
    }
    // intent:// 是 Android 专有写法,鸿蒙不识别,先还原成三方 scheme。
    const target: string = lower.startsWith('intent://') ? this.convertIntentUri(url) : url;
    const targetLower: string = target.toLowerCase();
    // 还原结果是 browser_fallback_url 这类网页地址时,交回 Web 组件加载。
    if (targetLower.startsWith('http://') || targetLower.startsWith('https://')) {
      // 避免在拦截回调里同步重入 controller,放到下一个事件循环再加载。
      setTimeout(() => {
        try {
          this.controller.loadUrl(target);
        } catch (e) {
          console.error(`QXWebView 加载回退地址失败: ${target}`);
        }
      }, 0);
      return true;
    }
    const want: Want = { action: 'ohos.want.action.viewData', uri: target };
    this.abilityContext?.startAbility(want).catch((e: BusinessError) => {
      console.error(`QXWebView 唤起外部应用失败: ${target}, ${e.message}`);
    });
    return true;
  }

  /**
   * intent://host/path?query#Intent;scheme=weixin;package=com.tencent.mm;end
   *   → weixin://host/path?query
   * 取不到 scheme 时退回 S.browser_fallback_url,再取不到则返回原串。
   */
  private convertIntentUri(url: string): string {
    const markIndex: number = url.toLowerCase().indexOf('#intent;');
    if (markIndex < 0) {
      return url;
    }
    const body: string = url.substring('intent://'.length, markIndex);
    const extras: string[] = url.substring(markIndex + '#intent;'.length).split(';');
    let scheme: string = '';
    let fallback: string = '';
    for (const item of extras) {
      if (item.startsWith('scheme=')) {
        scheme = item.substring('scheme='.length);
      } else if (item.startsWith('S.browser_fallback_url=')) {
        fallback = decodeURIComponent(item.substring('S.browser_fallback_url='.length));
      }
    }
    if (scheme.length > 0) {
      return `${scheme}://${body}`;
    }
    return fallback.length > 0 ? fallback : url;
  }

  build() {
    Web({ src: this.url, controller: this.controller })
      .onLoadIntercept((event: OnLoadInterceptEvent) => {
        return this.handleUrlLoad(event.data.getRequestUrl());
      })
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
