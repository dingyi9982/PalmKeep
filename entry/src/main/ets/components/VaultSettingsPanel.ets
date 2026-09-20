import {
  COLOR_BORDER,
  COLOR_DANGER,
  COLOR_MUTED,
  COLOR_PRIMARY,
  COLOR_SURFACE,
  COLOR_SURFACE_2,
  COLOR_TEXT
} from './VaultTheme';

@Component
export struct VaultSettingsPanel {
  @Prop faceEnabled: boolean = false;
  @Prop faceAvailable: boolean = false;
  @Prop fingerprintEnabled: boolean = false;
  @Prop fingerprintAvailable: boolean = false;
  @Prop gestureEnabled: boolean = false;
  @Prop preferredUnlockLabel: string = '密码';
  @Prop autoLockLabel: string = '10 分钟';
  @Prop versionLabel: string = '';
  @Prop buildLabel: string = '';
  onToggleFace: () => void = (): void => {};
  onToggleFingerprint: () => void = (): void => {};
  onToggleGesture: () => void = (): void => {};
  onChoosePreferredUnlock: () => void = (): void => {};
  onChangePassword: () => void = (): void => {};
  onChooseAutoLock: () => void = (): void => {};
  onOpenGroupManager: () => void = (): void => {};
  onLockVault: () => void = (): void => {};

  build() {
    Scroll() {
      Column({ space: 16 }) {
        Column() {
          Text('快捷登录').fontSize(15).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT)
            .width('100%').padding(15)
          Row({ space: 12 }) {
            Stack() { Text('◉').fontSize(22).fontColor(COLOR_PRIMARY) }
              .width(44).height(44).borderRadius(14).backgroundColor('#183029')
            Column({ space: 3 }) {
              Text('人脸登录').fontSize(14).fontColor(COLOR_TEXT)
              Text(this.faceEnabled ? '已启用 · 由系统人脸验证' :
                (this.faceAvailable ? '未启用' : '设备未录入或不支持'))
                .fontSize(12).fontColor(COLOR_MUTED)
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            Button(this.faceEnabled ? '关闭' : '启用')
              .height(38).fontColor(this.faceEnabled ? COLOR_DANGER : COLOR_PRIMARY)
              .backgroundColor(COLOR_SURFACE_2).enabled(this.faceEnabled || this.faceAvailable)
              .onClick((): void => { this.onToggleFace(); })
          }.width('100%').padding(15).border({ width: { top: 1 }, color: COLOR_BORDER })
          Row({ space: 12 }) {
            Stack() { Text('◎').fontSize(22).fontColor(COLOR_PRIMARY) }
              .width(44).height(44).borderRadius(14).backgroundColor('#183029')
            Column({ space: 3 }) {
              Text('指纹登录').fontSize(14).fontColor(COLOR_TEXT)
              Text(this.fingerprintEnabled ? '已启用 · 由系统指纹验证' :
                (this.fingerprintAvailable ? '未启用' : '设备未录入或不支持'))
                .fontSize(12).fontColor(COLOR_MUTED)
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            Button(this.fingerprintEnabled ? '关闭' : '启用')
              .height(38).fontColor(this.fingerprintEnabled ? COLOR_DANGER : COLOR_PRIMARY)
              .backgroundColor(COLOR_SURFACE_2).enabled(this.fingerprintEnabled || this.fingerprintAvailable)
              .onClick((): void => { this.onToggleFingerprint(); })
          }.width('100%').padding(15).border({ width: { top: 1 }, color: COLOR_BORDER })
          Row({ space: 12 }) {
            Stack() {
              Grid() {
                ForEach([0, 1, 2, 3, 4, 5, 6, 7, 8], (): void => {
                  GridItem() { Circle({ width: 4, height: 4 }).fill(COLOR_PRIMARY) }
                })
              }
              .columnsTemplate('1fr 1fr 1fr').columnsGap(3).rowsGap(3).width(18).height(18)
            }.width(44).height(44).borderRadius(14).backgroundColor('#183029')
            Column({ space: 3 }) {
              Text('手势登录').fontSize(14).fontColor(COLOR_TEXT)
              Text(this.gestureEnabled ? '已启用 · 九宫格快捷解锁' : '未启用 · 至少连接 4 个点')
                .fontSize(12).fontColor(COLOR_MUTED)
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            Button(this.gestureEnabled ? '关闭' : '启用')
              .height(38).fontColor(this.gestureEnabled ? COLOR_DANGER : COLOR_PRIMARY)
              .backgroundColor(COLOR_SURFACE_2).onClick((): void => { this.onToggleGesture(); })
          }.width('100%').padding(15).border({ width: { top: 1 }, color: COLOR_BORDER })
          Row() {
            Column({ space: 3 }) {
              Text('首选登录方式').fontSize(14).fontColor(COLOR_TEXT)
              Text('打开应用时优先使用').fontSize(12).fontColor(COLOR_MUTED)
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            Text(this.preferredUnlockLabel).fontSize(13).fontColor(COLOR_PRIMARY)
            Text('›').fontSize(22).fontColor('#B2B8C2').margin({ left: 8 })
          }
          .width('100%').padding(15).border({ width: { top: 1 }, color: COLOR_BORDER })
          .onClick((): void => { this.onChoosePreferredUnlock(); })
        }
        .width('100%').backgroundColor(COLOR_SURFACE).borderRadius(18)
        .border({ width: 1, color: COLOR_BORDER })

        Column() {
          Text('密码与安全').fontSize(15).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT)
            .width('100%').padding(15)
          Row({ space: 12 }) {
            Stack() { Text('••').fontSize(18).fontWeight(FontWeight.Bold).fontColor(COLOR_PRIMARY) }
              .width(44).height(44).borderRadius(14).backgroundColor('#183029')
            Column({ space: 3 }) {
              Text('修改密码').fontSize(14).fontColor(COLOR_TEXT)
              Text('修改后快捷登录需要重新启用').fontSize(12).fontColor(COLOR_MUTED)
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            Text('›').fontSize(22).fontColor('#B2B8C2')
          }
          .width('100%').padding(15).border({ width: { top: 1 }, color: COLOR_BORDER })
          .onClick((): void => { this.onChangePassword(); })
          Row() {
            Column({ space: 3 }) {
              Text('自动锁定').fontSize(14).fontColor(COLOR_TEXT)
              Text('应用切换到后台后').fontSize(12).fontColor(COLOR_MUTED)
            }.alignItems(HorizontalAlign.Start)
            Blank()
            Text(this.autoLockLabel).fontSize(12).fontColor(COLOR_PRIMARY)
            Text('›').fontSize(22).fontColor('#B2B8C2').margin({ left: 8 })
          }
          .width('100%').padding(15).border({ width: { top: 1 }, color: COLOR_BORDER })
          .onClick((): void => { this.onChooseAutoLock(); })
        }
        .width('100%').backgroundColor(COLOR_SURFACE).borderRadius(18)
        .border({ width: 1, color: COLOR_BORDER })

        Row({ space: 12 }) {
          Stack() {
            Column({ space: 3 }) {
              ForEach([0, 1, 2], (): void => {
                Row({ space: 4 }) {
                  Circle({ width: 4, height: 4 }).fill(COLOR_PRIMARY)
                  Divider().width(13).strokeWidth(3).color(COLOR_PRIMARY).borderRadius(2)
                }
              })
            }
          }.width(44).height(44).borderRadius(14).backgroundColor('#183029')
          Column({ space: 3 }) {
            Text('分组管理').fontSize(15).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT)
            Text('查看和删除自定义分组').fontSize(11).fontColor(COLOR_MUTED)
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          Text('›').fontSize(22).fontColor('#B2B8C2')
        }
        .width('100%').padding(14).backgroundColor(COLOR_SURFACE).borderRadius(17)
        .border({ width: 1, color: COLOR_BORDER }).onClick((): void => { this.onOpenGroupManager(); })

        Column() {
          Row() {
            Text('版本与构建').fontSize(15).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT)
            Blank()
            Text(this.versionLabel).fontSize(12).fontColor(COLOR_MUTED)
          }.width('100%').padding({ left: 15, right: 15, top: 14, bottom: 12 })
          Row() {
            Text('构建标识').fontSize(13).fontColor(COLOR_MUTED)
            Blank()
            Text(this.buildLabel).fontSize(12).fontColor('#607B72').maxLines(1)
          }
          .width('100%').padding({ left: 15, right: 15, top: 12, bottom: 14 })
          .border({ width: { top: 1 }, color: COLOR_BORDER })
        }
        .width('100%').backgroundColor(COLOR_SURFACE).borderRadius(17)
        .border({ width: 1, color: COLOR_BORDER })
        Button('立即锁定保险库').width('100%').height(50).fontColor(COLOR_PRIMARY)
          .backgroundColor('#173128').borderRadius(14).onClick((): void => { this.onLockVault(); })
        Text('掌心密匣 PalmVault').fontSize(12).fontColor('#607B72')
          .width('100%').textAlign(TextAlign.Center)
      }
      .width('100%').padding({ left: 18, right: 18, top: 12, bottom: 105 })
    }.width('100%').height('100%')
  }
}
