/*
 * 扫码。对应 Android ScanQrBridge / QRScannerActivity。
 * 使用华为 Scan Kit 的默认扫码界面 scanBarcode.startScanForResult。
 *
 * 回包结构与 Android 完全一致:
 *   成功 -> onSuccess({ data: <二维码内容>, success: true })
 *   失败 -> onError(QXBridgeError 信封):没有相机权限 1001 / 结果为空(取消) 1002 / 未知错误 -1
 *
 * 需要:module.json5 声明 ohos.permission.CAMERA;真机运行(模拟器无相机)。
 */

import { scanBarcode, scanCore } from '@kit.ScanKit';
import { common, abilityAccessCtrl, Permissions } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { BridgeCallback } from '../bridge/BridgeTypes';
import { QXBridgeError } from '../bridge/QXBridgeError';

/** 成功回包。对应 Android ScanQrBridge.successPayload。 */
interface ScanSuccessPayload {
  data: string;
  success: boolean;
}

/** Scan Kit 的「用户取消」错误码。 */
const SCAN_CANCELLED: number = 1000500001;

export class ScanHelper {
  /** 扫码前先确认相机权限,未授权时按 Android 的 1001 回错。 */
  static scan(context: common.UIAbilityContext, callback: BridgeCallback): void {
    const perm: Permissions = 'ohos.permission.CAMERA';
    const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
    try {
      const tokenId: number = context.applicationInfo.accessTokenId;
      const status: abilityAccessCtrl.GrantStatus = atManager.checkAccessTokenSync(tokenId, perm);
      if (status === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
        ScanHelper.startScan(context, callback);
        return;
      }
    } catch (e) {
      // 校验失败时继续走申请流程,由用户决定。
    }
    atManager.requestPermissionsFromUser(context, [perm])
      .then((result) => {
        const granted: boolean = result.authResults.length > 0 && result.authResults[0] === 0;
        if (granted) {
          ScanHelper.startScan(context, callback);
        } else {
          callback.onError(QXBridgeError.noPermission('没有相机权限'));
        }
      })
      .catch(() => callback.onError(QXBridgeError.noPermission('没有相机权限')));
  }

  private static startScan(context: common.UIAbilityContext, callback: BridgeCallback): void {
    const options: scanBarcode.ScanOptions = {
      scanTypes: [scanCore.ScanType.ALL],
      enableMultiMode: true,
      enableAlbum: true
    };
    try {
      scanBarcode.startScanForResult(context, options)
        .then((result: scanBarcode.ScanResult) => {
          const value: string = result.originalValue ?? '';
          if (value.length === 0) {
            callback.onError(QXBridgeError.cancelled('扫描结果为空'));
            return;
          }
          const payload: ScanSuccessPayload = { data: value, success: true };
          callback.onSuccess(payload);
        })
        .catch((error: BusinessError) => {
          if (error.code === SCAN_CANCELLED) {
            callback.onError(QXBridgeError.cancelled('扫描结果为空'));
          } else {
            callback.onError(QXBridgeError.unknown(`未知错误: ${error.code} ${error.message}`));
          }
        });
    } catch (err) {
      callback.onError(QXBridgeError.unknown(`未知错误: ${(err as BusinessError).message}`));
    }
  }
}
