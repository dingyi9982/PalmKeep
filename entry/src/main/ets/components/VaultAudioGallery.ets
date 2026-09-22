import fs from '@ohos.file.fs';
import picker from '@ohos.file.picker';
import { VaultAttachmentInput, VaultAttachmentSummary, VaultItemType } from '../models/VaultModels';
import { mediaPickerService, PickedMedia } from '../services/MediaPickerService';
import { vaultRepository } from '../services/VaultRepository';
import { MAX_AUDIO_ATTACHMENTS } from '../services/VaultLimits';
import { VaultAudioPlayer } from './VaultAudioPlayer';
import {
  COLOR_DANGER, COLOR_DANGER_TINT, COLOR_MUTED, COLOR_MUTED_DARK, COLOR_ON_DARK,
  COLOR_NEUTRAL_BORDER, COLOR_NEUTRAL_TINT, COLOR_PRIMARY, COLOR_PRIMARY_DARK,
  COLOR_PRIMARY_SELECTED_BG, COLOR_SELECTION_BORDER, COLOR_SURFACE_2,
  COLOR_SURFACE_WASH, COLOR_TEXT_DARK, COLOR_TRANSPARENT
} from './VaultTheme';

@Component
export struct VaultAudioGallery {
  itemId: string = '';
  readOnly: boolean = false;
  onRecord: () => void = (): void => {};
  onChanged: () => void = (): void => {};
  @State private attachments: VaultAttachmentSummary[] = [];
  @State private selectedPosition: number = 0;
  @State private managing: boolean = false;
  @State private selectedIndexes: number[] = [];
  @State private busy: boolean = false;
  @State private playerVersion: number = 0;

  aboutToAppear(): void { this.load(); }

  private async load(): Promise<void> {
    this.attachments = (await vaultRepository.listItemAttachments(this.itemId))
      .filter((attachment: VaultAttachmentSummary): boolean => attachment.type === VaultItemType.Audio);
    this.selectedPosition = Math.max(0, Math.min(this.selectedPosition, this.attachments.length - 1));
    this.playerVersion += 1;
  }

  private readableSize(bytes: number): string {
    if (bytes < 1024) { return `${bytes} B`; }
    const kb = bytes / 1024;
    if (kb < 1024) { return `${kb >= 100 ? kb.toFixed(0) : kb.toFixed(1)} KB`; }
    const mb = kb / 1024;
    return `${mb >= 100 ? mb.toFixed(0) : mb.toFixed(1)} MB`;
  }

  private async addAudio(): Promise<void> {
    if (this.busy || this.readOnly) { return; }
    try {
      const picked = await mediaPickerService.pickAudio();
      if (picked.length === 0) { return; }
      const warning = mediaPickerService.takeAudioImportWarning();
      const available = Math.max(0, MAX_AUDIO_ATTACHMENTS - this.attachments.length);
      if (available === 0) { throw new Error('每项音频资料最多保存 50 段音频'); }
      const unique = picked.filter((audio: PickedMedia): boolean =>
        this.attachments.every((attachment: VaultAttachmentSummary): boolean => attachment.sourceUri !== audio.uri));
      const accepted = unique.slice(0, available);
      const duplicateCount = picked.length - unique.length;
      if (accepted.length === 0) {
        this.getUIContext().getPromptAction().showToast({ message: '音频已存在，未重复添加' });
        return;
      }
      this.busy = true;
      const inputs: VaultAttachmentInput[] = accepted.map((audio: PickedMedia): VaultAttachmentInput => ({
        type: VaultItemType.Audio, uri: audio.uri, sourceUri: audio.uri, name: audio.name, ocrText: ''
      }));
      await vaultRepository.appendItemAttachments(this.itemId, inputs);
      await this.load();
      this.selectedPosition = Math.max(0, this.attachments.length - accepted.length);
      this.onChanged();
      let message = `已添加 ${accepted.length} 段音频`;
      if (duplicateCount > 0) { message += `，${duplicateCount} 段已存在`; }
      if (unique.length > accepted.length) { message += '，已达到 50 段上限'; }
      this.getUIContext().getPromptAction().showToast({ message: message });
      if (warning.length > 0) {
        this.getUIContext().getPromptAction().showToast({ message: warning });
      }
    } catch (error) {
      this.getUIContext().getPromptAction().showToast({
        message: error instanceof Error ? error.message : '添加音频失败'
      });
    } finally { this.busy = false; }
  }

  private async download(attachment: VaultAttachmentSummary): Promise<void> {
    if (this.busy) { return; }
    let target: fs.File | undefined = undefined;
    try {
      const options = new picker.DocumentSaveOptions();
      options.newFileNames = [attachment.name.length > 0 ? attachment.name : '掌心密匣音频.m4a'];
      const uris = await new picker.DocumentViewPicker().save(options);
      if (uris.length === 0) { return; }
      this.busy = true;
      target = fs.openSync(uris[0], fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      const size = await vaultRepository.writeAttachmentToFd(this.itemId, target.fd, attachment.index);
      fs.fsyncSync(target.fd);
      if (size <= 0) { throw new Error('音频内容不可用'); }
      this.getUIContext().getPromptAction().showToast({ message: '音频已保存' });
    } catch (error) {
      this.getUIContext().getPromptAction().showToast({
        message: error instanceof Error ? error.message : '音频下载失败'
      });
    } finally {
      if (target) { fs.closeSync(target); }
      this.busy = false;
    }
  }

  private toggleManaging(): void {
    this.managing = !this.managing;
    this.selectedIndexes = [];
  }

  private toggleSelected(index: number): void {
    const values = this.selectedIndexes.slice();
    const position = values.indexOf(index);
    if (position >= 0) { values.splice(position, 1); } else { values.push(index); }
    this.selectedIndexes = values;
  }

  private async deleteSelected(): Promise<void> {
    if (this.busy || this.readOnly || this.selectedIndexes.length === 0) { return; }
    if (this.selectedIndexes.length >= this.attachments.length) {
      this.getUIContext().getPromptAction().showToast({ message: '音频资料至少需要保留一段音频' });
      return;
    }
    const result = await this.getUIContext().getPromptAction().showDialog({
      title: '删除所选音频？', message: `将永久删除 ${this.selectedIndexes.length} 段音频，此操作不可恢复。`,
      buttons: [{ text: '取消', color: COLOR_MUTED_DARK }, { text: '删除', color: COLOR_DANGER }]
    });
    if (result.index !== 1) { return; }
    this.busy = true;
    try {
      await vaultRepository.deleteItemAttachments(this.itemId, this.selectedIndexes);
      this.managing = false;
      this.selectedIndexes = [];
      await this.load();
      this.onChanged();
      this.getUIContext().getPromptAction().showToast({ message: '所选音频已删除' });
    } catch (error) {
      this.getUIContext().getPromptAction().showToast({ message: '删除音频失败' });
    } finally { this.busy = false; }
  }

  @Builder
  private audioRow(attachment: VaultAttachmentSummary, position: number): void {
    Row({ space: 9 }) {
      if (this.managing) {
        Text(this.selectedIndexes.indexOf(attachment.index) >= 0 ? '✓' : '')
          .fontSize(13).fontWeight(FontWeight.Bold).fontColor(COLOR_ON_DARK).textAlign(TextAlign.Center)
          .width(24).height(24).borderRadius(12)
          .backgroundColor(this.selectedIndexes.indexOf(attachment.index) >= 0 ? COLOR_PRIMARY : COLOR_SELECTION_BORDER)
      } else {
        Text('♪').fontSize(18).fontColor(COLOR_PRIMARY_DARK).textAlign(TextAlign.Center)
          .width(34).height(34).backgroundColor(COLOR_NEUTRAL_TINT).borderRadius(10)
      }
      Column({ space: 3 }) {
        Text(attachment.name.length > 0 ? attachment.name : '未命名音频')
          .fontSize(13).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_DARK)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        Text(this.readableSize(attachment.sizeBytes)).fontSize(10).fontColor(COLOR_MUTED)
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      if (!this.managing) {
        Button('下载').height(32).fontSize(11).fontColor(COLOR_PRIMARY_DARK)
          .backgroundColor(COLOR_TRANSPARENT).enabled(!this.busy)
          .onClick((): void => { this.download(attachment); })
      }
    }
    .width('100%').padding({ left: 9, right: 9, top: 8, bottom: 8 })
    .backgroundColor(this.selectedPosition === position || this.selectedIndexes.indexOf(attachment.index) >= 0 ?
      COLOR_PRIMARY_SELECTED_BG : COLOR_SURFACE_2).borderRadius(12)
    .onClick((): void => {
      if (this.managing) { this.toggleSelected(attachment.index); }
      else { this.selectedPosition = position; this.playerVersion += 1; }
    })
  }

  build() {
    Column({ space: 8 }) {
      Row({ space: 7 }) {
        Text('音频').fontSize(14).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_DARK)
        Text(`${this.attachments.length}`).fontSize(10).fontColor(COLOR_MUTED_DARK)
          .padding({ left: 7, right: 7, top: 2, bottom: 2 }).backgroundColor(COLOR_NEUTRAL_TINT).borderRadius(10)
        Blank()
        if (!this.readOnly) {
          Button('导入').height(32).fontSize(12).fontColor(COLOR_PRIMARY_DARK).backgroundColor(COLOR_TRANSPARENT)
            .enabled(!this.busy && this.attachments.length < MAX_AUDIO_ATTACHMENTS)
            .onClick((): void => { this.addAudio(); })
          Button('录音').height(32).fontSize(12).fontColor(COLOR_PRIMARY_DARK).backgroundColor(COLOR_TRANSPARENT)
            .enabled(!this.busy && this.attachments.length < MAX_AUDIO_ATTACHMENTS)
            .onClick((): void => { this.onRecord(); })
          Button(this.managing ? '完成' : '管理').height(32).fontSize(12)
            .fontColor(this.managing ? COLOR_MUTED_DARK : COLOR_PRIMARY_DARK).backgroundColor(COLOR_TRANSPARENT)
            .enabled(!this.busy).onClick((): void => { this.toggleManaging(); })
        }
      }.width('100%')
      if (this.attachments.length > 0 && this.selectedPosition < this.attachments.length) {
        ForEach([this.playerVersion], (_version: number): void => {
          VaultAudioPlayer({ itemId: this.itemId,
            attachmentIndex: this.attachments[this.selectedPosition].index })
        }, (version: number): string => `audio-player-${version}`)
      }
      ForEach(this.attachments, (attachment: VaultAttachmentSummary, position: number): void => {
        this.audioRow(attachment, position)
      }, (attachment: VaultAttachmentSummary): string => `${attachment.index}-${attachment.name}`)
      if (this.managing) {
        Row({ space: 8 }) {
          Text(`已选择 ${this.selectedIndexes.length} 项`).fontSize(11).fontColor(COLOR_MUTED_DARK).layoutWeight(1)
          Button('删除所选').height(36).fontSize(12).fontColor(COLOR_DANGER)
            .backgroundColor(COLOR_DANGER_TINT).borderRadius(11)
            .enabled(this.selectedIndexes.length > 0 && !this.busy)
            .onClick((): void => { this.deleteSelected(); })
        }.width('100%')
      }
    }.width('100%').padding(10).backgroundColor(COLOR_SURFACE_WASH)
      .border({ width: 1, color: COLOR_NEUTRAL_BORDER }).borderRadius(15)
  }
}
