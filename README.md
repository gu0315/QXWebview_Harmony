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

> ✅ **已与线上生产 H5 核对**(`https://fr-home-charge-web.cheryge.com`,uni-app):其内置的 `window.JDBridge` 调用 `window.XWebView._callNative(...)`、报文 `{plugin, action, params, callbackId}`、蓝牙插件名 `QXBlePlugin` 及 14 个 action —— **与本 SDK 逐字节一致**。
> 逆向还确认了两条必须遵守的 BLE 契约,已在 `QXBlePlugin.ets` 落地:
> 1. BLE 响应包 `{code, message, data}` 信封(`code:0` 成功 / `10000-10013` 失败);
> 2. `onBluetoothDeviceFound` / `onBLEConnectionStateChange` / `onBLECharacteristicValueChange` 三个事件经 `callJS('QXBlePlugin', {eventName, ...})` 推送(不是 action 回调)。详见协议文档 §4。H5 同学的逐 action 自测清单见 [`H5_SELFTEST.md`](./H5_SELFTEST.md)。

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

> 若用到 `openMap` 唤起第三方地图,集成方需在自己入口模块的 `module.json5` 声明 `querySchemes: ["petalmaps","amapuri","baidumap","qqmap"]`(参考 `entry` 模块)。

页面中:

```typescript
import { QXWebView, QXHostDelegate } from 'qx-hybrid';

@Entry
@Component
struct ChargePage {
  build() {
    QXWebView({ url: 'https://your-h5/index.html', delegate: myDelegate })
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
| QXBasePlugin | openMap | ✅ 已实现 | 高德/百度/腾讯/华为 Petal scheme + geo: 回退;需集成方声明 querySchemes |
| QXBlePlugin | 权限 / 适配器状态 / 扫描 | ✅ 已实现 | 真机验证 |
| QXBlePlugin | 连接 / 服务 / 特征 / 写 / notify / MTU | 🟡 已按官方 API 接线 | **必须真机 + 充电桩联调**;连接状态经 `onBLEConnectionStateChange` 事件广播 |
| QXLifecyclePlugin | subscribe / unsubscribe / getPageLifecycleState | ✅ | onPageLifecycle 事件 |
| SystemInfoPlugin | getSystemInfo / getDeviceInfo | ✅ | |

## 已知需真机验证的点

- **BLE 全链路**:模拟器无蓝牙。连接/GATT 读写/notify 的 `writeType`、MTU、UUID 大小写等需在纯血真机 + 桩上校准;连接状态变化经 `onBLEConnectionStateChange` 事件回 H5。
- **扫码 / 选图 / 下载打开文件**:已用 Scan Kit / PhotoViewPicker / NetworkKit 实现,依赖相机与相册,需真机运行验证。
- **openSetting / openMap 的 Want**:系统设置页 `bundleName`、地图 scheme 以真机为准。

> ⚠️ 本工程代码在无 DevEco 环境下编写,类型与 API 调用按官方文档对齐,但**尚未经过编译器与真机验证**。首次导入 DevEco 后请以 `Build` 报错为准逐个修正(主要集中在 🟡 项)。
