/*
 * WebView 承载页:用 QXWebView 加载 H5,并通过宿主桥代理把 手机号/VIN/MAC 提供给 H5。
 * H5 调 QXHostBridgePlugin 的 getUserInfo -> DemoHostBridgeDelegate 返回 {phone, list:[{vin,mac}]}。
 */

import { router } from '@kit.ArkUI';
import { QXWebView, QXHostDelegate, OpenWebViewOptions, NavigationBarStyle,
  QXHostBridgeDelegate, HostMethodResolve, HostMethodReject } from 'qx-hybrid';
import { FRConfirmPayResultCenter } from '../common/FRConfirmPayResultCenter';

interface LaunchParams {
  url: string;
  phone: string;
  vin: string;
  mac: string;
  token: string;
}

interface CarItem {
  vin: string;
  mac: string;
}

interface UserInfoResult {
  isLogin: boolean;
  userId: string;
  userName: string;
  phone: string;
  token: string;
  list: CarItem[];
}

/** app://openFRConfirmPay 的返回数据,回传给 H5 */
interface FRConfirmPayResult {
  code: string;
  message: string;
  orderSeq: string;
}

/** getToken 的返回数据 */
interface TokenResult {
  token: string;
}

/** 未处理的 url / 未知方法的统一返回,与 iOS / Android 的 default 分支对齐 */
interface FailResult {
  success: boolean;
  message: string;
}

/** 参数容错:H5 传来的值统一按字符串取 */
function toStr(value: Object | undefined): string {
  if (value === undefined || value === null) {
    return '';
  }
  return typeof value === 'string' ? value as string : String(value);
}

/** 宿主页面代理:H5 请求返回/关闭时退回表单页。 */
class DemoHostDelegate implements QXHostDelegate {
  /** 当前页的用户信息,openWebView 时透传给下一个 WebPage,避免新页 getUserInfo 取不到值。 */
  private session: LaunchParams;

  constructor(session: LaunchParams) {
    this.session = session;
  }

  onGoBack(): void {
    router.back();
  }

  onCloseWebView(): void {
    router.back();
  }

  onCloseWithResult(result: object): void {
    console.info('closeWithResult: ' + JSON.stringify(result));
    router.back();
  }

  onOpenWebView(options: OpenWebViewOptions): void {
    // options 只有 { url, title, extra },不含用户信息;
    // 这里补上当前页的 phone/vin/mac/token,保证新开的 WebPage 仍是已登录态。
    const next: LaunchParams = {
      url: options.url,
      phone: this.session.phone,
      vin: this.session.vin,
      mac: this.session.mac,
      token: this.session.token
    };
    router.pushUrl({ url: 'pages/WebPage', params: next });
  }

  onSetNavigationBarStyle(style: NavigationBarStyle): void {
    console.info('setNavigationBarStyle: ' + JSON.stringify(style));
  }
}

/** 宿主桥代理:响应 H5 的自定义方法。这里用表单填的值拼出 getUserInfo 的返回。 */
class DemoHostBridgeDelegate implements QXHostBridgeDelegate {
  private phone: string;
  private vin: string;
  private mac: string;
  private token: string;

  constructor(phone: string, vin: string, mac: string, token: string) {
    this.phone = phone;
    this.vin = vin;
    this.mac = mac;
    this.token = token;
  }

  /**
   * 用表单填的值拼出用户信息,getUserInfo 与 app://login 共用。
   * 与 iOS UserSession.userInfoPayload / Android UserSession.userInfoPayload 对齐。
   */
  private buildUserInfo(): UserInfoResult {
    const car: CarItem = { vin: this.vin, mac: this.mac };
    // H5 的登录重试循环判断的是 e.isLogin;phone 非空即视为已登录,避免反复拉起登录。
    const loggedIn: boolean = this.phone.length > 0;
    const info: UserInfoResult = {
      isLogin: loggedIn,
      userId: this.phone,
      userName: this.phone,
      phone: this.phone,
      token: this.token,
      list: [car]
    };
    return info;
  }

  onCustomMethod(method: string, params: object | undefined,
    resolve: HostMethodResolve, reject: HostMethodReject): void {
    console.info(`宿主自定义方法: ${method}, params=${JSON.stringify(params)}`);
    if (method === 'getUserInfo') {
      resolve(this.buildUserInfo());
      return;
    }
    // 与 iOS / Android 的 getToken 对齐:返回 { token }
    if (method === 'getToken') {
      const tokenResult: TokenResult = { token: this.token };
      resolve(tokenResult);
      return;
    }
    // H5 通过 openPage 拉起原生页面:{ url, params }
    if (method === 'openPage') {
      const outer: Record<string, Object> = (params as Record<string, Object>) ?? {};
      const url: string = toStr(outer['url']);
      if (url === 'app://openFRConfirmPay') {
        this.openFRConfirmPay(outer['params'] as Record<string, Object>, resolve);
        return;
      }
      // 宿主登录:登录成功后回传用户信息(与 iOS / Android 的 app://login 对齐)。
      if (url === 'app://login') {
        resolve(this.buildUserInfo());
        return;
      }
      // 其它 url(如 app://pay)暂未实现:与 iOS / Android default 分支一致,回未处理提示。
      const unhandledUrl: FailResult = { success: false, message: `未处理的 url: ${url}` };
      resolve(unhandledUrl);
      return;
    }
    // 其它方法暂未实现:与 iOS / Android default 分支一致,回未知方法提示。
    const unknownMethod: FailResult = { success: false, message: `未知的方法: ${method}` };
    resolve(unknownMethod);
  }

  /**
   * 拉起模拟的 FR 确认支付页,页面结束时通过结果中心把 {code,message,orderSeq} 回传给 H5。
   * 真实宿主替换成自己的收银台即可。
   */
  private openFRConfirmPay(inner: Record<string, Object> | undefined, resolve: HostMethodResolve): void {
    const params: Record<string, Object> = inner ?? {};
    const orderSeq: string = toStr(params['orderSeq']);          // 绿能侧充电订单号
    const stationName: string = toStr(params['stationName']);    // 充电站名称
    const powerConnectorId: string = toStr(params['powerConnectorId']); // 充电桩编号

    FRConfirmPayResultCenter.register((code: string, message: string, seq: string): void => {
      const result: FRConfirmPayResult = { code, message, orderSeq: seq };
      resolve(result);
    });

    router.pushUrl({
      url: 'pages/FRConfirmPay',
      params: { orderSeq, stationName, powerConnectorId }
    }).catch((err: Error): void => {
      // 拉不起页面 -> code 2,并撤销挂起的回调
      FRConfirmPayResultCenter.deliver('2', `跳转失败: ${err?.message ?? ''}`, orderSeq);
    });
  }
}

@Entry
@Component
struct WebPage {
  @State targetUrl: string = '';
  private delegate: DemoHostDelegate = new DemoHostDelegate({ url: '', phone: '', vin: '', mac: '', token: '' });
  private hostBridgeDelegate: DemoHostBridgeDelegate = new DemoHostBridgeDelegate('', '', '', '');

  aboutToAppear(): void {
    const p: LaunchParams = router.getParams() as LaunchParams;
    if (p) {
      // 上级页面可能只透传部分字段,统一兜底成字符串,避免后续 .length 取到 undefined 崩溃。
      const session: LaunchParams = {
        url: toStr(p.url),
        phone: toStr(p.phone),
        vin: toStr(p.vin),
        mac: toStr(p.mac),
        token: toStr(p.token)
      };
      this.targetUrl = session.url;
      this.delegate = new DemoHostDelegate(session);
      this.hostBridgeDelegate =
        new DemoHostBridgeDelegate(session.phone, session.vin, session.mac, session.token);
    }
  }

  build() {
    Column() {
      QXWebView({
        url: this.targetUrl,
        delegate: this.delegate,
        hostBridgeDelegate: this.hostBridgeDelegate
      })
    }
    .width('100%')
    .height('100%')
  }
}
