import { VaultThumbnail } from './VaultThumbnail';
import { VaultAttachmentSummary, VaultItemType } from '../models/VaultModels';
import { vaultRepository } from '../services/VaultRepository';

@Component
export struct VaultAttachmentPreview {
  itemId: string = '';
  fallbackType: VaultItemType = VaultItemType.Image;
  @State private attachments: VaultAttachmentSummary[] = [];

  aboutToAppear(): void {
    this.load();
  }

  private async load(): Promise<void> {
    this.attachments = await vaultRepository.listItemAttachments(this.itemId);
  }

  build() {
    Row({ space: 4 }) {
      if (this.attachments.length === 0) {
        VaultThumbnail({ itemId: this.itemId, mediaType: this.fallbackType, thumbnailSize: 36 })
      } else {
        ForEach(this.attachments.slice(0, 3), (attachment: VaultAttachmentSummary): void => {
          VaultThumbnail({
            itemId: this.itemId,
            mediaType: attachment.type,
            attachmentIndex: attachment.index,
            thumbnailSize: 36
          })
        }, (attachment: VaultAttachmentSummary): string => `${attachment.index}`)
        if (this.attachments.length > 3) {
          Stack() {
            Text(`+${this.attachments.length - 3}`).fontSize(10).fontColor('#24B88A')
          }.width(36).height(36).borderRadius(10).backgroundColor('#E8F7F2')
        }
      }
    }
  }
}
