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
import { SafeAreaHolder } from '../utils/SafeAreaHolder';
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

/** 等待避让区就绪的轮询参数。沉浸式全屏 setWindowLayoutFullScreen 异步生效,首帧可能取到 0。 */
const AVOID_AREA_MAX_TRIES: number = 20;
const AVOID_AREA_RETRY_INTERVAL_MS: number = 50;

/**
 * 沉浸式下测不到状态栏高度时的兜底值(vp)。
 *
 * 沉浸式全屏时 Web 内容铺到状态栏底下,statusBarHeight 若为 0,H5 头部不垫占位、
 * 返回按钮会顶进状态栏 —— 这种情况下 0 一定是错的,宁可给个通用值也不能回 0。
 * 40vp 接近华为机型常见状态栏高度,也与 H5 侧默认值(43)同量级。
 * 注意:仅在沉浸式下启用;非沉浸式由系统自动避让,0 是正确值。
 */
const FALLBACK_STATUS_BAR_HEIGHT_VP: number = 40;

/** 简易 sleep。 */
function delay(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void): void => {
    setTimeout((): void => resolve(), ms);
  });
}

/**
 * 读取状态栏避让高度(px),等它就绪。
 *
 * 关键点:H5 在 onLaunch 只调一次 getSystemInfo 并永久缓存结果。若首帧沉浸式全屏还没生效,
 * getWindowAvoidArea(TYPE_SYSTEM).topRect.height 会是 0,H5 就把 statusBarHeight 记成 0、
 * 返回按钮顶进状态栏(实测 HUAWEI ALN-AL00 / OpenHarmony 6.1.1 复现)。
 * getSystemInfo 本身是异步的,这里轮询直到拿到正值或超时,保证首次调用就返回正确高度。
 *
 * 取值优先级:实时避让区 → 缓存值 → 沉浸式兜底常量。日志带 [QXSafeArea] 前缀,
 * 真机排查时过滤这个关键字即可看出到底是「等几轮就好了」还是「这台机器恒为 0」。
 */
async function resolveStatusBarHeightPx(win: window.Window, density: number): Promise<number> {
  for (let i: number = 0; i < AVOID_AREA_MAX_TRIES; i++) {
    let px: number = 0;
    try {
      px = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM).topRect.height;
    } catch (e) {
      px = 0;
    }
    if (px > 0) {
      SafeAreaHolder.updateStatusBarHeightPx(px);
      console.info(`[QXSafeArea] 第 ${i + 1} 次取到状态栏高度 ${px}px`);
      return px;
    }
    await delay(AVOID_AREA_RETRY_INTERVAL_MS);
  }

  // 轮询超时:窗口可能一直没进全屏(setWindowLayoutFullScreen 失败),或该机型避让区恒为 0。
  const cached: number = SafeAreaHolder.getStatusBarHeightPx();
  if (cached > 0) {
    console.warn(`[QXSafeArea] 轮询 ${AVOID_AREA_MAX_TRIES} 次均为 0,回退缓存值 ${cached}px`);
    return cached;
  }
  if (SafeAreaHolder.isImmersive()) {
    const fallback: number = Math.round(FALLBACK_STATUS_BAR_HEIGHT_VP * density);
    console.warn(`[QXSafeArea] 沉浸式下始终取不到状态栏高度,启用兜底 ${FALLBACK_STATUS_BAR_HEIGHT_VP}vp = ${fallback}px`);
    return fallback;
  }
  console.info('[QXSafeArea] 非沉浸式,状态栏高度 0 为正确值(系统已自动避让)');
  return 0;
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
    // 状态栏:轮询等就绪(见 resolveStatusBarHeightPx 注释),保证首次调用就返回正确高度。
    const statusTopPx: number = await resolveStatusBarHeightPx(win, density);
    // 导航条:读一次即可,拿不到就用缓存(手势导航隐藏时本就可能为 0)。
    const navArea: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
    let navBottomPx: number = navArea.bottomRect.height;
    if (navBottomPx > 0) {
      SafeAreaHolder.updateNavBarHeightPx(navBottomPx);
    } else {
      navBottomPx = SafeAreaHolder.getNavBarHeightPx();
    }
    metrics.statusBarHeight = px2dp(statusTopPx, density);
    metrics.navBarHeight = px2dp(navBottomPx, density);
    // Android 的 bottomSafeHeight 取的是刘海屏底部留白,鸿蒙用导航条避让区等价表达。
    metrics.bottomSafeHeight = metrics.navBarHeight;
  } catch (e) {
    // 窗口未就绪(如尚未 loadContent)时:退到缓存值,仍拿不到才保持 0。
    metrics.statusBarHeight = px2dp(SafeAreaHolder.getStatusBarHeightPx(), density);
    metrics.navBarHeight = px2dp(SafeAreaHolder.getNavBarHeightPx(), density);
    metrics.bottomSafeHeight = metrics.navBarHeight;
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
