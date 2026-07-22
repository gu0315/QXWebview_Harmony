/*
 * QX Hybrid 桥常量。与 Android com.jd.jdbridge.JDBridgeConstant / JDBridge 保持一致,
 * 保证同一份 H5 无需改动即可在鸿蒙侧运行。
 */

/** 注入到 window 上的对象名。JS 通过 window.XWebView._callNative(...) 调用原生。 */
export const JS_NAME: string = 'XWebView';

/** 原生 -> JS:响应回调。参数为 Response 的 JSON 字符串。 */
export const JS_RESPOND_TO_WEB: string = 'window.JDBridge._handleResponseFromNative(%s)';

/** 原生 -> JS:原生主动发起的请求(如订阅推送)。 */
export const JS_CALL_WEB: string = 'window.JDBridge._handleRequestFromNative(%s)';

/** 原生 -> JS:派发 CustomEvent 事件。 */
export const JS_DISPATCH_EVENT: string =
  ";(function(){var event = new CustomEvent('%s', {'detail': %s}); window.dispatchEvent(event);})();";

/** 状态码,与 Android 完全一致。 */
export const STATUS_SUCCESS: string = '0';
export const STATUS_ERROR: string = '-1';
export const STATUS_EXCEPTION: string = '1';
export const STATUS_NOT_FOUND: string = '-2';

export const MSG_PLUGIN_NOT_FOUND: string = 'Target plugin not found.';
export const MSG_ACTION_NOT_FOUND: string = 'Target action not found.';
export const MSG_EXCEPTION: string = 'Execute plugin throws.';

export const MODULE_TAG: string = 'JDBridge';
