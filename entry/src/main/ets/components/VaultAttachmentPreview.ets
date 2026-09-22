import { VaultThumbnail } from './VaultThumbnail';
import { VaultAttachmentSummary, VaultItemType } from '../models/VaultModels';
import { vaultRepository } from '../services/VaultRepository';
import { COLOR_ON_DARK, COLOR_PRIMARY, COLOR_SCRIM, COLOR_TRANSPARENT } from './VaultTheme';

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
    if (this.fallbackType === VaultItemType.Audio) {
      Stack({ alignContent: Alignment.Center }) {
        Text('♪').fontSize(Math.max(18, this.thumbnailSize * 0.42)).fontColor(COLOR_PRIMARY)
        if (this.attachments.length > 0) {
          Text(`${this.attachments.length}`).fontSize(9).fontColor(COLOR_ON_DARK)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 }).backgroundColor(COLOR_SCRIM)
            .borderRadius(9).position({ right: 5, bottom: 5 })
        }
      }.width(this.thumbnailSize).height(this.thumbnailSize).backgroundColor('#E8F8F2').borderRadius(12)
    } else if (this.gridMode) {
      Stack({ alignContent: Alignment.BottomEnd }) {
        if (this.attachments.length === 0) {
          VaultThumbnail({ itemId: this.itemId, mediaType: this.fallbackType,
            thumbnailSize: this.thumbnailSize })
        } else {
          VaultThumbnail({ itemId: this.itemId, mediaType: this.attachments[0].type,
            attachmentIndex: this.attachments[0].index, thumbnailSize: this.thumbnailSize })
          if (this.attachments[0].type === VaultItemType.Video) {
            Text('▶').fontSize(11).fontColor(COLOR_ON_DARK)
              .width(25).height(25).textAlign(TextAlign.Center)
              .backgroundColor(COLOR_SCRIM).borderRadius(13)
              .position({ left: 7, bottom: 7 })
          }
          if (this.attachments.length > 1) {
            Text(`${this.attachments.length}`)
              .fontSize(10).fontWeight(FontWeight.Medium).fontColor(COLOR_ON_DARK)
              .padding({ left: 7, right: 7, top: 3, bottom: 3 })
              .backgroundColor(COLOR_SCRIM).borderRadius(10)
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
            .fontSize(10).fontWeight(FontWeight.Medium).fontColor(COLOR_PRIMARY)
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
            color: attachment.index === this.highlightAttachmentIndex ? COLOR_PRIMARY : COLOR_TRANSPARENT })
          .borderRadius(10)
        }, (attachment: VaultAttachmentSummary): string => `${attachment.index}`)
        if (this.attachments.length > this.visibleCount()) {
          Text(`+${this.attachments.length - this.visibleCount()}`)
            .fontSize(10).fontWeight(FontWeight.Medium).fontColor(COLOR_PRIMARY)
            .textAlign(TextAlign.Center)
            .width(this.thumbnailSize).height(this.thumbnailSize)
            .border({ width: this.highlightIsHidden() ? 2 : 0,
              color: this.highlightIsHidden() ? COLOR_PRIMARY : COLOR_TRANSPARENT })
            .borderRadius(9)
        }
      }
      }
    }
  }
}
