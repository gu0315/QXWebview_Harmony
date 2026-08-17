/*
 * QXBlePlugin —— 蓝牙 BLE。逐个 action 对齐 Android com/jd/plugins/QXBlePlugin.kt(微信小程序风格 API)。
 *
 * action 全量(15 个,与 Android 完全一致):
 *   openBluetoothAdapter / closeBluetoothAdapter / getBluetoothAdapterState /
 *   startBluetoothDevicesDiscovery / stopBluetoothDevicesDiscovery / getBluetoothDevices /
 *   createBLEConnection / closeBLEConnection /
 *   getBLEDeviceServices / getBLEDeviceCharacteristics /
 *   writeBLECharacteristicValue / notifyBLECharacteristicValueChange / requestBLEMtu /
 *   requestBluetoothPermission / checkBluetoothPermission
 *
 * 回包约定(与 Android sendSuccessCallback / sendFailCallback 一致):
 *   成功 -> onSuccess({ code:0, message:<中文提示>, data:<载荷> })
 *   失败 -> onError(JSON.stringify({ code:<QXBleErrorCode>, message, data:{} }))
 *   权限类失败 -> onError(QXBridgeError.noPermission(...)) —— 1001 信封,带权限明细
 *
 * 事件走 callJS('QXBlePlugin', {eventName, ...}),不占用 action 回调。
 *
 * 说明:BLE 依赖真机(模拟器无蓝牙硬件),最终需真机 + 充电桩联调。
 */

import { BasePlugin } from '../bridge/BridgePlugin';
import { BridgeCallback, BridgeHost } from '../bridge/BridgeTypes';
import { QXBridgeError } from '../bridge/QXBridgeError';
import { QXBLEventType, QXBleErrorCode, bleErrorMessage } from './QXBleDefine';
import { access, ble } from '@kit.ConnectivityKit';
import { abilityAccessCtrl, common, Permissions, PermissionRequestResult } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { parseValueByType, bytesToHex, BleParseError } from '../utils/BleDataParser';
import { StorageUtil } from '../utils/StorageUtil';

const BLE_DOMAIN: number = 0x00B1;
const BLE_TAG: string = 'QXBlePlugin';

/** ble.GattClientDevice 的连接态取值(与鸿蒙 ProfileConnectionState 一致)。 */
const STATE_DISCONNECTED: number = 0;
const STATE_CONNECTED: number = 2;

/** Android Options.connectTimeout = 10000ms,这里保持相同的连接等待上限。 */
const CONNECT_TIMEOUT_MS: number = 10000;

/** 鸿蒙侧 BLE 所需的运行时权限。对应 Android 的 BLUETOOTH_SCAN/BLUETOOTH_CONNECT。 */
const BLE_PERMISSIONS: Array<Permissions> = ['ohos.permission.ACCESS_BLUETOOTH'];

// ---------------- 回包载荷(ArkTS 要求对象字面量必须有显式类型) ----------------

/** BLE 统一响应信封。 */
interface BleEnvelope {
  code: number;
  message: string;
  data: Object;
  /** 仅 startBluetoothDevicesDiscovery 携带,兼容 uni 老式 errMsg 判定。 */
  errMsg?: string;
}

interface EmptyObj {
}

const EMPTY_DATA: EmptyObj = {};

/** getBluetoothDevices / onBluetoothDeviceFound 的设备结构。字段名与 Android 一致(注意 RSSI 大写)。 */
interface BleDeviceInfo {
  name: string;
  RSSI: number;
  deviceId: string;
  isSystemConnected: boolean;
  isBonded: boolean;
}

interface DevicesResult {
  devices: BleDeviceInfo[];
}

interface AdapterStateResult {
  available: boolean;
  discovering: boolean;
}

interface ScanStopResult {
  deviceCount: number;
}

interface ConnectedResult {
  deviceId: string;
  name: string;
}

interface ServiceItem {
  serviceId: string;
  isPrimary: boolean;
}

interface ServicesResult {
  services: ServiceItem[];
}

interface CharacteristicItem {
  serviceId: string;
  characteristicId: string;
  properties: string[];
  isNotifying: boolean;
}

interface CharsResult {
  characteristics: CharacteristicItem[];
}

interface WriteResult {
  characteristicId: string;
  value: string;
}

interface NotifyResult {
  deviceId: string;
  serviceId: string;
  characteristicId: string;
  enabled: boolean;
}

interface MtuResult {
  deviceId: string;
  requestedMtu: number;
  actualMtu: number;
}

/** checkBluetoothPermission 的载荷,字段与 Android 完全一致。 */
interface PermissionResult {
  /** 0 未决定 / 1 已授权 / 2 已拒绝 */
  authorization: number;
  authorizationDesc: string;
  isAuthorized: boolean;
  isDenied: boolean;
  isNotDetermined: boolean;
  isSupported: boolean;
  grantedPermissions: string[];
  deniedPermissions: string[];
}

/** noPermission 信封里带的权限明细。 */
interface PermissionDeniedData {
  deniedPermissions: string[];
  isAuthorized: boolean;
  isDenied: boolean;
  isNotDetermined: boolean;
}

// ---------------- 推送给 H5 的事件 ----------------

interface DeviceFoundEvent {
  eventName: string;
  name: string;
  RSSI: number;
  deviceId: string;
  isSystemConnected: boolean;
  isBonded: boolean;
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

/** 一次连接请求的在途状态(等待 BLEConnectionStateChange 回调)。 */
class PendingConnect {
  callback: BridgeCallback;
  timer: number;
  settled: boolean = false;

  constructor(callback: BridgeCallback, timer: number) {
    this.callback = callback;
    this.timer = timer;
  }
}

export class QXBlePlugin extends BasePlugin {
  static readonly NAME: string = 'QXBlePlugin';
  readonly name: string = QXBlePlugin.NAME;

  private context: common.UIAbilityContext;
  /** 仅用于持久化「是否已弹过蓝牙权限」,还原 Android 的 authorization 三态。 */
  private storage: StorageUtil;
  private bridge: BridgeHost | null = null;
  /** 对应 Android 的 `ble != null`:openBluetoothAdapter 之后才算已初始化。 */
  private initialized: boolean = false;
  private scanning: boolean = false;
  private found: Map<string, BleDeviceInfo> = new Map();
  private gattClients: Map<string, ble.GattClientDevice> = new Map();
  private connected: Set<string> = new Set();
  private pendingConnects: Map<string, PendingConnect> = new Map();
  /** 已订阅通知的特征,用于 getBLEDeviceCharacteristics 的 isNotifying 字段。 */
  private notifying: Set<string> = new Set();

  /** 调试日志开关。默认关(不刷屏);需要排查时改成 true,日志会同时打到 hilog 和 H5 vConsole。 */
  private static readonly DEBUG: boolean = false;

  constructor(context: common.UIAbilityContext, storage: StorageUtil) {
    super();
    this.context = context;
    this.storage = storage;
  }

  private log(msg: string): void {
    if (QXBlePlugin.DEBUG) {
      hilog.info(BLE_DOMAIN, BLE_TAG, '%{public}s', msg);
      this.bridge?.runJavaScript(`console.log(${JSON.stringify(`[QXBle] ${msg}`)})`);
    }
  }

  // ---------------- 统一信封 ----------------

  /** 成功回包。对应 Android sendSuccessCallback(callback, data, message)。 */
  private ok(callback: BridgeCallback, data: Object | undefined, message: string): void {
    const env: BleEnvelope = { code: QXBleErrorCode.SUCCESS, message: message, data: data ?? EMPTY_DATA };
    this.log(`↩ 成功回包 ${JSON.stringify(env)}`);
    callback.onSuccess(env);
  }

  /** 失败回包。对应 Android sendFailCallback(callback, errorCode, customMessage)。 */
  private fail(callback: BridgeCallback, code: QXBleErrorCode, message?: string): void {
    const env: BleEnvelope = { code: code, message: message ?? bleErrorMessage(code), data: EMPTY_DATA };
    this.log(`↩ 失败回包 ${JSON.stringify(env)}`);
    callback.onError(JSON.stringify(env));
  }

  /**
   * 权限类失败。对应 Android sendBluetoothPermissionDenied —— 走 1001 的 QXBridgeError 信封,
   * 而不是 BLE 的数字错误码,H5 侧统一按 code===1001 判「去设置里开权限」。
   */
  private failPermission(callback: BridgeCallback, message: string, isNotDetermined: boolean): void {
    const data: PermissionDeniedData = {
      deniedPermissions: BLE_PERMISSIONS.slice(),
      isAuthorized: false,
      isDenied: !isNotDetermined,
      isNotDetermined: isNotDetermined
    };
    callback.onError(QXBridgeError.noPermission(message, data));
  }

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
      case 'getBluetoothDevices':
        this.getDevices(callback);
        return true;
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

  private isGranted(): boolean {
    try {
      const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
      const tokenId: number = this.context.applicationInfo.accessTokenId;
      return BLE_PERMISSIONS.every((p: Permissions) =>
        atManager.checkAccessTokenSync(tokenId, p) === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED);
    } catch (e) {
      return false;
    }
  }

  /** 蓝牙硬件是否可用(取得到适配器状态即视为支持)。 */
  private static isSupported(): boolean {
    try {
      access.getState();
      return true;
    } catch (e) {
      return false;
    }
  }

  /**
   * 权限检查。authorization 三态与 Android 一致:
   *   1 authorized / 2 denied(弹过框但没给) / 0 notDetermined(还没弹过)
   */
  private checkPermission(callback: BridgeCallback): void {
    const granted: boolean = this.isGranted();
    const requestedBefore: boolean = this.storage.hasRequestedBlePermission();
    const authorization: number = granted ? 1 : (requestedBefore ? 2 : 0);
    const result: PermissionResult = {
      authorization: authorization,
      authorizationDesc: granted ? 'authorized' : (requestedBefore ? 'denied' : 'notDetermined'),
      isAuthorized: granted,
      isDenied: !granted && requestedBefore,
      isNotDetermined: !granted && !requestedBefore,
      isSupported: QXBlePlugin.isSupported(),
      grantedPermissions: granted ? BLE_PERMISSIONS.slice() : [],
      deniedPermissions: granted ? [] : BLE_PERMISSIONS.slice()
    };
    this.ok(callback, result, '权限检查完成');
  }

  private requestPermission(callback: BridgeCallback): void {
    if (this.isGranted()) {
      this.ok(callback, undefined, '蓝牙权限已授权');
      return;
    }
    this.askPermission((granted: boolean) => {
      if (granted) {
        this.ok(callback, undefined, '蓝牙权限已授权');
      } else {
        this.failPermission(callback, '蓝牙权限被拒绝', false);
      }
    }, callback);
  }

  /** 弹系统权限框,并记下「已弹过」,供 checkBluetoothPermission 区分 denied / notDetermined。 */
  private askPermission(done: (granted: boolean) => void, callback: BridgeCallback): void {
    const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
    this.storage.markBlePermissionRequested();
    atManager.requestPermissionsFromUser(this.context, BLE_PERMISSIONS)
      .then((data: PermissionRequestResult) => {
        const granted: boolean = data.authResults.length > 0 &&
          data.authResults.every((r: number) => r === 0);
        done(granted);
      })
      .catch((e: BusinessError) =>
        this.fail(callback, QXBleErrorCode.UNKNOWN_ERROR, `权限请求失败: ${e.message}`));
  }

  // ---------------- 适配器 ----------------

  /**
   * 初始化蓝牙。对应 Android initBle:先确认权限,再确认适配器已开启。
   * 与 Android 一致,成功回空 data,message 区分「初始化成功 / 已初始化」。
   */
  private openAdapter(callback: BridgeCallback): void {
    if (!this.isGranted()) {
      // 已经弹过框仍未授权:不再打扰用户,直接回「去设置里开」,与 Android initBle 分支一致。
      if (this.storage.hasRequestedBlePermission()) {
        this.failPermission(callback, '蓝牙权限被拒绝，请前往设置开启', false);
        return;
      }
      this.askPermission((granted: boolean) => {
        if (granted) {
          this.enableAdapter(callback);
        } else {
          this.failPermission(callback, '蓝牙权限被拒绝，请前往设置开启', false);
        }
      }, callback);
      return;
    }
    this.enableAdapter(callback);
  }

  private enableAdapter(callback: BridgeCallback): void {
    const alreadyInited: boolean = this.initialized;
    try {
      const state: access.BluetoothState = access.getState();
      this.log(`openBluetoothAdapter 当前状态=${state}(2=STATE_ON)`);
      if (state === access.BluetoothState.STATE_ON) {
        this.initialized = true;
        this.ok(callback, undefined, alreadyInited ? '蓝牙已初始化' : '蓝牙初始化成功');
        return;
      }
      // 蓝牙未开:尝试开启(部分设备不允许应用直接开启,会抛异常,需用户手动开)。
      try {
        access.enableBluetooth();
        this.log('enableBluetooth() 已调用');
      } catch (e2) {
        this.log(`enableBluetooth() 抛异常(设备可能需手动开蓝牙): ${(e2 as BusinessError).message}`);
      }
      const nowState: access.BluetoothState = access.getState();
      if (nowState === access.BluetoothState.STATE_ON) {
        this.initialized = true;
        this.ok(callback, undefined, alreadyInited ? '蓝牙已初始化' : '蓝牙初始化成功');
        return;
      }
      // enableBluetooth 是异步的,此刻多半还没 ON。与 Android 一样把「适配器不可用」如实回给 H5。
      this.fail(callback, QXBleErrorCode.UNKNOWN_ERROR, '蓝牙适配器不可用，请确认系统蓝牙已开启');
    } catch (err) {
      this.fail(callback, QXBleErrorCode.UNKNOWN_ERROR, `蓝牙初始化失败: ${(err as BusinessError).message}`);
    }
  }

  /**
   * 关闭蓝牙适配器。与 Android 一致:**不关闭系统蓝牙**,只停扫描 + 断开全部连接 + 释放资源。
   */
  private closeAdapter(callback: BridgeCallback): void {
    try {
      this.stopScanInternal();
      this.gattClients.forEach((client: ble.GattClientDevice) => {
        try {
          client.disconnect();
          client.close();
        } catch (e) {
          // ignore
        }
      });
      this.gattClients.clear();
      this.connected.clear();
      this.notifying.clear();
      this.found.clear();
      this.initialized = false;
      this.ok(callback, undefined, '蓝牙适配器已关闭');
    } catch (err) {
      this.fail(callback, QXBleErrorCode.UNKNOWN_ERROR, `关闭蓝牙适配器失败：${(err as BusinessError).message}`);
    }
  }

  private getAdapterState(callback: BridgeCallback): void {
    if (!QXBlePlugin.isSupported()) {
      this.fail(callback, QXBleErrorCode.SYSTEM_NOT_SUPPORT, '设备不支持蓝牙');
      return;
    }
    if (!this.isGranted()) {
      this.failPermission(callback, '蓝牙权限未授权，请先授权', !this.storage.hasRequestedBlePermission());
      return;
    }
    try {
      const state: access.BluetoothState = access.getState();
      if (state !== access.BluetoothState.STATE_ON) {
        this.fail(callback, QXBleErrorCode.NOT_AVAILABLE, '当前蓝牙适配器不可用');
        return;
      }
      if (!this.initialized) {
        this.fail(callback, QXBleErrorCode.NOT_INIT, '未初始化蓝牙适配器');
        return;
      }
      const r: AdapterStateResult = { available: true, discovering: this.scanning };
      this.ok(callback, r, '获取蓝牙适配器状态成功');
    } catch (err) {
      this.fail(callback, QXBleErrorCode.SYSTEM_ERROR, `获取蓝牙适配器状态失败：${(err as BusinessError).message}`);
    }
  }

  // ---------------- 扫描 ----------------

  /**
   * 开始扫描。与 Android 一致,**立即**回成功(不等扫描结束),
   * 回包同时带信封字段和 uni 老式的 errMsg,两种判定方式都能通过。
   */
  private startDiscovery(callback: BridgeCallback): void {
    if (!this.initialized) {
      this.fail(callback, QXBleErrorCode.PERIPHERAL_NIL, '蓝牙未初始化');
      return;
    }
    if (this.scanning) {
      this.log('startDiscovery: 已在扫描中,直接返回成功');
      this.okScanStarted(callback);
      return;
    }
    try {
      // 新一轮扫描:清空上一轮结果,让设备能重新被上报(配合去重)。
      this.found.clear();
      this.log(`startDiscovery: 适配器状态=${access.getState()}(2=STATE_ON)`);

      ble.on('BLEDeviceFind', (devices: Array<ble.ScanResult>) => {
        devices.forEach((d: ble.ScanResult) => {
          // 去重:同一台设备只上报一次(对齐 Android,避免 aggressive 模式重复刷屏)。
          if (this.found.has(d.deviceId)) {
            return;
          }
          const dev: BleDeviceInfo = {
            name: d.deviceName ?? '',
            RSSI: d.rssi,
            deviceId: d.deviceId,
            isSystemConnected: this.connected.has(d.deviceId),
            isBonded: false
          };
          this.found.set(d.deviceId, dev);
          this.log(`发现新设备 id=${dev.deviceId} name=${dev.name} rssi=${dev.RSSI}`);
          const ev: DeviceFoundEvent = {
            eventName: QXBLEventType.ON_BLUETOOTH_DEVICE_FOUND,
            name: dev.name,
            RSSI: dev.RSSI,
            deviceId: dev.deviceId,
            isSystemConnected: dev.isSystemConnected,
            isBonded: dev.isBonded
          };
          this.pushEvent(ev);
        });
      });
      // 低时延 + 主动匹配,尽量快地扫到充电桩。filters=null 表示不过滤,扫描全部 BLE 设备。
      const options: ble.ScanOptions = {
        interval: 0,
        dutyMode: ble.ScanDuty.SCAN_MODE_LOW_LATENCY,
        matchMode: ble.MatchMode.MATCH_MODE_AGGRESSIVE
      };
      ble.startBLEScan(null, options);
      this.log('ble.startBLEScan 已调用(等待 BLEDeviceFind 回调)');
      this.scanning = true;
      this.okScanStarted(callback);
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      this.log(`❌ startBLEScan 抛异常 code=${e.code} msg=${e.message}`);
      this.fail(callback, QXBleErrorCode.SCAN_NOT_AVAILABLE, `扫描失败: ${e.code} ${e.message}`);
    }
  }

  private okScanStarted(callback: BridgeCallback): void {
    const env: BleEnvelope = {
      code: QXBleErrorCode.SUCCESS,
      message: 'ok',
      data: EMPTY_DATA,
      // Android 的裸回包字段,H5 里仍有按 errMsg 判定的老代码,一并带上。
      errMsg: 'startBluetoothDevicesDiscovery:ok'
    };
    this.log(`↩ 成功回包 ${JSON.stringify(env)}`);
    callback.onSuccess(env);
  }

  private stopDiscovery(callback: BridgeCallback): void {
    try {
      const count: number = this.found.size;
      this.stopScanInternal();
      const r: ScanStopResult = { deviceCount: count };
      this.ok(callback, r, '已停止扫描');
    } catch (err) {
      this.fail(callback, QXBleErrorCode.SCAN_NOT_AVAILABLE, `停止扫描失败: ${(err as BusinessError).message}`);
    }
  }

  private stopScanInternal(): void {
    if (this.scanning) {
      try {
        ble.off('BLEDeviceFind');
        ble.stopBLEScan();
      } catch (e) {
        // ignore
      }
      this.scanning = false;
    }
  }

  private getDevices(callback: BridgeCallback): void {
    if (!this.initialized) {
      this.fail(callback, QXBleErrorCode.NOT_INIT, '未初始化蓝牙适配器');
      return;
    }
    const devices: BleDeviceInfo[] = Array.from(this.found.values());
    // 已连接但不在本轮扫描结果里的设备也要带上(对齐 Android 的 connectedDevices 合并)。
    this.connected.forEach((deviceId: string) => {
      if (!this.found.has(deviceId)) {
        const item: BleDeviceInfo = {
          name: '',
          RSSI: 0,
          deviceId: deviceId,
          isSystemConnected: true,
          isBonded: false
        };
        devices.push(item);
      }
    });
    const r: DevicesResult = { devices: devices };
    this.ok(callback, r, '获取已发现设备成功');
  }

  // ---------------- 连接 ----------------

  /**
   * 连接设备。与 Android onReady 语义一致:**连接真正建立后**才回成功,
   * 超时(10s)回 CONNECT_TIMEOUT(-4)。连接状态变化另经事件推送。
   */
  private createConnection(params: object | undefined, callback: BridgeCallback): void {
    const deviceId: string | undefined = this.str(params, 'deviceId');
    if (!deviceId || deviceId.trim().length === 0) {
      this.fail(callback, QXBleErrorCode.INVALID_DATA, 'deviceId 为空或格式不正确');
      return;
    }
    const name: string = this.found.get(deviceId)?.name ?? '';
    if (this.connected.has(deviceId)) {
      const already: ConnectedResult = { deviceId: deviceId, name: name.length > 0 ? name : '未知设备' };
      this.ok(callback, already, '设备已连接');
      return;
    }

    try {
      let client: ble.GattClientDevice | undefined = this.gattClients.get(deviceId);
      if (!client) {
        client = ble.createGattClientDevice(deviceId);
        this.gattClients.set(deviceId, client);
        client.on('BLEConnectionStateChange', (state: ble.BLEConnectionChangeState) => {
          this.onConnectionStateChange(state, name);
        });
      }
      // 超时兜底:到点仍未连上就按 Android 的连接超时回错,避免 H5 永久 pending。
      const timer: number = setTimeout(() => {
        const pending: PendingConnect | undefined = this.pendingConnects.get(deviceId);
        if (!pending || pending.settled) {
          return;
        }
        pending.settled = true;
        this.pendingConnects.delete(deviceId);
        this.fail(callback, QXBleErrorCode.CONNECT_TIMEOUT, '设备连接超时');
      }, CONNECT_TIMEOUT_MS);
      this.pendingConnects.set(deviceId, new PendingConnect(callback, timer));
      client.connect();
    } catch (err) {
      this.clearPending(deviceId);
      this.fail(callback, QXBleErrorCode.CONNECTION_FAIL, `连接失败: ${(err as BusinessError).message}`);
    }
  }

  /** 连接状态变化:推事件 + 结算在途的 createBLEConnection 回调。 */
  private onConnectionStateChange(state: ble.BLEConnectionChangeState, name: string): void {
    const deviceId: string = state.deviceId;
    const isConnected: boolean = state.state === STATE_CONNECTED;
    if (isConnected) {
      this.connected.add(deviceId);
    } else if (state.state === STATE_DISCONNECTED) {
      this.connected.delete(deviceId);
    }

    const ev: ConnChangeEvent = {
      eventName: QXBLEventType.ON_BLE_CONNECTION_STATE_CHANGE,
      isConnected: isConnected,
      deviceId: deviceId,
      name: name
    };
    this.pushEvent(ev);

    const pending: PendingConnect | undefined = this.pendingConnects.get(deviceId);
    if (!pending || pending.settled) {
      return;
    }
    if (isConnected) {
      pending.settled = true;
      clearTimeout(pending.timer);
      this.pendingConnects.delete(deviceId);
      const r: ConnectedResult = { deviceId: deviceId, name: name.length > 0 ? name : '未知设备' };
      this.ok(pending.callback, r, '设备连接成功');
    } else if (state.state === STATE_DISCONNECTED) {
      pending.settled = true;
      clearTimeout(pending.timer);
      this.pendingConnects.delete(deviceId);
      this.fail(pending.callback, QXBleErrorCode.CONNECT_TIMEOUT, '连接失败: 设备已断开');
    }
  }

  private clearPending(deviceId: string): void {
    const pending: PendingConnect | undefined = this.pendingConnects.get(deviceId);
    if (pending) {
      clearTimeout(pending.timer);
      this.pendingConnects.delete(deviceId);
    }
  }

  private closeConnection(params: object | undefined, callback: BridgeCallback): void {
    const deviceId: string | undefined = this.str(params, 'deviceId');
    const client: ble.GattClientDevice | undefined = deviceId ? this.gattClients.get(deviceId) : undefined;
    if (!client || !deviceId) {
      this.fail(callback, QXBleErrorCode.DEVICE_NOT_FOUND, '设备未连接');
      return;
    }
    try {
      client.disconnect();
      client.close();
      this.gattClients.delete(deviceId);
      this.connected.delete(deviceId);
      this.clearPending(deviceId);
      this.ok(callback, undefined, '已断开连接');
    } catch (err) {
      this.fail(callback, QXBleErrorCode.SYSTEM_ERROR, `断开失败: ${(err as BusinessError).message}`);
    }
  }

  // ---------------- 服务 / 特征 ----------------

  private getServices(params: object | undefined, callback: BridgeCallback): void {
    const client: ble.GattClientDevice | undefined = this.clientOf(params, callback);
    if (!client) {
      return;
    }
    client.getServices().then((services: Array<ble.GattService>) => {
      const list: ServiceItem[] = services.map((s: ble.GattService): ServiceItem => {
        // 鸿蒙未暴露 primary/secondary,BLE 场景下均为 primary,与 Android 的取值保持一致。
        const item: ServiceItem = { serviceId: s.serviceUuid, isPrimary: true };
        return item;
      });
      const r: ServicesResult = { services: list };
      this.ok(callback, r, `发现服务成功，共${list.length}个服务`);
    }).catch((e: BusinessError) => {
      this.fail(callback, QXBleErrorCode.NO_SERVICE, `获取服务失败${e.message}`);
    });
  }

  /**
   * 获取特征。与 Android 一致:**遍历全部服务**返回所有特征(不按 serviceId 过滤),
   * 每项带 serviceId / characteristicId / properties / isNotifying。
   */
  private getCharacteristics(params: object | undefined, callback: BridgeCallback): void {
    const client: ble.GattClientDevice | undefined = this.clientOf(params, callback);
    if (!client) {
      return;
    }
    const deviceId: string = this.str(params, 'deviceId') ?? '';
    client.getServices().then((services: Array<ble.GattService>) => {
      const chars: CharacteristicItem[] = [];
      services.forEach((s: ble.GattService) => {
        s.characteristics.forEach((c: ble.BLECharacteristic) => {
          const item: CharacteristicItem = {
            serviceId: s.serviceUuid,
            characteristicId: c.characteristicUuid,
            properties: QXBlePlugin.formatProperties(c.properties),
            isNotifying: this.notifying.has(QXBlePlugin.notifyKey(deviceId, s.serviceUuid, c.characteristicUuid))
          };
          chars.push(item);
        });
      });
      const r: CharsResult = { characteristics: chars };
      this.ok(callback, r, `获取特征成功，共${chars.length}个特征`);
    }).catch((e: BusinessError) => {
      this.fail(callback, QXBleErrorCode.NO_CHARACTERISTIC, `获取特征失败${e.message}`);
    });
  }

  /** 属性位 -> 字符串数组。取值与 Android QXBleUtils.formatCharacteristicProperties 一致。 */
  private static formatProperties(props: ble.GattProperties | undefined): string[] {
    const out: string[] = [];
    if (!props) {
      return out;
    }
    if (props.read) {
      out.push('read');
    }
    if (props.write) {
      out.push('write');
    }
    if (props.writeNoResponse) {
      out.push('writeWithoutResponse');
    }
    if (props.notify) {
      out.push('notify');
    }
    if (props.indicate) {
      out.push('indicate');
    }
    return out;
  }

  private static notifyKey(deviceId: string, serviceId: string, characteristicId: string): string {
    return `${deviceId}|${serviceId}|${characteristicId}`;
  }

  // ---------------- 写 / 通知 / MTU ----------------

  private writeCharacteristic(params: object | undefined, callback: BridgeCallback): void {
    const deviceId: string = (this.str(params, 'deviceId') ?? '').trim();
    const serviceUuid: string = (this.str(params, 'serviceId') ?? '').trim();
    const charUuid: string = (this.str(params, 'characteristicId') ?? '').trim();
    if (deviceId.length === 0 || serviceUuid.length === 0 || charUuid.length === 0) {
      this.fail(callback, QXBleErrorCode.UNKNOWN_ERROR,
        `deviceId/serviceId/characteristicId不能为空（deviceId=${deviceId}, serviceId=${serviceUuid}, characteristicId=${charUuid}）`);
      return;
    }
    const client: ble.GattClientDevice | undefined = this.gattClients.get(deviceId);
    if (!client || !this.connected.has(deviceId)) {
      this.fail(callback, QXBleErrorCode.NO_CONNECTION, '当前连接已断开');
      return;
    }

    // valueType 与 Android 同名同义(BASE64 / BUFFER / HEX / UTF8 / TEXT),默认 UTF8。
    const valueType: string = this.str(params, 'valueType') ?? 'UTF8';
    let bytes: Uint8Array;
    try {
      bytes = parseValueByType(this.raw(params, 'value'), valueType);
    } catch (err) {
      const e: BleParseError = err as BleParseError;
      this.fail(callback, QXBleErrorCode.UNKNOWN_ERROR, e.message ?? '参数解析失败');
      return;
    }
    if (bytes.length === 0) {
      this.fail(callback, QXBleErrorCode.UNKNOWN_ERROR, `数据解析后为空：type=${valueType}`);
      return;
    }

    const characteristic: ble.BLECharacteristic = {
      serviceUuid: serviceUuid,
      characteristicUuid: charUuid,
      characteristicValue: bytes.buffer as ArrayBuffer,
      descriptors: []
    };
    const hex: string = bytesToHex(bytes);
    client.writeCharacteristicValue(characteristic, ble.GattWriteType.WRITE)
      .then(() => {
        const r: WriteResult = { characteristicId: charUuid, value: hex };
        this.ok(callback, r, '写入特征值成功');
      })
      .catch((e: BusinessError) => {
        this.fail(callback, QXBleErrorCode.SYSTEM_ERROR, `数据发送失败: 错误码=${e.code}`);
      });
  }

  /**
   * 开启/关闭特征值通知。参数名与 Android 一致:enable(布尔),兼容旧的 state 字段。
   */
  private notifyCharacteristic(params: object | undefined, callback: BridgeCallback): void {
    const deviceId: string = (this.str(params, 'deviceId') ?? '').trim();
    const serviceUuid: string = (this.str(params, 'serviceId') ?? '').trim();
    const charUuid: string = (this.str(params, 'characteristicId') ?? '').trim();
    const enable: boolean = this.coerceBool(params, 'enable') ?? this.coerceBool(params, 'state') ?? true;

    if (serviceUuid.length === 0 || charUuid.length === 0) {
      this.fail(callback, QXBleErrorCode.NO_CHARACTERISTIC, 'notifyBLECharacteristicValueChange 参数不完整');
      return;
    }
    const client: ble.GattClientDevice | undefined = this.gattClients.get(deviceId);
    if (!client || !this.connected.has(deviceId)) {
      this.fail(callback, QXBleErrorCode.DEVICE_NOT_FOUND, '设备未连接');
      return;
    }

    // 桩上报特征值 -> onBLECharacteristicValueChange 事件。value 一律用大写 HEX(对齐 Android)。
    client.on('BLECharacteristicChange', (c: ble.BLECharacteristic) => {
      const ev: CharValueEvent = {
        eventName: QXBLEventType.ON_BLE_CHARACTERISTIC_VALUE_CHANGE,
        deviceId: deviceId,
        value: bytesToHex(new Uint8Array(c.characteristicValue)),
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
    const key: string = QXBlePlugin.notifyKey(deviceId, serviceUuid, charUuid);
    client.setCharacteristicChangeNotification(characteristic, enable)
      .then(() => {
        if (enable) {
          this.notifying.add(key);
        } else {
          this.notifying.delete(key);
        }
        const r: NotifyResult = {
          deviceId: deviceId,
          serviceId: serviceUuid,
          characteristicId: charUuid,
          enabled: enable
        };
        this.ok(callback, r, enable ? '通知已启用' : '通知已关闭');
      })
      .catch((e: BusinessError) => {
        this.fail(callback, QXBleErrorCode.SYSTEM_ERROR, `CC'D描述符写入失败: ${e.message}`);
      });
  }

  private requestMtu(params: object | undefined, callback: BridgeCallback): void {
    const deviceId: string = (this.str(params, 'deviceId') ?? '').trim();
    // Android 默认 255,保持一致。
    const requestedMtu: number = this.numLoose(params, 'mtu') ?? 255;
    const client: ble.GattClientDevice | undefined = this.clientOf(params, callback);
    if (!client) {
      return;
    }
    try {
      client.setBLEMtuSize(requestedMtu);
      // 鸿蒙的 setBLEMtuSize 无协商结果回调,actualMtu 以请求值上报。
      const r: MtuResult = { deviceId: deviceId, requestedMtu: requestedMtu, actualMtu: requestedMtu };
      this.ok(callback, r, `MTU协商成功，实际大小: ${requestedMtu}字节`);
    } catch (err) {
      this.fail(callback, QXBleErrorCode.UNKNOWN_ERROR, `MTU请求异常: ${(err as BusinessError).message}`);
    }
  }

  private clientOf(params: object | undefined, callback: BridgeCallback): ble.GattClientDevice | undefined {
    const deviceId: string | undefined = this.str(params, 'deviceId');
    if (!deviceId || deviceId.trim().length === 0) {
      this.fail(callback, QXBleErrorCode.DEVICE_NOT_FOUND, '设备ID（MAC地址）不能为空');
      return undefined;
    }
    const client: ble.GattClientDevice | undefined = this.gattClients.get(deviceId);
    if (!client) {
      this.fail(callback, QXBleErrorCode.PERIPHERAL_NIL, `未找到设备：${deviceId}`);
    }
    return client;
  }

  onDestroy(): void {
    this.stopScanInternal();
    this.pendingConnects.forEach((p: PendingConnect) => clearTimeout(p.timer));
    this.pendingConnects.clear();
    this.gattClients.forEach((c: ble.GattClientDevice) => {
      try {
        c.disconnect();
        c.close();
      } catch (e) {
        // ignore
      }
    });
    this.gattClients.clear();
    this.connected.clear();
    this.notifying.clear();
    this.found.clear();
  }
}
