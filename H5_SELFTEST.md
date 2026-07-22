# H5 接入自测清单(鸿蒙)

给 H5 同学:下面每个 action 给出**调用示例**与**预期返回**,方便在鸿蒙容器里逐个自测,确认桥协议与安卓/iOS 一致。桥协议本身见 [`BRIDGE_PROTOCOL.md`](./BRIDGE_PROTOCOL.md)。

## 通用调用封装

H5 侧通常已有封装。若要直接测,可用:

```js
function callNative(plugin, action, params) {
  return new Promise((resolve, reject) => {
    const callbackId = 'cb_' + Date.now() + '_' + Math.random().toString(36).slice(2);
    // 由 JDBridge 运行时注册回调;这里演示直连底层。
    window.JDBridge._pending = window.JDBridge._pending || {};
    window.JDBridge._pending[callbackId] = { resolve, reject };
    window.XWebView._callNative(JSON.stringify({ plugin, action, params, callbackId }));
  });
}
```

> 实际项目请用现有 JDBridge JS SDK,它已实现 `_handleResponseFromNative` / `_handleRequestFromNative` / `complete` 流式分发。以下"预期返回"均指 `data` 字段。

## 一、可在模拟器自测(无需真机)

| # | 调用 | 预期返回 data | 说明 |
|---|---|---|---|
| 1 | `callNative('QXBasePlugin','getDeviceInfo')` | `{platform:'harmony', brand, model, system:'HarmonyOS', osVersion, ...}` | 字段与安卓对齐,多一个 `platform:'harmony'` |
| 2 | `callNative('SystemInfoHandler','getSystemInfo')` | 同上 | 与 getDeviceInfo 等价 |
| 3 | `callNative('QXBasePlugin','setStorage',{key:'k',data:'v'})` | `null`,status `0` | |
| 4 | `callNative('QXBasePlugin','getStorage',{key:'k'})` | `{data:'v'}` | 需先 setStorage |
| 5 | `callNative('QXBasePlugin','removeStorage',{key:'k'})` | `null` | |
| 6 | `callNative('QXBasePlugin','clearStorage')` | `null` | |
| 7 | `callNative('QXBasePlugin','location')` | `{latitude, longitude, wgsLatitude, wgsLongitude, accuracy}` | 首次弹权限;`latitude/longitude` 为 GCJ-02 |
| 8 | `callNative('QXBasePlugin','openUrl',{url:'https://www.huawei.com'})` | `null` | 唤起浏览器 |
| 9 | `callNative('QXBasePlugin','notifyFirstRender')` | `null` | 首屏渲染通知 |
| 10 | `callNative('QXLifecyclePlugin','subscribe')` | `{subscribed:true}` | 之后切前后台会收到事件(见下) |
| 11 | `callNative('QXLifecyclePlugin','getPageLifecycleState')` | `{state:'onShow'}` | |

**生命周期事件**(订阅后,App 切前后台触发):
```js
window.addEventListener('onPageLifecycle', (e) => {
  console.log(e.detail.state); // 'onShow' | 'onHide' | 'onCreate' | 'onDestroy'
});
```

**宿主 UI 类**(`goBack`/`closeWebView`/`openWebView`/`setNavigationBarStyle`/`closeWithResult`):返回 `null` 且由集成方的 `QXHostDelegate` 处理,自测时确认不报错、原生侧收到回调即可。

## 二、需真机自测(相机 / 相册 / 网络)

| # | 调用 | 预期返回 data |
|---|---|---|
| 12 | `callNative('QXBasePlugin','scanQRCode')` | `{result:'<二维码内容>', scanType}` |
| 13 | `callNative('QXBasePlugin','chooseImage',{count:1})` | `{paths:['file://...'], tempFilePaths:[...]}` |
| 14 | `callNative('QXBasePlugin','downloadAndOpenFile',{url:'https://.../a.pdf'})` | `{path:'.../a.pdf'}` |
| 15 | `callNative('QXBasePlugin','openMap',{latitude:31.2,longitude:121.4,name:'目的地',app:'amap'})` | `{uri}`;`app` 可省(自动择优) |

## 三、蓝牙(必须纯血真机 + 充电桩)

标准流程(与微信小程序 BLE API 同名):
```js
await callNative('QXBlePlugin','checkBluetoothPermission');   // {granted}
await callNative('QXBlePlugin','requestBluetoothPermission'); // {granted}
await callNative('QXBlePlugin','openBluetoothAdapter');       // {available, discovering}
await callNative('QXBlePlugin','startBluetoothDevicesDiscovery');
// 轮询或等待,然后:
await callNative('QXBlePlugin','getBluetoothDevices');        // {devices:[{deviceId,name,rssi}]}
await callNative('QXBlePlugin','createBLEConnection',{deviceId});
await callNative('QXBlePlugin','getBLEDeviceServices',{deviceId});           // {services:[{uuid}]}
await callNative('QXBlePlugin','getBLEDeviceCharacteristics',{deviceId,serviceId}); // {characteristics:[{uuid}]}
await callNative('QXBlePlugin','notifyBLECharacteristicValueChange',{deviceId,serviceId,characteristicId,state:true,format:'BUFFER'});
await callNative('QXBlePlugin','writeBLECharacteristicValue',{deviceId,serviceId,characteristicId,value:'a1b2c3',format:'BUFFER'});
```

**连接状态事件**:
```js
window.addEventListener('onBLEConnectionStateChange', (e) => {
  console.log(e.detail); // {deviceId, connected, state}
});
```

**notify 数据**:`notifyBLECharacteristicValueChange` 是**流式**——首帧 `complete:true` 表示订阅成功,之后每次桩上报为 `complete:false` 的数据帧,`data = {serviceId, characteristicId, value}`。value 编码由 `format` 决定(`BUFFER` 十六进制 / `BASE64` / `TEXT`)。

## 错误码对照

| status | 处理建议 |
|---|---|
| `0` | 成功 |
| `-1` | 业务失败,读 `msg` |
| `1` | 原生异常,读 `msg` |
| `-2` | 插件/action 未实现——大概率是三端 action 名不一致,核对 [`BRIDGE_PROTOCOL.md`](./BRIDGE_PROTOCOL.md) |
