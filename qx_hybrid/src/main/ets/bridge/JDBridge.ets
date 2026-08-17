/*
 * JDBridge:桥的核心分发器。对应 Android com.jd.jdbridge.JDBridge。
 *
 * 职责:
 *  1. 通过 Web 组件的 javaScriptProxy 把自身以 window.XWebView 注入页面;
 *  2. JS 调用 XWebView._callNative(jsonStr) -> 解析 -> 按 plugin/action 分发到插件;
 *  3. 插件结果经 window.JDBridge._handleResponseFromNative(...) 回给 H5;
 *  4. 原生主动反调 Web 插件(callJS)并接收 JS 的回执(_respondFromJs);
 *  5. H5 侧 JDBridge 就绪前的 callJS 先入队,收到 _jsInit 后统一补发。
 *
 * 注入名、报文字段、状态码均与 Android 保持一致,因此同一份 H5 无需改动。
 */

import { BusinessError } from '@kit.BasicServicesKit';
import { JS_NAME, JS_RESPOND_TO_WEB, JS_CALL_WEB, JS_DISPATCH_EVENT,
  STATUS_SUCCESS, STATUS_ERROR, STATUS_EXCEPTION, STATUS_NOT_FOUND,
  MSG_PLUGIN_NOT_FOUND, MSG_ACTION_NOT_FOUND, MSG_EXCEPTION, MODULE_TAG } from './BridgeConstant';
import { BridgeRequest, BridgeResponse, BridgeCallback, BridgeHost } from './BridgeTypes';
import { IBridgePlugin } from './BridgePlugin';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x00A0;

/** 内置插件名,处理 H5 的 _jsInit / _respondFromJs 回执。与 Android 一致。 */
const INTERNAL_PLUGIN: string = '_jdbridge';

/** 原生 -> Web 请求报文(对应 Android Request)。 */
interface RequestWire {
  plugin: string;
  params: Object | null;
  callbackId: string;
}

/** 一次待发送的 callJS 请求(H5 未就绪时先入队)。 */
class PendingJsCall {
  wire: RequestWire;
  callback?: BridgeCallback;

  constructor(wire: RequestWire, callback?: BridgeCallback) {
    this.wire = wire;
    this.callback = callback;
  }
}

/** H5 回执报文 _respondFromJs 的字段。 */
interface JsResponse {
  callbackId?: string;
  status?: string;
  data?: Object;
  msg?: Object;
  complete?: boolean;
}

export class JDBridge {
  /** 与 Android 相同的注入名。 */
  static readonly JS_NAME: string = JS_NAME;

  private host: BridgeHost;
  private plugins: Map<string, IBridgePlugin> = new Map();
  /** callJS 的回调 id 生成器(对应 Android callbackIdCreator)。 */
  private jsCallbackId: number = 0;
  /**
   * H5 侧 JDBridge 就绪前的 callJS 缓冲区。null 表示已就绪、直接下发。
   * 对应 Android callJsQueue —— 没有它,aboutToAppear 期间派发的生命周期事件会丢。
   */
  private callJsQueue: PendingJsCall[] | null = [];
  /** 是否还没被 startQueueRequest 重置过(对应 Android firstJsQueue)。 */
  private firstJsQueue: boolean = true;
  /** callJS 挂起的原生回调,等 H5 经 _respondFromJs 回执后取出。 */
  private nativeCallbacks: Map<string, BridgeCallback> = new Map();

  constructor(host: BridgeHost) {
    this.host = host;
    // 内置插件:接收 H5 的 _jsInit(就绪通知)与 _respondFromJs(callJS 回执)。
    this.registerPlugin(new JDBridgeModule(this));
  }

  /** 注册插件。重复注册以后者为准(与 Android HashMap 语义一致)。 */
  registerPlugin(plugin: IBridgePlugin): void {
    this.plugins.set(plugin.name, plugin);
  }

  unregisterPlugin(name: string): void {
    this.plugins.delete(name);
  }

  getPlugin(name: string | undefined): IBridgePlugin | undefined {
    if (!name) {
      return undefined;
    }
    return this.plugins.get(name);
  }

  /**
   * 供 Web 组件 javaScriptProxy 暴露给 JS 的方法名列表里的核心方法。
   * JS 侧:window.XWebView._callNative(JSON.stringify({plugin, action, params, callbackId}))
   */
  _callNative(objStr: string): void {
    let req: BridgeRequest | undefined;
    try {
      req = JSON.parse(objStr) as BridgeRequest;
    } catch (e) {
      hilog.error(DOMAIN, MODULE_TAG, 'callNative 解析失败: %{public}s', JSON.stringify(e));
      return;
    }
    if (!req) {
      return;
    }
    const callbackId: string | undefined = req.callbackId;
    const action: string | undefined = req.action;
    const plugin: IBridgePlugin | undefined = this.getPlugin(req.plugin);

    if (!plugin) {
      this.respond(callbackId, STATUS_NOT_FOUND, null, MSG_PLUGIN_NOT_FOUND);
      return;
    }

    const callback: BridgeCallback = new PluginCallback(this, callbackId);

    try {
      const handled: boolean = plugin.execute(this.host, action, req.params, callback);
      if (!handled) {
        this.respond(callbackId, STATUS_NOT_FOUND, '', MSG_ACTION_NOT_FOUND);
      }
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      this.respond(callbackId, STATUS_EXCEPTION, null, `${MSG_EXCEPTION}, e: ${e.message}`);
      hilog.error(DOMAIN, MODULE_TAG, 'callNative 执行异常: %{public}s', JSON.stringify(err));
    }
  }

  /** 原生 -> JS 响应。对应 Android respondToWeb。由 PluginCallback 回调。 */
  respond(callbackId: string | undefined, status: string,
    data?: Object | null, msg?: string | null, complete: boolean = true): void {
    const resp: BridgeResponse =
      new BridgeResponse(status, callbackId, data, JDBridge.normalizeMsg(msg), complete);
    const script: string =
      JS_RESPOND_TO_WEB.replace('%s', JSON.stringify(resp.toJsonString()));
    this.host.runJavaScript(script);
  }

  /**
   * 若 msg 是形如 `{...}` / `[...]` 的结构化 JSON 字符串(QXBridgeError.make / BLE 信封的输出),
   * 解析成对象再下发,这样 H5 的 errorFunc 拿到的是对象而不是字符串,
   * 与 Android normalizeMsg、iOS NSError.userInfo 的语义一致。非 JSON 串原样返回。
   */
  private static normalizeMsg(msg: string | null | undefined): Object | null {
    if (msg === undefined || msg === null) {
      return null;
    }
    const trimmed: string = msg.trim();
    if (trimmed.length === 0) {
      return msg;
    }
    const first: string = trimmed.charAt(0);
    if (first !== '{' && first !== '[') {
      return msg;
    }
    try {
      return JSON.parse(trimmed) as Object;
    } catch (e) {
      return msg;
    }
  }

  /** 原生主动向 H5 派发一个 CustomEvent。对应 Android dispatchEvent。 */
  dispatchEvent(eventName: string, detail?: Object): void {
    const detailStr: string = JSON.stringify(detail ?? null);
    const script: string =
      JS_DISPATCH_EVENT.replace('%s', eventName).replace('%s', detailStr);
    this.host.runJavaScript(script);
  }

  /**
   * 原生反调 Web 侧已 registerPlugin 的插件。对应 Android JDBridge.callJS。
   * 报文:{plugin, params, callbackId} -> window.JDBridge._handleRequestFromNative('json')。
   * @param callback 可选;H5 处理完后经 _respondFromJs 回执时触发。
   */
  callJS(pluginName: string, params?: Object, callback?: BridgeCallback): void {
    this.jsCallbackId += 1;
    const wire: RequestWire = {
      plugin: pluginName,
      params: params ?? null,
      callbackId: `${this.jsCallbackId}`
    };
    this.queueJsCall(new PendingJsCall(wire, callback));
  }

  /** H5 未就绪就先入队,就绪后由 dispatchStartupJsCall 补发。 */
  private queueJsCall(call: PendingJsCall): void {
    const queue: PendingJsCall[] | null = this.callJsQueue;
    if (queue) {
      queue.push(call);
      return;
    }
    this.dispatchJsCall(call);
  }

  private dispatchJsCall(call: PendingJsCall): void {
    if (call.callback) {
      this.nativeCallbacks.set(call.wire.callbackId, call.callback);
    }
    // 与 respond 相同:双重 stringify 产出 JS 字符串字面量。
    const script: string = JS_CALL_WEB.replace('%s', JSON.stringify(JSON.stringify(call.wire)));
    this.host.runJavaScript(script);
  }

  /**
   * 页面开始加载时调用,重新开启入队(新页面的 H5 JDBridge 还没就绪)。
   * 对应 Android JDBridgeInstaller.loadUrl / reload -> startQueueRequest。
   * 首次调用是空操作:构造时队列已是空的。
   */
  startQueueRequest(): void {
    if (this.firstJsQueue) {
      this.firstJsQueue = false;
      return;
    }
    // 上一个页面遗留的未发送请求连同其回调一起丢弃,避免跨页面串扰。
    this.callJsQueue?.forEach((call: PendingJsCall) => {
      this.nativeCallbacks.delete(call.wire.callbackId);
    });
    this.callJsQueue = [];
  }

  /** H5 的 JDBridge 就绪:把入队期间积压的 callJS 全部补发。对应 Android jsInit。 */
  private dispatchStartupJsCall(): void {
    const queue: PendingJsCall[] | null = this.callJsQueue;
    this.callJsQueue = null;
    queue?.forEach((call: PendingJsCall) => this.dispatchJsCall(call));
  }

  /** H5 侧 JDBridge 初始化完成的通知(_jdbridge/_jsInit)。 */
  onJsInit(): void {
    hilog.info(DOMAIN, MODULE_TAG, 'H5 JDBridge 就绪,补发积压的 callJS');
    this.dispatchStartupJsCall();
  }

  /**
   * H5 对 callJS 的回执(_jdbridge/_respondFromJs)。
   * 按 callbackId 取回原生回调并分发,complete=true 时移除。对应 Android respondFromJs。
   */
  onRespondFromJs(params: object | undefined): void {
    if (!params) {
      return;
    }
    const resp: JsResponse = params as JsResponse;
    const callbackId: string | undefined = resp.callbackId;
    if (!callbackId) {
      return;
    }
    const cb: BridgeCallback | undefined = this.nativeCallbacks.get(callbackId);
    if (!cb) {
      return;
    }
    const complete: boolean = resp.complete !== false;
    try {
      if (complete) {
        this.nativeCallbacks.delete(callbackId);
        if (resp.status === STATUS_SUCCESS) {
          cb.onSuccess(resp.data);
        } else {
          const msg: Object | undefined = resp.msg;
          cb.onError(typeof msg === 'string' ? msg as string : JSON.stringify(msg ?? null));
        }
      } else {
        cb.onProgress(resp.data);
      }
    } catch (e) {
      hilog.error(DOMAIN, MODULE_TAG, '_respondFromJs 分发异常: %{public}s', JSON.stringify(e));
    }
  }

  /** 释放全部插件资源。页面 onDestroy / aboutToDisappear 调用。 */
  destroy(): void {
    this.plugins.forEach((p: IBridgePlugin) => {
      if (p.onDestroy) {
        p.onDestroy();
      }
    });
    this.plugins.clear();
    this.nativeCallbacks.clear();
    this.callJsQueue = [];
    this.firstJsQueue = true;
  }
}

/**
 * 内置插件 `_jdbridge`。对应 Android JDBridge.JDBridgeModule。
 * H5 的 JDBridge.js 会调:
 *   - _jsInit:JS 侧桥初始化完成
 *   - _respondFromJs:对原生 callJS 的回执
 */
class JDBridgeModule implements IBridgePlugin {
  readonly name: string = INTERNAL_PLUGIN;
  private bridge: JDBridge;

  constructor(bridge: JDBridge) {
    this.bridge = bridge;
  }

  execute(host: BridgeHost, action: string | undefined,
    params: object | undefined, callback: BridgeCallback): boolean {
    switch (action) {
      case '_jsInit':
        this.bridge.onJsInit();
        return true;
      case '_respondFromJs':
        this.bridge.onRespondFromJs(params);
        return true;
      default:
        return false;
    }
  }
}

/**
 * 插件回调实现。ArkTS 不允许用对象字面量实现带方法的接口,故用类。
 */
class PluginCallback implements BridgeCallback {
  private bridge: JDBridge;
  private callbackId?: string;

  constructor(bridge: JDBridge, callbackId?: string) {
    this.bridge = bridge;
    this.callbackId = callbackId;
  }

  onSuccess(result?: Object): void {
    this.bridge.respond(this.callbackId, STATUS_SUCCESS, result ?? null, null, true);
  }

  onError(errMsg?: string): void {
    this.bridge.respond(this.callbackId, STATUS_ERROR, null, errMsg ?? null, true);
  }

  onProgress(data?: Object): void {
    // complete=false:流式数据。msg 固定为 'onProgress',与 Android respondToWeb 一致。
    this.bridge.respond(this.callbackId, STATUS_SUCCESS, data ?? null, 'onProgress', false);
  }
}
