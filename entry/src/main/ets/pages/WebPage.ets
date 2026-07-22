/*
 * WebView 承载页:用 QXWebView 加载 H5,并通过宿主桥代理把 手机号/VIN/MAC 提供给 H5。
 * H5 调 QXHostBridgePlugin 的 getUserInfo -> DemoHostBridgeDelegate 返回 {phone, list:[{vin,mac}]}。
 */

import { router } from '@kit.ArkUI';
import { QXWebView, QXHostDelegate, OpenWebViewOptions, NavigationBarStyle,
  QXHostBridgeDelegate, HostMethodResolve, HostMethodReject } from 'qx-hybrid';

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

/** 宿主页面代理:H5 请求返回/关闭时退回表单页。 */
class DemoHostDelegate implements QXHostDelegate {
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
    router.pushUrl({ url: 'pages/WebPage', params: options });
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

  onCustomMethod(method: string, params: object | undefined,
    resolve: HostMethodResolve, reject: HostMethodReject): void {
    console.info(`宿主自定义方法: ${method}, params=${JSON.stringify(params)}`);
    if (method === 'getUserInfo') {
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
      resolve(info);
      return;
    }
    // 其它方法暂未实现:回空对象,避免 H5 卡住(按需扩展)。
    const empty: Record<string, Object> = {};
    resolve(empty);
  }
}

@Entry
@Component
struct WebPage {
  @State targetUrl: string = '';
  private delegate: DemoHostDelegate = new DemoHostDelegate();
  private hostBridgeDelegate: DemoHostBridgeDelegate = new DemoHostBridgeDelegate('', '', '', '');

  aboutToAppear(): void {
    const p: LaunchParams = router.getParams() as LaunchParams;
    if (p) {
      this.targetUrl = p.url;
      this.hostBridgeDelegate = new DemoHostBridgeDelegate(p.phone, p.vin, p.mac, p.token);
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
