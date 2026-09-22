import { itemDisplayTitle, itemTypeLabel, VaultGroup, VaultItem, VaultItemType } from '../models/VaultModels';
import { VaultAttachmentPreview } from './VaultAttachmentPreview';
import { VaultFileSummary } from './VaultFileSummary';
import {
  COLOR_BG, COLOR_BORDER, COLOR_CHEVRON, COLOR_DANGER, COLOR_DANGER_TINT, COLOR_DISABLED,
  COLOR_MUTED, COLOR_MUTED_LIGHT, COLOR_ON_DARK,
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
  @Prop audioCount: number = 0;
  @Prop fileCount: number = 0;
  @Prop managing: boolean = false;
  @Prop selectedIds: string[] = [];
  @Prop busy: boolean = false;
  onSelectType: (type: VaultItemType) => void = (_: VaultItemType): void => {};
  onSelectGroup: (groupId: number) => void = (_: number): void => {};
  onChooseSort: () => void = (): void => {};
  onOpenItem: (item: VaultItem) => void = (_: VaultItem): void => {};
  onEnterManagement: (itemId: string) => void = (_: string): void => {};
  onToggleSelection: (itemId: string) => void = (_: string): void => {};
  onToggleAll: () => void = (): void => {};
  onCancelManagement: () => void = (): void => {};
  onMoveSelected: () => void = (): void => {};
  onTrashSelected: () => void = (): void => {};

  private isSelected(id: string): boolean {
    return this.selectedIds.indexOf(id) >= 0;
  }

  private activateItem(item: VaultItem): void {
    if (this.managing) { this.onToggleSelection(item.id); }
    else { this.onOpenItem(item); }
  }

  @Builder
  private selectionMark(item: VaultItem): void {
    if (this.managing) {
      Stack({ alignContent: Alignment.Center }) {
        Circle({ width: 22, height: 22 })
          .fill(this.isSelected(item.id) ? COLOR_PRIMARY : Color.Transparent)
          .stroke(this.isSelected(item.id) ? COLOR_PRIMARY : COLOR_DISABLED).strokeWidth(1.5)
        if (this.isSelected(item.id)) {
          Text('✓').fontSize(13).fontWeight(FontWeight.Bold).fontColor(COLOR_ON_DARK)
        }
      }.width(26).height(30)
    }
  }

  private countType(type: VaultItemType): number {
    if (type === VaultItemType.Login) { return this.loginCount; }
    if (type === VaultItemType.Note) { return this.noteCount; }
    if (type === VaultItemType.File) { return this.fileCount; }
    if (type === VaultItemType.Audio) { return this.audioCount; }
    return this.mediaCount;
  }

  private countGroupByType(groupId: number): number {
    return this.allItems.filter((item: VaultItem): boolean => item.groupId === groupId &&
      (this.selectedType === VaultItemType.Image ?
        (item.type === VaultItemType.Image || item.type === VaultItemType.Video) : item.type === this.selectedType)).length;
  }

  private groupName(groupId: number): string {
    const group = this.groups.find((value: VaultGroup): boolean => value.id === groupId);
    return group ? group.name : '分组已删除';
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
          this.selectionMark(item)
          Text(item.title.length > 0 ? item.title : ' ').fontSize(14).fontWeight(FontWeight.Medium)
            .fontColor(COLOR_TEXT).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
          Text('›').fontSize(19).fontColor(COLOR_CHEVRON)
        }.width('100%')
        VaultAttachmentPreview({ itemId: item.id, fallbackType: item.type, maxVisibleCount: 6, thumbnailSize: 44 })
        this.itemMeta(item)
      }
      .width('100%').padding({ left: 11, right: 10, top: 8, bottom: 8 }).alignItems(HorizontalAlign.Start)
      .backgroundColor(COLOR_SURFACE).borderRadius(14)
      .border({ width: 1, color: this.isSelected(item.id) ? COLOR_PRIMARY : COLOR_BORDER })
      .onClick((): void => { this.activateItem(item); })
      .priorityGesture(LongPressGesture({ repeat: false, duration: 500 })
        .onAction((): void => { this.onEnterManagement(item.id); }))
    } else if (this.selectedType === VaultItemType.File || this.selectedType === VaultItemType.Audio) {
      Column({ space: 5 }) {
        Row({ space: 8 }) {
          this.selectionMark(item)
          Column({ space: 4 }) {
            Text(itemDisplayTitle(item)).fontSize(14).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
            if (this.selectedType === VaultItemType.File) {
              VaultFileSummary({ itemId: item.id })
            } else {
              VaultAttachmentPreview({ itemId: item.id, fallbackType: VaultItemType.Audio,
                maxVisibleCount: 1, thumbnailSize: 34 })
            }
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          Text('›').fontSize(19).fontColor(COLOR_CHEVRON)
        }.width('100%')
        this.itemMeta(item)
      }
      .width('100%').padding({ left: 11, right: 10, top: 8, bottom: 8 })
      .backgroundColor(COLOR_SURFACE).borderRadius(14)
      .border({ width: 1, color: this.isSelected(item.id) ? COLOR_PRIMARY : COLOR_BORDER })
      .onClick((): void => { this.activateItem(item); })
      .priorityGesture(LongPressGesture({ repeat: false, duration: 500 })
        .onAction((): void => { this.onEnterManagement(item.id); }))
    } else if (this.selectedType === VaultItemType.Note) {
      Column({ space: 5 }) {
        Row({ space: 8 }) {
          this.selectionMark(item)
          Text(itemDisplayTitle(item)).fontSize(14).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
        }.width('100%')
        if (item.notes.length > 0) {
          Text(item.notes).fontSize(11).lineHeight(16).fontColor(COLOR_MUTED)
            .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        }
        this.itemMeta(item)
      }
      .width('100%').alignItems(HorizontalAlign.Start).padding({ left: 11, right: 11, top: 8, bottom: 8 })
      .backgroundColor(COLOR_SURFACE).borderRadius(14)
      .border({ width: 1, color: this.isSelected(item.id) ? COLOR_PRIMARY : COLOR_BORDER })
      .onClick((): void => { this.activateItem(item); })
      .priorityGesture(LongPressGesture({ repeat: false, duration: 500 })
        .onAction((): void => { this.onEnterManagement(item.id); }))
    } else {
      Column({ space: 5 }) {
        Row({ space: 8 }) {
          this.selectionMark(item)
          Column({ space: 2 }) {
            Text(itemDisplayTitle(item)).fontSize(14).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT)
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
      .backgroundColor(COLOR_SURFACE).borderRadius(14)
      .border({ width: 1, color: this.isSelected(item.id) ? COLOR_PRIMARY : COLOR_BORDER })
      .onClick((): void => { this.activateItem(item); })
      .priorityGesture(LongPressGesture({ repeat: false, duration: 500 })
        .onAction((): void => { this.onEnterManagement(item.id); }))
    }
  }

  build() {
    Column({ space: 8 }) {
      Row({ space: 5 }) {
        this.typeSwitch(VaultItemType.Image)
        this.typeSwitch(VaultItemType.Note)
        this.typeSwitch(VaultItemType.Login)
        this.typeSwitch(VaultItemType.File)
        this.typeSwitch(VaultItemType.Audio)
      }.width('100%')
      Row({ space: 6 }) {
        Scroll() {
          Row({ space: 5 }) {
            this.groupChip(-1, '全部分组')
            ForEach(this.groups, (group: VaultGroup): void => {
              if (this.countGroupByType(group.id) > 0) { this.groupChip(group.id, group.name) }
            }, (group: VaultGroup): string => `${group.id}-${group.name}`)
          }
        }.layoutWeight(1).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
        Button(`${this.sortLabel}  ▾`).height(31).fontSize(10).fontColor(COLOR_MUTED)
          .padding({ left: 9, right: 9 }).backgroundColor(COLOR_SURFACE).borderRadius(12)
          .border({ width: 1, color: COLOR_BORDER }).onClick((): void => { this.onChooseSort(); })
      }.width('100%')
      if (this.managing) {
        Row() {
          Text(`已选择 ${this.selectedIds.length} 项`).fontSize(12).fontColor(COLOR_TEXT)
          Blank()
          Text(this.selectedIds.length === this.items.length && this.items.length > 0 ? '取消全选' : '全选')
            .fontSize(12).fontColor(COLOR_PRIMARY).padding(6)
            .onClick((): void => { this.onToggleAll(); })
          Text('取消').fontSize(12).fontColor(COLOR_MUTED).padding(6)
            .onClick((): void => { this.onCancelManagement(); })
        }.width('100%').height(34)
      } else {
        Row() {
          Text(`${this.items.length} 条资料`).fontSize(11).fontColor(COLOR_MUTED)
          Blank()
          if (this.items.length > 0) {
            Button('管理').height(32).fontSize(11).fontColor(COLOR_PRIMARY)
              .backgroundColor(COLOR_SURFACE).borderRadius(11)
              .onClick((): void => { this.onEnterManagement(''); })
          }
        }.width('100%').padding({ left: 2 })
      }
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
      if (this.managing) {
        Row({ space: 8 }) {
          Button('移动到分组').layoutWeight(1).height(44).fontColor(COLOR_PRIMARY)
            .backgroundColor(COLOR_PRIMARY_TINT).borderRadius(13)
            .enabled(this.selectedIds.length > 0 && !this.busy)
            .opacity(this.selectedIds.length > 0 && !this.busy ? 1 : 0.45)
            .onClick((): void => { this.onMoveSelected(); })
          Button('移入回收站').layoutWeight(1).height(44).fontColor(COLOR_DANGER)
            .backgroundColor(COLOR_DANGER_TINT).borderRadius(13)
            .enabled(this.selectedIds.length > 0 && !this.busy)
            .opacity(this.selectedIds.length > 0 && !this.busy ? 1 : 0.45)
            .onClick((): void => { this.onTrashSelected(); })
        }.width('100%')
      }
    }
    .width('100%').height('100%').padding({ left: 18, right: 18, top: 10, bottom: 92 })
  }
}
