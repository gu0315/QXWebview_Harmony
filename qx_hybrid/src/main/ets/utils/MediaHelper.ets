/*
 * 选图与文件下载打开。对应 Android ImagePickerActivity / QXBasePlugin.handleDownloadAndOpenFile。
 *
 * 回包结构与 Android 完全一致:
 *   chooseImage        -> { count, images:[{ base64, path, width, height, size }] };用户取消 -> { cancelled:true }
 *   downloadAndOpenFile-> 一律走 onSuccess:{ code:200|400|500, msg, filePath? }
 */

import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { cameraPicker, camera } from '@kit.CameraKit';
import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { common, Want, wantConstant } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { BridgeCallback } from '../bridge/BridgeTypes';

/** chooseImage 单张图片的结构,字段对齐 Android ImagePickerActivity.processImage。 */
interface ChosenImage {
  /** "data:image/jpeg;base64,..." */
  base64: string;
  /** 本地 file:// 路径 */
  path: string;
  width: number;
  height: number;
  /** 字节数 */
  size: number;
}

interface ChooseImageResult {
  count: number;
  images: ChosenImage[];
}

interface CancelledResult {
  cancelled: boolean;
}

/** downloadAndOpenFile 的回包。与 Android 一致:失败也走 onSuccess,由 code 区分。 */
interface DownloadResult {
  code: number;
  msg: string;
  filePath?: string;
}

const CANCELLED: CancelledResult = { cancelled: true };
const base64Helper: util.Base64Helper = new util.Base64Helper();

export class MediaHelper {

  /**
   * 选择图片。sourceType 支持 'album' / 'camera',与 Android 同义。
   * @param sources 允许的来源,空数组等价于 ['album','camera']
   * @param maxSize 长边最大像素(默认 1280)
   * @param quality JPEG 压缩质量 1~100(默认 80)
   */
  static chooseImage(context: common.UIAbilityContext, sources: string[],
    maxSize: number, quality: number, callback: BridgeCallback): void {
    const list: string[] = sources.length > 0 ? sources : ['album', 'camera'];
    const allowAlbum: boolean = list.includes('album');
    const allowCamera: boolean = list.includes('camera');

    if (allowCamera && !allowAlbum) {
      MediaHelper.pickFromCamera(context, maxSize, quality, callback);
      return;
    }
    // 相册选择;允许拍照时打开选择器内置的相机入口(对应 Android 的「拍照/从相册选择」二选一)。
    MediaHelper.pickFromAlbum(context, allowCamera, maxSize, quality, callback);
  }

  private static pickFromAlbum(context: common.UIAbilityContext, allowCamera: boolean,
    maxSize: number, quality: number, callback: BridgeCallback): void {
    try {
      const options: photoAccessHelper.PhotoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      // Android 每次只回一张,这里保持一致。
      options.maxSelectNumber = 1;
      options.isPhotoTakingSupported = allowCamera;
      const picker: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker();
      picker.select(options)
        .then((res: photoAccessHelper.PhotoSelectResult) => {
          const uris: Array<string> = res.photoUris ?? [];
          if (uris.length === 0) {
            callback.onSuccess(CANCELLED);
            return;
          }
          MediaHelper.processImage(context, uris[0], maxSize, quality, callback);
        })
        .catch(() => callback.onSuccess(CANCELLED));
    } catch (err) {
      callback.onSuccess(CANCELLED);
    }
  }

  private static pickFromCamera(context: common.UIAbilityContext,
    maxSize: number, quality: number, callback: BridgeCallback): void {
    try {
      const profile: cameraPicker.PickerProfile = { cameraPosition: camera.CameraPosition.CAMERA_POSITION_BACK };
      cameraPicker.pick(context, [cameraPicker.PickerMediaType.PHOTO], profile)
        .then((result: cameraPicker.PickerResult) => {
          if (result.resultCode !== 0 || !result.resultUri) {
            callback.onSuccess(CANCELLED);
            return;
          }
          MediaHelper.processImage(context, result.resultUri, maxSize, quality, callback);
        })
        .catch(() => callback.onSuccess(CANCELLED));
    } catch (err) {
      callback.onSuccess(CANCELLED);
    }
  }

  /**
   * 解码 -> 按 maxSize 等比缩放 -> JPEG 压缩 -> 落盘 + base64。
   * 对应 Android decodeSampledBitmap + resizeBitmap + compress。
   */
  private static async processImage(context: common.UIAbilityContext, uri: string,
    maxSize: number, quality: number, callback: BridgeCallback): Promise<void> {
    let file: fileIo.File | null = null;
    try {
      file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      const source: image.ImageSource = image.createImageSource(file.fd);
      const info: image.ImageInfo = await source.getImageInfo();
      const srcW: number = info.size.width;
      const srcH: number = info.size.height;
      const longSide: number = Math.max(srcW, srcH);
      // maxSize<=0 表示不缩放。
      const scale: number = (maxSize > 0 && longSide > maxSize) ? maxSize / longSide : 1;
      const dstW: number = Math.max(1, Math.round(srcW * scale));
      const dstH: number = Math.max(1, Math.round(srcH * scale));

      const opts: image.DecodingOptions = { desiredSize: { width: dstW, height: dstH } };
      const pixelMap: image.PixelMap = await source.createPixelMap(opts);
      const packer: image.ImagePacker = image.createImagePacker();
      const packOpts: image.PackingOption = { format: 'image/jpeg', quality: quality };
      const buffer: ArrayBuffer = await packer.packing(pixelMap, packOpts);
      const bytes: Uint8Array = new Uint8Array(buffer);

      const filePath: string = `${context.cacheDir}/img_${Date.now()}.jpg`;
      const out: fileIo.File = fileIo.openSync(filePath, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE);
      fileIo.writeSync(out.fd, buffer);
      fileIo.closeSync(out);

      await packer.release();
      await pixelMap.release();
      await source.release();

      const item: ChosenImage = {
        base64: `data:image/jpeg;base64,${base64Helper.encodeToStringSync(bytes)}`,
        path: `file://${filePath}`,
        width: dstW,
        height: dstH,
        size: bytes.length
      };
      const result: ChooseImageResult = { count: 1, images: [item] };
      callback.onSuccess(result);
    } catch (e) {
      // 与 Android 一致:处理失败也不抛错,回取消,避免 H5 永久 pending。
      callback.onSuccess(CANCELLED);
    } finally {
      if (file) {
        try {
          fileIo.closeSync(file);
        } catch (e) {
          // ignore
        }
      }
    }
  }

  /**
   * 下载文件到应用缓存目录,可选地用系统能力打开。
   * 与 Android 一致:成功/失败都走 onSuccess,由 code 区分(200 成功 / 400 链接无效 / 500 失败)。
   */
  static downloadAndOpenFile(context: common.UIAbilityContext, url: string,
    fileName: string, isOpen: boolean, callback: BridgeCallback): void {
    const filePath: string = `${context.cacheDir}/${fileName}`;
    const request: http.HttpRequest = http.createHttp();
    request.request(url, { method: http.RequestMethod.GET, expectDataType: http.HttpDataType.ARRAY_BUFFER },
      (err: BusinessError, data: http.HttpResponse) => {
        try {
          if (err) {
            MediaHelper.emit(callback, 500, `下载失败：${err.message}`);
            request.destroy();
            return;
          }
          if (data.responseCode !== 200) {
            MediaHelper.emit(callback, 500, `下载失败，服务器返回异常:${data.responseCode}`);
            request.destroy();
            return;
          }
          const body: ArrayBuffer = data.result as ArrayBuffer;
          if (!body || body.byteLength === 0) {
            MediaHelper.emit(callback, 500, '下载失败，文件为空');
            request.destroy();
            return;
          }
          const file: fileIo.File = fileIo.openSync(filePath, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE);
          fileIo.writeSync(file.fd, body);
          fileIo.closeSync(file);
          request.destroy();

          const ok: DownloadResult = { code: 200, msg: '下载成功', filePath: filePath };
          callback.onSuccess(ok);
          if (isOpen) {
            MediaHelper.openFile(context, filePath);
          }
        } catch (e) {
          request.destroy();
          MediaHelper.emit(callback, 500, `下载失败：${(e as BusinessError).message ?? '未知异常'}`);
        }
      });
  }

  private static emit(callback: BridgeCallback, code: number, msg: string): void {
    const r: DownloadResult = { code: code, msg: msg };
    callback.onSuccess(r);
  }

  /** 打开已下载的文件。与 Android openFileWithNoCrash 一致:打不开只记日志,不影响已回的下载结果。 */
  private static openFile(context: common.UIAbilityContext, filePath: string): void {
    const want: Want = {
      action: 'ohos.want.action.viewData',
      uri: `file://${filePath}`,
      flags: wantConstant.Flags.FLAG_AUTH_READ_URI_PERMISSION
    };
    context.startAbility(want).catch((e: BusinessError) => {
      console.error(`打开文件异常: ${e.message}`);
    });
  }
}
