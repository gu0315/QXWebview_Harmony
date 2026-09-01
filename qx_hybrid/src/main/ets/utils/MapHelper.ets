/*
 * 打开地图导航。对应 Android OpenMapAppUtils。
 *
 * 与 Android 一致的关键约定:
 *   - 入参 latitude / longitude 已是 **GCJ-02** 坐标,原样使用,不再做坐标转换;
 *   - 不指定 app 时弹「选择导航地图」面板让用户挑,对齐 Android showMapSelectSheet;
 *   - 候选顺序:高德 -> 百度 -> 腾讯 -> 华为花瓣;选中项未装则回退到它的网页版。
 *
 * ⚠️ scheme/host 必须以真机 `bm dump -n <包名>` 为准,**不能照抄 Android**:
 *   - 鸿蒙版高德是 `amapuri`(Android 为 `androidamap`);
 *   - 百度是 `baidumap://map/...`,host 写死为 map,探测时必须带上;
 *   - 腾讯鸿蒙版是 `com.tencent.mapohos`,只认 `qqmap://map/routeplan`,
 *     Android 那套 `qqmap://map/marker` 在鸿蒙版没有对应路由,会显示「网络异常」;
 *   - 华为花瓣只认标准 `geo:`,它自己的 `maps://navigation` / `petalmaps://` 都进不了导航;
 *   - 唤起一律锁 `bundleName`,不锁会被别的 App 接管。
 *
 * 关于 querySchemes:声明第三方 scheme 只影响 canOpenLink 的「是否已安装」检测,
 * startAbility 唤起本身不需要。所以集成方漏声明时,这里检测不到任何地图,
 * 面板会列出全部候选而不是静默跳网页 —— 用户选中后仍按真实 uri 唤起,
 * 唤起失败才落网页版。这样漏声明只是少了「置灰未安装项」的能力,功能不会废。
 */

import { common, Want, bundleManager } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { window, promptAction, ComponentContent } from '@kit.ArkUI';
import { BridgeCallback } from '../bridge/BridgeTypes';
import { QXBridgeError } from '../bridge/QXBridgeError';
import { QXUIContextHolder } from './UIContextHolder';

export type MapApp = 'amap' | 'baidu' | 'tencent' | 'petal' | 'system';

export interface MapTarget {
  /** GCJ-02 纬度 */
  latitude: number;
  /** GCJ-02 经度 */
  longitude: number;
  name: string;
  /** 指定地图 App;不传则按 Android 的顺序自动择优。 */
  app?: MapApp;
}

interface MapCandidate {
  app: MapApp;
  /** 选择面板上的显示名 */
  label: string;
  /** 需要在集成方 module.json5 的 querySchemes 里声明的 scheme(仅用于文档与日志) */
  scheme: string;
  /**
   * canOpenLink 的探测串。**不填就用 uri 本身**,这是默认且推荐的做法 ——
   * 实测把百度的探测串从完整 uri 缩成 `baidumap://map`(只少了 /navi 这段 path),
   * 装着的百度就检测不出来了,所以别自作聪明去截断。
   * 只有花瓣需要单独填:它用 geo: 唤起,而 geo: 没有 // 属 opaque URI,匹配不上 skill。
   */
  probe?: string;
  /**
   * 唤起时锁定的包名,对齐 Android 的 `Intent.setPackage(...)`。
   *
   * 不锁包名时,`qqmap://` 这类 scheme 可能被别的 App 接管,那个 App 打不开这个页面,
   * 用户看到的就是一张「网络异常」——地图压根没参与。鸿蒙包名与 Android **不同**,
   * 必须用真机 `bm dump -a` 查到的值。
   */
  bundleName?: string;
  /** 已安装时唤起的完整 uri */
  uri: string;
  /** 未安装时的网页兜底 */
  webUrl: string;
}

interface OpenMapResult {
  code: number;
  msg: string;
  uri: string;
}

/**
 * 选择面板的数据载体。@Builder 只接一个参数,回调也一并挂在这里。
 */
class MapPickerModel {
  labels: string[] = [];
  onPick: (index: number) => void = () => {};
  onCancel: () => void = () => {};
}

/** ActionSheet 配色,对齐 iOS 系统面板观感。 */
const SHEET_TINT: string = '#007AFF';
const SHEET_TITLE_COLOR: string = '#8A8A8E';
const SHEET_CARD_BG: string = '#F7F7F7';
const SHEET_DIVIDER: string = '#D6D6DA';
const SHEET_RADIUS: number = 14;

/**
 * 自绘的底部 ActionSheet。系统 promptAction.showActionMenu 样式不可控,
 * 这里自己画:标题 + 纵向选项 + 分离的取消按钮。
 *
 * ⚠️ 必须经 ComponentContent + wrapBuilder 使用,**不能**直接传给
 * openCustomDialog({ builder: () => mapPickerSheet(m) }):
 * @Builder 编译后会调 `this.observeComponentCreation2`,而那种写法下没有
 * ViewPU 实例作 this,首个 Column() 就抛
 * "Cannot read property observeComponentCreation2 of undefined",弹窗一闪即退。
 * ComponentContent 会自带渲染上下文,这个坑才绕得过去。
 */
@Builder
function mapPickerSheet(model: MapPickerModel) {
  Column() {
    // 选项卡片
    Column() {
      Text('选择导航地图')
        .fontSize(13)
        .fontColor(SHEET_TITLE_COLOR)
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding({ top: 18, bottom: 18 })

      // ForEach 每次迭代只能产出**一个**根组件,分隔线和选项必须包在同一个容器里,
      // 否则渲染期直接崩溃(表现为弹窗一闪即退)。
      ForEach(model.labels, (label: string, index: number) => {
        Column() {
          Divider().color(SHEET_DIVIDER).strokeWidth(0.5)
          Text(label)
            .fontSize(20)
            .fontColor(SHEET_TINT)
            .width('100%')
            .textAlign(TextAlign.Center)
            .padding({ top: 17, bottom: 17 })
        }
        .width('100%')
        .onClick(() => model.onPick(index))
      }, (label: string, index: number) => `${index}-${label}`)
    }
    .width('100%')
    .backgroundColor(SHEET_CARD_BG)
    .borderRadius(SHEET_RADIUS)
    .clip(true)

    // 取消按钮:与卡片留出间距,单独成块。
    Text('取消')
      .fontSize(20)
      .fontWeight(FontWeight.Medium)
      .fontColor(SHEET_TINT)
      .width('100%')
      .textAlign(TextAlign.Center)
      .padding({ top: 17, bottom: 17 })
      .backgroundColor(Color.White)
      .borderRadius(SHEET_RADIUS)
      .margin({ top: 8 })
      .onClick(() => model.onCancel())
  }
  .width('100%')
  // 弹窗容器的背景由这里决定(BaseDialogOptions 设不了),必须透明,
  // 否则卡片圆角外会露出一块白底方角。
  .backgroundColor(Color.Transparent)
  .padding({ left: 8, right: 8, bottom: 8 })
}

export class MapHelper {
  static open(context: common.UIAbilityContext, target: MapTarget, callback: BridgeCallback): void {
    const lat: number = target.latitude;
    const lng: number = target.longitude;
    const rawName: string = target.name ?? '';
    const enc: string = encodeURIComponent(rawName);

    const candidates: MapCandidate[] = [
      {
        // 鸿蒙版高德(com.amap.hmapp)注册的是 amapuri,**不是** Android 版的 androidamap ——
        // 真机 `bm dump -n com.amap.hmapp` 可见。照抄 Android 的 androidamap 会导致
        // canOpenLink 恒为 false(检测不到高德)且 startAbility 唤起失败落到网页版。
        // dev=0 表示传入的是 GCJ-02 坐标,t=0 为驾车,与 Android openAmap 语义一致。
        app: 'amap', label: '高德地图', scheme: 'amapuri://',
        bundleName: 'com.amap.hmapp',
        uri: `amapuri://route/plan?sourceApplication=app_name&dlat=${lat}&dlon=${lng}&dname=${enc}&dev=0&t=0`,
        webUrl: `https://uri.amap.com/navigation?to=${lng},${lat},${enc}&mode=car`
      },
      {
        app: 'baidu', label: '百度地图', scheme: 'baidumap://',
        bundleName: 'com.baidu.hmmap',
        uri: `baidumap://map/navi?location=${lat},${lng}&title=${enc}&coord_type=gcj02&src=ohos.jd.plugin`,
        webUrl: `https://api.map.baidu.com/direction?destination=latlng:${lat},${lng}|name:${enc}&mode=driving&output=html&coord_type=gcj02`
      },
      {
        // 鸿蒙版腾讯地图是 com.tencent.mapohos(Android 为 com.tencent.map)。
        //
        // 必须用 routeplan,**不能**照抄 Android 的 `qqmap://map/marker`:鸿蒙版只注册了
        // navigation / routePlan / search 三个 host 外加一条空 host(真机 bm dump 可见),
        // marker 靠空 host 能把 App 拉起来,但内部没有这个路由,页面加载失败 →「网络异常」。
        // routeplan 直接进路线规划页(起终点、方案、导航按钮都在),实测通过。
        //
        // to= 的名称**不能** encodeURIComponent —— 编码后会原样显示成 %E5%A5%87...,
        // 和花瓣一个毛病。
        //
        // 网页兜底也不能用 apis.map.qq.com/uri/v1/*:那是要 referer 备案的开放接口,
        // 拿占位值调会被服务端拒掉。map.qq.com/nav/drive 是普通网页版,不需要 key。
        app: 'tencent', label: '腾讯地图', scheme: 'qqmap://',
        bundleName: 'com.tencent.mapohos',
        uri: `qqmap://map/routeplan?type=drive&to=${rawName}&tocoord=${lat},${lng}&referer=qx_hybrid`,
        webUrl: `https://map.qq.com/nav/drive?to=${enc}&tocoord=${lat},${lng}`
      },
      {
        // 华为花瓣地图(com.huawei.hmos.maps.app),鸿蒙设备一般预装。
        //
        // 只有标准 geo: 能用,真机逐个试过:
        //   maps://navigation?daddr=   → App 自己提示「无法发起导航」
        //   maps://routes?daddr=       → 停在首页
        //   maps://navigation?destination= → 停在首页
        //   geo:lat,lng?q=lat,lng(名称) → 正确定位到目的地并给出「路线」入口 ✓
        //
        // 注意两点:
        //   1. 括号里的名称**不能** encodeURIComponent —— 花瓣不解码,会原样显示成 %E5%A5%87...;
        //   2. 花瓣停在 POI 卡片,要用户再点一次「路线」,比另外三家多一步。没找到能直接
        //      进导航的入口,先这样,总比没有强。
        // geo 只有花瓣注册(高德/百度都没有),不会弹系统选择器。
        app: 'petal', label: '花瓣地图', scheme: 'geo:',
        bundleName: 'com.huawei.hmos.maps.app',
        // 探测用 petalmaps://(花瓣注册了 host='' 的那条,匹配得上),唤起才用 geo:。
        probe: 'petalmaps://',
        uri: rawName.length > 0
          ? `geo:${lat},${lng}?q=${lat},${lng}(${rawName})`
          : `geo:${lat},${lng}?q=${lat},${lng}`,
        webUrl: `https://uri.amap.com/navigation?to=${lng},${lat},${enc}&mode=car`
      }
    ];

    // 指定了 app:跳过选择面板直接唤起它,供 H5 自建选择 UI 的场景使用。
    if (target.app && target.app !== 'system') {
      const picked: MapCandidate | undefined = candidates.find((c: MapCandidate) => c.app === target.app);
      if (!picked) {
        callback.onError(QXBridgeError.invalidParams(`不支持的地图应用: ${target.app}`));
        return;
      }
      MapHelper.launch(context, picked, callback);
      return;
    }

    // 未指定:弹面板让用户选,对齐 Android 的「选择地图导航」。
    //
    // 探测串必须带 host:鸿蒙 skill 匹配要 scheme + host 都对得上,而百度鸿蒙版把 host
    // 全写死成 map/hicarmap/cuid(真机 bm dump 可见),只给 `baidumap://` 匹配不到任何
    // skill,装了也判成没装。query 不参与匹配,所以带不带参数无所谓。
    // 所以默认直接拿唤起用的完整 uri 探测。花瓣是唯一例外:geo: 没有 // 属 opaque URI,
    // 匹配不上,只能用 petalmaps:// 探测(实测拿 geo: 探测会让花瓣从面板里消失)。
    const installed: MapCandidate[] = candidates.filter((c: MapCandidate) => MapHelper.canOpen(c.probe ?? c.uri));
    // 检测不到任何一个(多半是集成方漏声明 querySchemes)时列出全部,交给用户选。
    const list: MapCandidate[] = installed.length > 0 ? installed : candidates;
    MapHelper.log(`候选=${candidates.length} 已安装=${installed.length}` +
      `(${installed.map((c: MapCandidate) => c.app).join(',')}) 面板列出=${list.length}`);

    // 只有一个可选就不必打扰用户。
    if (list.length === 1) {
      MapHelper.log(`只有 ${list[0].app} 可选,跳过面板直接唤起`);
      MapHelper.launch(context, list[0], callback);
      return;
    }
    MapHelper.pick(context, list, callback);
  }

  /**
   * 弹「选择地图导航」面板。用户取消回 cancelled,与其它取消类能力的约定一致。
   *
   * UIContext 优先取 QXWebView 登记的那份(见 QXUIContextHolder)。
   * **不要**退回 `window.getLastWindow` 作为首选:宿主 App 常有多个窗口,
   * 它拿到的未必是当前前台那个,弹窗会挂到看不见的窗口上 —— 不报错、不回调,
   * 用户点了「毫无反应」,日志停在最后一条正常输出,极难定位(真机踩过)。
   */
  private static pick(context: common.UIAbilityContext, list: MapCandidate[],
    callback: BridgeCallback): void {
    const held: UIContext | null = QXUIContextHolder.get();
    if (held) {
      MapHelper.log('使用 QXWebView 登记的 UIContext 弹面板');
      MapHelper.showSheet(context, held, list, callback);
      return;
    }
    // 没有 QXWebView 在场(理论上不该发生)时才反查窗口。
    MapHelper.log('未登记 UIContext,回退 getLastWindow 反查');
    window.getLastWindow(context).then((win: window.Window): void => {
      let ui: UIContext;
      try {
        ui = win.getUIContext();
      } catch (err) {
        MapHelper.fallbackMenu(context, list, callback,
          `getUIContext 抛异常: ${(err as BusinessError).message}`);
        return;
      }
      MapHelper.showSheet(context, ui, list, callback);
    }).catch((e: BusinessError): void =>
      MapHelper.fallbackMenu(context, list, callback, `getLastWindow 失败: ${e.message}`));
  }

  /** 在给定 UIContext 上弹面板。 */
  private static showSheet(context: common.UIAbilityContext, ui: UIContext,
    list: MapCandidate[], callback: BridgeCallback): void {
    {
      // 选中/取消后都要自己关掉自定义弹窗,系统不会代劳。
      let content: ComponentContent<MapPickerModel> | null = null;
      const dismiss = (): void => {
        if (content) {
          ui.getPromptAction().closeCustomDialog(content).catch((): void => {});
          content = null;
        }
      };
      // 点选项、点取消、点遮罩三条路都会走到收尾,H5 的 callback 只能回一次。
      let settled: boolean = false;
      const finish = (fn: () => void): void => {
        if (settled) {
          return;
        }
        settled = true;
        fn();
      };

      const model: MapPickerModel = new MapPickerModel();
      model.labels = list.map((c: MapCandidate) => c.label);
      model.onPick = (index: number): void => finish((): void => {
        dismiss();
        const chosen: MapCandidate | undefined = list[index];
        if (!chosen) {
          MapHelper.log(`面板返回越界下标 ${index},按取消处理`);
          callback.onError(QXBridgeError.cancelled());
          return;
        }
        MapHelper.log(`用户选择 ${chosen.app}`);
        MapHelper.launch(context, chosen, callback);
      });
      model.onCancel = (): void => finish((): void => {
        dismiss();
        MapHelper.log('用户取消了地图选择');
        callback.onError(QXBridgeError.cancelled());
      });

      // BaseDialogOptions 没有 backgroundColor / cornerRadius(那是 CustomDialogOptions 的字段),
      // 走 ComponentContent 这条路时,底色和圆角只能在 builder 内部自己画。
      const options: promptAction.BaseDialogOptions = {
        alignment: DialogAlignment.Bottom,
        // 只用 autoCancel 让系统自己收走弹窗。不要用 onWillDismiss:
        // 注册它之后系统就不再自动关闭,得自己 close,和点选项那条路容易重入。
        autoCancel: true,
        // 点遮罩关掉时补一个 cancelled,否则 H5 的 Promise 永远悬着。
        // 选中/取消已经 settled,这里不会重复回调。
        onDidDisappear: (): void => finish((): void => {
          content = null;
          MapHelper.log('面板被遮罩关闭,按取消处理');
          callback.onError(QXBridgeError.cancelled());
        })
      };

      try {
        content = new ComponentContent(ui, wrapBuilder<[MapPickerModel]>(mapPickerSheet), model);
      } catch (err) {
        MapHelper.fallbackMenu(context, list, callback,
          `构建面板节点失败: ${(err as BusinessError).message}`);
        return;
      }
      MapHelper.log('打开面板');
      ui.getPromptAction().openCustomDialog(content, options)
        .catch((e: BusinessError): void => {
          content = null;
          MapHelper.fallbackMenu(context, list, callback, `openCustomDialog 失败: ${e.message}`);
        });
    }
  }

  /**
   * 自定义弹窗弹不出来时的兜底:退回系统 ActionSheet。
   * 系统面板样式不受控,但总好过「点了导航什么都没发生」。
   */
  private static fallbackMenu(context: common.UIAbilityContext, list: MapCandidate[],
    callback: BridgeCallback, why: string): void {
    MapHelper.log(`自定义弹窗不可用(${why}),退回系统 ActionSheet`);
    const options: promptAction.ActionMenuOptions = {
      title: '选择导航地图',
      buttons: MapHelper.menuButtons(list)
    };
    promptAction.showActionMenu(options)
      .then((res: promptAction.ActionMenuSuccessResponse): void => {
        const chosen: MapCandidate | undefined = list[res.index];
        if (!chosen) {
          callback.onError(QXBridgeError.cancelled());
          return;
        }
        MapHelper.log(`用户选择 ${chosen.app}`);
        MapHelper.launch(context, chosen, callback);
      })
      .catch((e: BusinessError): void => {
        // 两条路都弹不出来才回退直接唤起,否则导航整个不可用。
        MapHelper.log(`系统 ActionSheet 也失败(${e.message}),回退直接唤起 ${list[0].app}`);
        MapHelper.launch(context, list[0], callback);
      });
  }

  /**
   * showActionMenu 的 buttons 是定长元组,ArkTS 不允许把普通 Array 塞进去,
   * 只能按候选个数显式构造。候选 4 个(高德/百度/腾讯/花瓣),元组上限 6,够用。
   */
  private static menuButtons(list: MapCandidate[]):
    [promptAction.Button, promptAction.Button?, promptAction.Button?, promptAction.Button?] {
    const b = (i: number): promptAction.Button =>
      ({ text: list[i].label, color: '#182431' } as promptAction.Button);
    if (list.length >= 4) {
      return [b(0), b(1), b(2), b(3)];
    }
    if (list.length === 3) {
      return [b(0), b(1), b(2)];
    }
    if (list.length === 2) {
      return [b(0), b(1)];
    }
    return [b(0)];
  }

  private static log(msg: string): void {
    console.info(`[QXMap] ${msg}`);
  }

  private static canOpen(scheme: string): boolean {
    try {
      return bundleManager.canOpenLink(scheme);
    } catch (err) {
      // 未在 querySchemes 声明或 API 不支持时,视为未安装,交由网页兜底。
      return false;
    }
  }

  /**
   * 唤起选中的地图 App;失败则回退它的网页版,仍失败才回错误。
   *
   * 唤起时锁定 bundleName(对齐 Android 的 Intent.setPackage):不锁的话
   * `qqmap://` 这类 scheme 会被别的 App 接管,那个 App 打不开页面,用户看到的是
   * 「网络异常」,还以为是地图坏了。锁上之后,没装该地图就是干脆的唤起失败,直接落网页版。
   */
  private static launch(context: common.UIAbilityContext, candidate: MapCandidate,
    callback: BridgeCallback): void {
    const want: Want = candidate.bundleName
      ? { action: 'ohos.want.action.viewData', uri: candidate.uri, bundleName: candidate.bundleName }
      : { action: 'ohos.want.action.viewData', uri: candidate.uri };
    MapHelper.log(`唤起 ${candidate.app} bundle=${candidate.bundleName ?? '(未锁定)'} uri=${candidate.uri}`);
    context.startAbility(want)
      .then(() => {
        const r: OpenMapResult = { code: 0, msg: '打开地图成功', uri: candidate.uri };
        callback.onSuccess(r);
      })
      .catch((e: BusinessError) => {
        MapHelper.log(`唤起失败(${e.code} ${e.message}),回退网页版 ${candidate.webUrl}`);
        MapHelper.launchWeb(context, candidate.webUrl, callback);
      });
  }

  /** 网页兜底。**不能**带 bundleName —— 要交给浏览器,不是交给地图 App。 */
  private static launchWeb(context: common.UIAbilityContext, webUrl: string,
    callback: BridgeCallback): void {
    const want: Want = { action: 'ohos.want.action.viewData', uri: webUrl };
    context.startAbility(want)
      .then(() => {
        const r: OpenMapResult = { code: 0, msg: '打开地图成功', uri: webUrl };
        callback.onSuccess(r);
      })
      .catch((e: BusinessError) => {
        MapHelper.log(`网页版也打不开: ${e.code} ${e.message}`);
        callback.onError(QXBridgeError.unsupported(`打开地图失败: ${e.message}`));
      });
  }
}
