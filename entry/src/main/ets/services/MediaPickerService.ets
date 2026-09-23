import photoAccessHelper from '@ohos.file.photoAccessHelper';
import fs from '@ohos.file.fs';
import picker from '@ohos.file.picker';
import image from '@ohos.multimedia.image';
import fileUri from '@ohos.file.fileuri';
import { AbilityContextHolder } from './AbilityContextHolder';
import { logRecoverableError, normalizeError } from './ErrorUtils';
import { VaultItemType } from '../models/VaultModels';
import {
  checkedTotalBytes,
  isSupportedAudioFileName,
  validateImportedAttachmentSize
} from './VaultCorePolicy';
import {
  MAX_AUDIO_ATTACHMENTS,
  MAX_MEDIA_IMPORT_BATCH_BYTES
} from './VaultLimits';

export interface PickedMedia {
  uri: string;
  type: VaultItemType;
  name: string;
  ocrText: string;
  // Empty means that the source was created privately and never belonged to the system gallery.
  sourceUri?: string;
}

export class MediaPickerService {
  private audioImportWarning: string = '';

  takeAudioImportWarning(): string {
    const warning = this.audioImportWarning;
    this.audioImportWarning = '';
    return warning;
  }

  async pickAudio(): Promise<PickedMedia[]> {
    try {
      this.audioImportWarning = '';
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = MAX_AUDIO_ATTACHMENTS;
      options.fileSuffixFilters = ['音频文件|.mp3,.m4a,.aac,.wav,.amr,.flac,.ogg'];
      const uris = await new picker.DocumentViewPicker().select(options);
      const picked: PickedMedia[] = [];
      const rejected: string[] = [];
      for (let index = 0; index < uris.length; index += 1) {
        const uri = uris[index];
        const name = this.fileName(uri, VaultItemType.Audio);
        if (!isSupportedAudioFileName(name)) {
          rejected.push(`“${name}”格式不受支持`);
          continue;
        }
        try { validateImportedAttachmentSize(VaultItemType.Audio, this.fileSize(uri), name); }
        catch (error) { rejected.push(normalizeError(error).message); continue; }
        picked.push({ uri: uri, sourceUri: uri, type: VaultItemType.Audio, name: name, ocrText: '' });
      }
      if (rejected.length > 0) {
        this.audioImportWarning = `${rejected.length} 个音频未导入：${rejected.slice(0, 2).join('；')}`;
      }
      if (picked.length === 0 && rejected.length > 0) { throw new Error(this.audioImportWarning); }
      return picked;
    } catch (error) {
      const message = normalizeError(error).message;
      if (this.audioImportWarning.length > 0) { throw new Error(this.audioImportWarning); }
      if (message.indexOf('格式不受支持') >= 0 || message.indexOf('超过 10 MB') >= 0) {
        throw new Error(message);
      }
      throw new Error('音频导入失败，请确认文件完整且格式受支持');
    }
  }

  async pickFiles(): Promise<PickedMedia[]> {
    try {
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 50;
    const uris = await new picker.DocumentViewPicker().select(options);
    const picked: PickedMedia[] = [];
    try {
      for (let index = 0; index < uris.length; index += 1) {
        const uri = uris[index];
        const name = this.fileName(uri, VaultItemType.File);
        validateImportedAttachmentSize(VaultItemType.File, this.fileSize(uri), name);
        picked.push({
          uri: uri,
          type: VaultItemType.File,
          name: name,
          ocrText: ''
        });
      }
      return picked;
    } catch (error) {
      const message = normalizeError(error).message;
      if (message.indexOf('超过 10 MB') >= 0) { throw new Error(message); }
      throw new Error('文件导入失败，请确认所选文件完整且大小受支持');
    }
      } catch (error) {
      throw normalizeError(error);
    }
  }

  async pickMany(preselectedUris: string[] = []): Promise<PickedMedia[]> {
    try {
    const options = new photoAccessHelper.PhotoSelectOptions();
    options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_VIDEO_TYPE;
    options.maxSelectNumber = 50;
    options.preselectedUris = preselectedUris;
    const result = await new photoAccessHelper.PhotoViewPicker().select(options);
    const picked: PickedMedia[] = [];
    try {
      let totalBytes = 0;
      for (let index = 0; index < result.photoUris.length; index += 1) {
        const uri = result.photoUris[index];
        const type = await this.detectMediaType(uri);
        const name = this.fileName(uri, type);
        const size = this.fileSize(uri);
        validateImportedAttachmentSize(type, size, name);
        totalBytes = checkedTotalBytes(totalBytes, size, MAX_MEDIA_IMPORT_BATCH_BYTES,
          '一次导入的图片和视频总大小不能超过 1 GB');
        picked.push({ uri: uri, sourceUri: uri, type: type, name: name, ocrText: '' });
      }
      return picked;
    } catch (error) {
      const message = normalizeError(error).message;
      if (message.indexOf('超过 64 MB') >= 0 || message.indexOf('超过 500 MB') >= 0 ||
        message.indexOf('不能超过 1 GB') >= 0 ||
        message.indexOf('内容为空') >= 0) {
        throw new Error(message);
      }
      throw new Error('媒体导入失败，请确认所选文件完整且受支持');
    }
      } catch (error) {
      throw normalizeError(error);
    }
  }

  async saveMediaToGallery(path: string, type: VaultItemType, title: string): Promise<string> {
    try {
    const saved = await this.saveMediaBatchToGallery([path], [type], [title]);
    return saved.length > 0 ? saved[0] : '';
      } catch (error) {
      throw normalizeError(error);
    }
  }

  async saveMediaBatchToGallery(paths: string[], types: VaultItemType[], titles: string[]): Promise<string[]> {
    try {
    if (paths.length === 0 || paths.length !== types.length || paths.length !== titles.length) { return []; }
    const helper = photoAccessHelper.getPhotoAccessHelper(AbilityContextHolder.getContext());
    const configs: photoAccessHelper.PhotoCreationConfig[] = [];
    const uris: string[] = [];
    for (let index = 0; index < paths.length; index += 1) {
      const type = types[index];
      uris.push(fileUri.getUriFromPath(paths[index]));
      configs.push({
        title: this.albumTitle(titles[index]),
        fileNameExtension: type === VaultItemType.Video ? 'mp4' : 'jpg',
        photoType: type === VaultItemType.Video ? photoAccessHelper.PhotoType.VIDEO : photoAccessHelper.PhotoType.IMAGE
      });
    }
    const albumUris = await helper.showAssetsCreationDialog(uris, configs);
    if (albumUris.length !== paths.length) { return albumUris; }
    for (let index = 0; index < paths.length; index += 1) {
      let source: fs.File | undefined = undefined;
      let target: fs.File | undefined = undefined;
      try {
        source = fs.openSync(paths[index], fs.OpenMode.READ_ONLY);
        target = fs.openSync(albumUris[index], fs.OpenMode.READ_WRITE);
        await fs.copyFile(source.fd, target.fd);
        fs.fsyncSync(target.fd);
      } finally {
        if (target) { fs.closeSync(target); }
        if (source) { fs.closeSync(source); }
      }
    }
    return albumUris;
      } catch (error) {
      throw normalizeError(error);
    }
  }

  isMediaInGallery(uri: string): boolean {
    try {
    if (uri.length === 0) { return false; }
    let file: fs.File | undefined = undefined;
    try {
      file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      return fs.statSync(file.fd).size > 0;
    } catch (error) {
      return false;
    } finally {
      if (file) { fs.closeSync(file); }
    }
      } catch (error) {
      throw normalizeError(error);
    }
  }

  private fileName(uri: string, type: VaultItemType): string {
    const withoutQuery = uri.split('?')[0];
    const slash = Math.max(withoutQuery.lastIndexOf('/'), withoutQuery.lastIndexOf('\\'));
    let name = slash >= 0 ? withoutQuery.substring(slash + 1) : withoutQuery;
    try { name = decodeURIComponent(name); }
    catch (error) { logRecoverableError('could not decode selected file name', error); }
    if (name.length > 0 && name.indexOf('.') > 0) { return this.safeFileName(name); }
    if (type === VaultItemType.Image) { return '私密图片.jpg'; }
    if (type === VaultItemType.Video) { return '私密视频.mp4'; }
    if (type === VaultItemType.Audio) { return '未命名音频.m4a'; }
    return '私密文件';
  }

  private fileSize(uri: string): number {
    let file: fs.File | undefined = undefined;
    try {
      file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      return fs.statSync(file.fd).size;
    } catch (error) {
      throw normalizeError(error);
    } finally {
      if (file) {
        try { fs.closeSync(file); }
        catch (closeError) { logRecoverableError('could not close selected file after size check', closeError); }
      }
    }
  }

  private async detectMediaType(uri: string): Promise<VaultItemType> {
    try {
    let file: fs.File | undefined = undefined;
    let source: image.ImageSource | undefined = undefined;
    try {
      file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      source = image.createImageSource(file.fd);
      await source.getImageInfo();
      return VaultItemType.Image;
    } catch (error) {
      return VaultItemType.Video;
    } finally {
      if (source) { await source.release(); }
      if (file) { fs.closeSync(file); }
    }
      } catch (error) {
      throw normalizeError(error);
    }
  }

  private safeFileName(name: string): string {
    const cleaned = name.replace(/[\\/:*?"<>|]/g, '_').trim();
    return cleaned.length > 0 ? cleaned : 'PalmKeep文件';
  }

  private albumTitle(name: string): string {
    const safe = this.safeFileName(name);
    const dot = safe.lastIndexOf('.');
    return dot > 0 ? safe.substring(0, dot) : safe;
  }

}

export const mediaPickerService = new MediaPickerService();
