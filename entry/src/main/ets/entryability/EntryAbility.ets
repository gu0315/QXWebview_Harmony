import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'EntryAbility', 'onCreate');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'EntryAbility', 'loadContent failed: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'EntryAbility', 'loadContent succeeded');
      this.enableFullScreenLayout(windowStage);
    });
  }

  /**
   * 开启沉浸式布局,与 iOS / Android 对齐。
   * H5 的 HeaderNavBar 自己按 statusBarHeight 垫了状态栏占位,
   * 容器若再避让一次,顶部会多出一整个状态栏高度的空白。
   */
  private enableFullScreenLayout(windowStage: window.WindowStage): void {
    windowStage.getMainWindow().then((win: window.Window): void => {
      win.setWindowLayoutFullScreen(true).catch((e: Error): void => {
        hilog.error(DOMAIN, 'EntryAbility', 'setWindowLayoutFullScreen failed: %{public}s', e?.message ?? '');
      });
      // H5 头部是浅色底,状态栏文字用深色。
      win.setWindowSystemBarProperties({
        statusBarContentColor: '#000000'
      }).catch((e: Error): void => {
        hilog.error(DOMAIN, 'EntryAbility', 'setWindowSystemBarProperties failed: %{public}s', e?.message ?? '');
      });
    }).catch((e: Error): void => {
      hilog.error(DOMAIN, 'EntryAbility', 'getMainWindow failed: %{public}s', e?.message ?? '');
    });
  }
}
