import common from '@ohos.app.ability.common';
import fs from '@ohos.file.fs';
import util from '@ohos.util';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { systemShare } from '@kit.ShareKit';
import { VaultItemType } from '../models/VaultModels';
import { logRecoverableError, normalizeError } from './ErrorUtils';
import { PickedMedia } from './MediaPickerService';
import { MAX_FILE_ATTACHMENT_BYTES } from './VaultLimits';

const SHARE_PREFIX: string = 'pv-share-';
const REQUEST_PREFIX: string = 'pv-share-request-';
const REQUEST_SUFFIX: string = '.json';
const MAX_SHARED_ITEMS: number = 50;
const STALE_AFTER_MS: number = 24 * 60 * 60 * 1000;

export interface PendingShareRequest {
  id: string;
  type: VaultItemType;
  title: string;
  notes: string;
  items: PickedMedia[];
  createdAt: number;
}

class ShareImportService {
  async stage(context: common.Context, data: systemShare.SharedData): Promise<PendingShareRequest> {
    const records = data.getRecords();
    if (records.length === 0) { throw new Error('没有收到可保存的内容'); }
    if (records.length > MAX_SHARED_ITEMS) { throw new Error('一次最多收进 50 项内容'); }

    const id = util.generateRandomUUID();
    const items: PickedMedia[] = [];
    const textParts: string[] = [];
    let requestType: VaultItemType | undefined = undefined;
    let suggestedTitle = '';
    try {
      for (let index = 0; index < records.length; index += 1) {
        const record = records[index];
        if (record.content && record.content.trim().length > 0) {
          textParts.push(record.content.trim());
        } else if (record.description && record.description.trim().length > 0 && !record.uri) {
          textParts.push(record.description.trim());
        }
        if (!record.uri || record.uri.length === 0) {
          if (!suggestedTitle && record.title) { suggestedTitle = record.title.trim(); }
          continue;
        }

        const itemType = this.mediaType(record.utd);
        const groupType = itemType === VaultItemType.File ? VaultItemType.File : VaultItemType.Image;
        if (requestType !== undefined && requestType !== groupType) {
          throw new Error('媒体和普通文件请分开收进密匣');
        }
        requestType = groupType;
        const name = this.sharedName(record, itemType, index + 1);
        const path = this.cachePath(context, id, index + 1, name);
        await this.copyRecord(record.uri, path, itemType, name);
        items.push({ uri: path, sourceUri: '', type: itemType, name: name, ocrText: '' });
        if (!suggestedTitle && record.title) { suggestedTitle = this.titleWithoutExtension(record.title.trim()); }
      }

      if (items.length === 0 && textParts.length === 0) {
        throw new Error('分享内容为空或暂不受支持');
      }
      const type = requestType ?? VaultItemType.Note;
      const request: PendingShareRequest = {
        id: id,
        type: type,
        title: type === VaultItemType.File ? '' : this.requestTitle(suggestedTitle),
        notes: textParts.join('\n\n'),
        items: items,
        createdAt: Date.now()
      };
      this.writeRequest(context, request);
      return request;
    } catch (error) {
      this.removeItems(items);
      this.removePath(this.requestPath(context, id));
      throw normalizeError(error);
    }
  }

  takeRequest(context: common.Context, requestId: string): PendingShareRequest {
    this.validateRequestId(requestId);
    const path = this.requestPath(context, requestId);
    let request: PendingShareRequest | undefined = undefined;
    try {
      request = JSON.parse(fs.readTextSync(path)) as PendingShareRequest;
      if (request.id !== requestId || !Array.isArray(request.items)) {
        throw new Error('分享请求已损坏');
      }
      request.items.forEach((item: PickedMedia): void => {
        if (!this.isOwnedPath(context, item.uri, requestId) || !fs.accessSync(item.uri)) {
          throw new Error('分享内容已失效，请重新分享');
        }
      });
      this.removePath(path);
      return request;
    } catch (error) {
      if (request) { this.removeItems(request.items); }
      this.removePath(path);
      throw normalizeError(error);
    }
  }

  discardRequest(context: common.Context, requestId: string): void {
    try {
      const request = this.takeRequest(context, requestId);
      this.removeItems(request.items);
    } catch (error) {
      logRecoverableError(`could not discard share request ${requestId}`, error);
    }
  }

  cleanupStale(context: common.Context, preserveRequestId: string = ''): number {
    let removed = 0;
    try {
      fs.listFileSync(context.cacheDir).forEach((name: string): void => {
        if (!name.startsWith(SHARE_PREFIX) ||
          (preserveRequestId.length > 0 && name.indexOf(preserveRequestId) >= 0)) {
          return;
        }
        const path = `${context.cacheDir}/${name}`;
        try {
          if (Date.now() - fs.statSync(path).mtime < STALE_AFTER_MS) { return; }
          fs.unlinkSync(path);
          removed += 1;
        } catch (error) {
          logRecoverableError(`could not remove stale shared file ${name}`, error);
        }
      });
    } catch (error) {
      logRecoverableError('could not inspect staged share files', error);
    }
    return removed;
  }

  isStagedPath(context: common.Context, path: string): boolean {
    return path.startsWith(`${context.cacheDir}/${SHARE_PREFIX}`) &&
      !path.startsWith(`${context.cacheDir}/${REQUEST_PREFIX}`);
  }

  private mediaType(typeId: string): VaultItemType {
    if (this.belongsTo(typeId, utd.UniformDataType.IMAGE)) { return VaultItemType.Image; }
    if (this.belongsTo(typeId, utd.UniformDataType.VIDEO)) { return VaultItemType.Video; }
    return VaultItemType.File;
  }

  private belongsTo(typeId: string, parent: string): boolean {
    if (typeId === parent) { return true; }
    try { return utd.getTypeDescriptor(typeId).belongsTo(parent); }
    catch (error) { return false; }
  }

  private async copyRecord(uri: string, path: string, type: VaultItemType, name: string): Promise<void> {
    let source: fs.File | undefined = undefined;
    let target: fs.File | undefined = undefined;
    let completed = false;
    try {
      source = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      const size = fs.statSync(source.fd).size;
      if (size <= 0) { throw new Error(`“${name}”内容为空`); }
      if (type === VaultItemType.File && size > MAX_FILE_ATTACHMENT_BYTES) {
        throw new Error(`文件“${name}”超过 10 MB，请选择较小的文件`);
      }
      target = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      await fs.copyFile(source.fd, target.fd);
      fs.fsyncSync(target.fd);
      if (fs.statSync(target.fd).size !== size) { throw new Error(`“${name}”接收不完整`); }
      completed = true;
    } catch (error) {
      throw normalizeError(error);
    } finally {
      if (target) {
        try { fs.closeSync(target); }
        catch (error) { logRecoverableError(`could not close shared target ${path}`, error); }
      }
      if (source) {
        try { fs.closeSync(source); }
        catch (error) { logRecoverableError(`could not close shared source ${uri}`, error); }
      }
      if (!completed) { this.removePath(path); }
    }
  }

  private writeRequest(context: common.Context, request: PendingShareRequest): void {
    const path = this.requestPath(context, request.id);
    let file: fs.File | undefined = undefined;
    try {
      const bytes = new util.TextEncoder().encodeInto(JSON.stringify(request));
      file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, bytes.buffer as ArrayBuffer, { length: bytes.length });
      fs.fsyncSync(file.fd);
    } catch (error) {
      this.removePath(path);
      throw normalizeError(error);
    } finally {
      if (file) {
        try { fs.closeSync(file); }
        catch (error) { logRecoverableError(`could not close share request ${request.id}`, error); }
      }
    }
  }

  private sharedName(record: systemShare.SharedRecord, type: VaultItemType, sequence: number): string {
    const uriName = this.nameFromUri(record.uri ?? '');
    const title = this.safeName(record.title ?? '');
    if (title.indexOf('.') > 0) { return title; }
    if (uriName.indexOf('.') > 0) { return uriName; }
    const extension = this.typeExtension(record.utd, type);
    if (title.length > 0) { return `${title}${extension}`; }
    return `收进密匣-${sequence}${extension}`;
  }

  private nameFromUri(uri: string): string {
    const plain = uri.split('?')[0];
    const slash = Math.max(plain.lastIndexOf('/'), plain.lastIndexOf('\\'));
    let name = slash >= 0 ? plain.substring(slash + 1) : plain;
    try { name = decodeURIComponent(name); }
    catch (error) { logRecoverableError('could not decode shared file name', error); }
    return this.safeName(name);
  }

  private safeName(name: string): string {
    const cleaned = name.replace(/[\\/:*?"<>|]/g, '_').trim();
    return cleaned.length > 120 ? cleaned.substring(0, 120) : cleaned;
  }

  private typeExtension(typeId: string, type: VaultItemType): string {
    try {
      const extensions = utd.getTypeDescriptor(typeId).filenameExtensions;
      if (extensions.length > 0) {
        return extensions[0].startsWith('.') ? extensions[0] : `.${extensions[0]}`;
      }
    } catch (error) {}
    if (type === VaultItemType.Image) { return '.jpg'; }
    if (type === VaultItemType.Video) { return '.mp4'; }
    return '';
  }

  private cachePath(context: common.Context, id: string, sequence: number, name: string): string {
    const dot = name.lastIndexOf('.');
    const extension = dot > 0 && name.length - dot <= 12 ? name.substring(dot).toLowerCase() : '';
    return `${context.cacheDir}/${SHARE_PREFIX}${id}-${sequence}${extension}`;
  }

  private requestPath(context: common.Context, id: string): string {
    return `${context.cacheDir}/${REQUEST_PREFIX}${id}${REQUEST_SUFFIX}`;
  }

  private requestTitle(suggested: string): string {
    const title = suggested.trim();
    return title.length > 80 ? title.substring(0, 80) : title;
  }

  private titleWithoutExtension(title: string): string {
    const safe = this.safeName(title);
    const dot = safe.lastIndexOf('.');
    return dot > 0 ? safe.substring(0, dot) : safe;
  }

  private validateRequestId(id: string): void {
    if (!/^[0-9a-fA-F-]{20,80}$/.test(id)) { throw new Error('分享请求无效'); }
  }

  private isOwnedPath(context: common.Context, path: string, requestId: string): boolean {
    return path.startsWith(`${context.cacheDir}/${SHARE_PREFIX}${requestId}-`);
  }

  private removeItems(items: PickedMedia[]): void {
    items.forEach((item: PickedMedia): void => { this.removePath(item.uri); });
  }

  private removePath(path: string): void {
    try { if (path.length > 0 && fs.accessSync(path)) { fs.unlinkSync(path); } }
    catch (error) { logRecoverableError(`could not remove staged share path ${path}`, error); }
  }
}

export const shareImportService = new ShareImportService();
