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
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { JDBridge } from '../bridge/JDBridge';
import { BridgeHost, BridgeCallback } from '../bridge/BridgeTypes';
import { QXHostDelegate, QXHostBridgeDelegate } from '../bridge/HostDelegate';
import { PageResultCenter } from '../bridge/PageResultCenter';
import { QXWebViewController } from './QXWebViewController';
import { StorageUtil } from '../utils/StorageUtil';
import { SafeAreaHolder } from '../utils/SafeAreaHolder';
import { QXWebDebug } from '../utils/WebDebug';
import { QXUIContextHolder } from '../utils/UIContextHolder';
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

  callJS(pluginName: string, params?: Object, callback?: BridgeCallback): void {
    this.bridge?.callJS(pluginName, params, callback);
  }
}

@Component
export struct QXWebView {
  /** 要加载的 H5 地址。 */
  url: string = '';
  /** 宿主页面代理(关闭/打开新页/导航栏/首屏渲染)。可选。 */
  delegate: QXHostDelegate | null = null;
  /** 宿主桥代理(处理 H5 的自定义方法,如 getUserInfo 返回 phone/vin/mac)。可选。 */
  hostBridgeDelegate: QXHostBridgeDelegate | null = null;
  /** 扫码实现(需 Scan Kit,真机),可选注入。 */
  scanHandler?: (cb: BridgeCallback) => void;
  /**
   * 本页的回传 id。由打开方 openWebView({forResult:true}) 生成并经
   * QXHostDelegate.onOpenWebView(options.pageId) 传下来,原样赋给本属性即可:
   * 本页 closeWithResult 时 SDK 会把数据回给打开方,被返回时自动回 {cancelled:true}。
   */
  pageId?: string;
  /**
   * 生命周期控制器。ArkUI 的 onPageShow/onPageHide 只在 @Entry 上触发,嵌套组件收不到,
   * 需承载页面持有一个 QXWebViewController 传进来并在自己的生命周期里转调,
   * H5 才能收到 pageWillShow/pageShow/pageWillHide/pageHide 事件。
   */
  webController: QXWebViewController | null = null;
  /**
   * 沉浸式布局。默认 true,与 iOS / Android 一致:
   * 窗口铺满全屏,Web 内容区顶到状态栏下,状态栏占位由 H5 自己按 statusBarHeight 垫。
   * 关掉则由系统避让状态栏 —— 此时 H5 若仍垫占位,顶部会多出一个状态栏高度的空白。
   */
  immersive: boolean = true;
  /** 沉浸式下的状态栏前景色。H5 头部多为浅色底,默认用深色文字。 */
  statusBarContentColor: string = '#000000';

  private controller: webview.WebviewController = new webview.WebviewController();
  private bridge: JDBridge | null = null;
  private lifecyclePlugin: QXLifecyclePlugin = new QXLifecyclePlugin();
  private storage: StorageUtil = new StorageUtil();
  private abilityContext: common.UIAbilityContext | null = null;
  /** 沉浸式下持有的窗口,用于注册/注销安全区变化监听。 */
  private immersiveWindow: window.Window | null = null;
  /** avoidAreaChange 回调引用,aboutToDisappear 时 off 掉。 */
  private avoidAreaListener: ((data: window.AvoidAreaOptions) => void) | null = null;
  /** 本组件所在的 UIContext,登记到 QXUIContextHolder 供工具类弹窗用。 */
  private uiContext: UIContext | null = null;

  aboutToAppear(): void {
    const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    this.abilityContext = context;

    // 存下本组件的 UIContext,供 SDK 内需要弹系统对话框的工具类使用。
    // 不能让它们去 getLastWindow 反查 —— 宿主 App 多窗口时会拿错窗口,
    // 弹窗挂到看不见的地方,表现为「点了没反应」且无任何报错。
    this.uiContext = this.getUIContext();
    QXUIContextHolder.set(this.uiContext);

    // H5 调试开关。必须赶在下面 build() 创建 Web 组件之前,所以放在 aboutToAppear 最前面。
    // 默认 debug 包开、release 包关,集成方不用在自己的 UIAbility 里写任何代码。
    QXWebDebug.applyOnce(context);

    // 运行时申请 user_grant 权限(定位/蓝牙/相机)。HAR 声明的权限不会自动生效,
    // 必须在运行时向用户申请,否则 H5 调 location/BLE/扫码会失败。
    this.requestRuntimePermissions(context);

    // 登记沉浸式状态:SystemInfoPlugin 只在沉浸式下才对「测不到状态栏高度」做兜底垫高,
    // 非沉浸式时系统已自动避让,statusBarHeight=0 是正确值,兜底反而会多垫一条空白。
    SafeAreaHolder.setImmersive(this.immersive);
    if (this.immersive) {
      this.applyImmersiveLayout(context);
    }

    // BridgeHost:插件通过它执行 JS。ArkTS 不允许对象字面量实现带方法的接口,故用类。
    const host: WebViewBridgeHost = new WebViewBridgeHost(this.controller);
    const bridge: JDBridge = new JDBridge(host);
    host.bridge = bridge;
    this.bridge = bridge;
    this.lifecyclePlugin.attachHost(host);
    this.lifecyclePlugin.setUrl(this.url);
    // 把生命周期插件和桥宿主一起交给控制器:承载页 onPageShow/onPageHide 转调生命周期,
    // onBackPress 通过 host 拿到 WebviewController 做 H5 逐级后退。
    this.webController?.attach(this.lifecyclePlugin, host);

    // 注册插件(与 Android QXBridgePluginRegister.registerAllPlugins 对齐)。
    const basePlugin: QXBasePlugin =
      new QXBasePlugin(context, this.storage, this.delegate, this.pageId);
    if (this.scanHandler) {
      basePlugin.setScanHandler(this.scanHandler);
    }
    bridge.registerPlugin(basePlugin);
    bridge.registerPlugin(new QXBlePlugin(context, this.storage));
    bridge.registerPlugin(this.lifecyclePlugin);
    bridge.registerPlugin(new SystemInfoPlugin(context));
    bridge.registerPlugin(new QXHostBridgePlugin(this.hostBridgeDelegate));

    // 初始化本地存储。
    this.storage.init(context);

    this.lifecyclePlugin.notifyState('pageLoad', 'aboutToAppear');
  }

  /**
   * 开启沉浸式布局。窗口层面铺满全屏,配合 build 里 Web 的 expandSafeArea 生效。
   * 只影响窗口属性,不改宿主的原生页面 —— 原生页未声明 expandSafeArea,仍由系统自动避让。
   */
  private applyImmersiveLayout(context: common.UIAbilityContext): void {
    // 取本组件所在的窗口。不能用 getLastWindow:宿主挂了悬浮窗时它返回的是悬浮窗,
    // 沉浸式会设到那个小窗上,页面这边毫无变化,安全区也跟着量错。
    QXUIContextHolder.getWindow(context).then((win: window.Window): void => {
      this.immersiveWindow = win;
      win.setWindowLayoutFullScreen(true).then((): void => {
        // 全屏生效后避让区才稳定:立即把状态栏 / 导航条高度写入缓存,
        // 让随后(哪怕深链首屏)的 getSystemInfo 一定能拿到非 0 的 statusBarHeight。
        console.info('[QXSafeArea] 沉浸式全屏已生效');
        this.cacheSafeArea(win);
      }).catch((e: BusinessError): void => {
        // 全屏失败 = 窗口一直不铺到状态栏下 = 避让区会恒为 0,状态栏高度只能走兜底。
        console.error('[QXSafeArea] setWindowLayoutFullScreen 失败(避让区将恒为 0): ' + e?.message);
      });
      win.setWindowSystemBarProperties({
        statusBarContentColor: this.statusBarContentColor
      }).catch((e: BusinessError): void => {
        console.error('QXWebView setWindowSystemBarProperties failed: ' + e?.message);
      });
      // 旋转 / 状态栏显隐等会改变避让区,持续刷新缓存。
      this.avoidAreaListener = (): void => this.cacheSafeArea(win);
      try {
        win.on('avoidAreaChange', this.avoidAreaListener);
      } catch (e) {
        // 个别版本不支持该事件时忽略,已有全屏后的一次性缓存兜底。
      }
    }).catch((e: BusinessError): void => {
      console.error('QXWebView 取窗口失败: ' + e?.message);
    });
  }

  /** 读取当前窗口的状态栏 / 底部导航条避让高度(px),写入进程内缓存。 */
  private cacheSafeArea(win: window.Window): void {
    try {
      const sysArea: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      console.info(`[QXSafeArea] 采集到状态栏避让高度 ${sysArea.topRect.height}px`);
      SafeAreaHolder.updateStatusBarHeightPx(sysArea.topRect.height);
      const navArea: window.AvoidArea =
        win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      SafeAreaHolder.updateNavBarHeightPx(navArea.bottomRect.height);
    } catch (e) {
      // 窗口尚未就绪,跳过本次采集。
    }
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

  aboutToDisappear(): void {
    // 注销安全区监听,避免页面销毁后回调悬挂。
    if (this.immersiveWindow && this.avoidAreaListener) {
      try {
        this.immersiveWindow.off('avoidAreaChange', this.avoidAreaListener);
      } catch (e) {
        // 忽略注销异常。
      }
    }
    this.avoidAreaListener = null;
    this.immersiveWindow = null;

    // 只清掉自己登记的那份,若期间已有新的 QXWebView 登记则不动。
    QXUIContextHolder.clear(this.uiContext);
    this.uiContext = null;

    this.lifecyclePlugin.notifyState('pageDestroy', 'aboutToDisappear');
    // 本页是被 forResult 打开的、且没主动 closeWithResult:回 {cancelled:true} 兜底,
    // 对应 Android QXWebViewActivity.onDestroy 里的 PageResultCenter.cancel。
    // PageResultCenter.resolve 已把回调摘走,这里的 cancel 对已回传过的页面是空操作。
    if (this.pageId) {
      PageResultCenter.cancel(this.pageId);
    }
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
      .onPageBegin((event: OnPageBeginEvent) => {
        // 新页面开始加载:H5 侧 JDBridge 还没就绪,重新开启 callJS 入队,
        // 收到 _jsInit 后统一补发。对应 Android JDBridgeInstaller.loadUrl -> startQueueRequest。
        this.bridge?.startQueueRequest();
        this.lifecyclePlugin.setUrl(event.url);
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
      // 仅开窗口全屏不够:ArkUI 组件默认避让安全区,需显式扩展才能顶到状态栏下。
      .expandSafeArea(
        this.immersive ? [SafeAreaType.SYSTEM] : [],
        this.immersive ? [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM] : []
      )
  }
}
