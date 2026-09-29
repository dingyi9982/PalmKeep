import fs from '@ohos.file.fs';
import picker from '@ohos.file.picker';
import { VaultAttachmentInput, VaultAttachmentSummary, VaultItemType } from '../models/VaultModels';
import { mediaPickerService, PickedMedia } from '../services/MediaPickerService';
import { vaultRepository } from '../services/VaultRepository';
import { logRecoverableError, normalizeError } from '../services/ErrorUtils';
import {
  vaultFilePreviewService, VaultFilePreviewResult
} from '../services/VaultFilePreviewService';
import {
  ACTION_ADD, ACTION_CANCEL, ACTION_DELETE, ACTION_DOWNLOAD, ACTION_PREVIEW, TITLE_FILES, managementAction
} from './VaultCopy';
import {
  COLOR_DANGER, COLOR_DANGER_TINT, COLOR_MUTED, COLOR_MUTED_DARK, COLOR_ON_DARK,
  COLOR_NEUTRAL_BORDER, COLOR_NEUTRAL_TINT, COLOR_PRIMARY, COLOR_PRIMARY_DARK,
  COLOR_PRIMARY_SELECTED_BG, COLOR_SELECTION_BORDER, COLOR_SURFACE_2,
  COLOR_SURFACE_WASH, COLOR_TEXT_DARK, COLOR_TRANSPARENT
} from './VaultTheme';

@Component
export struct VaultFileGallery {
  itemId: string = '';
  readOnly: boolean = false;
  @State private attachments: VaultAttachmentSummary[] = [];
  @State private managing: boolean = false;
  @State private selectedIndexes: number[] = [];
  @State private busy: boolean = false;
  @State private progress: number = 0;
  @State private progressText: string = '';
  @State private previewableIndexes: number[] = [];
  private previewSupportVersion: number = 0;

  aboutToAppear(): void {
    this.load();
  }

  aboutToDisappear(): void {
    this.previewSupportVersion += 1;
  }

  private async load(): Promise<void> {
    try {
    this.attachments = await vaultRepository.listItemAttachments(this.itemId);
    this.selectedIndexes = this.selectedIndexes.filter((index: number): boolean =>
      this.attachments.some((attachment: VaultAttachmentSummary): boolean => attachment.index === index));
    this.refreshPreviewSupport(this.attachments.slice());
      } catch (error) {
      throw normalizeError(error);
    }
  }

  private async refreshPreviewSupport(attachments: VaultAttachmentSummary[]): Promise<void> {
    const version = ++this.previewSupportVersion;
    const supportedIndexes: number[] = [];
    this.previewableIndexes = [];
    for (let index = 0; index < attachments.length; index += 1) {
      const attachment = attachments[index];
      const supported = await vaultFilePreviewService.canPreviewStored(this.itemId, attachment);
      if (version !== this.previewSupportVersion) { return; }
      if (supported) {
        supportedIndexes.push(attachment.index);
        this.previewableIndexes = supportedIndexes.slice();
      }
    }
  }

  private isPreviewable(index: number): boolean {
    return this.previewableIndexes.indexOf(index) >= 0;
  }

  private isSelected(index: number): boolean {
    return this.selectedIndexes.indexOf(index) >= 0;
  }

  private toggleSelected(index: number): void {
    const selected = this.selectedIndexes.slice();
    const position = selected.indexOf(index);
    if (position >= 0) { selected.splice(position, 1); } else { selected.push(index); }
    this.selectedIndexes = selected;
  }

  private toggleManaging(): void {
    this.managing = !this.managing;
    this.selectedIndexes = [];
  }

  private readableSize(sizeBytes: number): string {
    if (sizeBytes < 1024) { return `${sizeBytes} B`; }
    if (sizeBytes < 1024 * 1024) {
      const value = sizeBytes / 1024;
      return `${value >= 100 ? value.toFixed(0) : value.toFixed(1)} KB`;
    }
    if (sizeBytes < 1024 * 1024 * 1024) {
      const value = sizeBytes / (1024 * 1024);
      return `${value >= 100 ? value.toFixed(0) : value.toFixed(1)} MB`;
    }
    return `${(sizeBytes / (1024 * 1024 * 1024)).toFixed(2)} GB`;
  }

  private async addFiles(): Promise<void> {
    try {
    if (this.busy || this.readOnly) { return; }
    let files: PickedMedia[] = [];
    try {
      files = await mediaPickerService.pickFiles();
      if (files.length === 0) { return; }
      this.busy = true;
      this.progress = 0;
      this.progressText = '正在添加文件';
      const newFiles = files.filter((file: PickedMedia): boolean =>
        this.attachments.every((attachment: VaultAttachmentSummary): boolean =>
          attachment.sourceUri !== file.uri));
      const duplicateCount = files.length - newFiles.length;
      const inputs: VaultAttachmentInput[] = newFiles.map((file: PickedMedia): VaultAttachmentInput => ({
        type: VaultItemType.File,
        uri: file.uri,
        sourceUri: file.uri,
        name: file.name,
        ocrText: ''
      }));
      if (inputs.length > 0) {
        await vaultRepository.appendItemAttachments(this.itemId, inputs,
          (completed: number, total: number): void => {
            this.progress = Math.round(completed / total * 100);
          });
        await this.load();
      }
      let message = `已添加 ${newFiles.length} 个文件`;
      if (newFiles.length === 0 && duplicateCount > 0) {
        message = duplicateCount === 1 ? '文件已存在，未重复添加' : `${duplicateCount} 个文件已存在，未重复添加`;
      } else if (duplicateCount > 0) {
        message = `已添加 ${newFiles.length} 个文件，${duplicateCount} 个文件已存在，未重复添加`;
      }
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (error) {
      this.getUIContext().getPromptAction().showToast({ message: error instanceof Error ? error.message : '添加文件失败' });
    } finally {
      this.busy = false;
      this.progress = 0;
      this.progressText = '';
    }
      } catch (error) {
      throw normalizeError(error);
    }
  }

  private async download(attachment: VaultAttachmentSummary): Promise<void> {
    try {
    if (this.busy) { return; }
    let target: fs.File | undefined = undefined;
    try {
      const options = new picker.DocumentSaveOptions();
      options.newFileNames = [attachment.name.length > 0 ? attachment.name : '掌心密匣文件'];
      const uris = await new picker.DocumentViewPicker().save(options);
      if (uris.length === 0) { return; }
      this.busy = true;
      this.progressText = '正在下载文件';
      this.progress = 20;
      target = fs.openSync(uris[0], fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      const size = await vaultRepository.writeAttachmentToFd(this.itemId, target.fd, attachment.index);
      fs.fsyncSync(target.fd);
      if (size <= 0) { throw new Error('文件内容不可用'); }
      this.progress = 100;
      this.getUIContext().getPromptAction().showToast({ message: '文件已保存' });
    } catch (error) {
      this.getUIContext().getPromptAction().showToast({ message: error instanceof Error ? error.message : '文件下载失败' });
    } finally {
      if (target) { fs.closeSync(target); }
      this.busy = false;
      this.progress = 0;
      this.progressText = '';
    }
      } catch (error) {
      throw normalizeError(error);
    }
  }

  private async preview(attachment: VaultAttachmentSummary): Promise<void> {
    if (this.busy) { return; }
    this.busy = true;
    this.progressText = '正在准备预览';
    try {
      const result = await vaultFilePreviewService.open(this.itemId, attachment);
      if (result === VaultFilePreviewResult.Unsupported) {
        this.previewableIndexes = this.previewableIndexes.filter((index: number): boolean =>
          index !== attachment.index);
        this.getUIContext().getPromptAction().showToast({ message: '该文件暂不支持预览，可下载后用其他应用打开' });
      }
    } catch (error) {
      try {
        this.getUIContext().getPromptAction().showToast({
          message: error instanceof Error ? error.message : '文件预览失败'
        });
      } catch (toastError) {
        logRecoverableError('could not show file preview error', toastError);
      }
    } finally {
      this.busy = false;
      this.progressText = '';
    }
  }

  private async deleteSelected(): Promise<void> {
    try {
    if (this.busy || this.selectedIndexes.length === 0 || this.readOnly) { return; }
    if (this.selectedIndexes.length >= this.attachments.length) {
      this.getUIContext().getPromptAction().showToast({ message: '文件资料至少需要保留一个文件' });
      return;
    }
    const result = await this.getUIContext().getPromptAction().showDialog({
      title: '删除所选文件？',
      message: `将永久删除 ${this.selectedIndexes.length} 个文件，此操作不可恢复。`,
      buttons: [{ text: ACTION_CANCEL, color: COLOR_MUTED_DARK }, { text: ACTION_DELETE, color: COLOR_DANGER }]
    });
    if (result.index !== 1) { return; }
    this.busy = true;
    this.progressText = '正在删除文件';
    try {
      await vaultRepository.deleteItemAttachments(this.itemId, this.selectedIndexes);
      this.managing = false;
      this.selectedIndexes = [];
      await this.load();
      this.getUIContext().getPromptAction().showToast({ message: '所选文件已删除' });
    } catch (error) {
      this.getUIContext().getPromptAction().showToast({ message: error instanceof Error ? error.message : '删除文件失败' });
    } finally {
      this.busy = false;
      this.progressText = '';
    }
      } catch (error) {
      throw normalizeError(error);
    }
  }

  @Builder
  private fileRow(attachment: VaultAttachmentSummary): void {
    Row({ space: 9 }) {
      if (this.managing) {
        Text(this.isSelected(attachment.index) ? '✓' : '')
          .fontSize(13).fontWeight(FontWeight.Bold).fontColor(COLOR_ON_DARK).textAlign(TextAlign.Center)
          .width(24).height(24).borderRadius(12)
          .backgroundColor(this.isSelected(attachment.index) ? COLOR_PRIMARY : COLOR_SELECTION_BORDER)
      }
      Column({ space: 3 }) {
        Text(attachment.name.length > 0 ? attachment.name : '未命名文件')
          .fontSize(13).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_DARK)
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        Text(this.readableSize(attachment.sizeBytes)).fontSize(10).fontColor(COLOR_MUTED)
      }
      .layoutWeight(1).alignItems(HorizontalAlign.Start)
      if (!this.managing) {
        if (this.isPreviewable(attachment.index)) {
          Button(ACTION_PREVIEW).height(32).fontSize(11).fontColor(COLOR_PRIMARY_DARK)
            .backgroundColor(COLOR_TRANSPARENT).borderRadius(10)
            .enabled(!this.busy).onClick((): void => { this.preview(attachment); })
        }
        Button(ACTION_DOWNLOAD).height(32).fontSize(11).fontColor(COLOR_PRIMARY_DARK)
          .backgroundColor(COLOR_TRANSPARENT).borderRadius(10)
          .enabled(!this.busy).onClick((): void => { this.download(attachment); })
      }
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 9, bottom: 9 })
    .backgroundColor(this.isSelected(attachment.index) ? COLOR_PRIMARY_SELECTED_BG : COLOR_SURFACE_2)
    .borderRadius(12)
    .onClick((): void => {
      if (this.managing && !this.busy) { this.toggleSelected(attachment.index); }
    })
  }

  build() {
    Column({ space: 7 }) {
      Row({ space: 7 }) {
        Text(TITLE_FILES).fontSize(14).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_DARK)
        Text(`${this.attachments.length}`).fontSize(10).fontColor(COLOR_MUTED_DARK)
          .padding({ left: 7, right: 7, top: 2, bottom: 2 }).backgroundColor(COLOR_NEUTRAL_TINT).borderRadius(10)
        Blank()
        if (!this.readOnly) {
          Button(ACTION_ADD).height(32).fontSize(12).fontColor(COLOR_PRIMARY_DARK).backgroundColor(COLOR_TRANSPARENT)
            .enabled(!this.busy).onClick((): void => { this.addFiles(); })
          Button(managementAction(this.managing)).height(32).fontSize(12)
            .fontColor(this.managing ? COLOR_MUTED_DARK : COLOR_PRIMARY_DARK).backgroundColor(COLOR_TRANSPARENT)
            .enabled(!this.busy).onClick((): void => { this.toggleManaging(); })
        }
      }.width('100%').height(34)
      ForEach(this.attachments, (attachment: VaultAttachmentSummary): void => {
        this.fileRow(attachment)
      }, (attachment: VaultAttachmentSummary): string => `${attachment.index}-${attachment.name}`)
      if (this.managing) {
        Row({ space: 8 }) {
          Text(`已选择 ${this.selectedIndexes.length} 项`)
            .fontSize(11).fontColor(COLOR_MUTED_DARK).layoutWeight(1)
          Button(`${ACTION_DELETE}所选`).height(36).fontSize(12).fontColor(COLOR_DANGER)
            .backgroundColor(COLOR_DANGER_TINT).borderRadius(11)
            .enabled(this.selectedIndexes.length > 0 && !this.busy)
            .opacity(this.selectedIndexes.length > 0 ? 1 : 0.45)
            .onClick((): void => { this.deleteSelected(); })
        }.width('100%')
      }
      if (this.busy && this.progressText.length > 0) {
        Column({ space: 5 }) {
          Row() {
            Text(this.progressText).fontSize(11).fontColor(COLOR_MUTED_DARK).layoutWeight(1)
            if (this.progress > 0) { Text(`${this.progress}%`).fontSize(11).fontColor(COLOR_PRIMARY_DARK) }
          }.width('100%')
          if (this.progress > 0) {
            Progress({ value: this.progress, total: 100, type: ProgressType.Linear })
              .width('100%').height(4).color(COLOR_PRIMARY)
          }
        }.width('100%')
      }
    }
    .width('100%')
    .padding(10)
    .backgroundColor(COLOR_SURFACE_WASH)
    .border({ width: 1, color: COLOR_NEUTRAL_BORDER })
    .borderRadius(15)
  }
}
