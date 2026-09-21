import { VaultAttachmentGallery } from './VaultAttachmentGallery';
import { VaultFileGallery } from './VaultFileGallery';
import {
  VaultDialogHeader, VaultPasswordEyeButton, VaultScreenshotProtectionHint
} from './VaultCommonComponents';
import {
  COLOR_BG, COLOR_DANGER, COLOR_DANGER_TINT, COLOR_MUTED, COLOR_PRIMARY, COLOR_PRIMARY_TINT,
  COLOR_SCRIM, COLOR_SURFACE, COLOR_SURFACE_2, COLOR_TEXT
} from './VaultTheme';
import { itemTypeLabel, VaultItemType, VaultTrashEntry } from '../models/VaultModels';

@Component
export struct VaultTrashDetailDialog {
  entry: VaultTrashEntry = {
    item: {
      id: '',
      type: VaultItemType.Note,
      groupId: 0,
      title: '',
      username: '',
      password: '',
      notes: '',
      ocrText: '',
      createdAt: 0,
      updatedAt: 0,
      deletedAt: 0
    },
    originalGroupName: ''
  };
  deletedTimeText: string = '';
  @Link revealPassword: boolean;
  onClose: () => void = (): void => {};
  onRestore: () => void = (): void => {};
  onPermanentlyDelete: () => void = (): void => {};
  onCopyUsername: (username: string) => void = (): void => {};
  onPasswordVisibilityChange: (visible: boolean) => void = (): void => {};

  @Builder
  private readOnlyField(label: string, value: string): void {
    Column({ space: 4 }) {
      Text(label).fontSize(11).fontColor(COLOR_MUTED).width('100%')
      Text(value.length > 0 ? value : '—')
        .fontSize(14).fontColor(value.length > 0 ? COLOR_TEXT : COLOR_MUTED)
        .width('100%').textAlign(TextAlign.Start)
    }
    .width('100%').padding(10).backgroundColor(COLOR_SURFACE_2).borderRadius(11)
  }

  @Builder
  private loginFields(): void {
    Row({ space: 6 }) {
      Column({ space: 4 }) {
        Text('账号').fontSize(11).fontColor(COLOR_MUTED).width('100%')
        Text(this.entry.item.username.length > 0 ? this.entry.item.username : '—')
          .fontSize(14)
          .fontColor(this.entry.item.username.length > 0 ? COLOR_TEXT : COLOR_MUTED)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
      }.layoutWeight(1).padding(10).backgroundColor(COLOR_SURFACE_2).borderRadius(11)
      Button('复制').height(44).fontSize(12).fontColor(COLOR_PRIMARY)
        .backgroundColor(COLOR_PRIMARY_TINT).borderRadius(11)
        .enabled(this.entry.item.username.length > 0)
        .onClick((): void => { this.onCopyUsername(this.entry.item.username); })
    }.width('100%')
    Row({ space: 6 }) {
      Column({ space: 4 }) {
        Text('密码').fontSize(11).fontColor(COLOR_MUTED).width('100%')
        Text(this.revealPassword ? this.entry.item.password : '••••••••')
          .fontSize(14).fontColor(COLOR_TEXT).maxLines(1).width('100%')
      }.layoutWeight(1).padding(10).backgroundColor(COLOR_SURFACE_2).borderRadius(11)
      VaultPasswordEyeButton({
        revealed: this.revealPassword,
        controlHeight: 44,
        onToggle: (): void => {
          this.revealPassword = !this.revealPassword;
          this.onPasswordVisibilityChange(this.revealPassword);
        }
      })
    }.width('100%')
    if (this.revealPassword) {
      VaultScreenshotProtectionHint()
    }
  }

  build() {
    Column() {
      Blank().onClick((): void => { this.onClose(); })
      Scroll() {
        Column({ space: 8 }) {
          VaultDialogHeader({ title: '只读详情', onClose: (): void => { this.onClose(); } })
          Row({ space: 6 }) {
            Text(itemTypeLabel(this.entry.item.type)).fontSize(11).fontColor(COLOR_PRIMARY)
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .backgroundColor(COLOR_PRIMARY_TINT).borderRadius(9)
            Text(this.entry.originalGroupName).fontSize(11).fontColor(COLOR_MUTED)
            Blank()
            Text(this.deletedTimeText).fontSize(10).fontColor(COLOR_MUTED)
          }.width('100%')
          if (this.entry.item.type === VaultItemType.Image || this.entry.item.type === VaultItemType.Video) {
            if (this.entry.item.title.length > 0) {
              Text(this.entry.item.title).fontSize(16).fontWeight(FontWeight.Medium)
                .fontColor(COLOR_TEXT).width('100%')
            }
            VaultAttachmentGallery({
              itemId: this.entry.item.id,
              fallbackType: this.entry.item.type,
              readOnly: true
            })
            if (this.entry.item.notes.length > 0) {
              this.readOnlyField('备注', this.entry.item.notes)
            }
          } else {
            this.readOnlyField('名称', this.entry.item.title)
            if (this.entry.item.type === VaultItemType.Login) {
              this.loginFields()
            }
            if (this.entry.item.notes.length > 0) {
              this.readOnlyField(this.entry.item.type === VaultItemType.Note ? '内容' : '备注',
                this.entry.item.notes)
            }
            if (this.entry.item.type === VaultItemType.File) {
              VaultFileGallery({ itemId: this.entry.item.id, readOnly: true })
            }
          }
          Row({ space: 8 }) {
            Button('恢复').layoutWeight(1).height(46).fontWeight(FontWeight.Bold)
              .fontColor(COLOR_BG).backgroundColor(COLOR_PRIMARY).borderRadius(13)
              .onClick((): void => { this.onRestore(); })
            Button('永久删除').layoutWeight(1).height(46).fontColor(COLOR_DANGER)
              .backgroundColor(COLOR_DANGER_TINT).borderRadius(13)
              .onClick((): void => { this.onPermanentlyDelete(); })
          }.width('100%')
        }
        .width('100%').padding({ left: 16, right: 16, top: 10, bottom: 14 })
      }
      .width('100%').constraintSize({ maxHeight: '94%' }).scrollBar(BarState.Off)
      .backgroundColor(COLOR_SURFACE).borderRadius({ topLeft: 24, topRight: 24 })
    }
    .width('100%').height('100%').backgroundColor(COLOR_SCRIM)
  }
}
