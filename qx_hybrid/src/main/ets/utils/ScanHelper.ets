/*
 * 扫码。对应 Android ScanQrBridge / QRScannerActivity(zxing)。
 * 使用华为 Scan Kit 的默认扫码界面 scanBarcode.startScanForResult。
 *
 * 需要:module.json5 声明 ohos.permission.CAMERA;真机运行(模拟器无相机)。
 */

import { scanBarcode, scanCore } from '@kit.ScanKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { BridgeCallback } from '../bridge/BridgeTypes';

interface ScanResultData {
  result: string;
  scanType: string;
}

export class ScanHelper {
  /**
   * 拉起系统扫码界面,成功回传扫描内容。
   * 结果结构与 Android 对齐:{ result: string, scanType: string }。
   */
  static scan(context: common.UIAbilityContext, callback: BridgeCallback): void {
    const options: scanBarcode.ScanOptions = {
      scanTypes: [scanCore.ScanType.ALL],
      enableMultiMode: true,
      enableAlbum: true
    };
    try {
      scanBarcode.startScanForResult(context, options)
        .then((result: scanBarcode.ScanResult) => {
          const data: ScanResultData = {
            result: result.originalValue,
            scanType: `${result.scanType}`
          };
          callback.onSuccess(data);
        })
        .catch((error: BusinessError) => {
          // 用户取消(1000500001)也走这里,统一回错误码由 H5 处理。
          callback.onError(`扫码失败: ${error.code} ${error.message}`);
        });
    } catch (err) {
      callback.onError(`扫码异常: ${(err as BusinessError).message}`);
    }
  }
}
