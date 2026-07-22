/*
 * 选图与文件下载打开。对应 Android chooseImage / downloadAndOpenFile。
 * 选图用 PhotoViewPicker(无需权限);下载用 rcp/http,打开用 startAbility。
 */

import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { picker } from '@kit.CoreFileKit';
import { fileIo } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import { common, Want, wantConstant } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { BridgeCallback } from '../bridge/BridgeTypes';

interface ChooseImageResult {
  paths: string[];
  tempFilePaths: string[];
}

interface PathResult {
  path: string;
}

export class MediaHelper {
  /**
   * 选择图片。返回 { paths: string[] },与 Android chooseImage 的 tempFilePaths 对齐。
   * @param count 最大可选数量(默认 1)
   */
  static chooseImage(count: number, callback: BridgeCallback): void {
    try {
      const options: photoAccessHelper.PhotoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = count > 0 ? count : 1;
      const photoPicker: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker();
      photoPicker.select(options)
        .then((res: photoAccessHelper.PhotoSelectResult) => {
          const data: ChooseImageResult = { paths: res.photoUris, tempFilePaths: res.photoUris };
          callback.onSuccess(data);
        })
        .catch((e: BusinessError) => callback.onError(`选择图片失败: ${e.message}`));
    } catch (err) {
      callback.onError(`选择图片异常: ${(err as BusinessError).message}`);
    }
  }

  /**
   * 下载文件到应用缓存目录后用系统能力打开。对应 Android downloadAndOpenFile。
   */
  static downloadAndOpenFile(context: common.UIAbilityContext,
    url: string, fileName: string, callback: BridgeCallback): void {
    const filePath: string = `${context.cacheDir}/${fileName}`;
    const request: http.HttpRequest = http.createHttp();
    request.request(url, { method: http.RequestMethod.GET }, (err: BusinessError, data: http.HttpResponse) => {
      try {
        if (err) {
          callback.onError(`下载失败: ${err.message}`);
          request.destroy();
          return;
        }
        const body: ArrayBuffer = data.result as ArrayBuffer;
        const file: fileIo.File = fileIo.openSync(filePath, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE);
        fileIo.writeSync(file.fd, body);
        fileIo.closeSync(file);
        request.destroy();
        MediaHelper.openFile(context, filePath, callback);
      } catch (e) {
        request.destroy();
        callback.onError(`保存文件失败: ${(e as BusinessError).message}`);
      }
    });
  }

  private static openFile(context: common.UIAbilityContext, filePath: string, callback: BridgeCallback): void {
    // 用 fileUri 转成可共享 uri,授予读权限后交给系统选择打开方式。
    const want: Want = {
      action: 'ohos.want.action.viewData',
      uri: `file://${filePath}`,
      flags: wantConstant.Flags.FLAG_AUTH_READ_URI_PERMISSION
    };
    const data: PathResult = { path: filePath };
    context.startAbility(want)
      .then(() => callback.onSuccess(data))
      .catch((e: BusinessError) => callback.onError(`打开文件失败: ${e.message}`));
  }
}
