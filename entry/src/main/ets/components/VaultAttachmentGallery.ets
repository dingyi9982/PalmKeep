import fs from '@ohos.file.fs';
import util from '@ohos.util';
import promptAction from '@ohos.promptAction';
import { VaultMedia } from './VaultMedia';
import { VaultThumbnail } from './VaultThumbnail';
import { VaultAttachmentInput, VaultAttachmentSummary, VaultItemType } from '../models/VaultModels';
import { vaultRepository } from '../services/VaultRepository';
import { mediaPickerService, PickedMedia } from '../services/MediaPickerService';
import { mediaCompressionService } from '../services/MediaCompressionService';
import { AbilityContextHolder } from '../services/AbilityContextHolder';

@Component
export struct VaultAttachmentGallery {
  itemId: string = '';
  fallbackType: VaultItemType = VaultItemType.Image;
  @State private attachments: VaultAttachmentSummary[] = [];
  @State private currentIndex: number = 0;
  @State private showFullScreen: boolean = false;
  @State private savingToGallery: boolean = false;
  @State private replacingMedia: boolean = false;
  @State private replaceProgress: number = 0;
  @State private switchingMedia: boolean = false;
  private switchVersion: number = 0;

  aboutToAppear(): void { this.load(); }

  private async load(): Promise<void> {
    this.attachments = await vaultRepository.listItemAttachments(this.itemId);
    this.currentIndex = 0;
    this.switchingMedia = false;
  }

  private move(step: number): void {
    this.selectMedia(this.currentIndex + step);
  }

  private selectMedia(index: number): void {
    if (index < 0 || index >= this.attachments.length || index === this.currentIndex) { return; }
    this.switchVersion += 1;
    const version = this.switchVersion;
    const targetNeedsDecoder = this.attachments[index].type === VaultItemType.Video;
    // Only video needs a release gap. Images switch immediately.
    this.switchingMedia = targetNeedsDecoder;
    this.currentIndex = index;
    if (!targetNeedsDecoder) { return; }
    setTimeout((): void => {
      if (version === this.switchVersion) { this.switchingMedia = false; }
    }, 140);
  }

  private async saveCurrentToGallery(): Promise<void> {
    if (this.savingToGallery || this.replacingMedia || this.attachments.length === 0) { return; }
    this.savingToGallery = true;
    const attachment = this.attachments[this.currentIndex];
    const extension = attachment.type === VaultItemType.Video ? '.mp4' : '.jpg';
    const path = `${AbilityContextHolder.getContext().cacheDir}/pv-export-${util.generateRandomUUID()}${extension}`;
    let file: fs.File | undefined = undefined;
    try {
      file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      const size = await vaultRepository.writeAttachmentToFd(this.itemId, file.fd, attachment.index);
      fs.fsyncSync(file.fd);
      fs.closeSync(file);
      file = undefined;
      if (size <= 0) { throw new Error('媒体数据不可用'); }
      const saved = await mediaPickerService.saveMediaToGallery(path, attachment.type,
        attachment.name.length > 0 ? attachment.name : '掌心密匣媒体');
      if (saved) { promptAction.showToast({ message: '已保存到系统相册' }); }
    } catch (error) {
      promptAction.showToast({ message: '保存到相册失败' });
    } finally {
      if (file) { fs.closeSync(file); }
      try { fs.unlinkSync(path); } catch (error) {}
      this.savingToGallery = false;
    }
  }

  private async replaceMedia(): Promise<void> {
    if (this.replacingMedia || this.savingToGallery) { return; }
    const picked = await mediaPickerService.pickMany();
    if (picked.length === 0) { return; }
    this.replacingMedia = true;
    this.replaceProgress = 0;
    const temporaryPaths: string[] = [];
    try {
      const attachments: VaultAttachmentInput[] = [];
      for (let index = 0; index < picked.length; index += 1) {
        const mediaItem: PickedMedia = picked[index];
        const path = await mediaCompressionService.compress(mediaItem.uri, mediaItem.type,
          (progress: number): void => {
            this.replaceProgress = Math.round(((index + progress / 100) / picked.length) * 70);
          });
        temporaryPaths.push(path);
        attachments.push({ type: mediaItem.type, uri: path, name: mediaItem.name, data: new Uint8Array(0) });
      }
      await vaultRepository.replaceItemAttachments(this.itemId, attachments,
        (completed: number, total: number): void => {
          this.replaceProgress = 70 + Math.round((completed / total) * 30);
        });
      await this.load();
      promptAction.showToast({ message: '媒体已修改' });
    } catch (error) {
      promptAction.showToast({ message: error instanceof Error ? error.message : '媒体修改失败' });
    } finally {
      temporaryPaths.forEach((path: string): void => { mediaCompressionService.removeTemporary(path); });
      picked.forEach((mediaItem: PickedMedia): void => { mediaItem.data.fill(0); });
      this.replacingMedia = false;
      this.replaceProgress = 0;
    }
  }

  @Builder
  private currentMedia(fullScreen: boolean): void {
    ForEach(this.attachments.slice(this.currentIndex, this.currentIndex + 1),
      (attachment: VaultAttachmentSummary): void => {
        VaultMedia({
          itemId: this.itemId,
          mediaType: attachment.type,
          attachmentIndex: attachment.index,
          fullScreenMode: fullScreen,
          requestFullScreen: (): void => { this.showFullScreen = true; }
        })
      }, (attachment: VaultAttachmentSummary): string => `${attachment.index}-${fullScreen}`)
  }

  @Builder
  private thumbnailStrip(): void {
    if (this.attachments.length > 1) {
      Scroll() {
        Row({ space: 7 }) {
          ForEach(this.attachments, (attachment: VaultAttachmentSummary, index: number): void => {
            Stack() {
              VaultThumbnail({
                itemId: this.itemId,
                mediaType: attachment.type,
                attachmentIndex: attachment.index,
                thumbnailSize: 52
              })
            }
            .width(56).height(56).padding(2).borderRadius(13)
            .border({ width: index === this.currentIndex ? 2 : 0,
              color: index === this.currentIndex ? '#2DD6A6' : '#00000000' })
            .onClick((): void => { this.selectMedia(index); })
          }, (attachment: VaultAttachmentSummary): string => `${attachment.index}`)
        }.padding({ left: 2, right: 2 })
      }
      .width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
    }
  }

  @Builder
  private fullScreenViewer(): void {
    Stack({ alignContent: Alignment.Center }) {
      if (this.switchingMedia) {
        LoadingProgress().width(38).height(38).color('#2DD6A6')
      } else {
        this.currentMedia(true)
      }
      if (this.currentIndex > 0) {
        Text('‹').fontSize(38).fontColor('#FFFFFF').textAlign(TextAlign.Center)
          .width(46).height(54).backgroundColor('#55000000').borderRadius(23)
          .position({ left: 12 }).onClick((): void => { this.move(-1); })
      }
      if (this.currentIndex < this.attachments.length - 1) {
        Text('›').fontSize(38).fontColor('#FFFFFF').textAlign(TextAlign.Center)
          .width(46).height(54).backgroundColor('#55000000').borderRadius(23)
          .position({ right: 12 }).onClick((): void => { this.move(1); })
      }
      Row() {
        Text('×').fontSize(28).fontColor('#FFFFFF').textAlign(TextAlign.Center)
          .width(42).height(42).backgroundColor('#66000000').borderRadius(21)
          .onClick((): void => { this.showFullScreen = false; })
        Blank()
        Text(`${this.currentIndex + 1} / ${this.attachments.length}`)
          .fontSize(12).fontColor('#FFFFFF').padding({ left: 12, right: 12, top: 7, bottom: 7 })
          .backgroundColor('#66000000').borderRadius(16)
        Blank()
        Text(this.savingToGallery ? '…' : '⇩').fontSize(22).fontColor('#FFFFFF').textAlign(TextAlign.Center)
          .width(42).height(42).backgroundColor('#66000000').borderRadius(21)
          .onClick((): void => { this.saveCurrentToGallery(); })
      }.width('100%').position({ top: 18, left: 0 }).padding({ left: 16, right: 16 })
    }
    .width('100%').height('100%').backgroundColor('#000000')
    .gesture(PanGesture({ direction: PanDirection.Horizontal, distance: 30 })
      .onActionEnd((event: GestureEvent): void => {
        if (event.offsetX < -60) { this.move(1); }
        if (event.offsetX > 60) { this.move(-1); }
      }))
  }

  build() {
    Column({ space: 9 }) {
      if (this.attachments.length > 0) {
        if (!this.showFullScreen) {
          Stack({ alignContent: Alignment.Center }) {
            if (this.switchingMedia) {
              Stack() {
                LoadingProgress().width(34).height(34).color('#2DD6A6')
              }.width('100%').height(298).backgroundColor('#0A1210').borderRadius(17)
            } else {
              this.currentMedia(false)
            }
            if (this.currentIndex > 0) {
              Text('‹').fontSize(32).fontColor('#FFFFFF').textAlign(TextAlign.Center)
                .width(36).height(44).backgroundColor('#66000000').borderRadius(18)
                .position({ left: 8 }).onClick((): void => { this.move(-1); })
            }
            if (this.currentIndex < this.attachments.length - 1) {
              Text('›').fontSize(32).fontColor('#FFFFFF').textAlign(TextAlign.Center)
                .width(36).height(44).backgroundColor('#66000000').borderRadius(18)
                .position({ right: 8 }).onClick((): void => { this.move(1); })
            }
            Text(`${this.currentIndex + 1} / ${this.attachments.length}`)
              .fontSize(11).fontColor('#FFFFFF').padding({ left: 9, right: 9, top: 5, bottom: 5 })
              .backgroundColor('#66000000').borderRadius(13).position({ top: 9, left: 9 })
          }.width('100%')
          this.thumbnailStrip()
          Row({ space: 10 }) {
            Button(this.savingToGallery ? '正在下载…' : '下载')
              .fontSize(14).fontColor('#C7D2CE').layoutWeight(1).height(42)
              .backgroundColor('#17231F').borderRadius(13)
              .enabled(!this.savingToGallery && !this.replacingMedia)
              .onClick((): void => { this.saveCurrentToGallery(); })
            Button('重新选择媒体')
              .fontSize(14).fontColor('#2DD6A6').layoutWeight(1).height(42)
              .backgroundColor('#173128').borderRadius(13)
              .enabled(!this.replacingMedia && !this.savingToGallery)
              .onClick((): void => { this.replaceMedia(); })
          }.width('100%')
          if (this.replacingMedia) {
            Row({ space: 8 }) {
              Progress({ value: this.replaceProgress, total: 100, type: ProgressType.Linear })
                .layoutWeight(1).height(4).color('#2DD6A6')
              Text(`${this.replaceProgress}%`).fontSize(11).fontColor('#91A9A0')
            }.width('100%')
          }
        }
      } else {
        VaultMedia({ itemId: this.itemId, mediaType: this.fallbackType })
      }
    }.width('100%').bindContentCover(this.showFullScreen, this.fullScreenViewer)
  }
}
