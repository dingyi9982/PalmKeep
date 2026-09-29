import {
  COLOR_BG, COLOR_BORDER, COLOR_MUTED, COLOR_PRIMARY, COLOR_SCRIM, COLOR_SURFACE, COLOR_TEXT
} from './VaultTheme';

@Component
export struct VaultRestoreLoginNotice {
  onConfirm: () => void = (): void => {};

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column({ space: 14 }) {
        Text('备份恢复成功').fontSize(19).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT)
          .width('100%')
        Text('今后打开掌心密匣，请使用刚才输入的备份文件密码登录。')
          .fontSize(14).fontColor(COLOR_TEXT).width('100%')
        Text('请记住这个密码。').fontSize(12).fontColor(COLOR_MUTED).width('100%')
        Button('我知道了').width('100%').height(46).fontColor(COLOR_BG)
          .backgroundColor(COLOR_PRIMARY).borderRadius(12)
          .onClick((): void => { this.onConfirm(); })
      }
      .width('88%').padding(18).backgroundColor(COLOR_SURFACE).borderRadius(22)
      .border({ width: 1, color: COLOR_BORDER })
    }.width('100%').height('100%').backgroundColor(COLOR_SCRIM)
  }
}
