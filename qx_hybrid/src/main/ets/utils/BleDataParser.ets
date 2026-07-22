/*
 * 蓝牙数据编解码。对应 Android utils/BleDataParser.kt。
 * H5 与原生之间的特征值以字符串传输,format 指明编码:BASE64 / BUFFER(hex) / TEXT。
 */

import { util } from '@kit.ArkTS';

export type BleFormat = 'BASE64' | 'BUFFER' | 'TEXT';

const base64Helper: util.Base64Helper = new util.Base64Helper();

/** H5 字符串 -> 原生字节。 */
export function decodeToBytes(value: string, format: BleFormat): Uint8Array {
  switch (format) {
    case 'BASE64':
      return base64Helper.decodeSync(value);
    case 'TEXT': {
      const encoder: util.TextEncoder = new util.TextEncoder();
      return encoder.encodeInto(value);
    }
    case 'BUFFER':
    default:
      return hexToBytes(value);
  }
}

/** 原生字节 -> H5 字符串。 */
export function encodeFromBytes(bytes: Uint8Array, format: BleFormat): string {
  switch (format) {
    case 'BASE64':
      return base64Helper.encodeToStringSync(bytes);
    case 'TEXT': {
      const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
      return decoder.decodeToString(bytes);
    }
    case 'BUFFER':
    default:
      return bytesToHex(bytes);
  }
}

export function hexToBytes(hex: string): Uint8Array {
  const clean: string = hex.replace(/\s+/g, '');
  const len: number = Math.floor(clean.length / 2);
  const out: Uint8Array = new Uint8Array(len);
  for (let i = 0; i < len; i++) {
    out[i] = parseInt(clean.substr(i * 2, 2), 16);
  }
  return out;
}

export function bytesToHex(bytes: Uint8Array): string {
  let s: string = '';
  for (let i = 0; i < bytes.length; i++) {
    const h: string = bytes[i].toString(16);
    s += h.length === 1 ? '0' + h : h;
  }
  return s;
}
