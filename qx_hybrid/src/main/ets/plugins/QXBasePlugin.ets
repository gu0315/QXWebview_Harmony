/*
 * QXBasePlugin —— 基础能力插件。对应 Android QXBasePlugin。
 *
 * action 全量(与 Android 对齐):
 *   已实现(模拟器可跑):
 *     getDeviceInfo / location / setStorage / getStorage / removeStorage / clearStorage /
 *     setWebCacheToken / notifyFirstRender / goBack / closeWebView / closeWithResult /
 *     openWebView / setNavigationBarStyle / openUrl / openSetting(ble|wlan|general|privacy)
 *   待真机/Kit 补全(已接线,含 TODO):
 *     scanQRCode / chooseImage / downloadAndOpenFile / openMap
 */

import { BasePlugin } from '../bridge/BridgePlugin';
import { BridgeCallback, BridgeHost } from '../bridge/BridgeTypes';
import { QXHostDelegate, OpenWebViewOptions, NavigationBarStyle } from '../bridge/HostDelegate';
import { StorageUtil } from '../utils/StorageUtil';
import { collectDeviceInfo } from './SystemInfoPlugin';
import { wgs84ToGcj02, LatLng } from '../utils/GCJ02Converter';
import { common, Want } from '@kit.AbilityKit';
import { geoLocationManager } from '@kit.LocationKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ScanHelper } from '../utils/ScanHelper';
import { MediaHelper } from '../utils/MediaHelper';
import { MapHelper, MapApp, MapTarget } from '../utils/MapHelper';

interface DataResult {
  data: string;
}

interface StorageKV {
  key: string;
  data: string;
}

interface LocationResult {
  latitude: number;
  longitude: number;
  wgsLatitude: number;
  wgsLongitude: number;
  accuracy: number;
}

/** closeWithResult 无结果时的占位空对象。 */
interface EmptyResult {
}

const EMPTY_RESULT: EmptyResult = {};

export class QXBasePlugin extends BasePlugin {
  static readonly NAME: string = 'QXBasePlugin';
  readonly name: string = QXBasePlugin.NAME;

  private context: common.UIAbilityContext;
  private storage: StorageUtil;
  private delegate: QXHostDelegate | null;
  /** 由容器注入的扫码/选图回调(需真机能力,交给容器实现)。 */
  private onScanRequest: ((cb: BridgeCallback) => void) | null = null;
  private onChooseImageRequest: ((params: object | undefined, cb: BridgeCallback) => void) | null = null;

  constructor(context: common.UIAbilityContext, storage: StorageUtil, delegate: QXHostDelegate | null) {
    super();
    this.context = context;
    this.storage = storage;
    this.delegate = delegate;
  }

  setScanHandler(handler: (cb: BridgeCallback) => void): void {
    this.onScanRequest = handler;
  }

  setChooseImageHandler(handler: (params: object | undefined, cb: BridgeCallback) => void): void {
    this.onChooseImageRequest = handler;
  }

  execute(host: BridgeHost, action: string | undefined,
    params: object | undefined, callback: BridgeCallback): boolean {
    switch (action) {
      case 'getDeviceInfo':
        callback.onSuccess(collectDeviceInfo());
        return true;

      case 'location':
        this.handleLocation(callback);
        return true;

      case 'setStorage':
        this.handleSetStorage(params, callback);
        return true;
      case 'getStorage':
        this.handleGetStorage(params, callback);
        return true;
      case 'removeStorage':
        this.handleRemoveStorage(params, callback);
        return true;
      case 'clearStorage':
        this.storage.clear().then(() => callback.onSuccess())
          .catch((e: BusinessError) => callback.onError(e.message));
        return true;
      case 'setWebCacheToken':
        this.handleSetStorage(this.wrapToken(params), callback);
        return true;

      case 'notifyFirstRender':
        callback.onSuccess();
        return true;

      case 'goBack':
        this.delegate?.onGoBack();
        callback.onSuccess();
        return true;
      case 'closeWebView':
        this.delegate?.onCloseWebView();
        callback.onSuccess();
        return true;
      case 'closeWithResult':
        this.delegate?.onCloseWithResult(params ?? EMPTY_RESULT);
        callback.onSuccess();
        return true;
      case 'openWebView':
        this.delegate?.onOpenWebView(this.toOpenOptions(params));
        callback.onSuccess();
        return true;
      case 'setNavigationBarStyle':
        this.delegate?.onSetNavigationBarStyle(this.toNavStyle(params));
        callback.onSuccess();
        return true;

      case 'openUrl':
        this.handleOpenUrl(params, callback);
        return true;
      case 'openSetting':
        this.handleOpenSetting(params, callback);
        return true;

      // ↓↓↓ 需真机 / 华为 Kit 能力(相机/相册/网络),已实现,以真机为准 ↓↓↓
      case 'scanQRCode':
        // 允许集成方覆盖;默认走 Scan Kit。
        if (this.onScanRequest) {
          this.onScanRequest(callback);
        } else {
          ScanHelper.scan(this.context, callback);
        }
        return true;
      case 'chooseImage':
        if (this.onChooseImageRequest) {
          this.onChooseImageRequest(params, callback);
        } else {
          MediaHelper.chooseImage(this.num(params, 'count') ?? 1, callback);
        }
        return true;
      case 'downloadAndOpenFile':
        this.handleDownloadAndOpenFile(params, callback);
        return true;
      case 'openMap':
        this.handleOpenMap(params, callback);
        return true;

      default:
        return false;
    }
  }

  // ---------------- 定位 ----------------
  private handleLocation(callback: BridgeCallback): void {
    try {
      const request: geoLocationManager.SingleLocationRequest = {
        locatingPriority: geoLocationManager.LocatingPriority.PRIORITY_ACCURACY,
        locatingTimeoutMs: 10000
      };
      geoLocationManager.getCurrentLocation(request).then((loc: geoLocationManager.Location) => {
        // 系统返回 WGS-84,转成 H5 地图使用的 GCJ-02。
        const gcj: LatLng = wgs84ToGcj02(loc.latitude, loc.longitude);
        const result: LocationResult = {
          latitude: gcj.latitude,
          longitude: gcj.longitude,
          wgsLatitude: loc.latitude,
          wgsLongitude: loc.longitude,
          accuracy: loc.accuracy
        };
        callback.onSuccess(result);
      }).catch((e: BusinessError) => {
        callback.onError(`定位失败: ${e.message}`);
      });
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      callback.onError(`定位异常: ${e.message}`);
    }
  }

  // ---------------- 存储 ----------------
  private handleSetStorage(params: object | undefined, callback: BridgeCallback): void {
    const key: string | undefined = this.str(params, 'key');
    const data: string | undefined = this.str(params, 'data') ?? this.str(params, 'value');
    if (!key) {
      callback.onError('setStorage 缺少 key');
      return;
    }
    this.storage.set(key, data ?? '').then(() => callback.onSuccess())
      .catch((e: BusinessError) => callback.onError(e.message));
  }

  private handleGetStorage(params: object | undefined, callback: BridgeCallback): void {
    const key: string | undefined = this.str(params, 'key');
    if (!key) {
      callback.onError('getStorage 缺少 key');
      return;
    }
    this.storage.get(key).then((v: string) => {
      const r: DataResult = { data: v };
      callback.onSuccess(r);
    }).catch((e: BusinessError) => callback.onError(e.message));
  }

  private handleRemoveStorage(params: object | undefined, callback: BridgeCallback): void {
    const key: string | undefined = this.str(params, 'key');
    if (!key) {
      callback.onError('removeStorage 缺少 key');
      return;
    }
    this.storage.remove(key).then(() => callback.onSuccess())
      .catch((e: BusinessError) => callback.onError(e.message));
  }

  private wrapToken(params: object | undefined): object {
    const token: string | undefined = this.str(params, 'token');
    const kv: StorageKV = { key: 'web_cache_token', data: token ?? '' };
    return kv;
  }

  // ---------------- 打开 URL / 地图 / 系统设置 ----------------
  private handleOpenUrl(params: object | undefined, callback: BridgeCallback): void {
    const url: string | undefined = this.str(params, 'url');
    if (!url) {
      callback.onError('openUrl 缺少 url');
      return;
    }
    const want: Want = { action: 'ohos.want.action.viewData', uri: url };
    this.context.startAbility(want).then(() => callback.onSuccess())
      .catch((e: BusinessError) => callback.onError(`打开失败: ${e.message}`));
  }

  private handleDownloadAndOpenFile(params: object | undefined, callback: BridgeCallback): void {
    const url: string | undefined = this.str(params, 'url');
    if (!url) {
      callback.onError('downloadAndOpenFile 缺少 url');
      return;
    }
    // 未指定文件名时,从 url 末段推断。
    const fromUrl: string = url.substring(url.lastIndexOf('/') + 1);
    const fileName: string = this.str(params, 'fileName') ?? (fromUrl.length > 0 ? fromUrl : 'download.tmp');
    MediaHelper.downloadAndOpenFile(this.context, url, fileName, callback);
  }

  private handleOpenMap(params: object | undefined, callback: BridgeCallback): void {
    const lat: number | undefined = this.num(params, 'latitude');
    const lng: number | undefined = this.num(params, 'longitude');
    if (lat === undefined || lng === undefined) {
      callback.onError('openMap 缺少经纬度');
      return;
    }
    // 唤起第三方/系统地图导航。app 可选:amap/baidu/tencent/petal/system。
    const target: MapTarget = {
      latitude: lat,
      longitude: lng,
      name: this.str(params, 'name') ?? '',
      app: this.str(params, 'app') as MapApp
    };
    MapHelper.open(this.context, target, callback);
  }

  private handleOpenSetting(params: object | undefined, callback: BridgeCallback): void {
    const type: string | undefined = this.str(params, 'type') ?? 'general';
    // ble / wlan / general / privacy —— 唤起系统设置页。
    let want: Want;
    switch (type) {
      case 'ble':
        want = { bundleName: 'com.huawei.hmos.settings', abilityName: 'com.huawei.hmos.settings.MainAbility',
          uri: 'bluetooth_entry' };
        break;
      case 'wlan':
        want = { bundleName: 'com.huawei.hmos.settings', abilityName: 'com.huawei.hmos.settings.MainAbility',
          uri: 'wifi_entry' };
        break;
      case 'privacy':
      case 'general':
      default:
        want = { bundleName: 'com.huawei.hmos.settings', abilityName: 'com.huawei.hmos.settings.MainAbility' };
        break;
    }
    this.context.startAbility(want).then(() => callback.onSuccess())
      .catch((e: BusinessError) => callback.onError(`打开设置失败: ${e.message}`));
  }

  // ---------------- 参数转换 ----------------
  private toOpenOptions(params: object | undefined): OpenWebViewOptions {
    return {
      url: this.str(params, 'url') ?? '',
      title: this.str(params, 'title'),
      extra: params
    };
  }

  private toNavStyle(params: object | undefined): NavigationBarStyle {
    return {
      title: this.str(params, 'title'),
      frontColor: this.str(params, 'frontColor'),
      backgroundColor: this.str(params, 'backgroundColor'),
      hidden: this.bool(params, 'hidden')
    };
  }
}
