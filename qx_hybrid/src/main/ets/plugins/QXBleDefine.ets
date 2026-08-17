/*
 * 蓝牙常量定义。对应 Android com/jd/plugins/QXBleDefine.kt。
 * 事件名、错误码、结果信封三者与 Android 逐字对齐,H5 无需分平台判断。
 */

/** 蓝牙事件类型。经 callJS('QXBlePlugin', {eventName, ...}) 推送给 H5。 */
export enum QXBLEventType {
  /** 发现蓝牙设备 */
  ON_BLUETOOTH_DEVICE_FOUND = 'onBluetoothDeviceFound',
  /** BLE 连接状态变化 */
  ON_BLE_CONNECTION_STATE_CHANGE = 'onBLEConnectionStateChange',
  /** BLE 特征值变化(接收设备推送的数据) */
  ON_BLE_CHARACTERISTIC_VALUE_CHANGE = 'onBLECharacteristicValueChange',
  /** BLE 通知状态变化 */
  ON_BLE_NOTIFICATION_STATE_CHANGE = 'onBLENotificationStateChange',
  /** BLE 写入特征值结果 */
  ON_BLE_WRITE_CHARACTERISTIC_VALUE_RESULT = 'onBLEWriteCharacteristicValueResult'
}

/**
 * 蓝牙错误码。遵循 uni-app 标准错误码(0、10000~10013),
 * 负数区间为项目自定义扩展,与 Android QXBleErrorCode 完全一致。
 */
export enum QXBleErrorCode {
  /** 操作成功 */
  SUCCESS = 0,
  /** 未初始化蓝牙适配器 */
  NOT_INIT = 10000,
  /** 当前蓝牙适配器不可用(蓝牙未开启或不支持) */
  NOT_AVAILABLE = 10001,
  /** 没有找到指定设备 */
  NO_DEVICE = 10002,
  /** 连接失败 */
  CONNECTION_FAIL = 10003,
  /** 没有找到指定服务 */
  NO_SERVICE = 10004,
  /** 没有找到指定特征值 */
  NO_CHARACTERISTIC = 10005,
  /** 当前连接已断开 */
  NO_CONNECTION = 10006,
  /** 当前特征值不支持此操作 */
  PROPERTY_NOT_SUPPORT = 10007,
  /** 其余所有系统上报的异常 */
  SYSTEM_ERROR = 10008,
  /** 系统版本不支持 BLE */
  SYSTEM_NOT_SUPPORT = 10009,
  /** 设备已连接 */
  ALREADY_CONNECT = 10010,
  /** 配对设备需要配对码 */
  NEED_PIN = 10011,
  /** 操作超时 */
  OPERATE_TIME_OUT = 10012,
  /** deviceId 为空或格式不正确 */
  INVALID_DATA = 10013,

  /** 蓝牙未开启 */
  BLUETOOTH_NOT_OPEN = -1,
  /** 蓝牙权限被拒绝 */
  PERMISSION_DENIED = -2,
  /** 设备未找到 */
  DEVICE_NOT_FOUND = -3,
  /** 连接超时 */
  CONNECT_TIMEOUT = -4,
  /** 特征值未找到 */
  CHARACTERISTIC_NOT_FOUND = -5,
  /** 特征值不支持写入 */
  WRITE_NOT_SUPPORTED = -6,
  /** 蓝牙权限未确定 */
  PERMISSION_NOT_DETERMINED = -7,
  /** 扫描不可用 */
  SCAN_NOT_AVAILABLE = -8,
  /** 外设对象为空 */
  PERIPHERAL_NIL = -9,
  /** 未知错误 */
  UNKNOWN_ERROR = -99
}

/** 错误码对应的默认文案,与 Android QXBleErrorCode.message 一致。 */
export function bleErrorMessage(code: QXBleErrorCode): string {
  switch (code) {
    case QXBleErrorCode.SUCCESS: return 'ok';
    case QXBleErrorCode.NOT_INIT: return 'not init';
    case QXBleErrorCode.NOT_AVAILABLE: return 'not available';
    case QXBleErrorCode.NO_DEVICE: return 'no device';
    case QXBleErrorCode.CONNECTION_FAIL: return 'connection fail';
    case QXBleErrorCode.NO_SERVICE: return 'no service';
    case QXBleErrorCode.NO_CHARACTERISTIC: return 'no characteristic';
    case QXBleErrorCode.NO_CONNECTION: return 'no connection';
    case QXBleErrorCode.PROPERTY_NOT_SUPPORT: return 'property not support';
    case QXBleErrorCode.SYSTEM_ERROR: return 'system error';
    case QXBleErrorCode.SYSTEM_NOT_SUPPORT: return 'system not support';
    case QXBleErrorCode.ALREADY_CONNECT: return 'already connect';
    case QXBleErrorCode.NEED_PIN: return 'need pin';
    case QXBleErrorCode.OPERATE_TIME_OUT: return 'operate time out';
    case QXBleErrorCode.INVALID_DATA: return 'invalid_data';
    case QXBleErrorCode.BLUETOOTH_NOT_OPEN: return '蓝牙未开启';
    case QXBleErrorCode.PERMISSION_DENIED: return '蓝牙权限被拒绝，请前往设置开启';
    case QXBleErrorCode.DEVICE_NOT_FOUND: return '未找到指定设备';
    case QXBleErrorCode.CONNECT_TIMEOUT: return '设备连接超时';
    case QXBleErrorCode.CHARACTERISTIC_NOT_FOUND: return '未找到指定特征';
    case QXBleErrorCode.WRITE_NOT_SUPPORTED: return '特征不支持写入';
    case QXBleErrorCode.PERMISSION_NOT_DETERMINED: return '蓝牙权限未授权，请先授权';
    case QXBleErrorCode.SCAN_NOT_AVAILABLE: return '当前无法扫描蓝牙设备';
    case QXBleErrorCode.PERIPHERAL_NIL: return '蓝牙外设对象为空';
    default: return '未知错误';
  }
}
