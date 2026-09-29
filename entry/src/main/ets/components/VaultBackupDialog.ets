import {
  COLOR_BG,
  COLOR_BORDER,
  COLOR_DANGER,
  COLOR_MUTED,
  COLOR_PLACEHOLDER,
  COLOR_PRIMARY,
  COLOR_PRIMARY_TINT,
  COLOR_SCRIM,
  COLOR_SURFACE,
  COLOR_SURFACE_2,
  COLOR_TEXT
} from './VaultTheme';
@Component
export struct VaultBackupDialog {
  @Link password: string;
  @Prop action: string = 'create';
  @Prop freshInstall: boolean = false;
  @Prop stage: string = 'password';
  @Prop busy: boolean = false;
  @Prop errorMessage: string = '';
  @Prop progressText: string = '';
  @Prop progressValue: number = 0;
  @Prop backupDateText: string = '';
  @Prop itemCount: number = 0;
  @Prop attachmentCount: number = 0;
  @Prop attachmentSizeText: string = '';
  @Prop addedCount: number = 0;
  @Prop updatedCount: number = 0;
  @Prop retainedCount: number = 0;
  @Prop newerCount: number = 0;
  @Prop conflictCount: number = 0;
  @Prop unchangedCount: number = 0;
  @Prop deletedCount: number = 0;
  onClose: () => void = (): void => {};
  onPrimary: () => void = (): void => {};

  private restorePreviewText(): string {
    const parts: string[] = [];
    if (this.addedCount > 0) { parts.push(`新增 ${this.addedCount} 项`); }
    if (this.updatedCount > 0) { parts.push(`恢复或更新 ${this.updatedCount} 项`); }
    if (this.retainedCount > 0) { parts.push(`保留当前新增 ${this.retainedCount} 项`); }
    if (this.newerCount > 0) { parts.push(`保留本机较新版本 ${this.newerCount} 项`); }
    if (this.conflictCount > 0) { parts.push(`冲突副本 ${this.conflictCount} 项`); }
    if (this.unchangedCount > 0) { parts.push(`无需变更 ${this.unchangedCount} 项`); }
    if (this.deletedCount > 0) { parts.push(`同步删除 ${this.deletedCount} 项`); }
    return parts.length > 0 ? `预计${parts.join('，')}` : '当前资料与备份一致，无需变更';
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column({ space: 12 }) {
        Row() {
          Text(this.action === 'create' ? '创建加密备份' : '从备份恢复')
            .fontSize(19).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT)
          Blank()
          Button('×').width(34).height(34).fontSize(22).fontColor(COLOR_MUTED)
            .backgroundColor(COLOR_SURFACE_2).borderRadius(17).enabled(!this.busy)
            .onClick((): void => { this.onClose(); })
        }.width('100%')

        if (this.stage === 'password') {
          Text(this.action === 'create' ? '使用当前密匣密码加密备份。' :
            (this.freshInstall ? '请输入备份文件密码。恢复成功后，今后打开应用也使用这个密码登录。' :
              '请输入创建该备份时使用的密匣密码。'))
            .fontSize(13).fontColor(COLOR_MUTED).width('100%')
          TextInput({ placeholder: '密码', text: this.password })
            .type(InputType.Password).height(48).fontColor(COLOR_TEXT).placeholderColor(COLOR_PLACEHOLDER)
            .backgroundColor(COLOR_SURFACE_2).borderRadius(12).enabled(!this.busy)
            .onChange((value: string): void => { this.password = value; })
            .onSubmit((): void => { this.onPrimary(); })
        } else if (this.stage === 'preview') {
          Column({ space: 6 }) {
            Row() { Text('备份时间').fontSize(12).fontColor(COLOR_MUTED); Blank();
              Text(this.backupDateText).fontSize(12).fontColor(COLOR_TEXT) }.width('100%')
            Row() { Text('资料').fontSize(12).fontColor(COLOR_MUTED); Blank();
              Text(`${this.itemCount} 项`).fontSize(12).fontColor(COLOR_TEXT) }.width('100%')
            Row() { Text('附件').fontSize(12).fontColor(COLOR_MUTED); Blank();
              Text(`${this.attachmentCount} 个 · ${this.attachmentSizeText}`).fontSize(12).fontColor(COLOR_TEXT) }.width('100%')
          }.width('100%').padding(12).backgroundColor(COLOR_SURFACE_2).borderRadius(12)
          Text('将使用合并恢复：保留当前新增的资料，同一资料以更新的版本为准。')
            .fontSize(12).fontColor(COLOR_TEXT).width('100%').padding(10)
            .backgroundColor(COLOR_PRIMARY_TINT).borderRadius(10)
          Text(this.restorePreviewText())
            .fontSize(12).fontColor(COLOR_MUTED).width('100%')
          if (this.freshInstall) {
            Text('恢复后，本机密匣的登录密码就是这份备份文件的密码。')
              .fontSize(12).fontColor(COLOR_PRIMARY).width('100%')
          }
        } else {
          Column({ space: 10 }) {
            LoadingProgress().width(32).height(32).color(COLOR_PRIMARY)
            Text(this.progressText).fontSize(13).fontColor(COLOR_TEXT)
            Progress({ value: this.progressValue, total: 100, type: ProgressType.Linear })
              .width('100%').height(5).color(COLOR_PRIMARY).backgroundColor(COLOR_SURFACE_2)
          }.width('100%').padding({ top: 12, bottom: 12 })
        }
        if (this.errorMessage.length > 0) {
          Text(this.errorMessage).fontSize(12).fontColor(COLOR_DANGER).width('100%')
        }
        if (this.stage !== 'running') {
          Row({ space: 10 }) {
            Button('取消').layoutWeight(1).height(46).fontColor(COLOR_MUTED)
              .backgroundColor(COLOR_SURFACE_2).borderRadius(12).enabled(!this.busy)
              .onClick((): void => { this.onClose(); })
            Button(this.stage === 'preview' ? '开始恢复' : (this.action === 'create' ? '选择保存位置' : '读取备份'))
              .layoutWeight(1).height(46).fontColor(COLOR_BG).backgroundColor(COLOR_PRIMARY)
              .borderRadius(12).enabled(!this.busy && this.password.length > 0)
              .onClick((): void => { this.onPrimary(); })
          }.width('100%')
        }
      }
      .width('88%').padding(18).backgroundColor(COLOR_SURFACE).borderRadius(22)
      .border({ width: 1, color: COLOR_BORDER })
    }.width('100%').height('100%').backgroundColor(COLOR_SCRIM)
  }
}
