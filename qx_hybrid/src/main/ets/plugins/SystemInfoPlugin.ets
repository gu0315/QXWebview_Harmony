/*
 * 设备 / 系统信息。对应 Android QXBasePlugin.handleGetDeviceInfo + DeviceUtils。
 *
 * 字段与 Android 逐个对齐(H5 直接复用同一份适配代码):
 *   model / brand / systemVersion / systemSDK / deviceModel / appPlatform / OSVersion /
 *   appVersion / buildVersion / screenWidth / screenHeight / statusBarHeight /
 *   navBarHeight / bottomSafeHeight / locale / timezone
 *
 * 尺寸单位与 Android 一致:全部为 dp(鸿蒙的 vp),不是物理像素。
 */

import { BasePlugin } from '../bridge/BridgePlugin';
import { BridgeCallback, BridgeHost } from '../bridge/BridgeTypes';
import { QXBridgeError } from '../bridge/QXBridgeError';
import deviceInfo from '@ohos.deviceInfo';
import { display, window } from '@kit.ArkUI';
import { bundleManager, common } from '@kit.AbilityKit';
import { i18n } from '@kit.LocalizationKit';
import { BusinessError } from '@kit.BasicServicesKit';

/** 设备信息结构。字段名与 Android getDeviceInfo 完全一致。 */
export interface DeviceInfoResult {
  /** 设备型号,例:Mate 60 Pro */
  model: string;
  /** 设备品牌,例:HUAWEI */
  brand: string;
  /** 系统版本,例:HarmonyOS 5.0.0 */
  systemVersion: string;
  /** SDK API 版本,对应 Android 的 Build.VERSION.SDK_INT */
  systemSDK: number;
  /** 设备厂商 */
  deviceModel: string;
  /** 平台标识。Android 为 'android',此处为 'harmony' */
  appPlatform: string;
  /** 同 systemVersion,兼容旧字段 */
  OSVersion: string;
  /** App 版本名,例:1.0.0 */
  appVersion: string;
  /** App 版本号 */
  buildVersion: number;
  /** 屏幕宽(dp) */
  screenWidth: number;
  /** 屏幕高(dp) */
  screenHeight: number;
  /** 状态栏高度(dp) */
  statusBarHeight: number;
  /** 底部导航条高度(dp) */
  navBarHeight: number;
  /** 底部安全区高度(dp) */
  bottomSafeHeight: number;
  /** 系统语言+地区,例:zh-Hans-CN */
  locale: string;
  /** 系统时区,例:Asia/Shanghai */
  timezone: string;
}

/** 屏幕与安全区的 dp 值。 */
interface ScreenMetrics {
  screenWidth: number;
  screenHeight: number;
  statusBarHeight: number;
  navBarHeight: number;
  bottomSafeHeight: number;
}

const EMPTY_METRICS: ScreenMetrics = {
  screenWidth: 0,
  screenHeight: 0,
  statusBarHeight: 0,
  navBarHeight: 0,
  bottomSafeHeight: 0
};

/** 物理像素 -> dp。对应 Android DeviceUtils.px2dp。 */
function px2dp(px: number, density: number): number {
  if (!density || density <= 0) {
    return px;
  }
  return px / density;
}

/** 读取屏幕尺寸与安全区(dp)。任何环节失败都不阻断,回退为 0。 */
async function collectScreenMetrics(context: common.UIAbilityContext): Promise<ScreenMetrics> {
  const metrics: ScreenMetrics = {
    screenWidth: 0,
    screenHeight: 0,
    statusBarHeight: 0,
    navBarHeight: 0,
    bottomSafeHeight: 0
  };
  let density: number = 1;
  try {
    const d: display.Display = display.getDefaultDisplaySync();
    density = d.densityPixels > 0 ? d.densityPixels : 1;
    metrics.screenWidth = px2dp(d.width, density);
    metrics.screenHeight = px2dp(d.height, density);
  } catch (e) {
    // 取不到屏幕信息时保持 0。
  }
  try {
    const win: window.Window = await window.getLastWindow(context);
    const sysArea: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
    metrics.statusBarHeight = px2dp(sysArea.topRect.height, density);
    const navArea: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
    metrics.navBarHeight = px2dp(navArea.bottomRect.height, density);
    // Android 的 bottomSafeHeight 取的是刘海屏底部留白,鸿蒙用导航条避让区等价表达。
    metrics.bottomSafeHeight = metrics.navBarHeight;
  } catch (e) {
    // 窗口未就绪(如尚未 loadContent)时保持 0。
  }
  return metrics;
}

/** 读取 App 版本名 / 版本号。对应 Android DeviceUtils.getAppVersionName/Code。 */
function collectAppVersion(): bundleManager.BundleInfo | undefined {
  try {
    return bundleManager.getBundleInfoForSelfSync(
      bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
  } catch (e) {
    return undefined;
  }
}

/** 系统语言+地区。对应 Android DeviceUtils.getSystemLocale。 */
function currentLocale(): string {
  try {
    return i18n.System.getSystemLocale();
  } catch (e) {
    return '';
  }
}

/** 系统时区。对应 Android DeviceUtils.getSystemTimeZone。 */
function currentTimeZone(): string {
  try {
    return i18n.getTimeZone().getID();
  } catch (e) {
    return '';
  }
}

/**
 * 采集完整设备信息(异步:屏幕安全区需要窗口对象)。
 * @param context 承载页面的 UIAbility 上下文
 */
export async function collectDeviceInfo(context: common.UIAbilityContext): Promise<DeviceInfoResult> {
  const metrics: ScreenMetrics = context ? await collectScreenMetrics(context) : EMPTY_METRICS;
  const bundle: bundleManager.BundleInfo | undefined = collectAppVersion();
  const osVersion: string = deviceInfo.osFullName ?? '';
  const info: DeviceInfoResult = {
    model: deviceInfo.productModel ?? '',
    brand: deviceInfo.brand ?? '',
    systemVersion: osVersion,
    systemSDK: deviceInfo.sdkApiVersion ?? 0,
    deviceModel: deviceInfo.manufacture ?? '',
    appPlatform: 'harmony',
    OSVersion: osVersion,
    appVersion: bundle?.versionName ?? '1.0.0',
    buildVersion: bundle?.versionCode ?? 100,
    screenWidth: metrics.screenWidth,
    screenHeight: metrics.screenHeight,
    statusBarHeight: metrics.statusBarHeight,
    navBarHeight: metrics.navBarHeight,
    bottomSafeHeight: metrics.bottomSafeHeight,
    locale: currentLocale(),
    timezone: currentTimeZone()
  };
  return info;
}

/**
 * SystemInfoHandler 插件。对应 Android SystemInfoHandler。
 * 与 QXBasePlugin.getDeviceInfo 共用同一份采集逻辑。
 */
export class SystemInfoPlugin extends BasePlugin {
  static readonly NAME: string = 'SystemInfoHandler';
  readonly name: string = SystemInfoPlugin.NAME;

  private context: common.UIAbilityContext;

  constructor(context: common.UIAbilityContext) {
    super();
    this.context = context;
  }

  execute(host: BridgeHost, action: string | undefined,
    params: object | undefined, callback: BridgeCallback): boolean {
    switch (action) {
      case 'getSystemInfo':
      case 'getDeviceInfo':
        collectDeviceInfo(this.context)
          .then((info: DeviceInfoResult) => callback.onSuccess(info))
          .catch((e: BusinessError) => callback.onError(QXBridgeError.failure(`获取设备信息失败: ${e.message}`)));
        return true;
      default:
        return false;
    }
  }
}
