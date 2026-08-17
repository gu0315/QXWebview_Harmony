/*
 * 桥数据结构。对应 Android 的 Request.kt / Response.kt。
 *
 * ArkTS 约束:对象字面量必须对应显式声明的 class/interface(arkts-no-untyped-obj-literals)。
 * 因此数据载荷统一用 `Object` 顶层类型接收——各插件先构造带明确 interface 的局部变量再传入,
 * 序列化时用下方 ResponseWire 接口,避免出现"无类型字面量"。
 */

import { webview } from '@kit.ArkWeb';

/** JS 调原生的请求报文:{ plugin, action, params, callbackId }。 */
export interface BridgeRequest {
  plugin?: string;
  action?: string;
  params?: object;
  callbackId?: string;
}

/** 序列化到 JS 的响应报文结构。字段与 Android Response.kt 一致。 */
interface ResponseWire {
  status: string;
  callbackId: string | null;
  data: Object | null;
  /**
   * msg 允许是 string 或对象:插件通过 onError 传结构化 JSON 字符串
   * (如 QXBridgeError.make 的输出)时,JDBridge 会先解析成对象再塞进来,
   * H5 侧 errorFunc(response.msg) 直接就是对象,不用再 JSON.parse。
   */
  msg: Object | null;
  complete: boolean;
}

/**
 * 原生回给 JS 的响应。序列化后通过 window.JDBridge._handleResponseFromNative(...) 派发。
 */
export class BridgeResponse {
  status: string;
  callbackId?: string;
  data?: Object | null;
  msg?: Object | null;
  complete: boolean;

  constructor(status: string, callbackId?: string,
    data?: Object | null, msg?: Object | null, complete: boolean = true) {
    this.status = status;
    this.callbackId = callbackId;
    this.data = data;
    this.msg = msg;
    this.complete = complete;
  }

  toJsonString(): string {
    const wire: ResponseWire = {
      status: this.status,
      callbackId: this.callbackId ?? null,
      data: this.data ?? null,
      msg: this.msg ?? null,
      complete: this.complete
    };
    return JSON.stringify(wire);
  }
}

/**
 * 插件向 JS 回传结果的回调。对应 Android IBridgeProgressCallback。
 * - onSuccess:成功,complete=true(无数据时传空对象或不传)
 * - onError:失败(status=-1),errMsg 为错误信息
 * - onProgress:流式进度(complete=false,用于 notify/subscribe 等持续推送)
 */
export interface BridgeCallback {
  onSuccess(result?: Object): void;
  onError(errMsg?: string): void;
  onProgress(data?: Object): void;
}

/** 承载 Web 能力的宿主上下文,交给插件使用(执行 JS、访问 UIAbility 上下文等)。 */
export interface BridgeHost {
  /** 在 WebView 中执行一段 JS。 */
  runJavaScript(script: string): void;
  /** 获取 webview 控制器,供需要直接操作页面的插件使用。 */
  getController(): webview.WebviewController;
  /** 向 H5 主动派发一个 CustomEvent。 */
  dispatchEvent(eventName: string, detail?: Object): void;
  /**
   * 原生反调 Web 侧已 registerPlugin 的插件(对应 Android JDBridge.callJS)。
   * BLE 的 onBluetoothDeviceFound / onBLEConnectionStateChange / onBLECharacteristicValueChange
   * 与生命周期 onPageLifecycle 等事件均经此通道推送,params 需带 eventName 字段。
   *
   * H5 侧 JDBridge 尚未就绪时会先入队,等收到 _jsInit 再补发,不会丢事件。
   * @param callback 可选;H5 处理完经 _respondFromJs 回执时触发。
   */
  callJS(pluginName: string, params?: Object, callback?: BridgeCallback): void;
}
