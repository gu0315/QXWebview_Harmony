/*
 * QXWebPage —— SDK 自带的命名路由承载页,让宿主「零承载页代码」接入。
 *
 * 为什么需要:ArkUI 的 onBackPress()/onPageShow()/onPageHide() 只在 @Entry 组件上触发,
 * 嵌套的 QXWebView 收不到。若宿主自己写承载页(嵌入式接入),就必须逐一转调这几个方法,
 * 漏写系统返回键就会一次性退掉整个 WebView。本页把这些都做进 SDK 的 @Entry 里,
 * 宿主只需:① 启动时 QXWebRegistry.configure(...) 登记业务能力一次;
 *          ② 用 router.pushNamedRoute({ name: 'QXWebPage', params: { url } }) 打开。
 *
 * 命名路由注册:本页经 Index.ets 的 `export { QXWebPage }` 触发加载注册,宿主 import 'qx-hybrid'
 * 的任意符号即可使 'QXWebPage' 路由可用,无需在宿主 main_pages.json 里登记。
 */

import { router } from '@kit.ArkUI';
import { QXWebView } from '../components/QXWebView';
import { QXWebViewController } from '../components/QXWebViewController';
import { QXHostDelegate, OpenWebViewOptions, QXNavigationBarStyle,
  QXHostBridgeDelegate } from '../bridge/HostDelegate';
import { QXWebRegistry, QXWebPageConfig } from './QXWebRegistry';

/** 命名路由名。宿主 router.pushNamedRoute({ name: QX_WEB_PAGE_ROUTE_NAME }) 使用。 */
export const QX_WEB_PAGE_ROUTE_NAME: string = 'QXWebPage';

/** QXWebPage 的路由入参。 */
interface QXWebPageParams {
  /** 要加载的 H5 地址。 */
  url: string;
  /** forResult 打开时的回传 id;原样透传给 QXWebView.pageId。 */
  pageId?: string;
}

/**
 * 默认宿主页面代理:关闭=router.back;打开新页=再次 pushNamedRoute 到本页。
 * 与业务无关的容器行为都在这里,宿主无需实现 QXHostDelegate。
 */
class DefaultHostDelegate implements QXHostDelegate {
  onCloseWebView(): void {
    router.back();
  }

  onCloseWithResult(result: Object): void {
    // 回传由 SDK 内部 PageResultCenter 完成,这里只负责关页。
    router.back();
  }

  onOpenWebView(options: OpenWebViewOptions): void {
    const params: QXWebPageParams = {
      url: options.url,
      pageId: options.forResult ? options.pageId : undefined
    };
    router.pushNamedRoute({ name: QX_WEB_PAGE_ROUTE_NAME, params });
  }

  onSetNavigationBarStyle(style: QXNavigationBarStyle): void {
    // H5 自绘导航栏,原生侧无需处理。
  }

  onFirstRender(): void {
    // 无原生首屏 loading,无需处理。
  }
}

@Entry({ routeName: 'QXWebPage' })
@Component
export struct QXWebPage {
  @State private targetUrl: string = '';
  @State private pageId: string = '';
  private delegate: QXHostDelegate = new DefaultHostDelegate();
  private hostBridgeDelegate: QXHostBridgeDelegate | null = null;
  private webController: QXWebViewController = new QXWebViewController();

  aboutToAppear(): void {
    const p: QXWebPageParams = router.getParams() as QXWebPageParams;
    if (p) {
      this.targetUrl = p.url ?? '';
      this.pageId = p.pageId ?? '';
    }
    // 业务桥代理由宿主一次性登记,这里按页取。
    this.hostBridgeDelegate = QXWebRegistry.resolveHostBridgeDelegate();
  }

  // 生命周期 / 系统返回键:只在 @Entry 触发,统一转调 controller —— 这正是本页存在的意义。
  onPageShow(): void {
    this.webController.onPageShow();
  }

  onPageHide(): void {
    this.webController.onPageHide();
  }

  onBackPress(): boolean {
    return this.webController.onBackPress();
  }

  build() {
    Column() {
      QXWebView({
        url: this.targetUrl,
        delegate: this.delegate,
        hostBridgeDelegate: this.hostBridgeDelegate,
        scanHandler: QXWebRegistry.getConfig().scanHandler,
        pageId: this.pageId.length > 0 ? this.pageId : undefined,
        webController: this.webController,
        immersive: QXWebRegistry.getConfig().immersive ?? true,
        statusBarContentColor: QXWebRegistry.getConfig().statusBarContentColor ?? '#000000'
      })
    }
    .width('100%')
    .height('100%')
  }
}
