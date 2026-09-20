import { VaultAttachmentSummary } from '../models/VaultModels';
import { vaultRepository } from '../services/VaultRepository';
import { COLOR_MUTED, COLOR_PRIMARY_DARK, COLOR_PRIMARY_TINT, COLOR_TEXT_SECONDARY } from './VaultTheme';

@Component
export struct VaultFileSummary {
  itemId: string = '';
  @State private attachments: VaultAttachmentSummary[] = [];

  aboutToAppear(): void {
    this.load();
  }

  private async load(): Promise<void> {
    this.attachments = await vaultRepository.listItemAttachments(this.itemId);
  }

  build() {
    Column({ space: 3 }) {
      Row({ space: 6 }) {
        Text('文件')
          .fontSize(9).fontWeight(FontWeight.Medium).fontColor(COLOR_PRIMARY_DARK)
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .backgroundColor(COLOR_PRIMARY_TINT).borderRadius(7)
        if (this.attachments.length > 2) {
          Text(`另有 ${this.attachments.length - 2} 个文件`)
            .fontSize(9).fontColor(COLOR_MUTED)
        }
      }
      .width('100%')
      if (this.attachments.length === 0) {
        Text('文件内容暂不可用')
          .fontSize(11).fontColor(COLOR_MUTED).maxLines(1).width('100%')
      } else {
        ForEach(this.attachments.slice(0, 2), (attachment: VaultAttachmentSummary): void => {
          Text(attachment.name.length > 0 ? attachment.name : '未命名文件')
            .fontSize(11).fontColor(COLOR_TEXT_SECONDARY).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        }, (attachment: VaultAttachmentSummary): string => `${attachment.index}`)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
