/*
 * 宿主页面代理。对应 Android QXWebViewHostDelegate + QXWebViewActivity 的容器能力。
 * 桥无法自行完成的「与承载页面相关」的动作(关闭、打开新 WebView、改导航栏、隐藏首屏 loading),
 * 由集成方在创建 QXWebView 时实现并注入。
 */

/**
 * 导航栏样式。对应 Android QXWebViewActivity.NavigationBarStyle。
 * H5 传 'default'|'light'|0 -> DEFAULT(深色文字);'black'|'dark'|1 -> BLACK(浅色文字)。
 */
export enum QXNavigationBarStyle {
  DEFAULT = 0,
  BLACK = 1
}

/** 把 H5 传入的 style/barStyle 归一为枚举。无法识别返回 undefined(由调用方回参数错误)。 */
export function parseNavigationBarStyle(value: Object | undefined): QXNavigationBarStyle | undefined {
  if (value === undefined || value === null) {
    return undefined;
  }
  if (typeof value === 'number') {
    const n: number = value as number;
    return n === 0 ? QXNavigationBarStyle.DEFAULT : (n === 1 ? QXNavigationBarStyle.BLACK : undefined);
  }
  if (typeof value === 'string') {
    const s: string = (value as string).trim().toLowerCase();
    if (s === '0') {
      return QXNavigationBarStyle.DEFAULT;
    }
    if (s === '1') {
      return QXNavigationBarStyle.BLACK;
    }
    if (s === 'default' || s === 'light') {
      return QXNavigationBarStyle.DEFAULT;
    }
    if (s === 'black' || s === 'dark') {
      return QXNavigationBarStyle.BLACK;
    }
  }
  return undefined;
}

/** 枚举 -> H5 侧字符串值(回包里的 style 字段)。 */
export function navigationBarStyleJsValue(style: QXNavigationBarStyle): string {
  return style === QXNavigationBarStyle.BLACK ? 'black' : 'default';
}

/**
 * openWebView 的完整选项。字段与 Android QXBasePlugin.handleOpenWebView 逐个对应。
 */
export interface OpenWebViewOptions {
  /** 已把 query 拼好的最终地址。 */
  url: string;
  /** 是否隐藏原生导航栏。不传表示沿用容器默认值。 */
  navHidden?: boolean;
  /** 是否沉浸式状态栏。不传表示沿用容器默认值。 */
  immersive?: boolean;
  /** 原生导航栏标题。 */
  navTitle?: string;
  /** iOS 兼容字段(push/present),鸿蒙侧忽略。 */
  presentStyle?: string;
  /** 是否需要等待新页面回传结果。 */
  forResult: boolean;
  /**
   * 回传 id。forResult=true 时必须原样传给新页面的 QXWebView.pageId,
   * 新页面 closeWithResult 时 SDK 会据此把数据回给打开方。
   */
  pageId: string;
}

export interface QXHostDelegate {
  /** action: closeWebView / goBack 无可后退历史时 —— 关闭当前承载页面。 */
  onCloseWebView(): void;

  /** action: closeWithResult —— 关闭当前页面(回传由 SDK 内部的 PageResultCenter 完成)。 */
  onCloseWithResult(result: Object): void;

  /** action: openWebView —— 打开一个新的 H5 页面。 */
  onOpenWebView(options: OpenWebViewOptions): void;

  /** action: setNavigationBarStyle —— 设置导航栏样式。 */
  onSetNavigationBarStyle(style: QXNavigationBarStyle): void;

  /** action: notifyFirstRender —— H5 首屏渲染完成,隐藏容器的初始 loading。 */
  onFirstRender?(): void;
}

/** 宿主桥自定义方法的结果回调。 */
export type HostMethodResolve = (data: Object) => void;
export type HostMethodReject = (message: string) => void;

/**
 * 宿主桥代理。对应 Android QXHostBridgePlugin -> QXWebViewHostDelegate。
 * H5 通过 `JDBridge.callNative("QXHostBridgePlugin", {action:<方法名>, params})` 调用宿主自定义方法,
 * 典型如 `getUserInfo`(返回 {phone, list:[{vin,mac}]})。返回**裸数据**(不套 code/message 信封)。
 */
export interface QXHostBridgeDelegate {
  /**
   * action='openPage' 的专用入口。对应 Android delegate.webViewRequestOpenPage(url, params)。
   * @param url H5 传的 url 或 pageName
   * @param params 附加参数
   */
  onOpenPage?(url: string, params: object | undefined,
    resolve: HostMethodResolve, reject: HostMethodReject): void;

  /**
   * @param method H5 请求的方法名(action),如 'getUserInfo'
   * @param params H5 传的参数
   * @param resolve 成功时回传数据对象给 H5
   * @param reject 失败时回传错误信息
   */
  onCustomMethod(method: string, params: object | undefined,
    resolve: HostMethodResolve, reject: HostMethodReject): void;
}
