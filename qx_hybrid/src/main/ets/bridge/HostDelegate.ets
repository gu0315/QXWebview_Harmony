/*
 * 宿主页面代理。对应 Android QXWebViewHostDelegate。
 * 桥无法自行完成的「与承载页面相关」的动作(返回、关闭、打开新 WebView、改导航栏),
 * 由集成方在创建 QXWebView 时实现并注入。
 */

export interface OpenWebViewOptions {
  url: string;
  title?: string;
  /** 透传给下一页的自定义参数。 */
  extra?: object;
}

export interface NavigationBarStyle {
  /** 标题文字。 */
  title?: string;
  /** 前景色,如 '#FFFFFF'。 */
  frontColor?: string;
  /** 背景色,如 '#000000'。 */
  backgroundColor?: string;
  /** 是否隐藏导航栏。 */
  hidden?: boolean;
}

export interface QXHostDelegate {
  /** action: goBack —— H5 请求页面返回。 */
  onGoBack(): void;

  /** action: closeWebView —— 关闭当前承载页面。 */
  onCloseWebView(): void;

  /** action: closeWithResult —— 关闭并回传结果给上一页。 */
  onCloseWithResult(result: object): void;

  /** action: openWebView —— 打开一个新的 H5 页面。 */
  onOpenWebView(options: OpenWebViewOptions): void;

  /** action: setNavigationBarStyle —— 设置导航栏样式。 */
  onSetNavigationBarStyle(style: NavigationBarStyle): void;
}

/** 宿主桥自定义方法的结果回调。 */
export type HostMethodResolve = (data: Object) => void;
export type HostMethodReject = (message: string) => void;

/**
 * 宿主桥代理。对应 Android QXHostBridgePlugin -> QXWebViewHostDelegate.webViewRequestCustomMethod。
 * H5 通过 `JDBridge.callNative("QXHostBridgePlugin", {action:<方法名>, params})` 调用宿主自定义方法,
 * 典型如 `getUserInfo`(返回 {phone, list:[{vin,mac}]})。返回**裸数据**(不套 code/message 信封)。
 */
export interface QXHostBridgeDelegate {
  /**
   * @param method H5 请求的方法名(action),如 'getUserInfo'
   * @param params H5 传的参数
   * @param resolve 成功时回传数据对象给 H5
   * @param reject 失败时回传错误信息
   */
  onCustomMethod(method: string, params: object | undefined,
    resolve: HostMethodResolve, reject: HostMethodReject): void;
}
