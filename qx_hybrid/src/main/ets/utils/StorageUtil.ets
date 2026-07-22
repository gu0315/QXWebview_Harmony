/*
 * H5 本地存储。对应 Android setStorage/getStorage/removeStorage/clearStorage。
 * 使用 @ohos.data.preferences 持久化。
 */

import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

const STORE_NAME: string = 'qx_hybrid_storage';

export class StorageUtil {
  private store: preferences.Preferences | null = null;

  async init(context: common.UIAbilityContext): Promise<void> {
    this.store = await preferences.getPreferences(context, STORE_NAME);
  }

  async set(key: string, value: string): Promise<void> {
    if (!this.store) {
      return;
    }
    await this.store.put(key, value);
    await this.store.flush();
  }

  async get(key: string): Promise<string> {
    if (!this.store) {
      return '';
    }
    const v: preferences.ValueType = await this.store.get(key, '');
    return typeof v === 'string' ? v as string : '';
  }

  async remove(key: string): Promise<void> {
    if (!this.store) {
      return;
    }
    await this.store.delete(key);
    await this.store.flush();
  }

  async clear(): Promise<void> {
    if (!this.store) {
      return;
    }
    await this.store.clear();
    await this.store.flush();
  }
}
