import { VaultThumbnail } from './VaultThumbnail';
import { VaultAttachmentSummary, VaultItemType } from '../models/VaultModels';
import { vaultRepository } from '../services/VaultRepository';

@Component
export struct VaultAttachmentPreview {
  itemId: string = '';
  fallbackType: VaultItemType = VaultItemType.Image;
  highlightAttachmentIndex: number = -1;
  maxVisibleCount: number = 3;
  @State private attachments: VaultAttachmentSummary[] = [];

  aboutToAppear(): void {
    this.load();
  }

  private async load(): Promise<void> {
    this.attachments = await vaultRepository.listItemAttachments(this.itemId);
  }

  private visibleCount(): number {
    return Math.min(this.attachments.length, Math.max(1, this.maxVisibleCount));
  }

  private highlightIsHidden(): boolean {
    const hitPosition = this.attachments.findIndex((attachment: VaultAttachmentSummary): boolean =>
      attachment.index === this.highlightAttachmentIndex);
    return hitPosition >= this.visibleCount();
  }

  build() {
    Row({ space: 3 }) {
      if (this.attachments.length === 0) {
        VaultThumbnail({ itemId: this.itemId, mediaType: this.fallbackType, thumbnailSize: 36 })
      } else {
        ForEach(this.attachments.slice(0, this.visibleCount()), (attachment: VaultAttachmentSummary): void => {
          Stack() {
            VaultThumbnail({
              itemId: this.itemId,
              mediaType: attachment.type,
              attachmentIndex: attachment.index,
              thumbnailSize: 36
            })
          }
          .padding(2)
          .border({ width: 2,
            color: attachment.index === this.highlightAttachmentIndex ? '#24B88A' : '#00000000' })
          .borderRadius(10)
        }, (attachment: VaultAttachmentSummary): string => `${attachment.index}`)
        if (this.attachments.length > this.visibleCount()) {
          Text(`+${this.attachments.length - this.visibleCount()}`)
            .fontSize(10).fontWeight(FontWeight.Medium).fontColor('#24B88A')
            .textAlign(TextAlign.Center)
            .width(36).height(36)
            .border({ width: this.highlightIsHidden() ? 2 : 0,
              color: this.highlightIsHidden() ? '#24B88A' : '#00000000' })
            .borderRadius(9)
        }
      }
    }
  }
}
