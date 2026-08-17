/*
 * H5 本地存储(替代易丢失的 localStorage)。
 * 对应 Android QXBasePlugin 的 setStorage/getStorage/removeStorage/clearStorage
 * (Android 用 SharedPreferences "qx_bridge_storage",鸿蒙用 @ohos.data.preferences)。
 *
 * 值语义与 Android 一致:String / Number / Bool 原样落盘;
 * Array / Object 以 JSON 字符串落盘,读取时还原成相同结构。
 */

import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

/** H5 通过 Bridge 使用的原生 KV 存储命名空间(与 web 缓存 token 隔离)。 */
const STORE_NAME: string = 'qx_bridge_storage';
/** setWebCacheToken 专用命名空间,对应 Android PREFS_WEB_CACHE。 */
const CACHE_STORE_NAME: string = 'qx_web_cache';

export class StorageUtil {
  private store: preferences.Preferences | null = null;
  private cacheStore: preferences.Preferences | null = null;
  private ready: Promise<void> | null = null;

  init(context: common.UIAbilityContext): Promise<void> {
    this.ready = (async (): Promise<void> => {
      this.store = await preferences.getPreferences(context, STORE_NAME);
      this.cacheStore = await preferences.getPreferences(context, CACHE_STORE_NAME);
    })();
    return this.ready;
  }

  /** 等待 init 完成。插件方法可能在 init 之前被调用,统一在这里等一次。 */
  private async awaitReady(): Promise<void> {
    if (this.ready) {
      await this.ready;
    }
  }

  /**
   * 写入任意类型的值。对象 / 数组会被 JSON 序列化。
   * value 为 undefined/null 时等价于 remove(与 Android editor.remove 一致)。
   */
  async set(key: string, value: Object | undefined): Promise<void> {
    await this.awaitReady();
    if (!this.store) {
      return;
    }
    if (value === undefined || value === null) {
      await this.store.delete(key);
      await this.store.flush();
      return;
    }
    let stored: preferences.ValueType;
    if (typeof value === 'boolean') {
      stored = value as boolean;
    } else if (typeof value === 'number') {
      stored = value as number;
    } else if (typeof value === 'string') {
      stored = value as string;
    } else {
      // JSONObject / JSONArray 走 JSON 字符串,get 时按前缀还原。
      stored = JSON.stringify(value);
    }
    await this.store.put(key, stored);
    await this.store.flush();
  }

  /**
   * 读取值。key 不存在返回 undefined(H5 侧看到 value:null)。
   * 字符串若是合法 JSON 对象/数组则反序列化,否则原样返回 —— 对应 Android tryParseJson。
   */
  async get(key: string): Promise<Object | undefined> {
    await this.awaitReady();
    if (!this.store) {
      return undefined;
    }
    const has: boolean = await this.store.has(key);
    if (!has) {
      return undefined;
    }
    const v: preferences.ValueType = await this.store.get(key, '');
    if (typeof v === 'string') {
      return StorageUtil.tryParseJson(v as string);
    }
    return v as Object;
  }

  async remove(key: string): Promise<void> {
    await this.awaitReady();
    if (!this.store) {
      return;
    }
    await this.store.delete(key);
    await this.store.flush();
  }

  /** 仅清空 Bridge 自有命名空间,不影响 App 其它 preferences。 */
  async clear(): Promise<void> {
    await this.awaitReady();
    if (!this.store) {
      return;
    }
    await this.store.clear();
    await this.store.flush();
  }

  // ---------------- setWebCacheToken 专用 ----------------

  /** 读取上次记录的 web 缓存 token。 */
  async getCacheToken(): Promise<string> {
    await this.awaitReady();
    if (!this.cacheStore) {
      return '';
    }
    const v: preferences.ValueType = await this.cacheStore.get('cache_purge_token', '');
    return typeof v === 'string' ? v as string : '';
  }

  async setCacheToken(token: string): Promise<void> {
    await this.awaitReady();
    if (!this.cacheStore) {
      return;
    }
    await this.cacheStore.put('cache_purge_token', token);
    await this.cacheStore.flush();
  }

  // ---------------- 蓝牙权限状态 ----------------
  // 对应 Android 的 SharedPreferences "qx_ble_permissions"。鸿蒙 checkAccessTokenSync 无法区分
  // 「从未申请过」和「已拒绝」,靠这个标记还原 Android 的 authorization 三态。

  /** 是否已经向用户弹过一次蓝牙权限申请。 */
  hasRequestedBlePermission(): boolean {
    if (!this.cacheStore) {
      return false;
    }
    try {
      return this.cacheStore.getSync('ble_permission_requested', false) as boolean;
    } catch (e) {
      return false;
    }
  }

  async markBlePermissionRequested(): Promise<void> {
    await this.awaitReady();
    if (!this.cacheStore) {
      return;
    }
    await this.cacheStore.put('ble_permission_requested', true);
    await this.cacheStore.flush();
  }

  /** 字符串若是合法 JSON 对象/数组则反序列化,否则按字符串原样返回。 */
  private static tryParseJson(text: string): Object {
    const trimmed: string = text.trimStart();
    if (!trimmed.startsWith('{') && !trimmed.startsWith('[')) {
      return text;
    }
    try {
      return JSON.parse(text) as Object;
    } catch (e) {
      return text;
    }
  }
}
