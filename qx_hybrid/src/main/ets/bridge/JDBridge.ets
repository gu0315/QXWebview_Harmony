/*
 * JDBridge:桥的核心分发器。对应 Android com.jd.jdbridge.JDBridge。
 *
 * 职责:
 *  1. 通过 Web 组件的 javaScriptProxy 把自身以 window.XWebView 注入页面;
 *  2. JS 调用 XWebView._callNative(jsonStr) -> 解析 -> 按 plugin/action 分发到插件;
 *  3. 插件结果经 window.JDBridge._handleResponseFromNative(...) 回给 H5;
 *  4. 支持原生主动派发事件(dispatchEvent)与请求(_handleRequestFromNative)。
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

/** 原生 -> Web 请求报文(对应 Android Request)。 */
interface RequestWire {
  plugin: string;
  params: Object | null;
  callbackId: string;
}

export class JDBridge {
  /** 与 Android 相同的注入名。 */
  static readonly JS_NAME: string = JS_NAME;

  private host: BridgeHost;
  private plugins: Map<string, IBridgePlugin> = new Map();
  /** callJS 的回调 id 生成器(对应 Android callbackIdCreator)。 */
  private jsCallbackId: number = 0;

  constructor(host: BridgeHost) {
    this.host = host;
  }

  /** 注册插件。重复注册以后者为准(与 Android HashMap 语义一致)。 */
  registerPlugin(plugin: IBridgePlugin): void {
    this.plugins.set(plugin.name, plugin);
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
    const resp: BridgeResponse = new BridgeResponse(status, callbackId, data, msg, complete);
    const script: string =
      JS_RESPOND_TO_WEB.replace('%s', JSON.stringify(resp.toJsonString()));
    this.host.runJavaScript(script);
  }

  /** 原生主动向 H5 派发一个 CustomEvent(如生命周期广播)。对应 Android dispatchEvent。 */
  dispatchEvent(eventName: string, detail?: Object): void {
    const detailStr: string = JSON.stringify(detail ?? null);
    const script: string =
      JS_DISPATCH_EVENT.replace('%s', eventName).replace('%s', detailStr);
    this.host.runJavaScript(script);
  }

  /**
   * 原生反调 Web 侧已 registerPlugin 的插件。对应 Android JDBridge.callJS。
   * 报文:{plugin, params, callbackId} -> window.JDBridge._handleRequestFromNative('json')。
   */
  callJS(pluginName: string, params?: Object): void {
    const req: RequestWire = {
      plugin: pluginName,
      params: params ?? null,
      callbackId: `${this.jsCallbackId++}`
    };
    // 与 respond 相同:双重 stringify 产出 JS 字符串字面量。
    const script: string = JS_CALL_WEB.replace('%s', JSON.stringify(JSON.stringify(req)));
    this.host.runJavaScript(script);
  }

  /** 释放全部插件资源。页面 onDestroy / aboutToDisappear 调用。 */
  destroy(): void {
    this.plugins.forEach((p: IBridgePlugin) => {
      if (p.onDestroy) {
        p.onDestroy();
      }
    });
    this.plugins.clear();
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
    // complete=false:流式数据(蓝牙 notify、生命周期订阅等)。
    this.bridge.respond(this.callbackId, STATUS_SUCCESS, data ?? null, null, false);
  }
}
