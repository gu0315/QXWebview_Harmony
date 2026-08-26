# chery_harmony —— QX Hybrid 鸿蒙原生 SDK

Android `qx_hybrid`(`com.energy.sdk:qx-hybrid`)的**纯血鸿蒙(HarmonyOS NEXT / 5)** 原生实现,用 ArkTS 编写,打包为 **HAR**,通过 **OHPM** 私有源分发给集成方。

> 为什么需要它:纯血鸿蒙去掉了 Android 运行环境,`.aar` / APK 无法运行。要在纯血鸿蒙上提供同样的混合开发能力,必须有一套鸿蒙原生 SDK。非纯血(HarmonyOS 4 及以下)仍可直接用原 `.aar`。

## 核心设计:桥协议逐字节对齐,H5 零改动

本 SDK 与 Android 端保持**完全相同的 JS 桥协议**,因此同一份 H5(`fr-home-charge-h5`)无需任何改动即可运行:

| 约定 | 值(Android / 鸿蒙一致) |
|---|---|
| 注入对象名 | `window.XWebView` |
| JS 调原生 | `XWebView._callNative(JSON.stringify({plugin, action, params, callbackId}))` |
| 原生回 JS | `window.JDBridge._handleResponseFromNative({status, callbackId, data, msg, complete})` |
| 状态码 | `0` 成功 / `-1` 失败 / `1` 异常 / `-2` 未找到 |
| 事件派发 | `window.dispatchEvent(new CustomEvent(name, {detail}))` |

详见 [`BRIDGE_PROTOCOL.md`](./BRIDGE_PROTOCOL.md)。

## 目录结构

```
chery_harmony/
├── qx_hybrid/                 ← 对外发布的 HAR(SDK 本体)
│   ├── Index.ets              ← 对外 API 入口
│   └── src/main/ets/
│       ├── bridge/            ← 桥核心(与 Android JDBridge 对应)
│       │   ├── BridgeConstant.ets   注入名/状态码/JS 模板
│       │   ├── BridgeTypes.ets      Request/Response/Callback/Host
│       │   ├── BridgePlugin.ets     插件接口 + 基类
│       │   ├── HostDelegate.ets     宿主页面代理(返回/关闭/导航栏)
│       │   └── JDBridge.ets         分发器 + 注入 + 回调
│       ├── plugins/
│       │   ├── QXBasePlugin.ets     18 个基础 action
│       │   ├── QXBlePlugin.ets      15 个蓝牙 action
│       │   ├── QXLifecyclePlugin.ets 生命周期订阅
│       │   └── SystemInfoPlugin.ets  设备信息
│       ├── components/QXWebView.ets  Web 容器组件
│       └── utils/                    GCJ02 转换 / 存储 / BLE 编解码
└── entry/                     ← 演示 App(在模拟器里验证桥)
```

## 在 DevEco Studio 中打开

1. 安装 **DevEco Studio**(HarmonyOS 5 / API 12+),登录华为账号。
2. `File > Open` 选择 `chery_harmony` 目录。
3. 首次打开会提示补全工程资源:
   - `entry` 演示模块的图标等 **media 资源**由 DevEco 新建工程模板生成(`app_icon` / `startIcon` / `layered_image`)。若缺失,新建一个空模板工程把 `AppScope/resources` 与 `entry/src/main/resources/base/media` 拷过来即可。**HAR 本体(`qx_hybrid`)不依赖这些图标。**
4. `Sync` 让 hvigor 拉取依赖。

## 构建与发布 HAR

```bash
# 构建 HAR 产物
hvigorw assembleHar

# 产物:qx_hybrid/build/default/outputs/default/qx-hybrid.har
# 发布到 OHPM 私有源(先 ohpm config 配好私有 registry 与登录)
ohpm publish qx_hybrid/build/default/outputs/default/qx-hybrid.har
```

> **完整的打包 / 分发 / 集成流程**(HAR vs OHPM、私有源搭建、对方如何引入、权限不自动合并的坑)见
> [`PUBLISH_AND_INTEGRATE.md`](./PUBLISH_AND_INTEGRATE.md)。一句话:鸿蒙的 aar/pod 就是 **HAR**,私服就是 **OHPM 私有 Registry**。

## 集成方如何使用

在集成方工程 `oh-package.json5`:

```json5
"dependencies": {
  "qx-hybrid": "^0.1.10"   // 来自你的 OHPM 私有源
}
```

> 若用到 `openMap` 唤起第三方地图,集成方需在自己入口模块的 `module.json5` 声明 `querySchemes: ["geo","petalmaps","amapuri","androidamap","baidumap","qqmap"]`(鸿蒙版高德是 `amapuri`,花瓣用 `geo:` 唤起、`petalmaps` 探测,参考 `entry` 模块)。

### 接入方式一:零承载页(命名路由,**推荐**)

承载页由 SDK 提供(`QXWebPage`),生命周期与系统返回键全在 SDK 内处理,宿主**不用写承载页、不用写 `onBackPress`**。只需两步:

```typescript
// ① App 启动时(如 EntryAbility.onCreate)登记一次业务能力
import { QXWebRegistry } from 'qx-hybrid';

QXWebRegistry.configure({
  // 每次进页面时取当前登录态,拼 getUserInfo / getToken / openPage 的返回
  hostBridgeDelegateProvider: () => new MyHostBridgeDelegate()
  // scanHandler / immersive / statusBarContentColor 可选
});
```

```typescript
// ② 任意位置打开 H5:直接命名路由,无需在 main_pages.json 登记
import { router } from '@kit.ArkUI';
import { QX_WEB_PAGE_ROUTE_NAME } from 'qx-hybrid';   // = 'QXWebPage'

router.pushNamedRoute({ name: QX_WEB_PAGE_ROUTE_NAME, params: { url: 'https://your-h5/index.html' } });
```

> ⚠️ 系统返回键要「H5 逐级后退」而非退整个 WebView —— 用本方式**天然生效**,这也是修复「别的宿主系统返回键退整个 web」的推荐路径。

### 接入方式二:嵌入式(自写承载页)

需要把 H5 塞进宿主自己的页面 / tab / 布局时用。**注意 ArkUI 的 `onBackPress()`/`onPageShow()`/`onPageHide()` 只在 `@Entry` 上触发**,承载页必须逐一转调,否则:漏 `onPageShow` → H5 收不到生命周期;漏 `onBackPress` → 系统返回键一次性退整个 WebView。

```typescript
import { QXWebView, QXWebViewController, QXHostDelegate } from 'qx-hybrid';

@Entry
@Component
struct ChargePage {
  private webController: QXWebViewController = new QXWebViewController();

  onPageShow(): void { this.webController.onPageShow(); }
  onPageHide(): void { this.webController.onPageHide(); }
  // 不加这行,系统返回键会一次性关掉整个 WebView,而非 H5 逐级后退。
  onBackPress(): boolean { return this.webController.onBackPress(); }

  build() {
    QXWebView({
      url: 'https://your-h5/index.html',
      delegate: myDelegate,
      webController: this.webController
    })
  }
}
```

## action 实现状态

| 插件 | action | 状态 | 备注 |
|---|---|---|---|
| QXBasePlugin | getDeviceInfo / setStorage / getStorage / removeStorage / clearStorage / setWebCacheToken / notifyFirstRender | ✅ 模拟器可跑 | preferences / deviceInfo |
| QXBasePlugin | location | ✅ 模拟器可跑 | geoLocationManager + WGS84→GCJ02 |
| QXBasePlugin | goBack / closeWebView / closeWithResult / openWebView / setNavigationBarStyle | ✅ | 转宿主 delegate,集成方实现 UI |
| QXBasePlugin | openUrl / openSetting | ✅ | startAbility;openSetting 的系统页 bundleName 需真机核对 |
| QXBasePlugin | scanQRCode | ✅ 已实现(真机) | Scan Kit `startScanForResult`;可用 scanHandler 覆盖 |
| QXBasePlugin | chooseImage | ✅ 已实现(真机) | PhotoViewPicker;可用 chooseImageHandler 覆盖 |
| QXBasePlugin | downloadAndOpenFile | ✅ 已实现(真机) | NetworkKit 下载 + startAbility 打开 |
| QXBasePlugin | openMap | ✅ 已实现 | 不传 `app` 弹「选择地图导航」面板(对齐 Android showMapSelectSheet),传 `app` 则直接唤起;未装则走网页版;需集成方声明 querySchemes。候选为高德/百度/腾讯,面板是自绘 ActionSheet(openCustomDialog)。**scheme 以真机 `bm dump` 为准,勿照抄 Android**:鸿蒙版高德是 `amapuri`(Android 为 `androidamap`);百度是 `baidumap://map/...`,host 必须带上,否则 `canOpenLink` 判成没装;腾讯鸿蒙版包名是 `com.tencent.mapohos`,必须用 `qqmap://map/routeplan`(Android 的 `map/marker` 在鸿蒙版没有对应路由,会显示「网络异常」);华为花瓣只认标准 `geo:`,且停在 POI 卡片需再点「路线」。**唤起一律锁 `bundleName`**,否则 scheme 会被别的 App 接管 |
| QXBlePlugin | 权限 / 适配器状态 / 扫描 | ✅ 已实现 | 真机验证 |
| QXBlePlugin | 连接 / 服务 / 特征 / 写 / notify / MTU | ✅ 已实现(真机 + 充电桩验证) | 连接状态经 `onBLEConnectionStateChange` 事件广播。**GATT 写按 deviceId 串行化**:鸿蒙不排队并发写,上一次写未回 WriteComplete 时再写会返回 2900099,H5 会据此判链路失效并拆连接 |
| QXHostBridgePlugin | openPage / 宿主自定义方法 | ✅ | 转 QXHostBridgeDelegate,回裸数据 |
| QXLifecyclePlugin | subscribePageLifecycle / unsubscribePageLifecycle / getPageLifecycleState | ✅ | 事件走 callJS;承载页需转调 `QXWebViewController` |
| SystemInfoPlugin | getSystemInfo / getDeviceInfo | ✅ | |

> 所有 action 的入参名、返回结构、错误码均以 Android `qx_hybrid` 为准,详见 [BRIDGE_PROTOCOL.md](BRIDGE_PROTOCOL.md)。

## 已知需真机验证的点

- **BLE 全链路**:模拟器无蓝牙。连接/GATT 读写/notify 的 `writeType`、MTU、UUID 大小写等需在纯血真机 + 桩上校准;连接状态变化经 `onBLEConnectionStateChange` 事件回 H5。
- **扫码 / 选图 / 下载打开文件**:已用 Scan Kit / PhotoViewPicker / NetworkKit 实现,依赖相机与相册,需真机运行验证。
- **openSetting / openMap 的 Want**:系统设置页 `bundleName`、地图 scheme 以真机为准。
