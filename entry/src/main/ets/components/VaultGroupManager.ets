import { VaultGroup } from '../models/VaultModels';
import {
  COLOR_BORDER, COLOR_DANGER, COLOR_MUTED, COLOR_PRIMARY, COLOR_SURFACE, COLOR_SURFACE_2, COLOR_TEXT
} from './VaultTheme';

@Component
export struct VaultGroupManager {
  @Prop groups: VaultGroup[] = [];
  countGroup: (groupId: number) => number = (_: number): number => 0;
  onBack: () => void = (): void => {};
  onRename: (group: VaultGroup) => void = (_: VaultGroup): void => {};
  onDelete: (group: VaultGroup) => void = (_: VaultGroup): void => {};

  build() {
    Column({ space: 16 }) {
      Row({ space: 10 }) {
        Button('‹').width(40).height(40).fontSize(26).fontColor(COLOR_TEXT)
          .backgroundColor(COLOR_SURFACE).borderRadius(12).onClick((): void => { this.onBack(); })
        Text('分组管理').fontSize(25).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT).layoutWeight(1)
      }.width('100%')
      List({ space: 10 }) {
        ForEach(this.groups, (group: VaultGroup): void => {
          ListItem() {
            Row({ space: 12 }) {
              Column({ space: 3 }) {
                Text(group.name).fontSize(15).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT)
                Text(`${this.countGroup(group.id)} 条资料`).fontSize(11).fontColor(COLOR_MUTED)
              }.alignItems(HorizontalAlign.Start).layoutWeight(1)
              Row({ space: 6 }) {
                Button('重命名').height(36).fontSize(11).fontColor(COLOR_PRIMARY)
                  .backgroundColor(COLOR_SURFACE_2).borderRadius(10)
                  .onClick((): void => { this.onRename(group); })
                Button('删除').height(36).fontSize(11).fontColor(COLOR_DANGER)
                  .backgroundColor('#FDEDEF').borderRadius(10)
                  .onClick((): void => { this.onDelete(group); })
              }
            }
            .width('100%').padding(14).backgroundColor(COLOR_SURFACE).borderRadius(17)
            .border({ width: 1, color: COLOR_BORDER })
          }
        }, (group: VaultGroup): string => `${group.id}-${group.name}`)
      }.layoutWeight(1).width('100%').scrollBar(BarState.Off)
    }
    .width('100%').height('100%').padding({ left: 18, right: 18, top: 20, bottom: 92 })
  }
}
