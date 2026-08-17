/*
 * QXBasePlugin —— 基础能力插件。逐个 action 对齐 Android com/jd/plugins/QXBasePlugin.kt。
 *
 * action 全量(18 个,与 Android 完全一致):
 *   scanQRCode / goBack / closeWebView / getDeviceInfo / location / downloadAndOpenFile /
 *   openMap / setNavigationBarStyle / openWebView / closeWithResult / openUrl / chooseImage /
 *   setWebCacheToken / setStorage / getStorage / removeStorage / clearStorage / notifyFirstRender
 *
 * 另保留鸿蒙历史 action `openSetting`,内部并入 openUrl 的 type 解析,避免老接入方 H5 报错。
 *
 * 约定(与 Android 一致):
 *   - 失败统一 onError(QXBridgeError 信封 JSON 串),H5 侧 JSON.parse(err.message) 取 code/message;
 *   - location 的失败**不走 onError**,而是 onSuccess 一个 locationType='failure' 的完整结构;
 *   - downloadAndOpenFile 的失败也走 onSuccess,由 code(200/400/500)区分。
 */

import { BasePlugin } from '../bridge/BridgePlugin';
import { BridgeCallback, BridgeHost } from '../bridge/BridgeTypes';
import { QXBridgeError } from '../bridge/QXBridgeError';
import { PageResultCenter } from '../bridge/PageResultCenter';
import { QXHostDelegate, OpenWebViewOptions, QXNavigationBarStyle,
  parseNavigationBarStyle, navigationBarStyleJsValue } from '../bridge/HostDelegate';
import { StorageUtil } from '../utils/StorageUtil';
import { UrlUtil } from '../utils/UrlUtil';
import { collectDeviceInfo, DeviceInfoResult } from './SystemInfoPlugin';
import { wgs84ToGcj02, LatLng } from '../utils/GCJ02Converter';
import { common, Want, abilityAccessCtrl, Permissions } from '@kit.AbilityKit';
import { geoLocationManager } from '@kit.LocationKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { webview } from '@kit.ArkWeb';
import { ScanHelper } from '../utils/ScanHelper';
import { MediaHelper } from '../utils/MediaHelper';
import { MapHelper, MapApp, MapTarget } from '../utils/MapHelper';

// ============ 回包结构(ArkTS 要求对象字面量必须有显式类型) ============

/** 通用 {code,msg} 回包。setStorage/removeStorage/clearStorage 用。 */
interface CodeMsgResult {
  code: number;
  msg: string;
  key?: string;
}

/** getStorage 回包。key 不存在时 value 为 null。 */
interface GetStorageResult {
  code: number;
  key: string;
  value: Object | null;
}

/** setWebCacheToken 回包。 */
interface WebCacheTokenResult {
  code: number;
  msg: string;
  cleared: boolean;
  token: string;
}

/** setNavigationBarStyle 回包。 */
interface NavStyleResult {
  code: number;
  msg: string;
  style: string;
  rawValue: number;
}

/** openWebView(非 forResult)/ openUrl 回包。 */
interface OpenResult {
  code: number;
  msg: string;
  url?: string;
}

/** notifyFirstRender / closeWithResult 的 ack。 */
interface SuccessAck {
  success: boolean;
}

/**
 * location 回包。字段与 Android QXLocationManager.processLocation 逐个对齐。
 * 失败时同样返回本结构,locationType='failure' 并带 code/msg。
 */
interface LocationResult {
  /** GCJ-02 纬度 */
  latitude: number;
  /** GCJ-02 经度 */
  longitude: number;
  accuracy: number;
  altitude: number;
  /** 无速度时为 -1,与 Android 一致 */
  speed: number;
  /** 毫秒时间戳的字符串形式 */
  timestamp: string;
  /** "lat,lng",保留 6 位小数 */
  geopoint: string;
  gcoord: string;
  hasPermission: boolean;
  isEnable: boolean;
  /** 是否拿到了精确定位权限 */
  preciseLocation: boolean;
  /** new / cache / failure */
  locationType: string;
  /** 省(adminArea) */
  state: string;
  city: string;
  district: string;
  street: string;
  streetNum: string;
  /** 仅 locationType='failure' 时出现 */
  code?: number;
  msg?: string;
}

/** closeWithResult 未带 data 时的占位空对象。 */
interface EmptyResult {
}

const ACK_SUCCESS: SuccessAck = { success: true };
const EMPTY_RESULT: EmptyResult = {};

/** 与 Android LocationConstants 对齐的业务错误码。 */
const ERROR_PERMISSION_DENIED: number = 1002;
const ERROR_LOCATION_SERVICE_DISABLED: number = 1007;
const ERROR_LOCATION_TIMEOUT: number = 1008;
const PERMISSION_DENIED_MSG: string = '定位权限被拒绝，请在系统设置中开启';
const LOCATION_SERVICE_DISABLED_MSG: string = '系统定位服务未开启，请打开 GPS / 网络定位';
const LOCATION_TIMEOUT_MSG: string = '定位超时';
/** Android DEFAULT_TIMEOUT = 20000 */
const DEFAULT_LOCATION_TIMEOUT: number = 20000;

/** 鸿蒙系统设置的 bundle / ability 名。 */
const SETTINGS_BUNDLE: string = 'com.huawei.hmos.settings';
const SETTINGS_ABILITY: string = 'com.huawei.hmos.settings.MainAbility';

export class QXBasePlugin extends BasePlugin {
  static readonly NAME: string = 'QXBasePlugin';
  readonly name: string = QXBasePlugin.NAME;

  private context: common.UIAbilityContext;
  private storage: StorageUtil;
  private delegate: QXHostDelegate | null;
  /**
   * 当前页面的回传 id。由容器创建 QXWebView 时传入(来自打开方 openWebView 的 forResult)。
   * closeWithResult 时据此把数据回给打开方,对应 Android 的 Intent EXTRA_PAGE_ID。
   */
  private pageId: string | undefined;
  /** 由容器注入的扫码/选图实现(集成方可覆盖默认的 Scan Kit / 图库实现)。 */
  private onScanRequest: ((cb: BridgeCallback) => void) | null = null;
  private onChooseImageRequest: ((params: object | undefined, cb: BridgeCallback) => void) | null = null;

  constructor(context: common.UIAbilityContext, storage: StorageUtil,
    delegate: QXHostDelegate | null, pageId?: string) {
    super();
    this.context = context;
    this.storage = storage;
    this.delegate = delegate;
    this.pageId = pageId;
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
      case 'scanQRCode':
        if (this.onScanRequest) {
          this.onScanRequest(callback);
        } else {
          ScanHelper.scan(this.context, callback);
        }
        return true;

      case 'goBack':
        this.handleGoBack(host, callback);
        return true;

      case 'closeWebView':
        this.delegate?.onCloseWebView();
        callback.onSuccess();
        return true;

      case 'getDeviceInfo':
        collectDeviceInfo(this.context)
          .then((info: DeviceInfoResult) => callback.onSuccess(info))
          .catch((e: BusinessError) => callback.onError(QXBridgeError.failure(`获取设备信息失败: ${e.message}`)));
        return true;

      case 'location':
        this.handleLocation(params, callback);
        return true;

      case 'downloadAndOpenFile':
        this.handleDownloadAndOpenFile(params, callback);
        return true;

      case 'openMap':
        this.handleOpenMap(params, callback);
        return true;

      case 'setNavigationBarStyle':
        this.handleSetNavigationBarStyle(params, callback);
        return true;

      case 'openWebView':
        this.handleOpenWebView(params, callback);
        return true;

      case 'closeWithResult':
        this.handleCloseWithResult(params, callback);
        return true;

      case 'openUrl':
      // openSetting 是鸿蒙侧的历史 action,Android 没有;并入 openUrl 的 type 解析保持兼容。
      case 'openSetting':
        this.handleOpenUrl(params, callback);
        return true;

      case 'chooseImage':
        this.handleChooseImage(params, callback);
        return true;

      case 'setWebCacheToken':
        this.handleSetWebCacheToken(host, params, callback);
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
        this.handleClearStorage(callback);
        return true;

      case 'notifyFirstRender':
        this.delegate?.onFirstRender?.();
        callback.onSuccess(ACK_SUCCESS);
        return true;

      default:
        return false;
    }
  }

  // ---------------- 页面返回 ----------------

  /**
   * 对应 Android executeBackLogic:能后退就后退并回 true,否则关页面并回 false。
   */
  private handleGoBack(host: BridgeHost, callback: BridgeCallback): void {
    try {
      const controller: webview.WebviewController = host.getController();
      if (controller.accessBackward()) {
        controller.backward();
        callback.onSuccess(true);
        return;
      }
      this.delegate?.onCloseWebView();
      callback.onSuccess(false);
    } catch (err) {
      // 页面尚未加载完成时 accessBackward 会抛错,按「无历史」处理。
      this.delegate?.onCloseWebView();
      callback.onSuccess(false);
    }
  }

  // ---------------- 定位 ----------------

  /**
   * needAddress 三态(对齐 Android):不传 -> 省/市/区;true -> 完整地址含街道;false -> 仅坐标。
   * 失败不抛错,统一回 locationType='failure' 的完整结构,前端用 locationType/hasPermission/isEnable 判分支。
   */
  private handleLocation(params: object | undefined, callback: BridgeCallback): void {
    const needAddress: boolean | undefined = this.coerceBool(params, 'needAddress');
    const timeout: number = Math.max(1000, this.numLoose(params, 'timeout') ?? DEFAULT_LOCATION_TIMEOUT);

    const precise: boolean = this.hasPermission('ohos.permission.LOCATION');
    const approximate: boolean = this.hasPermission('ohos.permission.APPROXIMATELY_LOCATION');
    const hasPermission: boolean = precise || approximate;
    const isEnable: boolean = QXBasePlugin.isLocationEnabled();

    if (!hasPermission) {
      callback.onSuccess(QXBasePlugin.failureLocation(
        ERROR_PERMISSION_DENIED, PERMISSION_DENIED_MSG, false, isEnable, precise));
      return;
    }
    if (!isEnable) {
      callback.onSuccess(QXBasePlugin.failureLocation(
        ERROR_LOCATION_SERVICE_DISABLED, LOCATION_SERVICE_DISABLED_MSG, true, false, precise));
      return;
    }

    try {
      const request: geoLocationManager.SingleLocationRequest = {
        // 只授「粗略位置」时优先出首包速度,与 Android 放宽精度门槛的处理同义。
        locatingPriority: precise
          ? geoLocationManager.LocatingPriority.PRIORITY_ACCURACY
          : geoLocationManager.LocatingPriority.PRIORITY_LOCATING_SPEED,
        locatingTimeoutMs: timeout
      };
      geoLocationManager.getCurrentLocation(request).then((loc: geoLocationManager.Location) => {
        // 系统返回 WGS-84,转成 H5 地图使用的 GCJ-02(与 Android GCJ02Converter 同算法)。
        const gcj: LatLng = wgs84ToGcj02(loc.latitude, loc.longitude);
        const result: LocationResult = {
          latitude: gcj.latitude,
          longitude: gcj.longitude,
          accuracy: loc.accuracy,
          altitude: loc.altitude ?? 0,
          speed: (loc.speed === undefined || loc.speed < 0) ? -1 : loc.speed,
          timestamp: `${loc.timeStamp}`,
          geopoint: `${gcj.latitude.toFixed(6)},${gcj.longitude.toFixed(6)}`,
          gcoord: 'GCJ02',
          hasPermission: true,
          isEnable: true,
          preciseLocation: precise,
          locationType: 'new',
          state: '',
          city: '',
          district: '',
          street: '',
          streetNum: ''
        };
        if (needAddress === false) {
          callback.onSuccess(result);
          return;
        }
        this.fillAddress(loc.latitude, loc.longitude, needAddress === true, result, callback);
      }).catch((e: BusinessError) => {
        callback.onSuccess(QXBasePlugin.failureLocation(
          ERROR_LOCATION_TIMEOUT, `${LOCATION_TIMEOUT_MSG}: ${e.message}`, true, true, precise));
      });
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      callback.onSuccess(QXBasePlugin.failureLocation(
        ERROR_LOCATION_TIMEOUT, `${LOCATION_TIMEOUT_MSG}: ${e.message}`, true, true, precise));
    }
  }

  /** 逆地理编码补充省/市/区(和可选街道)。任何失败都不阻断,仍返回带坐标的结果。 */
  private fillAddress(lat: number, lng: number, includeStreet: boolean,
    result: LocationResult, callback: BridgeCallback): void {
    try {
      const req: geoLocationManager.ReverseGeoCodeRequest = {
        latitude: lat,
        longitude: lng,
        maxItems: 1
      };
      geoLocationManager.getAddressesFromLocation(req).then((addrs: Array<geoLocationManager.GeoAddress>) => {
        if (addrs.length > 0) {
          const a: geoLocationManager.GeoAddress = addrs[0];
          result.state = a.administrativeArea ?? '';
          result.city = a.locality ?? a.subAdministrativeArea ?? '';
          result.district = a.subLocality ?? '';
          if (includeStreet) {
            // 对齐 Android fillAddress:优先「路名+门牌号」,退化到 placeName / 完整地址行。
            const roadName: string = a.roadName ?? '';
            const subRoad: string = a.subRoadName ?? '';
            let street: string = '';
            if (roadName.length > 0 && subRoad.length > 0) {
              street = roadName + subRoad;
            } else if (roadName.length > 0) {
              street = roadName;
            } else {
              street = a.placeName ?? '';
            }
            result.street = street;
            result.streetNum = subRoad;
          }
        }
        callback.onSuccess(result);
      }).catch(() => {
        // 逆编码失败(如模拟器无地理编码服务):仍返回坐标,省市区为空。
        callback.onSuccess(result);
      });
    } catch (err) {
      callback.onSuccess(result);
    }
  }

  /** 构造 locationType='failure' 的完整结构。对应 Android buildEmptyResult + callbackError。 */
  private static failureLocation(code: number, msg: string,
    hasPermission: boolean, isEnable: boolean, precise: boolean): LocationResult {
    const r: LocationResult = {
      latitude: 0,
      longitude: 0,
      accuracy: 0,
      altitude: 0,
      speed: -1,
      timestamp: `${Date.now()}`,
      geopoint: '0.000000,0.000000',
      gcoord: 'GCJ02',
      hasPermission: hasPermission,
      isEnable: isEnable,
      preciseLocation: precise,
      locationType: 'failure',
      state: '',
      city: '',
      district: '',
      street: '',
      streetNum: '',
      code: code,
      msg: msg
    };
    return r;
  }

  private static isLocationEnabled(): boolean {
    try {
      return geoLocationManager.isLocationEnabled();
    } catch (e) {
      return false;
    }
  }

  private hasPermission(permission: Permissions): boolean {
    try {
      const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
      const tokenId: number = this.context.applicationInfo.accessTokenId;
      return atManager.checkAccessTokenSync(tokenId, permission) ===
        abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
    } catch (e) {
      return false;
    }
  }

  // ---------------- 原生 KV 存储 ----------------

  /** 取 key 并校验非空。对应 Android extractStorageKey。 */
  private extractKey(params: object | undefined, callback: BridgeCallback): string | undefined {
    const key: string = (this.str(params, 'key') ?? '').trim();
    if (key.length === 0) {
      callback.onError(QXBridgeError.invalidParams('key 不能为空'));
      return undefined;
    }
    return key;
  }

  private handleSetStorage(params: object | undefined, callback: BridgeCallback): void {
    const key: string | undefined = this.extractKey(params, callback);
    if (!key) {
      return;
    }
    // value 支持 String / Number / Bool / Array / Object;兼容鸿蒙老接入方传的 data 字段。
    const value: Object | undefined = this.raw(params, 'value') ?? this.raw(params, 'data');
    this.storage.set(key, value).then(() => {
      const r: CodeMsgResult = { code: 0, msg: 'ok', key: key };
      callback.onSuccess(r);
    }).catch((e: BusinessError) => callback.onError(QXBridgeError.failure(e.message)));
  }

  private handleGetStorage(params: object | undefined, callback: BridgeCallback): void {
    const key: string | undefined = this.extractKey(params, callback);
    if (!key) {
      return;
    }
    this.storage.get(key).then((v: Object | undefined) => {
      const r: GetStorageResult = { code: 0, key: key, value: v ?? null };
      callback.onSuccess(r);
    }).catch((e: BusinessError) => callback.onError(QXBridgeError.failure(e.message)));
  }

  private handleRemoveStorage(params: object | undefined, callback: BridgeCallback): void {
    const key: string | undefined = this.extractKey(params, callback);
    if (!key) {
      return;
    }
    this.storage.remove(key).then(() => {
      const r: CodeMsgResult = { code: 0, msg: 'ok', key: key };
      callback.onSuccess(r);
    }).catch((e: BusinessError) => callback.onError(QXBridgeError.failure(e.message)));
  }

  private handleClearStorage(callback: BridgeCallback): void {
    this.storage.clear().then(() => {
      const r: CodeMsgResult = { code: 0, msg: 'ok' };
      callback.onSuccess(r);
    }).catch((e: BusinessError) => callback.onError(QXBridgeError.failure(e.message)));
  }

  /**
   * H5 控制清 WebView 缓存。token 变化时清一次(不动 cookie / localStorage,不掉登录);不变则跳过。
   * 回包:{ code, msg, cleared, token } —— 与 Android / iOS 一致。
   */
  private handleSetWebCacheToken(host: BridgeHost, params: object | undefined, callback: BridgeCallback): void {
    const token: string = (this.str(params, 'token') ?? '').trim();
    if (token.length === 0) {
      callback.onError(QXBridgeError.invalidParams('token 不能为空'));
      return;
    }
    this.storage.getCacheToken().then((saved: string) => {
      if (saved === token) {
        const skip: WebCacheTokenResult = { code: 0, msg: 'token 未变化，已跳过', cleared: false, token: token };
        callback.onSuccess(skip);
        return;
      }
      try {
        // removeCache(true) 同时清内存与磁盘的 HTTP 资源缓存,不影响 cookie / localStorage。
        host.getController().removeCache(true);
      } catch (e) {
        callback.onError(QXBridgeError.notFound('获取WebView失败'));
        return;
      }
      this.storage.setCacheToken(token).then(() => {
        const done: WebCacheTokenResult = { code: 0, msg: '缓存已清理', cleared: true, token: token };
        callback.onSuccess(done);
      }).catch((e: BusinessError) => callback.onError(QXBridgeError.failure(e.message)));
    }).catch((e: BusinessError) => callback.onError(QXBridgeError.failure(e.message)));
  }

  // ---------------- 页面导航 ----------------

  /**
   * 打开新的 WebView 页面。
   * forResult=true 时挂起本次 callback,等新页面 closeWithResult 或被返回时回传;
   * 否则立即回 { code:0, msg, url }。
   */
  private handleOpenWebView(params: object | undefined, callback: BridgeCallback): void {
    const rawUrl: string = (this.str(params, 'url') ?? '').trim();
    if (rawUrl.length === 0) {
      callback.onError(QXBridgeError.invalidParams('url 不能为空'));
      return;
    }
    const delegate: QXHostDelegate | null = this.delegate;
    if (!delegate) {
      callback.onError(QXBridgeError.notFound('获取上下文失败'));
      return;
    }

    const finalUrl: string = UrlUtil.appendQueryParams(rawUrl, this.obj(params, 'query'));
    const forResult: boolean = this.coerceBool(params, 'forResult') ?? false;
    const pageId: string = PageResultCenter.newPageId();
    const options: OpenWebViewOptions = {
      url: finalUrl,
      navHidden: this.coerceBool(params, 'navHidden'),
      immersive: this.coerceBool(params, 'immersive'),
      navTitle: this.str(params, 'navTitle'),
      presentStyle: this.str(params, 'presentStyle'),
      forResult: forResult,
      pageId: pageId
    };

    if (forResult) {
      PageResultCenter.suspend(pageId, callback);
    }
    try {
      delegate.onOpenWebView(options);
      if (!forResult) {
        const r: OpenResult = { code: 0, msg: '打开 WebView 成功', url: finalUrl };
        callback.onSuccess(r);
      }
    } catch (err) {
      if (forResult) {
        PageResultCenter.discard(pageId);
      }
      const e: BusinessError = err as BusinessError;
      callback.onError(QXBridgeError.failure(`打开 WebView 失败: ${e.message ?? '未知异常'}`));
    }
  }

  /** 回传数据并关闭当前 WebView。data 回给打开方,本页收到 { success:true } 的 ack。 */
  private handleCloseWithResult(params: object | undefined, callback: BridgeCallback): void {
    // 与 Android 一致:未传 data 时回一个空对象,而不是 {success:true}。
    const data: Object = this.raw(params, 'data') ?? EMPTY_RESULT;
    if (this.pageId) {
      PageResultCenter.resolve(this.pageId, data);
    }
    this.delegate?.onCloseWithResult(data);
    callback.onSuccess(ACK_SUCCESS);
  }

  private handleSetNavigationBarStyle(params: object | undefined, callback: BridgeCallback): void {
    const delegate: QXHostDelegate | null = this.delegate;
    if (!delegate) {
      callback.onError(QXBridgeError.unsupported('当前页面不支持设置导航栏样式'));
      return;
    }
    const rawStyle: Object | undefined = this.raw(params, 'style') ?? this.raw(params, 'barStyle');
    const style: QXNavigationBarStyle | undefined = parseNavigationBarStyle(rawStyle);
    if (style === undefined) {
      callback.onError(QXBridgeError.invalidParams('style 参数仅支持 default/black 或 0/1'));
      return;
    }
    delegate.onSetNavigationBarStyle(style);
    const r: NavStyleResult = {
      code: 0,
      msg: 'navigationBar.barStyle 设置成功',
      style: navigationBarStyleJsValue(style),
      rawValue: style as number
    };
    callback.onSuccess(r);
  }

  // ---------------- 打开 URL / 系统设置 ----------------

  /**
   * 打开系统设置页或任意 URL(含三方 scheme)。
   * 支持的 type 与 Android resolveSystemIntent 一一对应。
   */
  private handleOpenUrl(params: object | undefined, callback: BridgeCallback): void {
    const type: string = (this.str(params, 'type') ?? '').trim().toLowerCase();
    const inputUrl: string = (this.str(params, 'url') ?? '').trim();
    const query: object | undefined = this.obj(params, 'query') ?? this.obj(params, 'params');

    const want: Want | undefined = this.resolveSystemWant(type, inputUrl, query);
    if (!want) {
      callback.onError(QXBridgeError.invalidParams('url 或 type 不能同时为空'));
      return;
    }
    const finalUrl: string = want.uri ?? inputUrl;
    this.context.startAbility(want).then(() => {
      const r: OpenResult = { code: 0, msg: '打开成功', url: finalUrl.length > 0 ? finalUrl : undefined };
      callback.onSuccess(r);
    }).catch((e: BusinessError) => {
      // 无应用可处理该 URL —— 对齐 Android 的 ActivityNotFoundException 分支。
      callback.onError(QXBridgeError.unsupported(`当前设备无法打开此 URL: ${e.message}`));
    });
  }

  /** type -> 系统设置页 Want。未命中 type 时按 url 构造。对应 Android resolveSystemIntent。 */
  private resolveSystemWant(type: string, fallbackUrl: string, query: object | undefined): Want | undefined {
    switch (type) {
      case 'settings':
      case 'app-settings':
      case 'appsettings':
      case 'camera':
      case 'camera-settings':
      case 'photo':
      case 'photos':
      case 'gallery':
      case 'location':
      case 'location-settings':
      case 'notification':
      case 'notifications':
      case 'notification-settings':
        // 鸿蒙没有独立的相机/相册/通知设置页,统一进本应用的详情页(与 Android appDetailsIntent 同义)。
        return this.appDetailsWant();
      case 'bluetooth':
      case 'ble':
        return QXBasePlugin.settingsWant('bluetooth_entry');
      case 'wifi':
      case 'wlan':
        return QXBasePlugin.settingsWant('wifi_entry');
      case 'cellular':
      case 'mobile-data':
        return QXBasePlugin.settingsWant('mobile_network_entry');
      case 'privacy':
        return QXBasePlugin.settingsWant('privacy_entry');
      case 'general':
        return QXBasePlugin.settingsWant(undefined);
      default:
        return QXBasePlugin.urlWant(fallbackUrl, query);
    }
  }

  /** 本应用的「应用信息」设置页。对应 Android ACTION_APPLICATION_DETAILS_SETTINGS。 */
  private appDetailsWant(): Want {
    const want: Want = {
      bundleName: SETTINGS_BUNDLE,
      abilityName: SETTINGS_ABILITY,
      uri: 'application_info_entry',
      parameters: {
        pushParams: this.context.abilityInfo.bundleName
      }
    };
    return want;
  }

  private static settingsWant(entry: string | undefined): Want {
    const want: Want = {
      bundleName: SETTINGS_BUNDLE,
      abilityName: SETTINGS_ABILITY,
      uri: entry
    };
    return want;
  }

  private static urlWant(url: string, query: object | undefined): Want | undefined {
    if (url.length === 0) {
      return undefined;
    }
    const want: Want = {
      action: 'ohos.want.action.viewData',
      uri: UrlUtil.appendQueryParams(url, query)
    };
    return want;
  }

  // ---------------- 下载 / 选图 / 地图 ----------------

  private handleDownloadAndOpenFile(params: object | undefined, callback: BridgeCallback): void {
    const url: string = (this.str(params, 'url') ?? '').trim();
    const isOpen: boolean = this.coerceBool(params, 'isOpen') ?? true;
    if (url.length === 0 || !url.startsWith('http')) {
      // 与 Android 一致:链接无效走 onSuccess,code=400。
      const r: CodeMsgResult = { code: 400, msg: '链接无效' };
      callback.onSuccess(r);
      return;
    }
    // 未指定文件名时,从 url 末段推断(与 Android substringAfterLast("/") 同义)。
    const fromUrl: string = url.substring(url.lastIndexOf('/') + 1);
    const fileName: string = this.str(params, 'fileName') ?? (fromUrl.length > 0 ? fromUrl : 'download.tmp');
    MediaHelper.downloadAndOpenFile(this.context, url, fileName, isOpen, callback);
  }

  private handleChooseImage(params: object | undefined, callback: BridgeCallback): void {
    if (this.onChooseImageRequest) {
      this.onChooseImageRequest(params, callback);
      return;
    }
    const sources: string[] = this.strArray(params, 'sourceType') ?? [];
    const maxSize: number = this.numLoose(params, 'maxSize') ?? 1280;
    const rawQuality: number = this.numLoose(params, 'quality') ?? 80;
    const quality: number = Math.min(100, Math.max(1, Math.round(rawQuality)));
    MediaHelper.chooseImage(this.context, sources, maxSize, quality, callback);
  }

  private handleOpenMap(params: object | undefined, callback: BridgeCallback): void {
    // Android 侧 latitude/longitude 以字符串传入,这里两种都兼容。
    const lat: number | undefined = this.numLoose(params, 'latitude');
    const lng: number | undefined = this.numLoose(params, 'longitude');
    if (lat === undefined || lng === undefined) {
      callback.onError(QXBridgeError.invalidParams('经纬度缺失'));
      return;
    }
    const target: MapTarget = {
      latitude: lat,
      longitude: lng,
      name: this.str(params, 'name') ?? '',
      app: this.str(params, 'app') as MapApp
    };
    MapHelper.open(this.context, target, callback);
  }
}
