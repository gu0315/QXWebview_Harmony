/*
 * BLE 数据解析。对应 Android com/jd/plugins/utils/BleDataParser.kt。
 *
 * writeBLECharacteristicValue 的 valueType 与 Android 完全一致:
 *   BASE64            -> base64 字符串
 *   BUFFER            -> 数组 [1,2,255] / 对象 {"0":1,"1":2} / 逗号分隔串 "1,2,255"
 *   HEX / 16进制      -> "0A1B2C"(允许空格)
 *   UTF8 / TEXT       -> 原文,按 UTF-8 编码
 *   未知类型          -> 按 UTF8 处理(与 Android 相同的兜底)
 *
 * 原生 -> H5 的特征值一律用**大写 HEX**下发(对齐 Android ByteUtils.bytes2HexStr)。
 */

import { util } from '@kit.ArkTS';

const base64Helper: util.Base64Helper = new util.Base64Helper();

/** parseValue 的解析结果。 */
export interface ParsedBleData {
  deviceId: string;
  serviceId: string;
  characteristicId: string;
  valueType: string;
  data: Uint8Array;
}

/** 解析失败时抛出,由调用方转成 BLE 错误信封。 */
export class BleParseError extends Error {
  constructor(message: string) {
    super(message);
  }
}

/**
 * 按 valueType 把 H5 传来的 value 解析成字节数组。
 * @throws BleParseError 格式非法或解析后为空
 */
export function parseValueByType(value: Object | undefined, valueType: string): Uint8Array {
  const type: string = (valueType ?? 'UTF8').toUpperCase();
  switch (type) {
    case 'BASE64':
      return parseBase64(value);
    case 'BUFFER':
      return parseBuffer(value);
    case 'HEX':
    case '16进制':
      return hexToBytes(textOf(value));
    case 'UTF8':
    case 'TEXT':
    default:
      // 未知 valueType 按 UTF8 兜底,与 Android 一致。
      return utf8ToBytes(textOf(value));
  }
}

function textOf(value: Object | undefined): string {
  if (value === undefined || value === null) {
    return '';
  }
  return typeof value === 'string' ? value as string : JSON.stringify(value);
}

function parseBase64(value: Object | undefined): Uint8Array {
  try {
    return base64Helper.decodeSync(textOf(value));
  } catch (e) {
    throw new BleParseError('Base64解码失败');
  }
}

/** BUFFER:支持数组、{"0":1,...} 对象、以及它们的字符串形式。 */
function parseBuffer(value: Object | undefined): Uint8Array {
  if (value === undefined || value === null) {
    throw new BleParseError('value为null，请检查JS端是否正确传递Buffer数据');
  }
  let source: Object = value;
  if (typeof value === 'string') {
    const trimmed: string = (value as string).trim();
    if (trimmed.length === 0) {
      throw new BleParseError('Buffer字符串为空');
    }
    if (trimmed.startsWith('[') || trimmed.startsWith('{')) {
      try {
        source = JSON.parse(trimmed) as Object;
      } catch (e) {
        throw new BleParseError('Buffer字符串不是合法 JSON');
      }
    } else {
      // "1,2,255" 逗号分隔。
      source = trimmed.split(',');
    }
  }

  let numbers: Array<Object>;
  if (Array.isArray(source)) {
    numbers = source as Array<Object>;
  } else if (typeof source === 'object') {
    // {"0":1,"1":2} —— ArrayBuffer 经 JSON 序列化后的常见形态,按数字 key 排序还原。
    const record: Record<string, Object> = source as Record<string, Object>;
    const keys: string[] = Object.keys(record);
    if (keys.length === 0) {
      throw new BleParseError('JSONObject为空，可能ArrayBuffer没有正确传递');
    }
    keys.sort((a: string, b: string) => Number.parseInt(a, 10) - Number.parseInt(b, 10));
    numbers = keys.map((k: string) => record[k]);
  } else {
    throw new BleParseError('BUFFER类型value必须是数组/对象/字符串');
  }

  if (numbers.length === 0) {
    throw new BleParseError('BUFFER数据为空');
  }
  const out: Uint8Array = new Uint8Array(numbers.length);
  for (let i = 0; i < numbers.length; i++) {
    const item: Object = numbers[i];
    const n: number = typeof item === 'number'
      ? item as number
      : Number.parseInt(`${item}`.trim(), 10);
    if (Number.isNaN(n) || n < 0 || n > 255) {
      throw new BleParseError(`第${i}位值${item}超出Uint8范围（0-255）`);
    }
    out[i] = n;
  }
  return out;
}

export function utf8ToBytes(text: string): Uint8Array {
  const encoder: util.TextEncoder = new util.TextEncoder();
  return encoder.encodeInto(text);
}

/** HEX 串 -> 字节。长度必须为偶数,与 Android 一致。 */
export function hexToBytes(hex: string): Uint8Array {
  const clean: string = hex.replace(/\s+/g, '').toUpperCase();
  if (clean.length % 2 !== 0) {
    throw new BleParseError(`HEX字符串长度必须是偶数（当前：${clean.length}）`);
  }
  const len: number = clean.length / 2;
  const out: Uint8Array = new Uint8Array(len);
  for (let i = 0; i < len; i++) {
    const byte: number = Number.parseInt(clean.substring(i * 2, i * 2 + 2), 16);
    if (Number.isNaN(byte)) {
      throw new BleParseError('HEX格式错误');
    }
    out[i] = byte;
  }
  return out;
}

/** 字节 -> 大写 HEX 串。对齐 Android ByteUtils.bytes2HexStr。 */
export function bytesToHex(bytes: Uint8Array): string {
  let s: string = '';
  for (let i = 0; i < bytes.length; i++) {
    const h: string = bytes[i].toString(16).toUpperCase();
    s += h.length === 1 ? `0${h}` : h;
  }
  return s;
}
