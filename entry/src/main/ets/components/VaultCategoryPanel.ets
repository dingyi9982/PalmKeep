import { itemTypeLabel, VaultGroup, VaultItem, VaultItemType } from '../models/VaultModels';
import { VaultAttachmentPreview } from './VaultAttachmentPreview';
import { VaultFileSummary } from './VaultFileSummary';
import {
  COLOR_BG, COLOR_BORDER, COLOR_CHEVRON, COLOR_MUTED, COLOR_MUTED_LIGHT, COLOR_ON_DARK,
  COLOR_PRIMARY, COLOR_PRIMARY_BORDER, COLOR_PRIMARY_ON_DARK, COLOR_PRIMARY_TINT,
  COLOR_SURFACE, COLOR_TEXT
} from './VaultTheme';

@Component
export struct VaultCategoryPanel {
  @Prop selectedType: VaultItemType = VaultItemType.Login;
  @Prop selectedGroupId: number = -1;
  @Prop sortLabel: string = '最近修改';
  @Prop groups: VaultGroup[] = [];
  @Prop items: VaultItem[] = [];
  @Prop allItems: VaultItem[] = [];
  @Prop loginCount: number = 0;
  @Prop noteCount: number = 0;
  @Prop mediaCount: number = 0;
  @Prop fileCount: number = 0;
  onSelectType: (type: VaultItemType) => void = (_: VaultItemType): void => {};
  onSelectGroup: (groupId: number) => void = (_: number): void => {};
  onChooseSort: () => void = (): void => {};
  onOpenItem: (item: VaultItem) => void = (_: VaultItem): void => {};

  private countType(type: VaultItemType): number {
    if (type === VaultItemType.Login) { return this.loginCount; }
    if (type === VaultItemType.Note) { return this.noteCount; }
    if (type === VaultItemType.File) { return this.fileCount; }
    return this.mediaCount;
  }

  private countGroupByType(groupId: number): number {
    return this.allItems.filter((item: VaultItem): boolean => item.groupId === groupId &&
      (this.selectedType === VaultItemType.Image ?
        (item.type === VaultItemType.Image || item.type === VaultItemType.Video) : item.type === this.selectedType)).length;
  }

  private groupName(groupId: number): string {
    if (groupId === 0) { return '未分组'; }
    const group = this.groups.find((value: VaultGroup): boolean => value.id === groupId);
    return group ? group.name : '未分组';
  }

  private formatTime(value: number): string {
    const date = new Date(value);
    const now = new Date();
    const today = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
    if (value >= today) {
      return `${date.getHours().toString().padStart(2, '0')}:${date.getMinutes().toString().padStart(2, '0')}`;
    }
    if (date.getFullYear() === now.getFullYear()) { return `${date.getMonth() + 1}/${date.getDate()}`; }
    return `${date.getFullYear()}/${date.getMonth() + 1}/${date.getDate()}`;
  }

  @Builder
  private typeSwitch(type: VaultItemType): void {
    Column({ space: 1 }) {
      Text(itemTypeLabel(type)).fontSize(12).fontWeight(FontWeight.Medium)
        .fontColor(this.selectedType === type ? COLOR_ON_DARK : COLOR_TEXT)
      Text(`${this.countType(type)}`).fontSize(10)
        .fontColor(this.selectedType === type ? COLOR_PRIMARY_ON_DARK : COLOR_MUTED)
    }
    .layoutWeight(1).height(48).justifyContent(FlexAlign.Center)
    .backgroundColor(this.selectedType === type ? COLOR_PRIMARY : COLOR_SURFACE).borderRadius(13)
    .border({ width: 1, color: this.selectedType === type ? COLOR_PRIMARY : COLOR_BORDER })
    .onClick((): void => { this.onSelectType(type); })
  }

  @Builder
  private groupChip(groupId: number, label: string): void {
    Text(label).fontSize(11).maxLines(1)
      .fontColor(this.selectedGroupId === groupId ? COLOR_PRIMARY : COLOR_MUTED)
      .padding({ left: 11, right: 11, top: 7, bottom: 7 })
      .backgroundColor(this.selectedGroupId === groupId ? COLOR_PRIMARY_TINT : COLOR_SURFACE).borderRadius(13)
      .border({ width: 1, color: this.selectedGroupId === groupId ? COLOR_PRIMARY_BORDER : COLOR_BORDER })
      .onClick((): void => { this.onSelectGroup(groupId); })
  }

  @Builder
  private itemMeta(item: VaultItem): void {
    Row({ space: 6 }) {
      Text(this.groupName(item.groupId)).fontSize(10).fontColor(COLOR_PRIMARY)
        .padding({ left: 6, right: 6, top: 2, bottom: 2 }).backgroundColor(COLOR_PRIMARY_TINT)
        .borderRadius(7).maxLines(1)
      Blank()
      Text(this.formatTime(item.updatedAt)).fontSize(10).fontColor(COLOR_MUTED_LIGHT)
    }.width('100%')
  }

  @Builder
  private itemRow(item: VaultItem): void {
    if (this.selectedType === VaultItemType.Image) {
      Column({ space: 5 }) {
        Row({ space: 8 }) {
          Text(item.title.length > 0 ? item.title : ' ').fontSize(14).fontWeight(FontWeight.Medium)
            .fontColor(COLOR_TEXT).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
          Text('›').fontSize(19).fontColor(COLOR_CHEVRON)
        }.width('100%')
        VaultAttachmentPreview({ itemId: item.id, fallbackType: item.type, maxVisibleCount: 6, thumbnailSize: 44 })
        this.itemMeta(item)
      }
      .width('100%').padding({ left: 11, right: 10, top: 8, bottom: 8 }).alignItems(HorizontalAlign.Start)
      .backgroundColor(COLOR_SURFACE).borderRadius(14).border({ width: 1, color: COLOR_BORDER })
      .onClick((): void => { this.onOpenItem(item); })
    } else if (this.selectedType === VaultItemType.File) {
      Column({ space: 5 }) {
        Row({ space: 8 }) {
          Column({ space: 4 }) {
            Text(item.title).fontSize(14).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
            VaultFileSummary({ itemId: item.id })
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          Text('›').fontSize(19).fontColor(COLOR_CHEVRON)
        }.width('100%')
        this.itemMeta(item)
      }
      .width('100%').padding({ left: 11, right: 10, top: 8, bottom: 8 })
      .backgroundColor(COLOR_SURFACE).borderRadius(14).border({ width: 1, color: COLOR_BORDER })
      .onClick((): void => { this.onOpenItem(item); })
    } else if (this.selectedType === VaultItemType.Note) {
      Column({ space: 5 }) {
        Text(item.title).fontSize(14).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        if (item.notes.length > 0) {
          Text(item.notes).fontSize(11).lineHeight(16).fontColor(COLOR_MUTED)
            .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        }
        this.itemMeta(item)
      }
      .width('100%').alignItems(HorizontalAlign.Start).padding({ left: 11, right: 11, top: 8, bottom: 8 })
      .backgroundColor(COLOR_SURFACE).borderRadius(14).border({ width: 1, color: COLOR_BORDER })
      .onClick((): void => { this.onOpenItem(item); })
    } else {
      Column({ space: 5 }) {
        Row({ space: 8 }) {
          Column({ space: 2 }) {
            Text(item.title).fontSize(14).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
            if (item.username.length > 0) {
              Text(item.username).fontSize(11).fontColor(COLOR_MUTED)
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
            }
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          Text('›').fontSize(19).fontColor(COLOR_CHEVRON)
        }.width('100%')
        this.itemMeta(item)
      }
      .width('100%').padding({ left: 11, right: 10, top: 8, bottom: 8 })
      .backgroundColor(COLOR_SURFACE).borderRadius(14).border({ width: 1, color: COLOR_BORDER })
      .onClick((): void => { this.onOpenItem(item); })
    }
  }

  build() {
    Column({ space: 8 }) {
      Row({ space: 5 }) {
        this.typeSwitch(VaultItemType.Login)
        this.typeSwitch(VaultItemType.Note)
        this.typeSwitch(VaultItemType.Image)
        this.typeSwitch(VaultItemType.File)
      }.width('100%')
      Row({ space: 6 }) {
        Scroll() {
          Row({ space: 5 }) {
            this.groupChip(-1, '全部分组')
            ForEach(this.groups, (group: VaultGroup): void => {
              if (this.countGroupByType(group.id) > 0) { this.groupChip(group.id, group.name) }
            }, (group: VaultGroup): string => `${group.id}-${group.name}`)
            if (this.countGroupByType(0) > 0) { this.groupChip(0, '未分组') }
          }
        }.layoutWeight(1).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
        Button(`${this.sortLabel}  ▾`).height(31).fontSize(10).fontColor(COLOR_MUTED)
          .padding({ left: 9, right: 9 }).backgroundColor(COLOR_SURFACE).borderRadius(12)
          .border({ width: 1, color: COLOR_BORDER }).onClick((): void => { this.onChooseSort(); })
      }.width('100%')
      Row() { Text(`${this.items.length} 条资料`).fontSize(11).fontColor(COLOR_MUTED) }
        .width('100%').padding({ left: 2 })
      Scroll() {
        if (this.items.length === 0) {
          Column({ space: 8 }) {
            Text(`还没有${itemTypeLabel(this.selectedType)}`)
              .fontSize(16).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT)
            Text('点击底部加号添加第一条资料').fontSize(12).fontColor(COLOR_MUTED)
          }.width('100%').padding({ top: 56, bottom: 56 })
        } else {
          Column({ space: 5 }) {
            ForEach(this.items, (item: VaultItem): void => { this.itemRow(item) },
              (item: VaultItem): string => `${item.id}-${item.updatedAt}`)
          }.width('100%')
        }
      }.layoutWeight(1).width('100%').scrollBar(BarState.Off)
    }
    .width('100%').height('100%').padding({ left: 18, right: 18, top: 10, bottom: 92 })
  }
}
