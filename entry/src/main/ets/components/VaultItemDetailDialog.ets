import { VaultAttachmentGallery } from './VaultAttachmentGallery';
import { VaultFileGallery } from './VaultFileGallery';
import { VaultLoginFieldsEditor } from './VaultLoginFieldsEditor';
import {
  COLOR_BG, COLOR_DANGER, COLOR_DANGER_DARK_SURFACE, COLOR_DARK_SURFACE, COLOR_MUTED,
  COLOR_PRIMARY, COLOR_SURFACE, COLOR_SURFACE_2, COLOR_TEXT, COLOR_TYPE_BADGE, COLOR_SCRIM
} from './VaultTheme';
import { LABEL_CONTENT, LABEL_NAME, LABEL_NOTES, TITLE_ITEM_DETAILS } from './VaultCopy';
import {
  itemTypeGlyph, itemTypeLabel, VaultGroup, VaultItem, VaultItemType
} from '../models/VaultModels';

@Component
export struct VaultItemDetailDialog {
  item: VaultItem = {
    id: '',
    type: VaultItemType.Note,
    groupId: 0,
    title: '',
    username: '',
    password: '',
    website: '',
    notes: '',
    ocrText: '',
    createdAt: 0,
    updatedAt: 0,
    deletedAt: 0
  };
  groups: VaultGroup[] = [];
  initialAttachmentIndex: number = -1;
  @Link title: string;
  @Link username: string;
  @Link password: string;
  @Link website: string;
  @Link notes: string;
  @Link groupId: number;
  @Link revealPassword: boolean;
  onClose: () => void = (): void => {};
  onSave: () => void = (): void => {};
  onTrash: () => void = (): void => {};
  onPasswordVisibilityChange: (visible: boolean) => void = (): void => {};
  onCopyLoginValue: (value: string, label: string) => void = (): void => {};
  onOpenWebsite: (website: string) => void = (): void => {};

  @Builder
  private typeIcon(type: VaultItemType): void {
    if (type === VaultItemType.Image || type === VaultItemType.Video) {
      Stack({ alignContent: Alignment.Center }) {
        Stack() {
          Circle({ width: 4, height: 4 }).fill(COLOR_PRIMARY).position({ left: 4, top: 3 })
          Text('▶').fontSize(7).fontColor(COLOR_PRIMARY)
            .width(9).height(9).textAlign(TextAlign.Center).position({ right: 2, bottom: 1 })
        }
        .width(20).height(15).border({ width: 1.6, color: COLOR_PRIMARY }).borderRadius(4)
      }.width(22).height(22)
    } else if (type === VaultItemType.File) {
      Stack({ alignContent: Alignment.Center }) {
        Stack() {
          Column({ space: 2 }) {
            Divider().width(8).strokeWidth(1.4).color(COLOR_PRIMARY)
            Divider().width(8).strokeWidth(1.4).color(COLOR_PRIMARY)
          }.position({ left: 4, top: 8 })
          Stack().width(5).height(5)
            .border({ width: { left: 1.4, bottom: 1.4 }, color: COLOR_PRIMARY })
            .position({ right: 0, top: 0 })
        }
        .width(16).height(19).border({ width: 1.6, color: COLOR_PRIMARY }).borderRadius(3)
      }.width(22).height(22)
    } else {
      Text(itemTypeGlyph(type)).fontSize(16).fontColor(COLOR_PRIMARY)
        .width(22).height(22).textAlign(TextAlign.Center)
    }
  }

  @Builder
  private header(type: VaultItemType): void {
    Row({ space: 9 }) {
      Text(TITLE_ITEM_DETAILS).fontSize(19).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT)
      Row({ space: 4 }) {
        this.typeIcon(type)
        Text(itemTypeLabel(type)).fontSize(11).fontColor(COLOR_PRIMARY)
      }
      .height(28).padding({ left: 7, right: 9 })
      .backgroundColor(COLOR_TYPE_BADGE).borderRadius(10)
      Blank()
      Stack() {
        Text('×').fontSize(22).lineHeight(24).fontColor(COLOR_MUTED)
      }
      .width(38).height(38).backgroundColor(COLOR_SURFACE_2).borderRadius(11)
      .onClick((): void => { this.onClose(); })
    }
    .width('100%')
  }

  private notesHeight(type: VaultItemType): number {
    const text = this.notes.trim();
    if (text.length === 0) { return 52; }
    let visualLines = 0;
    text.split('\n').forEach((line: string): void => {
      visualLines += Math.max(1, Math.ceil(line.length / 24));
    });
    const desiredHeight = 24 + visualLines * 20;
    const maximumHeight = type === VaultItemType.Note ? 160 :
      (type === VaultItemType.Login ? 82 : 104);
    return Math.max(52, Math.min(maximumHeight, desiredHeight));
  }

  @Builder
  private notesEditor(type: VaultItemType): void {
    TextArea({ placeholder: type === VaultItemType.Note ? LABEL_CONTENT : LABEL_NOTES, text: this.notes })
      .fontColor(COLOR_TEXT).backgroundColor(COLOR_SURFACE_2)
      .height(this.notesHeight(type)).borderRadius(11)
      .onChange((value: string): void => { this.notes = value; })
  }

  @Builder
  private groupChip(groupId: number, name: string): void {
    Text(name)
      .fontSize(12)
      .fontColor(this.groupId === groupId ? COLOR_BG : COLOR_MUTED)
      .maxLines(1)
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .backgroundColor(this.groupId === groupId ? COLOR_PRIMARY : COLOR_SURFACE_2)
      .borderRadius(16)
      .margin({ right: 6, bottom: 6 })
      .onClick((): void => { this.groupId = groupId; })
  }

  @Builder
  private groupPicker(): void {
    Column({ space: 6 }) {
      Text('移动到分组').fontSize(12).fontColor(COLOR_MUTED).width('100%')
      Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
        this.groupChip(0, '未分组')
        ForEach(this.groups, (group: VaultGroup): void => {
          this.groupChip(group.id, group.name)
        }, (group: VaultGroup): string => `${group.id}-${group.name}`)
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  private actionButtons(compact: boolean): void {
    Row({ space: 10 }) {
      Button('移入回收站')
        .fontSize(14).fontColor(COLOR_DANGER)
        .layoutWeight(1).height(compact ? 44 : 46)
        .backgroundColor(COLOR_DANGER_DARK_SURFACE).borderRadius(compact ? 14 : 12)
        .onClick((): void => { this.onTrash(); })
      Button('保存修改')
        .fontSize(14).fontWeight(FontWeight.Bold).fontColor(COLOR_BG)
        .layoutWeight(1).height(compact ? 44 : 46)
        .backgroundColor(COLOR_PRIMARY).borderRadius(compact ? 14 : 12)
        .onClick((): void => { this.onSave(); })
    }
    .width('100%')
  }

  @Builder
  private mediaContent(): void {
    Column({ space: 8 }) {
      this.header(VaultItemType.Image)
      VaultAttachmentGallery({
        itemId: this.item.id,
        fallbackType: this.item.type,
        initialAttachmentIndex: this.initialAttachmentIndex
      })
      Column() {
        this.groupPicker()
      }
      .width('100%').padding(9).backgroundColor(COLOR_DARK_SURFACE).borderRadius(15)
      Column({ space: 7 }) {
        TextInput({ placeholder: LABEL_NAME, text: this.title })
          .fontColor(COLOR_TEXT).backgroundColor(COLOR_SURFACE_2).height(42).borderRadius(11)
          .onChange((value: string): void => { this.title = value; })
        this.notesEditor(this.item.type)
      }
      .width('100%').padding(9).backgroundColor(COLOR_DARK_SURFACE).borderRadius(15)
      this.actionButtons(true)
    }
    .width('100%').padding({ left: 14, right: 14, top: 10, bottom: 12 })
  }

  @Builder
  private standardContent(): void {
    Column({ space: 9 }) {
      this.header(this.item.type)
      this.groupPicker()
      if (this.item.type === VaultItemType.File) {
        VaultFileGallery({ itemId: this.item.id })
      }
      TextInput({ placeholder: LABEL_NAME, text: this.title })
        .fontColor(COLOR_TEXT).backgroundColor(COLOR_SURFACE_2).height(44).borderRadius(11)
        .onChange((value: string): void => { this.title = value; })
      if (this.item.type === VaultItemType.Login) {
        Row({ space: 7 }) {
          TextInput({ placeholder: '网站地址', text: this.website })
            .layoutWeight(1).fontColor(COLOR_TEXT).backgroundColor(COLOR_SURFACE_2)
            .height(44).borderRadius(11)
            .onChange((value: string): void => { this.website = value; })
          Button('打开').height(42).fontSize(11).fontColor(COLOR_PRIMARY)
            .backgroundColor(COLOR_SURFACE_2).borderRadius(11)
            .enabled(this.website.trim().length > 0)
            .onClick((): void => { this.onOpenWebsite(this.website); })
        }.width('100%')
        VaultLoginFieldsEditor({
          username: $username,
          password: $password,
          revealPassword: $revealPassword,
          allowUtilities: true,
          onCopy: this.onCopyLoginValue,
          onPasswordVisibilityChange: this.onPasswordVisibilityChange
        })
      }
      this.notesEditor(this.item.type)
      this.actionButtons(false)
    }
    .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 14 })
  }

  build() {
    Column() {
      Blank().onClick((): void => { this.onClose(); })
      Scroll() {
        if (this.item.type === VaultItemType.Image || this.item.type === VaultItemType.Video) {
          this.mediaContent()
        } else {
          this.standardContent()
        }
      }
      .width('100%')
      .constraintSize({ maxHeight:
        this.item.type === VaultItemType.Image || this.item.type === VaultItemType.Video ? '96%' : '88%' })
      .scrollBar(BarState.Off)
      .backgroundColor(COLOR_SURFACE)
      .borderRadius({ topLeft: 24, topRight: 24 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(COLOR_SCRIM)
  }
}
