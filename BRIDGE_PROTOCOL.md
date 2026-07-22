# QX Hybrid 桥接协议(三端通用契约)

本文件是 Android / iOS / HarmonyOS 三端**共同遵守**的 H5↔原生通信契约。任意一端实现时必须与此一致,H5 才能一份代码跑三端。源头为 Android 的 JD 开源 JDBridge(MIT)。

## 1. 通道

### JS → 原生
```js
window.XWebView._callNative(JSON.stringify({
  plugin: "QXBasePlugin",   // 目标插件名
  action: "getDeviceInfo",  // 方法名
  params: { /* 入参对象 */ },
  callbackId: "cb_123"      // 由 H5 生成,用于匹配响应
}));
```

### 原生 → JS(响应)
```js
window.JDBridge._handleResponseFromNative({
  status: "0",              // 见状态码
  callbackId: "cb_123",     // 原样回传
  data: { /* 结果 */ },
  msg: null,                // 失败时为错误信息(string 或结构化对象)
  complete: true            // false = 流式中间帧(见 §4)
});
```

### 原生 → JS(事件广播)
```js
window.dispatchEvent(new CustomEvent("onPageLifecycle", { detail: { state: "onShow" } }));
```

## 2. 状态码

| status | 含义 |
|---|---|
| `"0"` | 成功 |
| `"-1"` | 业务失败(msg 为原因) |
| `"1"` | 原生异常 |
| `"-2"` | 插件或 action 未找到 |

## 3. 插件与 action 清单

### QXBasePlugin
`scanQRCode`, `goBack`, `closeWebView`, `getDeviceInfo`, `location`, `downloadAndOpenFile`, `openMap`, `setNavigationBarStyle`, `openWebView`, `closeWithResult`, `openUrl`, `chooseImage`, `setWebCacheToken`, `setStorage`, `getStorage`, `removeStorage`, `clearStorage`, `notifyFirstRender`, `openSetting`(type: `ble`/`wlan`/`general`/`privacy`)

### QXBlePlugin
`openBluetoothAdapter`, `closeBluetoothAdapter`, `getBluetoothAdapterState`, `startBluetoothDevicesDiscovery`, `stopBluetoothDevicesDiscovery`, `getBluetoothDevices`, `createBLEConnection`, `closeBLEConnection`, `getBLEDeviceServices`, `getBLEDeviceCharacteristics`, `writeBLECharacteristicValue`, `notifyBLECharacteristicValueChange`, `requestBLEMtu`, `requestBluetoothPermission`, `checkBluetoothPermission`

### QXLifecyclePlugin
`subscribe`, `unsubscribe`, `getPageLifecycleState` —— 事件名 `onPageLifecycle`

### SystemInfoHandler
`getSystemInfo`, `getDeviceInfo`

## 4. 原生 → Web 的事件推送(callJS,重要)

**这是从线上 H5(`fr-home-charge-web`)逆向确认的实际机制**,与"流式 complete"无关:

- H5 侧通过 `JDBridge.registerPlugin('QXBlePlugin', handler)` 注册一个 web 插件接收事件。
- 原生侧主动反调:`window.JDBridge._handleRequestFromNative('<json字符串>')`,报文为 `{plugin:"QXBlePlugin", params:{eventName, ...}, callbackId}`(**无 action 字段**)。
- H5 的 handler 按 `params.eventName` 分发到对应 `uni.on*` 回调。

BLE 三个事件均走此通道(字段与 Android 完全一致):

| eventName | payload 字段 |
|---|---|
| `onBluetoothDeviceFound` | `{name, RSSI, deviceId}` |
| `onBLEConnectionStateChange` | `{isConnected, deviceId, name}` |
| `onBLECharacteristicValueChange` | `{deviceId, value(hex), characteristicId}` |

> H5 动作调用形如:`typeof JDBridge!=='undefined' ? JDBridge.callNative("QXBlePlugin",{action,params,success,error}) : uni.*`。
> 即:**动作走 `callNative`,事件走 `callJS`/`registerPlugin`**。

## 4b. BLE 响应信封

`QXBlePlugin` 所有 action 的成功/失败结果都包一层信封(与 Android `sendSuccessCallback`/`sendFailCallback` 对齐,error code 沿用 uni-app 标准):

```json
{ "code": 0, "message": "ok", "data": { /* 具体结果 */ } }
```
- 成功:`code: 0`,结果在 `data` 里,经 `success` 回调返回。
- 失败:`code: 10000~10013`(not init / not available / no device / connection fail / no service …),信封 JSON 经 `error` 回调返回。

> 注意:只有 `QXBlePlugin` 用此信封;`QXBasePlugin` / `QXLifecyclePlugin` 直接返回结果对象。

## 5. BLE 数据编码

`writeBLECharacteristicValue` / `notifyBLECharacteristicValueChange` 的 `value` 为字符串,`format` 指明编码:
- `BUFFER`:十六进制字符串(默认,如 `"a1b2c3"`)
- `BASE64`:Base64 字符串
- `TEXT`:UTF-8 文本

## 6. 坐标系

`location` 返回 `latitude/longitude` 为 **GCJ-02**(与高德地图一致),另附 `wgsLatitude/wgsLongitude` 为原始 WGS-84。三端都需做 WGS-84→GCJ-02 转换。

## 7. 三端实现对照

| 能力 | Android | iOS | HarmonyOS |
|---|---|---|---|
| 注入 | `addJavascriptInterface` | `WKScriptMessageHandler` | `Web.javaScriptProxy` |
| 执行 JS | `evaluateJavascript` | `evaluateJavaScript` | `controller.runJavaScript` |
| BLE | Android-BLE | CoreBluetooth | `@kit.ConnectivityKit` |
| 扫码 | zxing | AVFoundation | Scan Kit |
| 定位 | 高德/系统 | CoreLocation | `geoLocationManager` |
