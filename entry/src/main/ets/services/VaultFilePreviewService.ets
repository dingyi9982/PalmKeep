import fs from '@ohos.file.fs';
import fileUri from '@ohos.file.fileuri';
import util from '@ohos.util';
import { filePreview } from '@kit.PreviewKit';
import { VaultAttachmentSummary } from '../models/VaultModels';
import { AbilityContextHolder } from './AbilityContextHolder';
import { logRecoverableError, normalizeError } from './ErrorUtils';
import { vaultRepository } from './VaultRepository';

export enum VaultFilePreviewResult {
  Opened = 'opened',
  Unsupported = 'unsupported'
}

class VaultFilePreviewService {
  canAttempt(name: string): boolean {
    return this.extension(name).length > 0;
  }

  async canPreviewStored(itemId: string, attachment: VaultAttachmentSummary): Promise<boolean> {
    if (!this.canAttempt(attachment.name)) { return false; }
    const path = this.previewPath(attachment.name);
    let target: fs.File | undefined = undefined;
    try {
      target = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      const size = await vaultRepository.writeAttachmentToFd(itemId, target.fd, attachment.index);
      fs.fsyncSync(target.fd);
      fs.closeSync(target);
      target = undefined;
      if (size <= 0) { return false; }
      return await this.canPreviewPath(path);
    } catch (error) {
      logRecoverableError('could not detect stored file preview support', error);
      return false;
    } finally {
      if (target) {
        try { fs.closeSync(target); }
        catch (closeError) { logRecoverableError('could not close preview support copy', closeError); }
      }
      this.remove(path);
    }
  }

  async canPreviewUri(sourceUri: string, name: string): Promise<boolean> {
    if (!this.canAttempt(name)) { return false; }
    const path = this.previewPath(name);
    let source: fs.File | undefined = undefined;
    let target: fs.File | undefined = undefined;
    try {
      source = fs.openSync(sourceUri, fs.OpenMode.READ_ONLY);
      const size = fs.statSync(source.fd).size;
      if (size <= 0) { return false; }
      target = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      await fs.copyFile(source.fd, target.fd);
      fs.fsyncSync(target.fd);
      if (fs.statSync(target.fd).size !== size) { return false; }
      fs.closeSync(target);
      target = undefined;
      fs.closeSync(source);
      source = undefined;
      return await this.canPreviewPath(path);
    } catch (error) {
      logRecoverableError('could not detect pending file preview support', error);
      return false;
    } finally {
      if (target) {
        try { fs.closeSync(target); }
        catch (closeError) { logRecoverableError('could not close pending preview support target', closeError); }
      }
      if (source) {
        try { fs.closeSync(source); }
        catch (closeError) { logRecoverableError('could not close pending preview support source', closeError); }
      }
      this.remove(path);
    }
  }

  async open(itemId: string, attachment: VaultAttachmentSummary): Promise<VaultFilePreviewResult> {
    const path = this.previewPath(attachment.name);
    let target: fs.File | undefined = undefined;
    try {
      target = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      const size = await vaultRepository.writeAttachmentToFd(itemId, target.fd, attachment.index);
      fs.fsyncSync(target.fd);
      fs.closeSync(target);
      target = undefined;
      if (size <= 0) { throw new Error('文件内容不可用'); }
      return await this.openCopiedPath(path, attachment.name);
    } catch (error) {
      if (target) {
        try { fs.closeSync(target); }
        catch (closeError) { logRecoverableError('could not close file preview copy', closeError); }
      }
      this.remove(path);
      throw new Error(`文件预览失败：${normalizeError(error).message}`);
    }
  }

  async openUri(sourceUri: string, name: string): Promise<VaultFilePreviewResult> {
    const path = this.previewPath(name);
    let source: fs.File | undefined = undefined;
    let target: fs.File | undefined = undefined;
    try {
      source = fs.openSync(sourceUri, fs.OpenMode.READ_ONLY);
      const size = fs.statSync(source.fd).size;
      if (size <= 0) { throw new Error('文件内容不可用'); }
      target = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      await fs.copyFile(source.fd, target.fd);
      fs.fsyncSync(target.fd);
      if (fs.statSync(target.fd).size !== size) { throw new Error('文件复制不完整'); }
      fs.closeSync(target);
      target = undefined;
      fs.closeSync(source);
      source = undefined;
      return await this.openCopiedPath(path, name);
    } catch (error) {
      if (target) {
        try { fs.closeSync(target); }
        catch (closeError) { logRecoverableError('could not close pending preview target', closeError); }
      }
      if (source) {
        try { fs.closeSync(source); }
        catch (closeError) { logRecoverableError('could not close pending preview source', closeError); }
      }
      this.remove(path);
      throw new Error(`文件预览失败：${normalizeError(error).message}`);
    }
  }

  private async openCopiedPath(path: string, name: string): Promise<VaultFilePreviewResult> {
    const context = AbilityContextHolder.getContext();
    if (!await this.canPreviewPath(path)) {
      this.remove(path);
      return VaultFilePreviewResult.Unsupported;
    }
    const uri = fileUri.getUriFromPath(path);
    await filePreview.openPreview(context, {
      title: name.length > 0 ? name : '未命名文件',
      uri: uri,
      mimeType: this.mimeType(name)
    });
    // Preview Kit may keep reading the file after openPreview returns. The copy stays in
    // cache so the system can finish rendering it, and the OS can reclaim it safely later.
    return VaultFilePreviewResult.Opened;
  }

  private async canPreviewPath(path: string): Promise<boolean> {
    return await filePreview.canPreview(AbilityContextHolder.getContext(), fileUri.getUriFromPath(path));
  }

  private previewPath(name: string): string {
    return `${AbilityContextHolder.getContext().cacheDir}/pv-preview-${util.generateRandomUUID()}${this.extension(name)}`;
  }

  private extension(name: string): string {
    const dot = name.lastIndexOf('.');
    if (dot < 0 || dot === name.length - 1) { return ''; }
    const extension = name.substring(dot).toLowerCase();
    return /^\.[a-z0-9]{1,12}$/.test(extension) ? extension : '';
  }

  private mimeType(name: string): string {
    const extension = this.extension(name);
    switch (extension) {
      case '.pdf': return 'application/pdf';
      case '.txt': return 'text/plain';
      case '.md': return 'text/markdown';
      case '.csv': return 'text/csv';
      case '.json': return 'application/json';
      case '.xml': return 'application/xml';
      case '.html':
      case '.htm': return 'text/html';
      case '.doc': return 'application/msword';
      case '.docx': return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case '.xls': return 'application/vnd.ms-excel';
      case '.xlsx': return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case '.ppt': return 'application/vnd.ms-powerpoint';
      case '.pptx': return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      case '.rtf': return 'application/rtf';
      case '.jpg':
      case '.jpeg': return 'image/jpeg';
      case '.png': return 'image/png';
      case '.gif': return 'image/gif';
      case '.webp': return 'image/webp';
      case '.svg': return 'image/svg+xml';
      case '.mp3': return 'audio/mpeg';
      case '.wav': return 'audio/wav';
      case '.mp4': return 'video/mp4';
      default: return 'application/octet-stream';
    }
  }

  private remove(path: string): void {
    try { fs.unlinkSync(path); }
    catch (error) { logRecoverableError('could not remove file preview copy', error); }
  }
}

export const vaultFilePreviewService = new VaultFilePreviewService();
