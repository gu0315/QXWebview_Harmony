/*
 * QXBlePlugin —— 蓝牙 BLE。对应 Android QXBlePlugin(微信小程序风格 API)。
 *
 * action 全量(15 个,与 Android 对齐):
 *   openBluetoothAdapter / closeBluetoothAdapter / getBluetoothAdapterState /
 *   startBluetoothDevicesDiscovery / stopBluetoothDevicesDiscovery / getBluetoothDevices /
 *   createBLEConnection / closeBLEConnection /
 *   getBLEDeviceServices / getBLEDeviceCharacteristics /
 *   writeBLECharacteristicValue / notifyBLECharacteristicValueChange / requestBLEMtu /
 *   requestBluetoothPermission / checkBluetoothPermission
 *
 * 说明:BLE 依赖真机(模拟器无蓝牙硬件)。此处用 @kit.ConnectivityKit 完成真实接线,
 * 扫描 / 适配器状态 / 权限已实现;GATT 连接、读写、notify 已按官方 API 接好,
 * 需在纯血鸿蒙真机 + 充电桩联调时校准(见各方法 TODO)。
 */

import { BasePlugin } from '../bridge/BridgePlugin';
import { BridgeCallback, BridgeHost } from '../bridge/BridgeTypes';
import { access, ble } from '@kit.ConnectivityKit';
import { abilityAccessCtrl, common, Permissions, PermissionRequestResult } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { decodeToBytes, encodeFromBytes, BleFormat } from '../utils/BleDataParser';

const BLE_DOMAIN: number = 0x00B1;
const BLE_TAG: string = 'QXBlePlugin';

interface FoundDevice {
  deviceId: string;
  name: string;
  rssi: number;
}

// ---- 回给 H5 的载荷结构(满足 ArkTS: 对象字面量须有显式类型) ----
interface GrantedResult {
  granted: boolean;
}

interface AdapterStateResult {
  available: boolean;
  discovering: boolean;
}

interface DevicesResult {
  devices: FoundDevice[];
}

interface DeviceIdResult {
  deviceId: string;
}

interface UuidItem {
  uuid: string;
}

interface ServicesResult {
  services: UuidItem[];
}

interface CharsResult {
  characteristics: UuidItem[];
}

interface MtuResult {
  mtu: number;
}

interface SubscribedResult {
  subscribed: boolean;
}

/** BLE 统一响应信封,与 Android sendSuccessCallback/sendFailCallback 对齐:{code, message, data}。 */
interface BleEnvelope {
  code: number;
  message: string;
  data: Object;
}

interface EmptyObj {
}

const EMPTY_DATA: EmptyObj = {};

// ---- 原生推送给 H5 的事件(经 callJS('QXBlePlugin', {...}) 下发),字段与 Android 完全一致 ----
interface DeviceFoundEvent {
  eventName: string;
  name: string;
  RSSI: number;
  deviceId: string;
}

interface ConnChangeEvent {
  eventName: string;
  isConnected: boolean;
  deviceId: string;
  name: string;
}

interface CharValueEvent {
  eventName: string;
  deviceId: string;
  value: string;
  characteristicId: string;
}

export class QXBlePlugin extends BasePlugin {
  static readonly NAME: string = 'QXBlePlugin';
  readonly name: string = QXBlePlugin.NAME;

  private context: common.UIAbilityContext;
  private bridge: BridgeHost | null = null;
  private scanning: boolean = false;
  private found: Map<string, FoundDevice> = new Map();
  private gattClients: Map<string, ble.GattClientDevice> = new Map();

  /** 调试日志开关。默认关(不刷屏);需要排查时改成 true,日志会同时打到 hilog 和 H5 vConsole。 */
  private static readonly DEBUG: boolean = false;

  constructor(context: common.UIAbilityContext) {
    super();
    this.context = context;
  }

  /**
   * 调试日志。DEBUG=true 时同时打到原生 hilog 和 H5 的 console(vConsole 按 "[QXBle]" 过滤)。
   * DEBUG=false 时为空操作,不产生任何输出。
   */
  private log(msg: string): void {
    if (QXBlePlugin.DEBUG) {
      hilog.info(BLE_DOMAIN, BLE_TAG, '%{public}s', msg);
      this.bridge?.runJavaScript(`console.log(${JSON.stringify('[QXBle] ' + msg)})`);
    }
  }

  // ---- 统一信封回调(对齐 Android)。成功:{code:0,message:'ok',data};失败:onError(JSON 信封) ----
  private ok(callback: BridgeCallback, data?: Object): void {
    const env: BleEnvelope = { code: 0, message: 'ok', data: data ?? EMPTY_DATA };
    this.log(`↩ 成功回包 ${JSON.stringify(env)}`);
    callback.onSuccess(env);
  }

  private fail(callback: BridgeCallback, code: number, message: string): void {
    const env: BleEnvelope = { code: code, message: message, data: EMPTY_DATA };
    this.log(`↩ 失败回包 ${JSON.stringify(env)}`);
    callback.onError(JSON.stringify(env));
  }

  // ---- 事件推送:经 callJS('QXBlePlugin', {eventName, ...}) 下发,H5 侧 registerPlugin 接收 ----
  private pushEvent(payload: Object): void {
    this.log(`⇢ 事件 ${JSON.stringify(payload)}`);
    this.bridge?.callJS(QXBlePlugin.NAME, payload);
  }

  execute(host: BridgeHost, action: string | undefined,
    params: object | undefined, callback: BridgeCallback): boolean {
    this.bridge = host;
    this.log(`▶ execute action=${action} params=${JSON.stringify(params)}`);
    switch (action) {
      case 'checkBluetoothPermission':
        this.checkPermission(callback);
        return true;
      case 'requestBluetoothPermission':
        this.requestPermission(callback);
        return true;
      case 'openBluetoothAdapter':
        this.openAdapter(callback);
        return true;
      case 'closeBluetoothAdapter':
        this.closeAdapter(callback);
        return true;
      case 'getBluetoothAdapterState':
        this.getAdapterState(callback);
        return true;
      case 'startBluetoothDevicesDiscovery':
        this.startDiscovery(callback);
        return true;
      case 'stopBluetoothDevicesDiscovery':
        this.stopDiscovery(callback);
        return true;
      case 'getBluetoothDevices': {
        const r: DevicesResult = { devices: Array.from(this.found.values()) };
        this.ok(callback, r);
        return true;
      }
      case 'createBLEConnection':
        this.createConnection(params, callback);
        return true;
      case 'closeBLEConnection':
        this.closeConnection(params, callback);
        return true;
      case 'getBLEDeviceServices':
        this.getServices(params, callback);
        return true;
      case 'getBLEDeviceCharacteristics':
        this.getCharacteristics(params, callback);
        return true;
      case 'writeBLECharacteristicValue':
        this.writeCharacteristic(params, callback);
        return true;
      case 'notifyBLECharacteristicValueChange':
        this.notifyCharacteristic(params, callback);
        return true;
      case 'requestBLEMtu':
        this.requestMtu(params, callback);
        return true;
      default:
        return false;
    }
  }

  // ---------------- 权限 ----------------
  private checkPermission(callback: BridgeCallback): void {
    const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
    const perm: Permissions = 'ohos.permission.ACCESS_BLUETOOTH';
    try {
      const tokenId: number = this.context.applicationInfo.accessTokenId;
      const status: abilityAccessCtrl.GrantStatus = atManager.checkAccessTokenSync(tokenId, perm);
      const r: GrantedResult = { granted: status === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED };
      this.ok(callback, r);
    } catch (err) {
      this.fail(callback, 10001, `权限检查失败: ${(err as BusinessError).message}`);
    }
  }

  private requestPermission(callback: BridgeCallback): void {
    const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
    const perms: Array<Permissions> = ['ohos.permission.ACCESS_BLUETOOTH'];
    atManager.requestPermissionsFromUser(this.context, perms)
      .then((data: PermissionRequestResult) => {
        const results: Array<number> = data.authResults;
        const r: GrantedResult = { granted: results.length > 0 && results[0] === 0 };
        this.ok(callback, r);
      })
      .catch((e: BusinessError) => this.fail(callback, 10001, `权限申请失败: ${e.message}`));
  }

  // ---------------- 适配器 ----------------
  private openAdapter(callback: BridgeCallback): void {
    try {
      const state: access.BluetoothState = access.getState();
      this.log(`openBluetoothAdapter 当前状态=${state}(2=STATE_ON)`);
      if (state === access.BluetoothState.STATE_ON) {
        const r: AdapterStateResult = { available: true, discovering: this.scanning };
        this.ok(callback, r);
        return;
      }
      // 蓝牙未开:尝试开启(部分设备不允许应用直接开启,会抛异常)。
      try {
        access.enableBluetooth();
        this.log('enableBluetooth() 已调用');
      } catch (e2) {
        this.log(`enableBluetooth() 抛异常(设备可能需手动开蓝牙): ${(e2 as BusinessError).message}`);
      }
      // 重新读一次状态(enableBluetooth 是异步的,此刻多半还没 ON)。
      const nowState: access.BluetoothState = access.getState();
      const r: AdapterStateResult = { available: nowState === access.BluetoothState.STATE_ON, discovering: false };
      this.ok(callback, r);
    } catch (err) {
      this.fail(callback, 10001, `打开蓝牙失败: ${(err as BusinessError).message}`);
    }
  }

  private closeAdapter(callback: BridgeCallback): void {
    try {
      this.stopScanInternal();
      access.disableBluetooth();
      this.ok(callback);
    } catch (err) {
      this.fail(callback, 10001, `关闭蓝牙失败: ${(err as BusinessError).message}`);
    }
  }

  private getAdapterState(callback: BridgeCallback): void {
    try {
      const state: access.BluetoothState = access.getState();
      const r: AdapterStateResult = {
        available: state === access.BluetoothState.STATE_ON,
        discovering: this.scanning
      };
      this.ok(callback, r);
    } catch (err) {
      this.fail(callback, 10001, `获取蓝牙状态失败: ${(err as BusinessError).message}`);
    }
  }

  // ---------------- 扫描 ----------------
  private startDiscovery(callback: BridgeCallback): void {
    if (this.scanning) {
      this.log('startDiscovery: 已在扫描中,直接返回成功');
      this.ok(callback);
      return;
    }
    try {
      // 新一轮扫描:清空上一轮结果,让设备能重新被上报(配合去重)。
      this.found.clear();
      const adapterState: access.BluetoothState = access.getState();
      this.log(`startDiscovery: 适配器状态=${adapterState}(2=STATE_ON)`);

      ble.on('BLEDeviceFind', (devices: Array<ble.ScanResult>) => {
        devices.forEach((d: ble.ScanResult) => {
          // 去重:同一台设备只上报一次(对齐 Android,避免 aggressive 模式重复刷屏)。
          if (this.found.has(d.deviceId)) {
            return;
          }
          const dev: FoundDevice = {
            deviceId: d.deviceId,
            name: d.deviceName ?? '',
            rssi: d.rssi
          };
          this.found.set(d.deviceId, dev);
          this.log(`发现新设备 id=${dev.deviceId} name=${dev.name} rssi=${dev.rssi}`);
          // 推送 onBluetoothDeviceFound 事件(字段对齐 Android)。
          const ev: DeviceFoundEvent = {
            eventName: 'onBluetoothDeviceFound',
            name: dev.name,
            RSSI: dev.rssi,
            deviceId: dev.deviceId
          };
          this.pushEvent(ev);
        });
      });
      // 用低时延 + 主动匹配,尽量快地扫到充电桩。filters=null 表示不过滤,扫描全部 BLE 设备。
      const options: ble.ScanOptions = {
        interval: 0,
        dutyMode: ble.ScanDuty.SCAN_MODE_LOW_LATENCY,
        matchMode: ble.MatchMode.MATCH_MODE_AGGRESSIVE
      };
      ble.startBLEScan(null, options);
      this.log('ble.startBLEScan 已调用(等待 BLEDeviceFind 回调)');
      this.scanning = true;
      this.ok(callback);
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      this.log(`❌ startBLEScan 抛异常 code=${e.code} msg=${e.message}`);
      this.fail(callback, 10001, `启动扫描失败: code=${e.code} ${e.message}`);
    }
  }

  private stopDiscovery(callback: BridgeCallback): void {
    try {
      this.stopScanInternal();
      this.ok(callback);
    } catch (err) {
      this.fail(callback, 10001, `停止扫描失败: ${(err as BusinessError).message}`);
    }
  }

  private stopScanInternal(): void {
    if (this.scanning) {
      ble.off('BLEDeviceFind');
      ble.stopBLEScan();
      this.scanning = false;
    }
  }

  // ---------------- 连接 ----------------
  private createConnection(params: object | undefined, callback: BridgeCallback): void {
    const deviceId: string | undefined = this.str(params, 'deviceId');
    if (!deviceId) {
      this.fail(callback, 10002, 'createBLEConnection 缺少 deviceId');
      return;
    }
    const name: string = this.found.get(deviceId)?.name ?? '';
    try {
      const client: ble.GattClientDevice = ble.createGattClientDevice(deviceId);
      client.on('BLEConnectionStateChange', (state: ble.BLEConnectionChangeState) => {
        // 连接状态变化 -> onBLEConnectionStateChange 事件(字段对齐 Android)。
        // state.state: 0 断开 / 1 连接中 / 2 已连接 / 3 断开中(以真机枚举为准)。
        const ev: ConnChangeEvent = {
          eventName: 'onBLEConnectionStateChange',
          isConnected: state.state === 2,
          deviceId: state.deviceId,
          name: name
        };
        this.pushEvent(ev);
      });
      client.connect();
      this.gattClients.set(deviceId, client);
      const r: DeviceIdResult = { deviceId: deviceId };
      this.ok(callback, r);
    } catch (err) {
      this.fail(callback, 10003, `连接失败: ${(err as BusinessError).message}`);
    }
  }

  private closeConnection(params: object | undefined, callback: BridgeCallback): void {
    const deviceId: string | undefined = this.str(params, 'deviceId');
    const client: ble.GattClientDevice | undefined = deviceId ? this.gattClients.get(deviceId) : undefined;
    if (!client || !deviceId) {
      this.fail(callback, 10006, 'closeBLEConnection: 设备未连接');
      return;
    }
    try {
      client.disconnect();
      client.close();
      this.gattClients.delete(deviceId);
      this.ok(callback);
    } catch (err) {
      this.fail(callback, 10006, `断开失败: ${(err as BusinessError).message}`);
    }
  }

  // ---------------- 服务 / 特征 ----------------
  private getServices(params: object | undefined, callback: BridgeCallback): void {
    const client: ble.GattClientDevice | undefined = this.clientOf(params, callback);
    if (!client) {
      return;
    }
    client.getServices().then((services: Array<ble.GattService>) => {
      const list: UuidItem[] = services.map((s: ble.GattService): UuidItem => {
        const item: UuidItem = { uuid: s.serviceUuid };
        return item;
      });
      const r: ServicesResult = { services: list };
      this.ok(callback, r);
    }).catch((e: BusinessError) => this.fail(callback, 10004, `获取服务失败: ${e.message}`));
  }

  private getCharacteristics(params: object | undefined, callback: BridgeCallback): void {
    const serviceUuid: string | undefined = this.str(params, 'serviceId');
    const client: ble.GattClientDevice | undefined = this.clientOf(params, callback);
    if (!client) {
      return;
    }
    if (!serviceUuid) {
      this.fail(callback, 10004, 'getBLEDeviceCharacteristics 缺少 serviceId');
      return;
    }
    client.getServices().then((services: Array<ble.GattService>) => {
      const target: ble.GattService | undefined =
        services.find((s: ble.GattService) => s.serviceUuid === serviceUuid);
      if (!target) {
        this.fail(callback, 10004, '未找到对应服务');
        return;
      }
      const chars: UuidItem[] = target.characteristics.map((c: ble.BLECharacteristic): UuidItem => {
        const item: UuidItem = { uuid: c.characteristicUuid };
        return item;
      });
      const r: CharsResult = { characteristics: chars };
      this.ok(callback, r);
    }).catch((e: BusinessError) => this.fail(callback, 10005, `获取特征失败: ${e.message}`));
  }

  // ---------------- 写 / 通知 / MTU ----------------
  private writeCharacteristic(params: object | undefined, callback: BridgeCallback): void {
    const serviceUuid: string | undefined = this.str(params, 'serviceId');
    const charUuid: string | undefined = this.str(params, 'characteristicId');
    const value: string | undefined = this.str(params, 'value');
    const format: BleFormat = (this.str(params, 'format') as BleFormat) ?? 'BUFFER';
    const client: ble.GattClientDevice | undefined = this.clientOf(params, callback);
    if (!client) {
      return;
    }
    if (!serviceUuid || !charUuid || value === undefined) {
      this.fail(callback, 10005, 'writeBLECharacteristicValue 参数不完整');
      return;
    }
    const bytes: Uint8Array = decodeToBytes(value, format);
    const characteristic: ble.BLECharacteristic = {
      serviceUuid: serviceUuid,
      characteristicUuid: charUuid,
      characteristicValue: bytes.buffer,
      descriptors: []
    };
    // TODO(真机): 按桩是否支持 write-without-response 选择 writeType。
    client.writeCharacteristicValue(characteristic, ble.GattWriteType.WRITE)
      .then(() => this.ok(callback))
      .catch((e: BusinessError) => this.fail(callback, 10007, `写入失败: ${e.message}`));
  }

  private notifyCharacteristic(params: object | undefined, callback: BridgeCallback): void {
    const serviceUuid: string | undefined = this.str(params, 'serviceId');
    const charUuid: string | undefined = this.str(params, 'characteristicId');
    const enable: boolean = this.bool(params, 'state') ?? true;
    const format: BleFormat = (this.str(params, 'format') as BleFormat) ?? 'BUFFER';
    const deviceId: string = this.str(params, 'deviceId') ?? '';
    const client: ble.GattClientDevice | undefined = this.clientOf(params, callback);
    if (!client) {
      return;
    }
    if (!serviceUuid || !charUuid) {
      this.fail(callback, 10005, 'notifyBLECharacteristicValueChange 参数不完整');
      return;
    }
    // 桩上报特征值 -> onBLECharacteristicValueChange 事件(字段对齐 Android:deviceId/value/characteristicId)。
    client.on('BLECharacteristicChange', (c: ble.BLECharacteristic) => {
      const hex: string = encodeFromBytes(new Uint8Array(c.characteristicValue), format);
      const ev: CharValueEvent = {
        eventName: 'onBLECharacteristicValueChange',
        deviceId: deviceId,
        value: hex,
        characteristicId: c.characteristicUuid
      };
      this.pushEvent(ev);
    });
    const characteristic: ble.BLECharacteristic = {
      serviceUuid: serviceUuid,
      characteristicUuid: charUuid,
      characteristicValue: new ArrayBuffer(0),
      descriptors: []
    };
    client.setCharacteristicChangeNotification(characteristic, enable)
      .then(() => {
        const r: SubscribedResult = { subscribed: enable };
        this.ok(callback, r);
      })
      .catch((e: BusinessError) => this.fail(callback, 10008, `订阅失败: ${e.message}`));
  }

  private requestMtu(params: object | undefined, callback: BridgeCallback): void {
    const mtu: number = this.num(params, 'mtu') ?? 247;
    const client: ble.GattClientDevice | undefined = this.clientOf(params, callback);
    if (!client) {
      return;
    }
    try {
      client.setBLEMtuSize(mtu);
      const r: MtuResult = { mtu: mtu };
      this.ok(callback, r);
    } catch (err) {
      this.fail(callback, 10001, `设置 MTU 失败: ${(err as BusinessError).message}`);
    }
  }

  private clientOf(params: object | undefined, callback: BridgeCallback): ble.GattClientDevice | undefined {
    const deviceId: string | undefined = this.str(params, 'deviceId');
    const client: ble.GattClientDevice | undefined = deviceId ? this.gattClients.get(deviceId) : undefined;
    if (!client) {
      this.fail(callback, 10006, '设备未连接,请先 createBLEConnection');
    }
    return client;
  }

  onDestroy(): void {
    this.stopScanInternal();
    this.gattClients.forEach((c: ble.GattClientDevice) => {
      try {
        c.disconnect();
        c.close();
      } catch (e) {
        // ignore
      }
    });
    this.gattClients.clear();
  }
}
