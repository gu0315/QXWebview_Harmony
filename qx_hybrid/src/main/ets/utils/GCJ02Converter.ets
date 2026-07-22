/*
 * WGS-84 <-> GCJ-02 坐标转换。对应 Android utils/GCJ02Converter.kt。
 * 鸿蒙 geoLocationManager 默认返回 WGS-84,H5 地图(高德等)使用 GCJ-02,需转换。
 */

const PI: number = 3.1415926535897932384626;
const A: number = 6378245.0;            // 长半轴
const EE: number = 0.00669342162296594323; // 偏心率平方

function outOfChina(lat: number, lng: number): boolean {
  return !(lng > 73.66 && lng < 135.05 && lat > 3.86 && lat < 53.55);
}

function transformLat(x: number, y: number): number {
  let ret: number = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * Math.sqrt(Math.abs(x));
  ret += (20.0 * Math.sin(6.0 * x * PI) + 20.0 * Math.sin(2.0 * x * PI)) * 2.0 / 3.0;
  ret += (20.0 * Math.sin(y * PI) + 40.0 * Math.sin(y / 3.0 * PI)) * 2.0 / 3.0;
  ret += (160.0 * Math.sin(y / 12.0 * PI) + 320 * Math.sin(y * PI / 30.0)) * 2.0 / 3.0;
  return ret;
}

function transformLng(x: number, y: number): number {
  let ret: number = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * Math.sqrt(Math.abs(x));
  ret += (20.0 * Math.sin(6.0 * x * PI) + 20.0 * Math.sin(2.0 * x * PI)) * 2.0 / 3.0;
  ret += (20.0 * Math.sin(x * PI) + 40.0 * Math.sin(x / 3.0 * PI)) * 2.0 / 3.0;
  ret += (150.0 * Math.sin(x / 12.0 * PI) + 300.0 * Math.sin(x / 30.0 * PI)) * 2.0 / 3.0;
  return ret;
}

export interface LatLng {
  latitude: number;
  longitude: number;
}

/** WGS-84 -> GCJ-02(火星坐标)。 */
export function wgs84ToGcj02(lat: number, lng: number): LatLng {
  if (outOfChina(lat, lng)) {
    return { latitude: lat, longitude: lng };
  }
  let dLat: number = transformLat(lng - 105.0, lat - 35.0);
  let dLng: number = transformLng(lng - 105.0, lat - 35.0);
  const radLat: number = lat / 180.0 * PI;
  let magic: number = Math.sin(radLat);
  magic = 1 - EE * magic * magic;
  const sqrtMagic: number = Math.sqrt(magic);
  dLat = (dLat * 180.0) / ((A * (1 - EE)) / (magic * sqrtMagic) * PI);
  dLng = (dLng * 180.0) / (A / sqrtMagic * Math.cos(radLat) * PI);
  return { latitude: lat + dLat, longitude: lng + dLng };
}
