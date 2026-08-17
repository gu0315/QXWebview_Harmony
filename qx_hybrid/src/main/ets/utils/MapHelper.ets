/*
 * 打开地图导航。对应 Android OpenMapAppUtils。
 *
 * 与 Android 一致的关键约定:
 *   - 入参 latitude / longitude 已是 **GCJ-02** 坐标,原样使用,不再做坐标转换;
 *   - 唤起顺序:高德 -> 百度 -> 腾讯 -> 华为花瓣;都没装则回退到各自的网页版。
 *   - URI 与 Android 逐字对齐,便于两端排查同一个导航问题。
 *
 * 注意:调用第三方 scheme 需在 module.json5 的 querySchemes 中声明对应 scheme,
 * canOpenLink 才能检测到已安装(见 README)。
 */

import { common, Want, bundleManager } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { BridgeCallback } from '../bridge/BridgeTypes';
import { QXBridgeError } from '../bridge/QXBridgeError';

export type MapApp = 'amap' | 'baidu' | 'tencent' | 'petal' | 'system';

export interface MapTarget {
  /** GCJ-02 纬度 */
  latitude: number;
  /** GCJ-02 经度 */
  longitude: number;
  name: string;
  /** 指定地图 App;不传则按 Android 的顺序自动择优。 */
  app?: MapApp;
}

interface MapCandidate {
  app: MapApp;
  /** canOpenLink 用的 scheme 前缀 */
  scheme: string;
  /** 已安装时唤起的完整 uri */
  uri: string;
  /** 未安装时的网页兜底 */
  webUrl: string;
}

interface OpenMapResult {
  code: number;
  msg: string;
  uri: string;
}

export class MapHelper {
  static open(context: common.UIAbilityContext, target: MapTarget, callback: BridgeCallback): void {
    const lat: number = target.latitude;
    const lng: number = target.longitude;
    const enc: string = encodeURIComponent(target.name ?? '');

    const candidates: MapCandidate[] = [
      {
        app: 'amap', scheme: 'androidamap://',
        // dev=0 表示传入的是 GCJ-02 坐标,style=2 自动模式,与 Android openAmap 一致。
        uri: `androidamap://navi?sourceApplication=app_name&poiname=${enc}&lat=${lat}&lon=${lng}&dev=0&style=2`,
        webUrl: `https://uri.amap.com/navigation?to=${lng},${lat},${enc}&mode=car`
      },
      {
        app: 'baidu', scheme: 'baidumap://',
        uri: `baidumap://map/navi?location=${lat},${lng}&title=${enc}&coord_type=gcj02&src=ohos.jd.plugin`,
        webUrl: `https://api.map.baidu.com/direction?destination=latlng:${lat},${lng}|name:${enc}&mode=driving&output=html&coord_type=gcj02`
      },
      {
        app: 'tencent', scheme: 'qqmap://',
        uri: `qqmap://map/marker?marker=coord:${lat},${lng};title=${enc}&referer=myapp`,
        webUrl: `https://apis.map.qq.com/uri/v1/marker?marker=coord:${lat},${lng};title=${enc}`
      },
      {
        // 鸿蒙原生地图,Android 侧没有对应项,作为纯血鸿蒙设备的兜底优先项之后再试。
        app: 'petal', scheme: 'petalmaps://',
        uri: `petalmaps://navigation?daddr=${lat},${lng}&type=drive`,
        webUrl: `https://uri.amap.com/navigation?to=${lng},${lat},${enc}&mode=car`
      }
    ];

    // 指定了 app 就只试它;否则按上面的顺序择首个已安装的。
    let list: MapCandidate[] = candidates;
    if (target.app && target.app !== 'system') {
      const picked: MapCandidate | undefined = candidates.find((c: MapCandidate) => c.app === target.app);
      list = picked ? [picked] : [];
    }

    const chosen: MapCandidate | undefined = list.find((c: MapCandidate) => MapHelper.canOpen(c.scheme));
    if (chosen) {
      MapHelper.launch(context, chosen.uri, callback, chosen.webUrl);
      return;
    }

    // 一个都没装:走网页版(Android 的 executeIntent 兜底逻辑)。
    const fallback: MapCandidate = list.length > 0 ? list[0] : candidates[0];
    MapHelper.launch(context, fallback.webUrl, callback, undefined);
  }

  private static canOpen(scheme: string): boolean {
    try {
      return bundleManager.canOpenLink(scheme);
    } catch (err) {
      // 未在 querySchemes 声明或 API 不支持时,视为未安装,交由网页兜底。
      return false;
    }
  }

  /** 唤起 uri;失败且有 webUrl 时再试一次网页版,仍失败才回错误。 */
  private static launch(context: common.UIAbilityContext, uri: string,
    callback: BridgeCallback, webFallback: string | undefined): void {
    const want: Want = { action: 'ohos.want.action.viewData', uri: uri };
    context.startAbility(want)
      .then(() => {
        const r: OpenMapResult = { code: 0, msg: '打开地图成功', uri: uri };
        callback.onSuccess(r);
      })
      .catch((e: BusinessError) => {
        if (webFallback) {
          MapHelper.launch(context, webFallback, callback, undefined);
          return;
        }
        callback.onError(QXBridgeError.unsupported(`打开地图失败: ${e.message}`));
      });
  }
}
