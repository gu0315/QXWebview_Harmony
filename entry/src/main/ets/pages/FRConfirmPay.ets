/*
 * 模拟的 FR 确认支付页(宿主 Demo 用)。
 * H5 通过 app://openFRConfirmPay 拉起,页面结束时把结果回传给 FRConfirmPayResultCenter:
 * 「确认支付」-> code 0,「取消」/ 返回 -> code 1。
 * 真实宿主替换成自己的收银台即可,只要保证结束时回传同样的 code / message / orderSeq。
 */

import { router } from '@kit.ArkUI';
import { FRConfirmPayResultCenter } from '../common/FRConfirmPayResultCenter';

/** 与 iOS / H5 约定一致的回调 code */
const FR_CODE_SUCCESS: string = '0';
const FR_CODE_CANCEL: string = '1';
/** 模拟支付耗时(ms) */
const MOCK_PAY_DELAY: number = 1500;

interface FRConfirmPayParams {
  orderSeq: string;
  stationName: string;
  powerConnectorId: string;
}

@Entry
@Component
struct FRConfirmPay {
  @State orderSeq: string = '';
  @State stationName: string = '';
  @State powerConnectorId: string = '';
  @State statusText: string = '';
  @State paying: boolean = false;
  /** 结果是否已回传,避免 aboutToDisappear 兜底时重复回调 */
  private delivered: boolean = false;
  private timerId: number = -1;

  aboutToAppear(): void {
    const p: FRConfirmPayParams = router.getParams() as FRConfirmPayParams;
    if (p) {
      this.orderSeq = p.orderSeq ?? '';
      this.stationName = p.stationName ?? '';
      this.powerConnectorId = p.powerConnectorId ?? '';
    }
  }

  aboutToDisappear(): void {
    if (this.timerId !== -1) {
      clearTimeout(this.timerId);
      this.timerId = -1;
    }
    // 兜底:返回键 / 被系统回收等未主动回传时,按用户取消处理,避免 H5 一直等
    this.deliver(FR_CODE_CANCEL, '用户取消支付');
  }

  private deliver(code: string, message: string): void {
    if (this.delivered) {
      return;
    }
    this.delivered = true;
    FRConfirmPayResultCenter.deliver(code, message, this.orderSeq);
  }

  private display(value: string): string {
    return value.length > 0 ? value : '-';
  }

  private handlePay(): void {
    this.paying = true;
    this.statusText = '支付处理中...';
    // 模拟支付耗时,完成后回调成功并关闭页面
    this.timerId = setTimeout((): void => {
      this.timerId = -1;
      this.statusText = '支付成功';
      this.deliver(FR_CODE_SUCCESS, 'success');
      router.back();
    }, MOCK_PAY_DELAY);
  }

  private handleCancel(): void {
    this.deliver(FR_CODE_CANCEL, '用户取消支付');
    router.back();
  }

  build() {
    Column({ space: 20 }) {
      Text('确认支付')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .margin({ bottom: 12 })

      Column({ space: 12 }) {
        Text(`电站名称：${this.display(this.stationName)}`).fontSize(16)
        Text(`充电桩编号：${this.display(this.powerConnectorId)}`).fontSize(16)
        Text(`订单号：${this.display(this.orderSeq)}`).fontSize(16)
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')

      if (this.statusText.length > 0) {
        Text(this.statusText)
          .fontSize(15)
          .fontColor('#236982')
      }

      Button('确认支付')
        .width('100%')
        .enabled(!this.paying)
        .onClick((): void => this.handlePay())

      Button('取消')
        .width('100%')
        .backgroundColor('#EEEEEE')
        .fontColor('#333333')
        .enabled(!this.paying)
        .onClick((): void => this.handleCancel())
    }
    .width('100%')
    .height('100%')
    .padding(24)
    .justifyContent(FlexAlign.Center)
  }
}
