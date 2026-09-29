import {
  COLOR_BG, COLOR_BORDER, COLOR_MUTED, COLOR_PRIMARY, COLOR_SCRIM, COLOR_SURFACE, COLOR_SURFACE_2,
  COLOR_TEXT
} from './VaultTheme';

@Component
export struct VaultBackupReminderDialog {
  @Prop hasPreviousBackup: boolean = false;
  onLater: () => void = (): void => {};
  onBackupNow: () => void = (): void => {};

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column({ space: 14 }) {
        Text('备份提醒').fontSize(19).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT)
          .width('100%')
        Text(this.hasPreviousBackup ? '距离上次备份已到设定周期，资料有未备份的更改。' :
          '当前资料尚未备份。建议保存一份加密备份文件。')
          .fontSize(14).fontColor(COLOR_MUTED).width('100%')
        Row({ space: 10 }) {
          Button('稍后').layoutWeight(1).height(46).fontColor(COLOR_MUTED)
            .backgroundColor(COLOR_SURFACE_2).borderRadius(12)
            .onClick((): void => { this.onLater(); })
          Button('立即备份').layoutWeight(1).height(46).fontColor(COLOR_BG)
            .backgroundColor(COLOR_PRIMARY).borderRadius(12)
            .onClick((): void => { this.onBackupNow(); })
        }.width('100%')
      }
      .width('88%').padding(18).backgroundColor(COLOR_SURFACE).borderRadius(22)
      .border({ width: 1, color: COLOR_BORDER })
    }.width('100%').height('100%').backgroundColor(COLOR_SCRIM)
  }
}
