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
  msg: null,                // 失败时为错误信息(见下)
  complete: true            // false = 流式中间帧,此时 msg 固定为 "onProgress"
});
```

> **`msg` 必须做一次 normalize**:插件 `onError` 传的是 JSON **字符串**(`QXBridgeError` / BLE 信封的输出),
> 原生下发前若发现它以 `{` 或 `[` 开头就要先解析成**对象**再塞进 `msg`。
> H5 的错误回调是 `errorFunc(response.msg, response)` —— 不 normalize 的话业务侧 `err.code` 恒为 `undefined`。

### 原生 → JS(事件推送)
生命周期与 BLE 事件都走 `callJS`(见 §4),**不是** CustomEvent:
```js
window.JDBridge._handleRequestFromNative('{"plugin":"QXLifecyclePlugin","params":{"eventName":"onPageLifecycle",...},"callbackId":"0"}');
```
`JDBridge.dispatchEvent`(CustomEvent)通道保留但当前无插件使用。

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

### QXHostBridgePlugin
`openPage`(参数 `{url|pageName, params}`),以及宿主 App 自定义的任意 action(如 `getUserInfo`、`getToken`)。
成功回**裸数据**(不套信封);宿主未返回数据时回 `{success:true}`。

### QXLifecyclePlugin
`subscribePageLifecycle` / `unsubscribePageLifecycle` / `getPageLifecycleState`
(`subscribe` / `unsubscribe` 为等价简写)—— 事件名 `onPageLifecycle`

state 结构:`{eventName, type, nativeType, timestamp, url, isForeground}`
`type` 取值:`pageLoad` / `pageWillShow` / `pageShow` / `pageWillHide` / `pageHide` / `pageDestroy`

### SystemInfoHandler
`getSystemInfo`, `getDeviceInfo`

## 3b. 非 BLE 插件的错误信封

`QXBasePlugin` / `QXLifecyclePlugin` / `QXHostBridgePlugin` **成功时回裸结果对象**,
失败时 `msg` 为一个 JSON 字符串,H5 侧 `JSON.parse` 后得到:

```json
{ "code": 1001, "message": "没有相机权限", "success": false, "data": { } }
```

| code | 含义 |
|---|---|
| `-1` | 未知错误 |
| `1` | 通用失败 |
| `1000` | 参数错误 |
| `1001` | 没有权限(相机/定位/蓝牙/通知) |
| `1002` | 用户取消 / 结果为空 |
| `1003` | 目标资源、页面、设备未找到 |
| `1004` | 超时 |
| `1005` | 功能未实现 / 不支持 |

**两个例外**(与 Android 一致,失败也走 `success` 回调):
- `location`:失败回 `locationType:"failure"` 的完整结构,附 `code`(1002 无权限 / 1007 定位服务未开 / 1008 超时)与 `msg`;
- `downloadAndOpenFile`:一律回 `{code, msg, filePath?}`,`code` 为 `200` 成功 / `400` 链接无效 / `500` 失败。

## 4. 原生 → Web 的事件推送(callJS,重要)

**这是从线上 H5(`fr-home-charge-web`)逆向确认的实际机制**,与"流式 complete"无关:

- H5 侧通过 `JDBridge.registerPlugin('QXBlePlugin', handler)` 注册一个 web 插件接收事件。
- 原生侧主动反调:`window.JDBridge._handleRequestFromNative('<json字符串>')`,报文为 `{plugin:"QXBlePlugin", params:{eventName, ...}, callbackId}`(**无 action 字段**)。
- H5 的 handler 按 `params.eventName` 分发到对应 `uni.on*` 回调。

以下事件均走此通道(字段与 Android 完全一致):

| plugin | eventName | payload 字段 |
|---|---|---|
| `QXBlePlugin` | `onBluetoothDeviceFound` | `{name, RSSI, deviceId, isSystemConnected, isBonded}` |
| `QXBlePlugin` | `onBLEConnectionStateChange` | `{isConnected, deviceId, name}` |
| `QXBlePlugin` | `onBLECharacteristicValueChange` | `{deviceId, value(大写HEX), characteristicId}` |
| `QXLifecyclePlugin` | `onPageLifecycle` | `{type, nativeType, timestamp, url, isForeground}` |

> H5 动作调用形如:`typeof JDBridge!=='undefined' ? JDBridge.callNative("QXBlePlugin",{action,params,success,error}) : uni.*`。
> 即:**动作走 `callNative`,事件走 `callJS`/`registerPlugin`**。

## 4a. 内置插件 `_jdbridge`(握手,必须实现)

H5 的 `JDBridge.js` 加载完成后会主动调:

```js
window.XWebView._callNative(JSON.stringify({ plugin: '_jdbridge', action: '_jsInit' }));
```

原生必须注册一个名为 `_jdbridge` 的内置插件处理两个 action:

| action | 作用 |
|---|---|
| `_jsInit` | H5 侧桥就绪。**收到之前 `callJS` 必须先入队**,收到后统一补发,否则首屏期间派发的事件(如 `pageLoad`)全部丢失。 |
| `_respondFromJs` | H5 对 `callJS` 的回执,报文为 `{callbackId, status, data, msg, complete}`,原生按 `callbackId` 取回挂起的回调。 |

未实现该插件时,H5 的握手会收到 `status:"-2" / "Target plugin not found."`。

## 4b. BLE 响应信封

`QXBlePlugin` 所有 action 的成功/失败结果都包一层信封(与 Android `sendSuccessCallback`/`sendFailCallback` 对齐,error code 沿用 uni-app 标准):

```json
{ "code": 0, "message": "ok", "data": { /* 具体结果 */ } }
```
- 成功:`code: 0`,结果在 `data` 里,经 `success` 回调返回。
- 失败:`code` 为 `10000~10013`(uni-app 标准:not init / not available / no device / connection fail / no service …)
  或负数扩展码(`-1`~`-9`、`-99`),信封 JSON 经 `error` 回调返回。
- **权限类失败例外**:`openBluetoothAdapter` / `getBluetoothAdapterState` / `requestBluetoothPermission`
  在无权限时回的是 §3b 的 `code:1001` 信封(带 `data.deniedPermissions` / `isDenied` / `isNotDetermined`),
  与 Android `sendBluetoothPermissionDenied` 一致。
- `startBluetoothDevicesDiscovery` 的成功回包额外带一个 `errMsg: "startBluetoothDevicesDiscovery:ok"`,
  兼容 H5 里按 uni 老式 `errMsg` 判定的代码。

各 action 的 `data` 载荷:

| action | data |
|---|---|
| `getBluetoothAdapterState` | `{available, discovering}` |
| `getBluetoothDevices` | `{devices:[{name, RSSI, deviceId, isSystemConnected, isBonded}]}` |
| `createBLEConnection` | `{deviceId, name}`(**连接真正建立后**才回,超时 10s 回 `-4`) |
| `getBLEDeviceServices` | `{services:[{serviceId, isPrimary}]}` |
| `getBLEDeviceCharacteristics` | `{characteristics:[{serviceId, characteristicId, properties[], isNotifying}]}`(遍历全部服务,不按 serviceId 过滤) |
| `writeBLECharacteristicValue` | `{characteristicId, value(大写HEX)}` |
| `notifyBLECharacteristicValueChange` | `{deviceId, serviceId, characteristicId, enabled}` |
| `requestBLEMtu` | `{deviceId, requestedMtu, actualMtu}` |
| `checkBluetoothPermission` | `{authorization(0/1/2), authorizationDesc, isAuthorized, isDenied, isNotDetermined, isSupported, grantedPermissions[], deniedPermissions[]}` |

> 注意:只有 `QXBlePlugin` 用此信封;`QXBasePlugin` / `QXLifecyclePlugin` / `QXHostBridgePlugin` 直接返回结果对象。

## 5. BLE 数据编码

`writeBLECharacteristicValue` 用 **`valueType`** 指明 `value` 的编码(与 Android 同名同义,默认 `UTF8`):

| valueType | value 形态 |
|---|---|
| `BUFFER` | 字节数组 `[161,178,195]`、`{"0":161,...}` 对象,或 `"161,178,195"` 字符串 |
| `HEX` / `16进制` | 十六进制串,如 `"A1B2C3"`(允许空格,长度须为偶数) |
| `BASE64` | Base64 字符串 |
| `UTF8` / `TEXT` | 原文,按 UTF-8 编码 |

`notifyBLECharacteristicValueChange` 用 **`enable`**(布尔)开关通知;为兼容旧 H5 也接受 `state`。
原生下发的特征值(写入回包与 `onBLECharacteristicValueChange` 事件)一律是**大写 HEX**。

## 6. 坐标系

`location` 返回 `latitude/longitude` 为 **GCJ-02**(与高德地图一致),三端都需做 WGS-84→GCJ-02 转换。
`openMap` 的入参 `latitude/longitude` 也已是 GCJ-02,原生侧**不再二次转换**。

## 7. 三端实现对照

| 能力 | Android | iOS | HarmonyOS |
|---|---|---|---|
| 注入 | `addJavascriptInterface` | `WKScriptMessageHandler` | `Web.javaScriptProxy` |
| 执行 JS | `evaluateJavascript` | `evaluateJavaScript` | `controller.runJavaScript` |
| BLE | Android-BLE | CoreBluetooth | `@kit.ConnectivityKit` |
| 扫码 | zxing | AVFoundation | Scan Kit |
| 定位 | 高德/系统 | CoreLocation | `geoLocationManager` |
