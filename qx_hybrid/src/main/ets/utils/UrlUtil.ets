/*
 * URL 拼参。对应 Android QXBasePlugin.appendQueryParams。
 * openWebView / openUrl 的 query 字段会经此拼到目标 url 上,保留原有 query 并做百分号编码。
 */

export class UrlUtil {
  /**
   * 把 JSON 参数拼到已有 URL 的 query 上。
   * 与 Android 行为一致:值为 null/undefined 时跳过;拼接失败时原样返回。
   */
  static appendQueryParams(urlString: string, params: object | undefined): string {
    if (!params) {
      return urlString;
    }
    const record: Record<string, Object> = params as Record<string, Object>;
    const keys: string[] = Object.keys(record);
    if (keys.length === 0) {
      return urlString;
    }
    try {
      // hash(#/pages/a/b) 必须留在最后,query 插到 hash 之前,否则 uni-app 路由取不到参数。
      const hashIndex: number = urlString.indexOf('#');
      const head: string = hashIndex >= 0 ? urlString.substring(0, hashIndex) : urlString;
      const hash: string = hashIndex >= 0 ? urlString.substring(hashIndex) : '';

      let pairs: string = '';
      keys.forEach((key: string) => {
        const value: Object = record[key];
        if (value === undefined || value === null) {
          return;
        }
        const text: string = typeof value === 'string' ? value as string : JSON.stringify(value);
        pairs += `${pairs.length > 0 ? '&' : ''}${encodeURIComponent(key)}=${encodeURIComponent(text)}`;
      });
      if (pairs.length === 0) {
        return urlString;
      }
      const separator: string = head.indexOf('?') >= 0 ? '&' : '?';
      return `${head}${separator}${pairs}${hash}`;
    } catch (e) {
      return urlString;
    }
  }
}
