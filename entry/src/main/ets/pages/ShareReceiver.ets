import common from '@ohos.app.ability.common';
import { logRecoverableError } from '../services/ErrorUtils';

@Entry
@Component
struct ShareReceiver {
  @StorageLink('vaultShareReceiveError') private errorMessage: string = '';

  private close(): void {
    const context = this.getUIContext().getHostContext() as common.UIExtensionContext;
    context.terminateSelf().catch((error: Error): void => {
      logRecoverableError('share-page-close', error);
    });
  }

  build() {
    Column({ space: 18 }) {
      Stack() {
        Circle()
          .width(68)
          .height(68)
          .fill('#EAF4EE')
        Text('⌄')
          .fontSize(36)
          .fontWeight(FontWeight.Bold)
          .fontColor('#2F6B4F')
          .translate({ y: -4 })
        Text('▣')
          .fontSize(22)
          .fontColor('#173C2B')
          .translate({ y: 13 })
      }
      .width(76)
      .height(76)

      Text(this.errorMessage.length > 0 ? '未能收进密匣' : '正在收进密匣')
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor('#173C2B')

      Text(this.errorMessage.length > 0 ? this.errorMessage :
        '内容只会先进入应用缓存，解锁后可确认名称、分组和备注。')
        .fontSize(14)
        .fontColor('#66756D')
        .textAlign(TextAlign.Center)
        .lineHeight(21)
        .width('82%')

      if (this.errorMessage.length > 0) {
        Button('返回')
          .width(128)
          .height(44)
          .fontColor('#FFFFFF')
          .fontWeight(FontWeight.Bold)
          .backgroundColor('#2F6B4F')
          .borderRadius(14)
          .margin({ top: 8 })
          .onClick((): void => { this.close(); })
      } else {
        LoadingProgress()
          .width(28)
          .height(28)
          .color('#2F6B4F')
          .margin({ top: 6 })
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#F7FAF8')
  }
}
