/*
 * QXBridgeError —— 桥统一错误构造器。对应 Android com/jd/plugins/QXBridgeError.kt。
 *
 * BridgeCallback.onError 只接受 String,因此把 {code, message, success:false, data}
 * 序列化成 JSON 字符串下发,H5 侧 JSON.parse(err.message) 即可拿到结构化字段,
 * 与 Android / iOS 完全一致。
 *
 * 注意:BLE 错误码(10000~10013、-1~-99)走 QXBlePlugin 自己的信封,不在此枚举内。
 */

/** 与 Android QXBridgeErrorCode、iOS、H5 错误码速查表保持一致。 */
export enum QXBridgeErrorCode {
  /** 未知错误 */
  UNKNOWN = -1,
  /** 通用失败 */
  FAILURE = 1,
  /** 参数错误 / 非法参数 */
  INVALID_PARAMS = 1000,
  /** 没有权限(相机 / 定位 / 蓝牙 / 通知 等统一使用) */
  NO_PERMISSION = 1001,
  /** 用户取消 / 结果为空 */
  CANCELLED = 1002,
  /** 目标资源 / 页面 / 设备未找到 */
  NOT_FOUND = 1003,
  /** 超时 */
  TIMEOUT = 1004,
  /** 功能未实现 / 不支持 */
  UNSUPPORTED = 1005
}

/** 序列化到 H5 的错误报文。字段与 Android QXBridgeError.make 一致。 */
interface ErrorWire {
  code: number;
  message: string;
  success: boolean;
  data?: Object;
}

export class QXBridgeError {

  /** 按原始 Int 错误码构造,供 BLE 等有自定义错误码体系的插件复用。 */
  static make(code: number, message: string, data?: Object): string {
    const wire: ErrorWire = {
      code: code,
      message: message,
      success: false,
      data: data
    };
    return JSON.stringify(wire);
  }

  static failure(message: string, data?: Object): string {
    return QXBridgeError.make(QXBridgeErrorCode.FAILURE, message, data);
  }

  static invalidParams(message: string = '参数错误', data?: Object): string {
    return QXBridgeError.make(QXBridgeErrorCode.INVALID_PARAMS, message, data);
  }

  static noPermission(message: string = '没有权限', data?: Object): string {
    return QXBridgeError.make(QXBridgeErrorCode.NO_PERMISSION, message, data);
  }

  static cancelled(message: string = '用户取消', data?: Object): string {
    return QXBridgeError.make(QXBridgeErrorCode.CANCELLED, message, data);
  }

  static notFound(message: string = '资源未找到', data?: Object): string {
    return QXBridgeError.make(QXBridgeErrorCode.NOT_FOUND, message, data);
  }

  static timeout(message: string = '超时', data?: Object): string {
    return QXBridgeError.make(QXBridgeErrorCode.TIMEOUT, message, data);
  }

  static unsupported(message: string = '不支持', data?: Object): string {
    return QXBridgeError.make(QXBridgeErrorCode.UNSUPPORTED, message, data);
  }

  static unknown(message: string = '未知错误', data?: Object): string {
    return QXBridgeError.make(QXBridgeErrorCode.UNKNOWN, message, data);
  }
}
