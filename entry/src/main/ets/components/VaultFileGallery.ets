import fs from '@ohos.file.fs';
import picker from '@ohos.file.picker';
import promptAction from '@ohos.promptAction';
import { VaultAttachmentInput, VaultAttachmentSummary, VaultItemType } from '../models/VaultModels';
import { mediaPickerService, PickedMedia } from '../services/MediaPickerService';
import { vaultRepository } from '../services/VaultRepository';

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

  aboutToAppear(): void {
    this.load();
  }

  private async load(): Promise<void> {
    this.attachments = await vaultRepository.listItemAttachments(this.itemId);
    this.selectedIndexes = this.selectedIndexes.filter((index: number): boolean =>
      this.attachments.some((attachment: VaultAttachmentSummary): boolean => attachment.index === index));
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
        ocrText: '',
        data: new Uint8Array(0)
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
      promptAction.showToast({ message: message });
    } catch (error) {
      promptAction.showToast({ message: error instanceof Error ? error.message : '添加文件失败' });
    } finally {
      files.forEach((file: PickedMedia): void => { file.data.fill(0); });
      this.busy = false;
      this.progress = 0;
      this.progressText = '';
    }
  }

  private async download(attachment: VaultAttachmentSummary): Promise<void> {
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
      promptAction.showToast({ message: '文件已保存' });
    } catch (error) {
      promptAction.showToast({ message: error instanceof Error ? error.message : '文件下载失败' });
    } finally {
      if (target) { fs.closeSync(target); }
      this.busy = false;
      this.progress = 0;
      this.progressText = '';
    }
  }

  private async deleteSelected(): Promise<void> {
    if (this.busy || this.selectedIndexes.length === 0 || this.readOnly) { return; }
    if (this.selectedIndexes.length >= this.attachments.length) {
      promptAction.showToast({ message: '文件资料至少需要保留一个文件' });
      return;
    }
    const result = await promptAction.showDialog({
      title: '删除所选文件？',
      message: `将永久删除 ${this.selectedIndexes.length} 个文件，此操作不可恢复。`,
      buttons: [{ text: '取消', color: '#738078' }, { text: '删除', color: '#D95656' }]
    });
    if (result.index !== 1) { return; }
    this.busy = true;
    this.progressText = '正在删除文件';
    try {
      await vaultRepository.deleteItemAttachments(this.itemId, this.selectedIndexes);
      this.managing = false;
      this.selectedIndexes = [];
      await this.load();
      promptAction.showToast({ message: '所选文件已删除' });
    } catch (error) {
      promptAction.showToast({ message: error instanceof Error ? error.message : '删除文件失败' });
    } finally {
      this.busy = false;
      this.progressText = '';
    }
  }

  @Builder
  private fileRow(attachment: VaultAttachmentSummary): void {
    Row({ space: 9 }) {
      if (this.managing) {
        Text(this.isSelected(attachment.index) ? '✓' : '')
          .fontSize(13).fontWeight(FontWeight.Bold).fontColor('#FFFFFF').textAlign(TextAlign.Center)
          .width(24).height(24).borderRadius(12)
          .backgroundColor(this.isSelected(attachment.index) ? '#24B88A' : '#D9E1DE')
      }
      Column({ space: 3 }) {
        Text(attachment.name.length > 0 ? attachment.name : '未命名文件')
          .fontSize(13).fontWeight(FontWeight.Medium).fontColor('#23312C')
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        Text(this.readableSize(attachment.sizeBytes)).fontSize(10).fontColor('#7D8696')
      }
      .layoutWeight(1).alignItems(HorizontalAlign.Start)
      if (!this.managing) {
        Button('下载').height(32).fontSize(11).fontColor('#20A47D')
          .backgroundColor('#E5F6F0').borderRadius(10)
          .enabled(!this.busy).onClick((): void => { this.download(attachment); })
      }
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 9, bottom: 9 })
    .backgroundColor(this.isSelected(attachment.index) ? '#EAF7F2' : '#F0F2F6')
    .borderRadius(12)
    .onClick((): void => {
      if (this.managing && !this.busy) { this.toggleSelected(attachment.index); }
    })
  }

  build() {
    Column({ space: 7 }) {
      Row({ space: 7 }) {
        Text('文件').fontSize(14).fontWeight(FontWeight.Bold).fontColor('#23312C')
        Text(`${this.attachments.length}`).fontSize(10).fontColor('#718078')
          .padding({ left: 7, right: 7, top: 2, bottom: 2 }).backgroundColor('#EDF2F0').borderRadius(10)
        Blank()
        if (!this.readOnly) {
          Button('添加').height(32).fontSize(12).fontColor('#20A47D').backgroundColor('#00000000')
            .enabled(!this.busy).onClick((): void => { this.addFiles(); })
          Button(this.managing ? '取消' : '管理').height(32).fontSize(12)
            .fontColor(this.managing ? '#738078' : '#20A47D').backgroundColor('#00000000')
            .enabled(!this.busy).onClick((): void => { this.toggleManaging(); })
        }
      }.width('100%').height(34)
      ForEach(this.attachments, (attachment: VaultAttachmentSummary): void => {
        this.fileRow(attachment)
      }, (attachment: VaultAttachmentSummary): string => `${attachment.index}-${attachment.name}`)
      if (this.managing) {
        Row({ space: 8 }) {
          Text(`已选择 ${this.selectedIndexes.length} 项`)
            .fontSize(11).fontColor('#738078').layoutWeight(1)
          Button('删除所选').height(36).fontSize(12).fontColor('#D95656')
            .backgroundColor('#FFF0F0').borderRadius(11)
            .enabled(this.selectedIndexes.length > 0 && !this.busy)
            .opacity(this.selectedIndexes.length > 0 ? 1 : 0.45)
            .onClick((): void => { this.deleteSelected(); })
        }.width('100%')
      }
      if (this.busy && this.progressText.length > 0) {
        Column({ space: 5 }) {
          Row() {
            Text(this.progressText).fontSize(11).fontColor('#738078').layoutWeight(1)
            if (this.progress > 0) { Text(`${this.progress}%`).fontSize(11).fontColor('#20A47D') }
          }.width('100%')
          if (this.progress > 0) {
            Progress({ value: this.progress, total: 100, type: ProgressType.Linear })
              .width('100%').height(4).color('#24B88A')
          }
        }.width('100%')
      }
    }
    .width('100%')
    .padding(10)
    .backgroundColor('#FAFCFB')
    .border({ width: 1, color: '#E2E9E6' })
    .borderRadius(15)
  }
}
