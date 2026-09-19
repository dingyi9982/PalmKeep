import { VaultThumbnail } from './VaultThumbnail';
import { VaultAttachmentSummary, VaultItemType } from '../models/VaultModels';
import { vaultRepository } from '../services/VaultRepository';

@Component
export struct VaultAttachmentPreview {
  itemId: string = '';
  fallbackType: VaultItemType = VaultItemType.Image;
  highlightAttachmentIndex: number = -1;
  maxVisibleCount: number = 3;
  gridMode: boolean = false;
  thumbnailSize: number = 36;
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
    if (this.gridMode) {
      Stack({ alignContent: Alignment.BottomEnd }) {
        if (this.attachments.length === 0) {
          VaultThumbnail({ itemId: this.itemId, mediaType: this.fallbackType,
            thumbnailSize: this.thumbnailSize })
        } else {
          VaultThumbnail({ itemId: this.itemId, mediaType: this.attachments[0].type,
            attachmentIndex: this.attachments[0].index, thumbnailSize: this.thumbnailSize })
          if (this.attachments[0].type === VaultItemType.Video) {
            Text('▶').fontSize(11).fontColor('#FFFFFF')
              .width(25).height(25).textAlign(TextAlign.Center)
              .backgroundColor('#99000000').borderRadius(13)
              .position({ left: 7, bottom: 7 })
          }
          if (this.attachments.length > 1) {
            Text(`${this.attachments.length}`)
              .fontSize(10).fontWeight(FontWeight.Medium).fontColor('#FFFFFF')
              .padding({ left: 7, right: 7, top: 3, bottom: 3 })
              .backgroundColor('#99000000').borderRadius(10)
              .margin({ right: 7, bottom: 7 })
          }
        }
      }
      .width(this.thumbnailSize).height(this.thumbnailSize).borderRadius(12).clip(true)
    } else {
      Row({ space: 2 }) {
      if (this.attachments.length === 0) {
        VaultThumbnail({ itemId: this.itemId, mediaType: this.fallbackType, thumbnailSize: this.thumbnailSize })
      } else if (this.highlightAttachmentIndex < 0) {
        ForEach(this.attachments.slice(0, this.visibleCount()), (attachment: VaultAttachmentSummary): void => {
          VaultThumbnail({
            itemId: this.itemId,
            mediaType: attachment.type,
            attachmentIndex: attachment.index,
            thumbnailSize: this.thumbnailSize
          })
        }, (attachment: VaultAttachmentSummary): string => `${attachment.index}`)
        if (this.attachments.length > this.visibleCount()) {
          Text(`+${this.attachments.length - this.visibleCount()}`)
            .fontSize(10).fontWeight(FontWeight.Medium).fontColor('#24B88A')
            .maxLines(1).margin({ left: -1 })
        }
      } else {
        ForEach(this.attachments.slice(0, this.visibleCount()), (attachment: VaultAttachmentSummary): void => {
          Stack() {
            VaultThumbnail({
              itemId: this.itemId,
              mediaType: attachment.type,
              attachmentIndex: attachment.index,
              thumbnailSize: this.thumbnailSize
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
            .width(this.thumbnailSize).height(this.thumbnailSize)
            .border({ width: this.highlightIsHidden() ? 2 : 0,
              color: this.highlightIsHidden() ? '#24B88A' : '#00000000' })
            .borderRadius(9)
        }
      }
      }
    }
  }
}
