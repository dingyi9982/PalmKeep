import fs from '@ohos.file.fs';
import util from '@ohos.util';
import { VaultMedia } from './VaultMedia';
import { VaultThumbnail } from './VaultThumbnail';
import { VaultAttachmentInput, VaultAttachmentSummary, VaultItemType } from '../models/VaultModels';
import { vaultRepository } from '../services/VaultRepository';
import { mediaPickerService, PickedMedia } from '../services/MediaPickerService';
import { mediaCompressionService } from '../services/MediaCompressionService';
import { mediaOcrService } from '../services/MediaOcrService';
import { AbilityContextHolder } from '../services/AbilityContextHolder';

@Component
export struct VaultAttachmentGallery {
  itemId: string = '';
  fallbackType: VaultItemType = VaultItemType.Image;
  initialAttachmentIndex: number = -1;
  readOnly: boolean = false;
  @State private attachments: VaultAttachmentSummary[] = [];
  @State private currentIndex: number = 0;
  @State private overlayMode: string = 'none';
  @State private selectionMode: boolean = false;
  @State private selectedIndexes: number[] = [];
  @State private busy: boolean = false;
  @State private progress: number = 0;
  @State private progressText: string = '';
  @State private switchingMedia: boolean = false;
  @State private fullScreenPlaybackTime: number = 0;
  @State private fullScreenAutoPlay: boolean = false;
  @State private attachmentRevision: number = 0;
  @State private playbackRevision: number = 0;
  private switchVersion: number = 0;
  private thumbnailLongPressTriggered: boolean = false;
  private suppressFullScreenUntil: number = 0;

  aboutToAppear(): void { this.load(); }

  private async load(keepIndex: boolean = false): Promise<void> {
    try {
    const previousIndex = this.currentIndex;
    this.attachments = await vaultRepository.listItemAttachments(this.itemId);
    this.attachmentRevision += 1;
    const initialIndex = this.attachments.findIndex((attachment: VaultAttachmentSummary): boolean =>
      attachment.index === this.initialAttachmentIndex);
    this.currentIndex = keepIndex ? Math.min(previousIndex, Math.max(0, this.attachments.length - 1)) :
      Math.max(0, initialIndex);
    this.switchingMedia = false;
    this.selectedIndexes = this.selectedIndexes.filter((index: number): boolean =>
      this.attachments.some((attachment: VaultAttachmentSummary): boolean => attachment.index === index));
      } catch (error) {
      if (error instanceof Error) { throw error; }
      throw new Error('系统操作失败');
    }
  }

  private move(step: number): void { this.selectMedia(this.currentIndex + step); }

  private closeFullScreen(): void {
    if (this.overlayMode !== 'fullscreen') { return; }
    this.overlayMode = 'none';
    this.playbackRevision += 1;
  }

  private selectMedia(index: number): void {
    if (index < 0 || index >= this.attachments.length || index === this.currentIndex) { return; }
    this.switchVersion += 1;
    const version = this.switchVersion;
    const targetNeedsDecoder = this.attachments[index].type === VaultItemType.Video;
    this.switchingMedia = targetNeedsDecoder;
    this.fullScreenPlaybackTime = 0;
    this.fullScreenAutoPlay = false;
    this.currentIndex = index;
    if (!targetNeedsDecoder) { return; }
    setTimeout((): void => {
      if (version === this.switchVersion) { this.switchingMedia = false; }
    }, 140);
  }

  private isInGallery(attachment: VaultAttachmentSummary): boolean {
    try {
    return mediaPickerService.isMediaInGallery(attachment.sourceUri);
      } catch (error) {
      if (error instanceof Error) { throw error; }
      throw new Error('系统操作失败');
    }
  }

  private exportPath(attachment: VaultAttachmentSummary): string {
    const extension = attachment.type === VaultItemType.Video ? '.mp4' : '.jpg';
    return `${AbilityContextHolder.getContext().cacheDir}/pv-export-${util.generateRandomUUID()}${extension}`;
  }

  private async exportAttachments(selected: VaultAttachmentSummary[]): Promise<void> {
    try {
    if (this.busy || selected.length === 0) { return; }
    const pending = selected.filter((attachment: VaultAttachmentSummary): boolean => !this.isInGallery(attachment));
    const existingCount = selected.length - pending.length;
    if (pending.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '所选素材已存在于系统相册' });
      return;
    }
    this.busy = true;
    this.progress = 0;
    this.progressText = '正在准备下载';
    const paths: string[] = [];
    const types: VaultItemType[] = [];
    const titles: string[] = [];
    try {
      for (let index = 0; index < pending.length; index += 1) {
        const attachment = pending[index];
        const path = this.exportPath(attachment);
        paths.push(path);
        types.push(attachment.type);
        titles.push(attachment.name.length > 0 ? attachment.name : `掌心密匣媒体-${attachment.index + 1}`);
        const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
        try {
          const size = await vaultRepository.writeAttachmentToFd(this.itemId, file.fd, attachment.index);
          fs.fsyncSync(file.fd);
          if (size <= 0) { throw new Error('媒体数据不可用'); }
        } finally { fs.closeSync(file); }
        this.progress = Math.round(((index + 1) / pending.length) * 55);
      }
      this.progressText = '请选择保存到系统相册';
      await AbilityContextHolder.setPrivacyMode(false);
      const savedUris = await mediaPickerService.saveMediaBatchToGallery(paths, types, titles);
      if (savedUris.length !== pending.length) { throw new Error('系统相册没有返回完整的保存结果'); }
      for (let index = 0; index < pending.length; index += 1) {
        await vaultRepository.updateAttachmentSourceUri(this.itemId, pending[index].index, savedUris[index]);
        this.progress = 55 + Math.round(((index + 1) / pending.length) * 45);
      }
      await this.load(true);
      const suffix = existingCount > 0 ? `，另有 ${existingCount} 项已在相册中` : '';
      this.getUIContext().getPromptAction().showToast({ message: `已下载 ${pending.length} 项到系统相册${suffix}` });
    } catch (error) {
      this.getUIContext().getPromptAction().showToast({ message: error instanceof Error ? error.message : '保存到相册失败' });
    } finally {
      paths.forEach((path: string): void => { try { fs.unlinkSync(path); } catch (error) {} });
      this.busy = false;
      this.progress = 0;
      this.progressText = '';
      await AbilityContextHolder.setPrivacyMode(true);
    }
      } catch (error) {
      if (error instanceof Error) { throw error; }
      throw new Error('系统操作失败');
    }
  }

  private saveCurrentToGallery(): void {
    if (this.attachments.length > 0) { this.exportAttachments([this.attachments[this.currentIndex]]); }
  }

  private async importMedia(): Promise<void> {
    try {
    if (this.busy) { return; }
    try {
      const picked = await mediaPickerService.pickMany();
      if (picked.length === 0) { return; }
      this.busy = true;
      this.progress = 0;
      const temporaryPaths: string[] = [];
      try {
        const newMedia = picked.filter((mediaItem: PickedMedia): boolean =>
          this.attachments.every((attachment: VaultAttachmentSummary): boolean =>
            attachment.sourceUri !== mediaItem.uri));
        const duplicateCount = picked.length - newMedia.length;
        const imageCount = newMedia.filter((mediaItem: PickedMedia): boolean =>
          mediaItem.type === VaultItemType.Image).length;
        if (imageCount > 0) {
          this.progressText = `正在识别图片文字 0/${imageCount}`;
          const ocrResults = await mediaOcrService.recognizeBatch(newMedia,
            (completed: number, total: number): void => {
              this.progressText = `正在识别图片文字 ${completed}/${total}`;
              this.progress = Math.round((completed / total) * 25);
            });
          for (let index = 0; index < newMedia.length; index += 1) {
            newMedia[index].ocrText = ocrResults[index];
          }
        }
        const attachments: VaultAttachmentInput[] = [];
        for (let index = 0; index < newMedia.length; index += 1) {
          const mediaItem = newMedia[index];
          this.progressText = `正在压缩 ${index + 1}/${newMedia.length}`;
          const path = await mediaCompressionService.compress(mediaItem.uri, mediaItem.type,
            (value: number): void => {
              this.progress = 25 + Math.round(((index + value / 100) / newMedia.length) * 50);
            });
          temporaryPaths.push(path);
          attachments.push({ type: mediaItem.type, uri: path, sourceUri: mediaItem.uri,
            name: mediaItem.name, ocrText: mediaItem.ocrText, data: new Uint8Array(0) });
        }
        if (attachments.length > 0) {
          this.progressText = '正在写入本地数据';
          await vaultRepository.appendItemAttachments(this.itemId, attachments,
            (completed: number, total: number): void => {
              this.progress = 75 + Math.round((completed / total) * 25);
            });
          await this.load(true);
          this.selectMedia(this.attachments.length - 1);
        }
        let message = `已导入，共 ${newMedia.length} 个素材`;
        if (newMedia.length === 0 && duplicateCount > 0) {
          message = duplicateCount === 1 ? '素材已存在，未重复导入' : `${duplicateCount} 个素材已存在，未重复导入`;
        } else if (duplicateCount > 0) {
          message = `已导入 ${newMedia.length} 个素材，${duplicateCount} 个素材已存在，未重复导入`;
        }
        this.getUIContext().getPromptAction().showToast({ message: message });
      } finally {
        temporaryPaths.forEach((path: string): void => { mediaCompressionService.removeTemporary(path); });
        picked.forEach((mediaItem: PickedMedia): void => { mediaItem.data.fill(0); });
      }
    } catch (error) {
      this.getUIContext().getPromptAction().showToast({ message: error instanceof Error ? error.message : '媒体导入失败' });
    } finally {
      this.busy = false;
      this.progress = 0;
      this.progressText = '';
    }
      } catch (error) {
      if (error instanceof Error) { throw error; }
      throw new Error('系统操作失败');
    }
  }

  private toggleSelectionMode(): void {
    this.selectionMode = !this.selectionMode;
    this.selectedIndexes = [];
  }

  private openManagerWithSelection(attachmentIndex: number): void {
    this.thumbnailLongPressTriggered = true;
    this.selectionMode = true;
    this.selectedIndexes = [attachmentIndex];
    this.overlayMode = 'manager';
    setTimeout((): void => { this.thumbnailLongPressTriggered = false; }, 350);
  }

  private selectManagerAttachment(attachmentIndex: number): void {
    this.thumbnailLongPressTriggered = true;
    this.selectionMode = true;
    if (!this.isSelected(attachmentIndex)) {
      this.selectedIndexes = this.selectedIndexes.concat([attachmentIndex]);
    }
    setTimeout((): void => { this.thumbnailLongPressTriggered = false; }, 350);
  }

  private isSelected(index: number): boolean { return this.selectedIndexes.indexOf(index) >= 0; }

  private toggleSelected(index: number): void {
    const selected = this.selectedIndexes.slice();
    const position = selected.indexOf(index);
    if (position >= 0) { selected.splice(position, 1); } else { selected.push(index); }
    this.selectedIndexes = selected;
  }

  private toggleSelectAll(): void {
    this.selectedIndexes = this.selectedIndexes.length === this.attachments.length ? [] :
      this.attachments.map((attachment: VaultAttachmentSummary): number => attachment.index);
  }

  private selectedAttachments(): VaultAttachmentSummary[] {
    return this.attachments.filter((attachment: VaultAttachmentSummary): boolean =>
      this.selectedIndexes.indexOf(attachment.index) >= 0);
  }

  private async deleteSelected(): Promise<void> {
    try {
    if (this.busy || this.selectedIndexes.length === 0) { return; }
    if (this.selectedIndexes.length === this.attachments.length) {
      this.getUIContext().getPromptAction().showToast({ message: '媒体资料至少需要保留一项' });
      return;
    }
    const result = await this.getUIContext().getPromptAction().showDialog({
      title: '删除所选媒体？',
      message: `将从此资料中永久删除 ${this.selectedIndexes.length} 项媒体。`,
      buttons: [{ text: '取消', color: '#738078' }, { text: '删除', color: '#D95656' }]
    });
    if (result.index !== 1) { return; }
    this.busy = true;
    try {
      await vaultRepository.deleteItemAttachments(this.itemId, this.selectedIndexes);
      this.selectionMode = false;
      this.selectedIndexes = [];
      await this.load();
      this.getUIContext().getPromptAction().showToast({ message: '所选媒体已删除' });
    } catch (error) {
      this.getUIContext().getPromptAction().showToast({ message: error instanceof Error ? error.message : '删除媒体失败' });
    } finally { this.busy = false; }
      } catch (error) {
      if (error instanceof Error) { throw error; }
      throw new Error('系统操作失败');
    }
  }

  @Builder
  private currentMedia(fullScreen: boolean): void {
    ForEach(this.attachments.slice(this.currentIndex, this.currentIndex + 1),
      (attachment: VaultAttachmentSummary): void => {
        VaultMedia({ itemId: this.itemId, mediaType: attachment.type, attachmentIndex: attachment.index,
          fullScreenMode: fullScreen,
          initialPlaybackTime: this.fullScreenPlaybackTime,
          autoPlay: this.fullScreenAutoPlay,
          requestFullScreen: (playbackTime: number, playing: boolean): void => {
            if (!fullScreen && Date.now() < this.suppressFullScreenUntil) { return; }
            this.fullScreenPlaybackTime = playbackTime;
            this.fullScreenAutoPlay = playing;
            this.overlayMode = 'fullscreen';
          },
          onPlaybackStateChange: (playbackTime: number, playing: boolean): void => {
            if ((fullScreen && this.overlayMode === 'fullscreen') ||
              (!fullScreen && this.overlayMode !== 'fullscreen')) {
              this.fullScreenPlaybackTime = playbackTime;
              this.fullScreenAutoPlay = playing;
            }
          } })
      }, (attachment: VaultAttachmentSummary): string =>
        `${this.attachmentRevision}-${this.playbackRevision}-${attachment.index}-${fullScreen}`)
  }

  @Builder
  private thumbnailStrip(): void {
    if (this.attachments.length > 0) {
      Scroll() {
        Row({ space: 7 }) {
          ForEach(this.attachments, (attachment: VaultAttachmentSummary, index: number): void => {
            Stack({ alignContent: Alignment.TopStart }) {
              VaultThumbnail({ itemId: this.itemId, mediaType: attachment.type,
                attachmentIndex: attachment.index, thumbnailSize: 52 })
              Circle({ width: 9, height: 9 })
                .fill(this.isInGallery(attachment) ? '#28C997' : '#F1B84B')
                .stroke('#FFFFFF').strokeWidth(2).margin({ top: 5, left: 5 })
            }
            .width(56).height(56).padding(2).borderRadius(13)
            .border({ width: index === this.currentIndex ? 2 : 0,
              color: index === this.currentIndex ? '#2DD6A6' : '#00000000' })
            .onClick((): void => {
              if (this.thumbnailLongPressTriggered) {
                this.thumbnailLongPressTriggered = false;
                return;
              }
              this.selectMedia(index);
            })
            .priorityGesture(LongPressGesture({ repeat: false, duration: 500 })
              .onAction((): void => {
                if (!this.readOnly) { this.openManagerWithSelection(attachment.index); }
              }))
          }, (attachment: VaultAttachmentSummary): string =>
            `${this.attachmentRevision}-${attachment.index}`)
        }.padding({ left: 2, right: 2 })
      }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
    }
  }

  @Builder
  private currentOcrText(): void {
    if (this.currentIndex >= 0 && this.currentIndex < this.attachments.length &&
      this.attachments[this.currentIndex].type === VaultItemType.Image &&
      this.attachments[this.currentIndex].ocrText.trim().length > 0) {
      Column({ space: 6 }) {
        Row({ space: 6 }) {
          Text('识别文字').fontSize(12).fontWeight(FontWeight.Medium).fontColor('#23312C')
          Text('只读').fontSize(9).fontColor('#20A47D')
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .backgroundColor('#DDF3EB').borderRadius(8)
        }.width('100%')
        Scroll() {
          Text(this.attachments[this.currentIndex].ocrText)
            .fontSize(12).fontColor('#52665F').lineHeight(19).width('100%')
            .textAlign(TextAlign.Start)
        }
        .width('100%')
        .constraintSize({ maxHeight: 108 })
        .scrollBar(BarState.Auto)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 11, right: 11, top: 9, bottom: 9 })
      .backgroundColor('#F0F8F5')
      .border({ width: { left: 3 }, color: '#20A47D' })
      .borderRadius(10)
    }
  }

  @Builder
  private progressRow(): void {
    if (this.busy && this.progressText.length > 0) {
      Column({ space: 6 }) {
        Row() {
          Text(this.progressText).fontSize(11).fontColor('#91A9A0').layoutWeight(1)
          Text(`${this.progress}%`).fontSize(11).fontColor('#91A9A0')
        }.width('100%')
        Progress({ value: this.progress, total: 100, type: ProgressType.Linear })
          .width('100%').height(4).color('#2DD6A6')
      }.width('100%')
    }
  }

  @Builder
  private fullScreenViewer(): void {
    Stack({ alignContent: Alignment.Center }) {
      if (this.switchingMedia) { LoadingProgress().width(38).height(38).color('#2DD6A6') }
      else { this.currentMedia(true) }
      Row() {
        if (this.currentIndex > 0) {
          Text('‹').fontSize(38).fontColor('#FFFFFF').textAlign(TextAlign.Center)
            .width(46).height(54).backgroundColor('#55000000').borderRadius(23)
            .onClick((): void => { this.move(-1); })
        } else {
          Blank().width(46).height(54)
        }
        Blank()
        Stack({ alignContent: Alignment.Center }) {
          if (this.busy) {
            Text('…').fontSize(22).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
              .width(30).height(30).textAlign(TextAlign.Center)
          } else {
            Text('↓').fontSize(21).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
              .width(30).height(30).textAlign(TextAlign.Center)
              .position({ left: 8, top: 5 })
            Divider().width(16).strokeWidth(3).color('#FFFFFF').borderRadius(2)
              .position({ left: 15, bottom: 18 })
          }
        }
        .width(46).height(54).backgroundColor('#66000000').borderRadius(23)
        .onClick((): void => { this.saveCurrentToGallery(); })
        Blank()
        if (this.currentIndex < this.attachments.length - 1) {
          Text('›').fontSize(38).fontColor('#FFFFFF').textAlign(TextAlign.Center)
            .width(46).height(54).backgroundColor('#55000000').borderRadius(23)
            .onClick((): void => { this.move(1); })
        } else {
          Blank().width(46).height(54)
        }
      }
      .width('100%').height(54).padding({ left: 18, right: 18 })
      .alignItems(VerticalAlign.Bottom)
      .position({ left: 0, bottom: 24 }).zIndex(10)
      Stack({ alignContent: Alignment.Center }) {
        Text('×').fontSize(28).fontColor('#FFFFFF').textAlign(TextAlign.Center)
          .width(42).height(42).backgroundColor('#66000000').borderRadius(21)
      }
      .width(58).height(58).position({ top: 33, right: 6 }).zIndex(20)
      .hitTestBehavior(HitTestMode.Block)
      .priorityGesture(TapGesture().onAction((): void => { this.closeFullScreen(); }))
      Text(`${this.currentIndex + 1} / ${this.attachments.length}`).fontSize(12).fontColor('#FFFFFF')
        .padding({ left: 12, right: 12, top: 7, bottom: 7 }).backgroundColor('#66000000')
        .borderRadius(16).position({ top: 47, left: 16 })
    }
    .width('100%').height('100%').backgroundColor('#000000')
    .gesture(PanGesture({ direction: PanDirection.Horizontal, distance: 30 })
      .onActionEnd((event: GestureEvent): void => {
        if (event.offsetX < -60) { this.move(1); }
        if (event.offsetX > 60) { this.move(-1); }
      }))
  }

  @Builder
  private managerThumbnail(attachment: VaultAttachmentSummary): void {
    Stack({ alignContent: Alignment.TopEnd }) {
      VaultThumbnail({ itemId: this.itemId, mediaType: attachment.type,
        attachmentIndex: attachment.index, thumbnailSize: 104 })
      if (attachment.type === VaultItemType.Video) {
        Text('▶').fontSize(15).fontColor('#FFFFFF').textAlign(TextAlign.Center)
          .width(30).height(30).backgroundColor('#77000000').borderRadius(15).position({ left: 8, bottom: 8 })
      }
      Circle({ width: 11, height: 11 })
        .fill(this.isInGallery(attachment) ? '#28C997' : '#F1B84B')
        .stroke('#FFFFFF').strokeWidth(2).position({ left: 7, top: 7 })
      if (this.selectionMode) {
        Text(this.isSelected(attachment.index) ? '✓' : '').fontSize(15).fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF').textAlign(TextAlign.Center).width(26).height(26)
          .backgroundColor(this.isSelected(attachment.index) ? '#22B98B' : '#66000000')
          .border({ width: 2, color: '#FFFFFF' }).borderRadius(13).margin({ top: 7, right: 7 })
      }
    }
    .width('100%').aspectRatio(1).borderRadius(15).clip(true)
    .border({ width: this.isSelected(attachment.index) ? 3 : 1,
      color: this.isSelected(attachment.index) ? '#2DD6A6' : '#DFE8E4' })
    .onClick((): void => {
      if (this.thumbnailLongPressTriggered) {
        this.thumbnailLongPressTriggered = false;
        return;
      }
      if (this.selectionMode) { this.toggleSelected(attachment.index); }
      else {
        const index = this.attachments.findIndex((item: VaultAttachmentSummary): boolean =>
          item.index === attachment.index);
        if (index >= 0) { this.currentIndex = index; this.overlayMode = 'none'; }
      }
    })
    .priorityGesture(LongPressGesture({ repeat: false, duration: 500 })
      .onAction((): void => { this.selectManagerAttachment(attachment.index); }))
  }

  @Builder
  private mediaManager(): void {
    Stack() {
      Column() {
        Row({ space: 10 }) {
        Text('×').fontSize(25).fontColor('#18231F').textAlign(TextAlign.Center)
          .width(38).height(38).backgroundColor('#EEF3F1').borderRadius(19)
          .onClick((): void => { if (!this.busy) { this.overlayMode = 'none'; } })
        Column({ space: 1 }) {
          Text('媒体管理').fontSize(20).fontWeight(FontWeight.Bold).fontColor('#18231F')
          Text(`${this.attachments.length} 项媒体`).fontSize(11).fontColor('#738078')
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Button('添加').height(36).fontSize(13).fontColor('#20A47D').backgroundColor('#E7F7F1')
          .borderRadius(18).enabled(!this.busy).onClick((): void => { this.importMedia(); })
        Button(this.selectionMode ? '取消' : '选择').height(36).fontSize(13)
          .fontColor(this.selectionMode ? '#738078' : '#20A47D').backgroundColor('#F0F4F2')
          .borderRadius(18).enabled(!this.busy).onClick((): void => { this.toggleSelectionMode(); })
        }.width('100%').padding({ left: 14, right: 14, top: 40, bottom: 10 })
        Row({ space: 7 }) {
          Circle({ width: 8, height: 8 }).fill('#28C997')
          Text('已在相册').fontSize(11).fontColor('#718078')
          Blank().width(7)
          Circle({ width: 8, height: 8 }).fill('#F1B84B')
          Text('未在相册').fontSize(11).fontColor('#718078')
        }.width('100%').padding({ left: 17, right: 17, bottom: 8 })
        if (this.selectionMode) {
          Row() {
          Text(`已选择 ${this.selectedIndexes.length} 项`).fontSize(13).fontColor('#35443E')
          Blank()
          Text(this.selectedIndexes.length === this.attachments.length ? '取消全选' : '全选')
            .fontSize(13).fontColor('#20A47D').padding({ left: 12, right: 4, top: 8, bottom: 8 })
            .onClick((): void => { this.toggleSelectAll(); })
          }.width('100%').padding({ left: 16, right: 16, bottom: 6 })
        }
        Grid() {
          ForEach(this.attachments, (attachment: VaultAttachmentSummary): void => {
            GridItem() { this.managerThumbnail(attachment) }
          }, (attachment: VaultAttachmentSummary): string =>
            `manager-${this.attachmentRevision}-${attachment.index}`)
        }
        .columnsTemplate('1fr 1fr 1fr').columnsGap(8).rowsGap(8)
        .width('100%').layoutWeight(1).padding({ left: 12, right: 12, top: 4, bottom: 10 })
        .scrollBar(BarState.Off)
        if (this.selectionMode) {
          Row({ space: 10 }) {
          Button('删除').layoutWeight(1).height(44).fontSize(15).fontColor('#D95656')
            .backgroundColor('#FFF0F0').borderRadius(15).enabled(this.selectedIndexes.length > 0 && !this.busy)
            .opacity(this.selectedIndexes.length > 0 ? 1 : 0.45).onClick((): void => { this.deleteSelected(); })
          Button('下载到相册').layoutWeight(1).height(44).fontSize(15).fontColor('#FFFFFF')
            .backgroundColor('#20B88A').borderRadius(15).enabled(this.selectedIndexes.length > 0 && !this.busy)
            .opacity(this.selectedIndexes.length > 0 ? 1 : 0.45)
            .onClick((): void => { this.exportAttachments(this.selectedAttachments()); })
          }.width('100%').padding({ left: 14, right: 14, top: 8, bottom: 14 })
        }
      }.width('100%').height('100%').backgroundColor('#F7FAF9')
      if (this.busy) {
        Column({ space: 14 }) {
          LoadingProgress().width(46).height(46).color('#2DD6A6')
          Text(this.progressText.length > 0 ? this.progressText : '正在处理媒体')
            .fontSize(15).fontWeight(FontWeight.Medium).fontColor('#23312C')
          Progress({ value: this.progress, total: 100, type: ProgressType.Linear })
            .width('68%').height(5).color('#2DD6A6')
          Text(`${this.progress}%`).fontSize(12).fontColor('#718078')
        }
        .width('100%').height('100%')
        .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
        .backgroundColor('#F2FFFFFF')
      }
    }.width('100%').height('100%').backgroundColor('#F7FAF9')
  }

  build() {
    Column({ space: 9 }) {
      if (this.attachments.length > 0) {
        Row() {
          Text('媒体').fontSize(15).fontWeight(FontWeight.Bold).fontColor('#23312C')
          Text(`${this.attachments.length}`).fontSize(10).fontColor('#718078')
            .padding({ left: 7, right: 7, top: 2, bottom: 2 }).backgroundColor('#EDF2F0').borderRadius(10)
          Blank()
          if (!this.readOnly) {
            Button('添加').height(32).fontSize(13).fontColor('#20A47D').backgroundColor('#00000000')
              .enabled(!this.busy).onClick((): void => { this.importMedia(); })
            Button('管理').height(32).fontSize(13).fontColor('#20A47D').backgroundColor('#00000000')
              .enabled(!this.busy).onClick((): void => {
                this.selectionMode = false; this.selectedIndexes = []; this.overlayMode = 'manager';
              })
          }
        }.width('100%').height(34)
        Stack({ alignContent: Alignment.Center }) {
          if (this.switchingMedia) {
            Stack() { LoadingProgress().width(34).height(34).color('#2DD6A6') }
              .width('100%').height(298).backgroundColor('#0A1210').borderRadius(17)
          } else { this.currentMedia(false) }
          if (this.currentIndex > 0) {
            Text('‹').fontSize(32).fontColor('#FFFFFF').textAlign(TextAlign.Center)
              .width(36).height(44).backgroundColor('#66000000').borderRadius(18)
              .position({ left: 8, top: 121 }).onClick((): void => { this.move(-1); })
          }
          if (this.currentIndex < this.attachments.length - 1) {
            Text('›').fontSize(32).fontColor('#FFFFFF').textAlign(TextAlign.Center)
              .width(36).height(44).backgroundColor('#66000000').borderRadius(18)
              .position({ right: 8, top: 121 }).onClick((): void => { this.move(1); })
          }
          Text(`${this.currentIndex + 1} / ${this.attachments.length}`).fontSize(11).fontColor('#FFFFFF')
            .padding({ left: 9, right: 9, top: 5, bottom: 5 }).backgroundColor('#66000000')
            .borderRadius(13).position({ top: 9, left: 9 })
        }
        .width('100%')
        .priorityGesture(PanGesture({ direction: PanDirection.Horizontal, distance: 20 })
          .onActionStart((): void => { this.suppressFullScreenUntil = Date.now() + 600; })
          .onActionEnd((event: GestureEvent): void => {
            this.suppressFullScreenUntil = Date.now() + 600;
            if (event.offsetX < -60) { this.move(1); }
            if (event.offsetX > 60) { this.move(-1); }
          }))
        this.thumbnailStrip()
        this.currentOcrText()
        this.progressRow()
      } else if (this.attachments.length === 0) {
        VaultMedia({ itemId: this.itemId, mediaType: this.fallbackType })
      }
    }
    .width('100%')
    .bindContentCover(this.overlayMode !== 'none', this.activeOverlay, {
      modalTransition: ModalTransition.NONE,
      onWillDisappear: (): void => {
        if (this.overlayMode === 'fullscreen') {
          this.closeFullScreen();
        } else {
          this.overlayMode = 'none';
        }
      },
      onDisappear: (): void => {
        if (!this.busy) {
          this.selectionMode = false;
          this.selectedIndexes = [];
          this.thumbnailLongPressTriggered = false;
        }
      }
    })
  }

  @Builder
  private activeOverlay(): void {
    if (this.overlayMode === 'fullscreen') {
      this.fullScreenViewer()
    } else if (this.overlayMode === 'manager') {
      this.mediaManager()
    }
  }
}
