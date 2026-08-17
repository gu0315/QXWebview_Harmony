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
    "querySchemes": ["petalmaps", "androidamap", "baidumap", "qqmap"],

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

## 使用方式

**使用内置的 `QXWebView` 组件:**

```typescript
import { QXWebView, QXHostDelegate, QXHostBridgeDelegate } from 'qx-hybrid';

@Entry
@Component
struct ChargePage {
  // 页面级代理(返回/关闭/新开页/导航栏)
  private delegate: MyHostDelegate = new MyHostDelegate();
  // 宿主桥代理(登录/用户信息/token 等自定义方法)
  private hostBridgeDelegate: MyHostBridgeDelegate = new MyHostBridgeDelegate();

  build() {
    Column() {
      QXWebView({
        url: 'https://fr-home-charge-web.cheryge.com',
        delegate: this.delegate,
        hostBridgeDelegate: this.hostBridgeDelegate
      })
    }
    .width('100%')
    .height('100%')
  }
}
```

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

```typescript
import { router } from '@kit.ArkUI';
import { QXHostDelegate, OpenWebViewOptions, NavigationBarStyle } from 'qx-hybrid';

export class MyHostDelegate implements QXHostDelegate {
  onGoBack(): void { router.back(); }
  onCloseWebView(): void { router.back(); }
  onCloseWithResult(result: object): void { router.back(); }
  onOpenWebView(options: OpenWebViewOptions): void {
    router.pushUrl({ url: 'pages/ChargePage', params: options });
  }
  onSetNavigationBarStyle(style: NavigationBarStyle): void { /* 按需设置导航栏 */ }
}
```

## 桥协议(与 iOS/Android 一致)

H5 通过 `window.XWebView._callNative(...)` 调原生,报文 `{plugin, action, params, callbackId}`,原生经 `window.JDBridge._handleResponseFromNative` 回包。插件名、action、蓝牙信封(`{code,message,data}`)、事件通道均与 iOS/Android 逐字节一致,H5 一份代码三端通用。

## 安装

提供 `.hap`/`.app` 安装包;或通过 AppGallery Connect 云测/内测邀请安装。
