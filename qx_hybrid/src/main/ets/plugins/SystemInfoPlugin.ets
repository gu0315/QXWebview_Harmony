/*
 * SystemInfoHandler —— 系统 / 设备信息。对应 Android SystemInfoHandler。
 * 通过 QXBasePlugin 的 getDeviceInfo 复用,也可单独注册为 'SystemInfoHandler' 插件。
 */

import { BasePlugin } from '../bridge/BridgePlugin';
import { BridgeCallback, BridgeHost } from '../bridge/BridgeTypes';
import deviceInfo from '@ohos.deviceInfo';

/** 设备信息结构,尽量与 Android/iOS 对齐。 */
export interface DeviceInfoResult {
  platform: string;
  brand: string;
  model: string;
  system: string;
  osVersion: string;
  sdkApiVersion: number;
  deviceType: string;
}

/** 采集设备信息。 */
export function collectDeviceInfo(): DeviceInfoResult {
  const info: DeviceInfoResult = {
    platform: 'harmony',
    brand: deviceInfo.brand,
    model: deviceInfo.productModel,
    system: 'HarmonyOS',
    osVersion: deviceInfo.osFullName,
    sdkApiVersion: deviceInfo.sdkApiVersion,
    deviceType: deviceInfo.deviceType
  };
  return info;
}

export class SystemInfoPlugin extends BasePlugin {
  static readonly NAME: string = 'SystemInfoHandler';
  readonly name: string = SystemInfoPlugin.NAME;

  execute(host: BridgeHost, action: string | undefined,
    params: object | undefined, callback: BridgeCallback): boolean {
    switch (action) {
      case 'getSystemInfo':
      case 'getDeviceInfo':
        callback.onSuccess(collectDeviceInfo());
        return true;
      default:
        return false;
    }
  }
}
