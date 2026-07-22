/*
 * 调试入口页(对标 Android/iOS 的调试启动页):填写 手机号 / VIN / MAC / URL,
 * 点「进入」跳到 WebView 页加载 H5。这三个值不是拼在 URL 上,而是通过 JSBridge——
 * H5 调 QXHostBridgePlugin 的 getUserInfo 时,由 WebPage 的宿主桥代理返回。
 */

import { router, promptAction } from '@kit.ArkUI';

interface LaunchParams {
  url: string;
  phone: string;
  vin: string;
  mac: string;
  token: string;
}

@Entry
@Component
struct Index {
  @State phone: string = '';
  @State vin: string = '';
  @State mac: string = '';
  @State url: string = 'https://test-fr-home-charge-web.cheryge.com';
  @State token: string = '';

  build() {
    Scroll() {
      Column() {
      Text('QX Hybrid 调试入口')
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .margin({ top: 40, bottom: 4 })
      Text('填写参数后进入 H5,VIN/MAC/手机号经 JSBridge 提供给页面')
        .fontSize(12)
        .fontColor('#999999')
        .margin({ bottom: 28 })
        .textAlign(TextAlign.Center)

      // 手机号
      Text('手机号').fontSize(14).fontColor('#666666').width('100%').margin({ bottom: 6 })
      TextInput({ placeholder: '请输入手机号', text: this.phone })
        .type(InputType.PhoneNumber)
        .fontSize(16).height(48).backgroundColor('#F5F6F8').borderRadius(10)
        .padding({ left: 12, right: 12 }).margin({ bottom: 16 })
        .onChange((v: string) => { this.phone = v })

      // VIN
      Text('VIN').fontSize(14).fontColor('#666666').width('100%').margin({ bottom: 6 })
      TextInput({ placeholder: '请输入车架号 VIN', text: this.vin })
        .fontSize(16).height(48).backgroundColor('#F5F6F8').borderRadius(10)
        .padding({ left: 12, right: 12 }).margin({ bottom: 16 })
        .onChange((v: string) => { this.vin = v })

      // MAC
      Text('MAC').fontSize(14).fontColor('#666666').width('100%').margin({ bottom: 6 })
      TextInput({ placeholder: '请输入设备蓝牙 MAC', text: this.mac })
        .fontSize(16).height(48).backgroundColor('#F5F6F8').borderRadius(10)
        .padding({ left: 12, right: 12 }).margin({ bottom: 16 })
        .onChange((v: string) => { this.mac = v })

      // URL
      Text('URL').fontSize(14).fontColor('#666666').width('100%').margin({ bottom: 6 })
      TextInput({ placeholder: 'H5 地址', text: this.url })
        .fontSize(16).height(48).backgroundColor('#F5F6F8').borderRadius(10)
        .padding({ left: 12, right: 12 }).margin({ bottom: 16 })
        .onChange((v: string) => { this.url = v })

      // Token(H5 用 token 非空判定"已登录";留空会导致反复拉起登录)
      Text('Token(可选,非空即视为已登录)').fontSize(14).fontColor('#666666').width('100%').margin({ bottom: 6 })
      TextInput({ placeholder: '填测试', text: this.token })
        .fontSize(16).height(48).backgroundColor('#F5F6F8').borderRadius(10)
        .padding({ left: 12, right: 12 }).margin({ bottom: 16 })
        .onChange((v: string) => { this.token = v })

      Button('进入')
        .width('100%').height(50).fontSize(17).fontColor(Color.White)
        .backgroundColor('#0A59F7').borderRadius(12).margin({ top: 12 })
        .onClick(() => this.enter())
      }
      .width('100%')
      .padding({ left: 24, right: 24, bottom: 40 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF')
  }

  private enter(): void {
    const targetUrl: string = this.url.trim();
    if (targetUrl.length === 0) {
      promptAction.showToast({ message: '请填写 URL' });
      return;
    }
    const params: LaunchParams = {
      url: targetUrl,
      phone: this.phone.trim(),
      vin: this.vin.trim(),
      mac: this.mac.trim(),
      token: this.token.trim()
    };
    router.pushUrl({ url: 'pages/WebPage', params: params })
      .catch((e: Object) => {
        promptAction.showToast({ message: `跳转失败: ${JSON.stringify(e)}` });
      });
  }
}
