import {
  COLOR_BORDER,
  COLOR_CHEVRON,
  COLOR_DARK_ACTION,
  COLOR_DARK_TINT,
  COLOR_DANGER,
  COLOR_MUTED,
  COLOR_PLACEHOLDER,
  COLOR_PRIMARY,
  COLOR_SURFACE,
  COLOR_SURFACE_2,
  COLOR_TEXT
} from './VaultTheme';
import { ACTION_CLOSE, ACTION_ENABLE } from './VaultCopy';

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
  @Prop backupStatusLabel: string = '尚未创建备份';
  @Prop backupChangeLabel: string = '当前资料尚未备份';
  @Prop backupNeedsUpdate: boolean = true;
  @Prop storageUsageLabel: string = '尚未检查';
  @Prop healthStatusLabel: string = '检查数据库、附件与搜索索引';
  @Prop healthBusy: boolean = false;
  onToggleFace: () => void = (): void => {};
  onToggleFingerprint: () => void = (): void => {};
  onToggleGesture: () => void = (): void => {};
  onChoosePreferredUnlock: () => void = (): void => {};
  onChangePassword: () => void = (): void => {};
  onChooseAutoLock: () => void = (): void => {};
  onOpenGroupManager: () => void = (): void => {};
  onCreateBackup: () => void = (): void => {};
  onRestoreBackup: () => void = (): void => {};
  onCheckDataHealth: () => void = (): void => {};
  onOpenPrivacyPolicy: () => void = (): void => {};
  onContactUs: () => void = (): void => {};
  onLockVault: () => void = (): void => {};

  build() {
    Scroll() {
      Column({ space: 16 }) {
        Column() {
          Text('快捷登录').fontSize(15).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT)
            .width('100%').padding(15)
          Row({ space: 12 }) {
            Stack() { Text('◉').fontSize(22).fontColor(COLOR_PRIMARY) }
              .width(44).height(44).borderRadius(14).backgroundColor(COLOR_DARK_TINT)
            Column({ space: 3 }) {
              Text('人脸登录').fontSize(14).fontColor(COLOR_TEXT)
              Text(this.faceEnabled ? '已启用 · 由系统人脸验证' :
                (this.faceAvailable ? '未启用' : '设备未录入或不支持'))
                .fontSize(12).fontColor(COLOR_MUTED)
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            Button(this.faceEnabled ? ACTION_CLOSE : ACTION_ENABLE)
              .height(38).fontColor(this.faceEnabled ? COLOR_DANGER : COLOR_PRIMARY)
              .backgroundColor(COLOR_SURFACE_2).enabled(this.faceEnabled || this.faceAvailable)
              .onClick((): void => { this.onToggleFace(); })
          }.width('100%').padding(15).border({ width: { top: 1 }, color: COLOR_BORDER })
          Row({ space: 12 }) {
            Stack() { Text('◎').fontSize(22).fontColor(COLOR_PRIMARY) }
              .width(44).height(44).borderRadius(14).backgroundColor(COLOR_DARK_TINT)
            Column({ space: 3 }) {
              Text('指纹登录').fontSize(14).fontColor(COLOR_TEXT)
              Text(this.fingerprintEnabled ? '已启用 · 由系统指纹验证' :
                (this.fingerprintAvailable ? '未启用' : '设备未录入或不支持'))
                .fontSize(12).fontColor(COLOR_MUTED)
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            Button(this.fingerprintEnabled ? ACTION_CLOSE : ACTION_ENABLE)
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
            }.width(44).height(44).borderRadius(14).backgroundColor(COLOR_DARK_TINT)
            Column({ space: 3 }) {
              Text('手势登录').fontSize(14).fontColor(COLOR_TEXT)
              Text(this.gestureEnabled ? '已启用 · 九宫格快捷解锁' : '未启用 · 至少连接 4 个点')
                .fontSize(12).fontColor(COLOR_MUTED)
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            Button(this.gestureEnabled ? ACTION_CLOSE : ACTION_ENABLE)
              .height(38).fontColor(this.gestureEnabled ? COLOR_DANGER : COLOR_PRIMARY)
              .backgroundColor(COLOR_SURFACE_2).onClick((): void => { this.onToggleGesture(); })
          }.width('100%').padding(15).border({ width: { top: 1 }, color: COLOR_BORDER })
          Row() {
            Column({ space: 3 }) {
              Text('首选登录方式').fontSize(14).fontColor(COLOR_TEXT)
              Text('打开应用时优先使用').fontSize(12).fontColor(COLOR_MUTED)
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            Text(this.preferredUnlockLabel).fontSize(13).fontColor(COLOR_PRIMARY)
            Text('›').fontSize(22).fontColor(COLOR_CHEVRON).margin({ left: 8 })
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
              .width(44).height(44).borderRadius(14).backgroundColor(COLOR_DARK_TINT)
            Column({ space: 3 }) {
              Text('修改密码').fontSize(14).fontColor(COLOR_TEXT)
              Text('修改后快捷登录需要重新启用').fontSize(12).fontColor(COLOR_MUTED)
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            Text('›').fontSize(22).fontColor(COLOR_CHEVRON)
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
            Text('›').fontSize(22).fontColor(COLOR_CHEVRON).margin({ left: 8 })
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
          }.width(44).height(44).borderRadius(14).backgroundColor(COLOR_DARK_TINT)
          Column({ space: 3 }) {
            Text('分组管理').fontSize(15).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT)
            Text('查看和删除自定义分组').fontSize(11).fontColor(COLOR_MUTED)
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          Text('›').fontSize(22).fontColor(COLOR_CHEVRON)
        }
        .width('100%').padding(14).backgroundColor(COLOR_SURFACE).borderRadius(17)
        .border({ width: 1, color: COLOR_BORDER }).onClick((): void => { this.onOpenGroupManager(); })

        Column() {
          Column({ space: 4 }) {
            Row() {
              Text('备份与恢复').fontSize(15).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT)
              Blank()
              Text(this.backupNeedsUpdate ? '待备份' : '已备份').fontSize(11)
                .fontColor(this.backupNeedsUpdate ? COLOR_DANGER : COLOR_PRIMARY)
            }.width('100%')
            Text(this.backupStatusLabel).fontSize(12).fontColor(COLOR_MUTED).width('100%')
            Text(this.backupChangeLabel).fontSize(12)
              .fontColor(this.backupNeedsUpdate ? COLOR_DANGER : COLOR_PRIMARY).width('100%')
          }.width('100%').padding(15).alignItems(HorizontalAlign.Start)
          Row({ space: 12 }) {
            Stack() { Text('↓').fontSize(22).fontWeight(FontWeight.Bold).fontColor(COLOR_PRIMARY) }
              .width(44).height(44).borderRadius(14).backgroundColor(COLOR_DARK_TINT)
            Column({ space: 3 }) {
              Text('创建备份').fontSize(14).fontColor(COLOR_TEXT)
              Text('导出密码加密的本地备份文件').fontSize(12).fontColor(COLOR_MUTED)
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            Text('›').fontSize(22).fontColor(COLOR_CHEVRON)
          }.width('100%').padding(15).border({ width: { top: 1 }, color: COLOR_BORDER })
          .onClick((): void => { this.onCreateBackup(); })
          Row({ space: 12 }) {
            Stack() { Text('↺').fontSize(21).fontWeight(FontWeight.Bold).fontColor(COLOR_PRIMARY) }
              .width(44).height(44).borderRadius(14).backgroundColor(COLOR_DARK_TINT)
            Column({ space: 3 }) {
              Text('从备份恢复').fontSize(14).fontColor(COLOR_TEXT)
              Text('默认合并恢复，不覆盖新增资料').fontSize(12).fontColor(COLOR_MUTED)
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            Text('›').fontSize(22).fontColor(COLOR_CHEVRON)
          }.width('100%').padding(15).border({ width: { top: 1 }, color: COLOR_BORDER })
          .onClick((): void => { this.onRestoreBackup(); })
        }
        .width('100%').backgroundColor(COLOR_SURFACE).borderRadius(18)
        .border({ width: 1, color: COLOR_BORDER })

        Column() {
          Column({ space: 4 }) {
            Row() {
              Text('存储与数据检查').fontSize(15).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT)
              Blank()
              Text(this.storageUsageLabel).fontSize(12).fontColor(COLOR_MUTED)
            }.width('100%')
            Text(this.healthStatusLabel).fontSize(12).fontColor(COLOR_MUTED).width('100%')
          }.width('100%').padding(15).alignItems(HorizontalAlign.Start)
          Row({ space: 12 }) {
            Stack() { Text('✓').fontSize(20).fontWeight(FontWeight.Bold).fontColor(COLOR_PRIMARY) }
              .width(44).height(44).borderRadius(14).backgroundColor(COLOR_DARK_TINT)
            Column({ space: 3 }) {
              Text(this.healthBusy ? '正在检查…' : '检查并安全修复').fontSize(14).fontColor(COLOR_TEXT)
              Text('不会删除缺失附件对应的资料').fontSize(12).fontColor(COLOR_MUTED)
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            Text('›').fontSize(22).fontColor(COLOR_CHEVRON)
          }.width('100%').padding(15).border({ width: { top: 1 }, color: COLOR_BORDER })
          .enabled(!this.healthBusy).onClick((): void => { this.onCheckDataHealth(); })
        }
        .width('100%').backgroundColor(COLOR_SURFACE).borderRadius(18)
        .border({ width: 1, color: COLOR_BORDER })

        Column() {
          Row() {
            Text('版本与构建').fontSize(15).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT)
            Blank()
            Text(this.versionLabel).fontSize(12).fontColor(COLOR_MUTED)
          }.width('100%').padding({ left: 15, right: 15, top: 14, bottom: 12 })
          Row() {
            Text('构建标识').fontSize(13).fontColor(COLOR_MUTED)
            Blank()
            Text(this.buildLabel).fontSize(12).fontColor(COLOR_PLACEHOLDER).maxLines(1)
          }
          .width('100%').padding({ left: 15, right: 15, top: 12, bottom: 14 })
          .border({ width: { top: 1 }, color: COLOR_BORDER })
        }
        .width('100%').backgroundColor(COLOR_SURFACE).borderRadius(17)
        .border({ width: 1, color: COLOR_BORDER })

        Column() {
          Text('关于与隐私').fontSize(15).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT)
            .width('100%').padding(15)
          Row({ space: 12 }) {
            Stack() { Text('◈').fontSize(21).fontColor(COLOR_PRIMARY) }
              .width(44).height(44).borderRadius(14).backgroundColor(COLOR_DARK_TINT)
            Column({ space: 3 }) {
              Text('隐私政策').fontSize(14).fontColor(COLOR_TEXT)
              Text('查看本地存储、相机、麦克风和文件访问说明').fontSize(12).fontColor(COLOR_MUTED)
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            Text('›').fontSize(22).fontColor(COLOR_CHEVRON)
          }
          .width('100%').padding(15).border({ width: { top: 1 }, color: COLOR_BORDER })
          .onClick((): void => { this.onOpenPrivacyPolicy(); })
          Row({ space: 12 }) {
            Stack() { Text('@').fontSize(20).fontWeight(FontWeight.Bold).fontColor(COLOR_PRIMARY) }
              .width(44).height(44).borderRadius(14).backgroundColor(COLOR_DARK_TINT)
            Column({ space: 3 }) {
              Text('联系我们').fontSize(14).fontColor(COLOR_TEXT)
              Text('有问题或建议，欢迎发送邮件至 dingyi9982@qq.com').fontSize(12).fontColor(COLOR_MUTED)
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            Text('›').fontSize(22).fontColor(COLOR_CHEVRON)
          }
          .width('100%').padding(15).border({ width: { top: 1 }, color: COLOR_BORDER })
          .onClick((): void => { this.onContactUs(); })
        }
        .width('100%').backgroundColor(COLOR_SURFACE).borderRadius(18)
        .border({ width: 1, color: COLOR_BORDER })

        Button('立即锁定密匣').width('100%').height(50).fontColor(COLOR_PRIMARY)
          .backgroundColor(COLOR_DARK_ACTION).borderRadius(14).onClick((): void => { this.onLockVault(); })
        Text('掌心密匣 PalmKeep').fontSize(12).fontColor(COLOR_PLACEHOLDER)
          .width('100%').textAlign(TextAlign.Center)
      }
      .width('100%').padding({ left: 18, right: 18, top: 12, bottom: 105 })
    }.width('100%').height('100%')
  }
}
