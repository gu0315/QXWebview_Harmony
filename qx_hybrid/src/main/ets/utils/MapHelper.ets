/*
 * 打开地图导航。对应 Android OpenMapAppUtils。
 * 按第三方地图 App 的 URI scheme 唤起;未指定或未安装时回退到系统 geo:。
 *
 * 注意:调用第三方 scheme 需在 module.json5 的 querySchemes 中声明对应 scheme,
 * canOpenLink 才能检测到已安装(见 README)。
 */

import { common, Want, bundleManager } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { BridgeCallback } from '../bridge/BridgeTypes';
import { wgs84ToGcj02, LatLng } from './GCJ02Converter';

export type MapApp = 'amap' | 'baidu' | 'tencent' | 'petal' | 'system';

export interface MapTarget {
  latitude: number;
  longitude: number;
  name: string;
  /** 指定地图 App;不传则自动择优。 */
  app?: MapApp;
}

interface MapCandidate {
  app: MapApp;
  scheme: string;   // canOpenLink 用的 scheme 前缀
  uri: string;      // 实际唤起的完整 uri
}

interface UriResult {
  uri: string;
}

export class MapHelper {
  static open(context: common.UIAbilityContext, target: MapTarget, callback: BridgeCallback): void {
    const lat: number = target.latitude;
    const lng: number = target.longitude;
    const name: string = target.name ?? '';
    const enc: string = encodeURIComponent(name);

    // 高德/腾讯用 GCJ-02;百度用 BD-09(此处不做 BD-09 转换,交由百度按 gcj02 参数处理)。
    const gcj: LatLng = wgs84ToGcj02(lat, lng);

    const candidates: MapCandidate[] = [
      {
        app: 'petal', scheme: 'petalmaps://',
        uri: `petalmaps://navigation?daddr=${gcj.latitude},${gcj.longitude}&type=drive`
      },
      {
        app: 'amap', scheme: 'amapuri://',
        uri: `amapuri://route/plan/?dlat=${gcj.latitude}&dlon=${gcj.longitude}&dname=${enc}&t=0`
      },
      {
        app: 'baidu', scheme: 'baidumap://',
        uri: `baidumap://map/direction?destination=name:${enc}|latlng:${gcj.latitude},${gcj.longitude}&coord_type=gcj02&mode=driving`
      },
      {
        app: 'tencent', scheme: 'qqmap://',
        uri: `qqmap://map/routeplan?type=drive&to=${enc}&tocoord=${gcj.latitude},${gcj.longitude}`
      }
    ];

    // 指定了 app 就只试它;否则按 candidates 顺序择首个已安装的。
    let list: MapCandidate[] = candidates;
    if (target.app && target.app !== 'system') {
      const picked: MapCandidate | undefined = candidates.find((c: MapCandidate) => c.app === target.app);
      list = picked ? [picked] : [];
    }

    const chosen: MapCandidate | undefined = list.find((c: MapCandidate) => MapHelper.canOpen(c.scheme));
    if (chosen) {
      MapHelper.launch(context, chosen.uri, callback);
      return;
    }

    // 回退:系统 geo:(由系统选择可用地图)。
    const geoUri: string = `geo:${gcj.latitude},${gcj.longitude}?q=${gcj.latitude},${gcj.longitude}(${enc})`;
    MapHelper.launch(context, geoUri, callback);
  }

  private static canOpen(scheme: string): boolean {
    try {
      return bundleManager.canOpenLink(scheme);
    } catch (err) {
      // 未在 querySchemes 声明或 API 不支持时,视为未知,交回退处理。
      return false;
    }
  }

  private static launch(context: common.UIAbilityContext, uri: string, callback: BridgeCallback): void {
    const want: Want = { action: 'ohos.want.action.viewData', uri: uri };
    const data: UriResult = { uri: uri };
    context.startAbility(want)
      .then(() => callback.onSuccess(data))
      .catch((e: BusinessError) => callback.onError(`打开地图失败: ${e.message}`));
  }
}
