# HarmonyOS(鸿蒙)

> 适用于**纯血鸿蒙**(HarmonyOS NEXT / 5,API 12+)。非纯血(HarmonyOS 4 及以下)可直接用 Android 的 `.aar`。
> Url、Token/用户信息结构、宿主 App 需实现的能力,与 iOS/Android 章节一致。

DevEco Studio 5.0+ · compatibleSdkVersion `5.0.0(12)`

产物:`qx-hybrid.har`

## 接入方式

**1. 把 `qx-hybrid.har` 复制到你的项目 `libs/` 目录**

**2. 在模块的 `oh-package.json5` 中添加依赖:**

```json5
"dependencies": {
  "qx-hybrid": "file:./libs/qx-hybrid.har"
}
```

执行 `ohpm install`。SDK 已内置 WebView 容器、蓝牙、扫码(Scan Kit)、定位、二维码等能力,**无需再单独引三方库**。

## 配置 module.json5

> ⚠️ **与 Android 最大的不同**:HAR 里声明的权限**不会**自动合并到宿主 App。你**必须**在自己入口模块的 `module.json5` 里再声明一遍,否则运行时申请失败,定位/蓝牙/扫码不可用。

```json5
{
  "module": {
    // openMap 唤起第三方地图需要(canOpenLink 检测)
    "querySchemes": ["geo", "petalmaps", "amapuri", "androidamap", "baidumap", "qqmap"],

    "requestPermissions": [
      { "name": "ohos.permission.INTERNET" },
      { "name": "ohos.permission.GET_NETWORK_INFO" },
      {
        "name": "ohos.permission.APPROXIMATELY_LOCATION",
        "reason": "$string:reason_location",
        "usedScene": { "when": "inuse" }
      },
      {
        "name": "ohos.permission.LOCATION",
        "reason": "$string:reason_location",
        "usedScene": { "when": "inuse" }
      },
      {
        "name": "ohos.permission.ACCESS_BLUETOOTH",
        "reason": "$string:reason_bluetooth",
        "usedScene": { "when": "inuse" }
      },
      {
        "name": "ohos.permission.CAMERA",
        "reason": "$string:reason_camera",
        "usedScene": { "when": "inuse" }
      }
    ]
  }
}
```

`$string:reason_*` 需在 `resources/base/element/string.json` 里补上对应文案(权限申请弹窗展示)。

> 定位、蓝牙、相机是 user_grant 权限,SDK 会在 `QXWebView` 加载时自动向用户申请弹窗。

## 使用方式(推荐:命名路由,零承载页)

承载页由 SDK 提供,生命周期与系统返回键都内置处理,宿主只需两步:

```typescript
// ① App 启动时(如 EntryAbility.onCreate)登记一次
import { QXWebRegistry } from 'qx-hybrid';
QXWebRegistry.configure({ hostBridgeDelegateProvider: () => new MyHostBridgeDelegate() });
```

```typescript
// ② 打开 H5
import { router } from '@kit.ArkUI';
import { QX_WEB_PAGE_ROUTE_NAME } from 'qx-hybrid';
router.pushNamedRoute({ name: QX_WEB_PAGE_ROUTE_NAME, params: { url: 'https://fr-home-charge-web.cheryge.com' } });
```

`MyHostBridgeDelegate` 写法见下方「① 宿主桥代理」。返回/关闭/新开页已内置,无需写 `QXHostDelegate`。

> 若必须把 H5 嵌进自己的页面(自写 `@Entry` 承载页),则要多做一步:持有 `QXWebViewController` 并在 `onPageShow/onPageHide/onBackPress` 里转调,再把它传给 `QXWebView`。**漏了 `onBackPress`,系统返回键会退掉整个 WebView 而非 H5 逐级后退。**

# FR 宿主 APP 容器需实现以下方法(解偶方案)

采用与 iOS/Android 一致的**协议解偶**:SDK 定义代理接口,宿主 App 实现。分两个代理:

- `QXHostBridgeDelegate` —— H5 的自定义方法(`getUserInfo` / `getToken` / `openPage` 拉起登录支付),对应 iOS `webViewRequestCustomMethod` / `webViewRequestOpenPage`。
- `QXHostDelegate` —— 页面级动作(返回 / 关闭 / 新开 H5 页 / 导航栏)。

## 鸿蒙解偶方案

### ① 宿主桥代理:登录 / 用户信息 / 支付

```typescript
import { QXHostBridgeDelegate, HostMethodResolve, HostMethodReject } from 'qx-hybrid';

interface CarItem { vin: string; mac: string; }
interface UserInfo {
  phone: string;
  list: CarItem[];
  isLogin: boolean;
  userId: string;
  userName: string;
}
interface TokenResult { token: string; }
interface FailResult { success: boolean; message: string; }

export class MyHostBridgeDelegate implements QXHostBridgeDelegate {
  onCustomMethod(method: string, params: object | undefined,
    resolve: HostMethodResolve, reject: HostMethodReject): void {
    switch (method) {
      // 能提供 token 就实现 getToken;不能就实现 getUserInfo
      case 'getToken': {
        const r: TokenResult = { token: 'xxx' };
        resolve(r);
        break;
      }
      case 'getUserInfo': {
        const info: UserInfo = {
          phone: 'xxx',
          list: [{ vin: 'vin1', mac: 'mac1' }],
          isLogin: true,
          userId: 'xxx',
          userName: 'xxx'
        };
        resolve(info);
        break;
      }
      // 拉起登录/支付:H5 通过 openPage 传 app://login、app://pay
      case 'openPage': {
        const url: string = (params as Record<string, string>)?.['url'] ?? '';
        if (url === 'app://login') {
          // 宿主实现登录,登录成功后回传用户信息
          const info: UserInfo = {
            phone: 'xxx',
            list: [{ vin: 'vin1', mac: 'mac1' }],
            isLogin: true,
            userId: 'xxx',
            userName: 'xxx'
          };
          resolve(info);
        } else if (url === 'app://pay') {
          // 宿主实现支付,回传支付结果
          resolve({ success: true } as object);
        } else if (url === 'app://openFRConfirmPay') {
          // fr-charge-h5 点「预付并充电」拉起原生确认支付页。
          // params.params = { orderSeq, stationName, powerConnectorId }
          // 宿主拉起自己的收银台,支付结束后回传 { code, message, orderSeq }:
          //   code: '0' 成功 / '1' 用户取消 / '2' 跳转失败
          // 因为要等页面结果,这里通常异步 resolve(见 entry/pages/WebPage.ets 的 openFRConfirmPay 实现)。
          resolve({ code: '0', message: 'success', orderSeq: 'xxx' } as object);
        } else {
          const f: FailResult = { success: false, message: `未处理的 url: ${url}` };
          reject(JSON.stringify(f));
        }
        break;
      }
      default: {
        const f: FailResult = { success: false, message: `未知方法: ${method}` };
        reject(JSON.stringify(f));
      }
    }
  }
}
```

### ② 页面代理:返回 / 关闭 / 新开页 / 导航栏

> 仅**方式二(嵌入式)**需要。方式一(命名路由)已内置默认实现,可跳过本段。
>
> 注意接口方法名与类型(照抄即可):没有 `onGoBack`;导航栏枚举是 **`QXNavigationBarStyle`**(不是 `NavigationBarStyle`);`onCloseWithResult` 的参数类型是 **`Object`**(大写)。返回键的「有历史就后退、到根才关页」由 SDK 内部处理,`goBack` 到根时会回调 `onCloseWebView`。

```typescript
import { router } from '@kit.ArkUI';
import { QXHostDelegate, OpenWebViewOptions, QXNavigationBarStyle } from 'qx-hybrid';

export class MyHostDelegate implements QXHostDelegate {
  onCloseWebView(): void { router.back(); }
  onCloseWithResult(result: Object): void { router.back(); }
  onOpenWebView(options: OpenWebViewOptions): void {
    router.pushUrl({ url: 'pages/ChargePage', params: options });
  }
  onSetNavigationBarStyle(style: QXNavigationBarStyle): void { /* 按需设置导航栏 */ }
  // onFirstRender?(): void {}  // 可选,H5 首屏渲染完成回调
}
```

## 桥协议(与 iOS/Android 一致)

H5 通过 `window.XWebView._callNative(...)` 调原生,报文 `{plugin, action, params, callbackId}`,原生经 `window.JDBridge._handleResponseFromNative` 回包。插件名、action、蓝牙信封(`{code,message,data}`)、事件通道均与 iOS/Android 逐字节一致,H5 一份代码三端通用。

## 安装

提供 `.hap`/`.app` 安装包;或通过 AppGallery Connect 云测/内测邀请安装。
