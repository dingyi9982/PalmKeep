import photoAccessHelper from '@ohos.file.photoAccessHelper';
import fs from '@ohos.file.fs';
import picker from '@ohos.file.picker';
import image from '@ohos.multimedia.image';
import fileUri from '@ohos.file.fileuri';
import { AbilityContextHolder } from './AbilityContextHolder';
import { VaultItemType } from '../models/VaultModels';

export interface PickedMedia {
  uri: string;
  type: VaultItemType;
  data: Uint8Array;
  name: string;
}

export class MediaPickerService {
  private readonly maxImportBytes: number = 256 * 1024 * 1024;

  async pickFile(type: VaultItemType): Promise<PickedMedia | undefined> {
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 1;
    if (type === VaultItemType.Video) {
      options.fileSuffixFilters = ['视频|.mp4,.mov,.mkv,.m4v,.webm'];
    } else if (type === VaultItemType.Image) {
      options.fileSuffixFilters = ['图片|.png,.jpg,.jpeg,.webp,.heic,.gif'];
    }
    const uris = await new picker.DocumentViewPicker().select(options);
    if (uris.length === 0) { return undefined; }
    return { uri: uris[0], type: type, data: this.readMedia(uris[0]), name: this.fileName(uris[0], type) };
  }

  async pickFiles(): Promise<PickedMedia[]> {
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 50;
    const uris = await new picker.DocumentViewPicker().select(options);
    const picked: PickedMedia[] = [];
    try {
      for (let index = 0; index < uris.length; index += 1) {
        const uri = uris[index];
        picked.push({
          uri: uri,
          type: VaultItemType.File,
          data: new Uint8Array(0),
          name: this.fileName(uri, VaultItemType.File)
        });
      }
      return picked;
    } catch (error) {
      picked.forEach((file: PickedMedia): void => { file.data.fill(0); });
      throw new Error('文件导入失败，请确认所选文件完整且大小受支持');
    }
  }

  async pickOne(preferredType: VaultItemType = VaultItemType.Image): Promise<PickedMedia | undefined> {
    const options = new photoAccessHelper.PhotoSelectOptions();
    options.MIMEType = preferredType === VaultItemType.Video ?
      photoAccessHelper.PhotoViewMIMETypes.VIDEO_TYPE : photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
    options.maxSelectNumber = 1;
    const picker = new photoAccessHelper.PhotoViewPicker();
    const result = await picker.select(options);
    if (result.photoUris.length === 0) {
      return undefined;
    }
    const uri = result.photoUris[0];
    const normalized = uri.toLowerCase();
    const isVideo = preferredType === VaultItemType.Video || normalized.indexOf('video') >= 0 || normalized.endsWith('.mp4') ||
      normalized.endsWith('.mov') || normalized.endsWith('.mkv');
    return {
      uri: uri,
      type: isVideo ? VaultItemType.Video : VaultItemType.Image,
      data: this.readMedia(uri),
      name: this.fileName(uri, isVideo ? VaultItemType.Video : VaultItemType.Image)
    };
  }

  async pickMany(preselectedUris: string[] = []): Promise<PickedMedia[]> {
    const options = new photoAccessHelper.PhotoSelectOptions();
    options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_VIDEO_TYPE;
    options.maxSelectNumber = 50;
    options.preselectedUris = preselectedUris;
    const result = await new photoAccessHelper.PhotoViewPicker().select(options);
    const picked: PickedMedia[] = [];
    try {
      for (let index = 0; index < result.photoUris.length; index += 1) {
        const uri = result.photoUris[index];
        const type = await this.detectMediaType(uri);
        picked.push({ uri: uri, type: type, data: new Uint8Array(0), name: this.fileName(uri, type) });
      }
      return picked;
    } catch (error) {
      picked.forEach((media: PickedMedia): void => { media.data.fill(0); });
      throw new Error('媒体导入失败，请确认所选文件完整且受支持');
    }
  }

  async saveCopy(data: Uint8Array, suggestedName: string): Promise<boolean> {
    const options = new picker.DocumentSaveOptions();
    options.newFileNames = [this.safeFileName(suggestedName)];
    const uris = await new picker.DocumentViewPicker().save(options);
    if (uris.length === 0) { return false; }
    let file: fs.File | undefined = undefined;
    try {
      file = fs.openSync(uris[0], fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      let offset = 0;
      while (offset < data.length) {
        const length = Math.min(1024 * 1024, data.length - offset);
        const written = fs.writeSync(file.fd, data.buffer as ArrayBuffer, { offset: offset, length: length });
        if (written <= 0) { throw new Error('文件写入失败'); }
        offset += written;
      }
      fs.fsyncSync(file.fd);
      return true;
    } finally {
      if (file) { fs.closeSync(file); }
    }
  }

  async saveMediaToGallery(path: string, type: VaultItemType, title: string): Promise<boolean> {
    const helper = photoAccessHelper.getPhotoAccessHelper(AbilityContextHolder.getContext());
    const configs: photoAccessHelper.PhotoCreationConfig[] = [{
      title: title,
      fileNameExtension: type === VaultItemType.Video ? 'mp4' : 'jpg',
      photoType: type === VaultItemType.Video ? photoAccessHelper.PhotoType.VIDEO : photoAccessHelper.PhotoType.IMAGE
    }];
    const saved = await helper.showAssetsCreationDialog([fileUri.getUriFromPath(path)], configs);
    return saved.length > 0;
  }

  downloadName(title: string, sourceUri: string, type: VaultItemType): string {
    const sourceName = this.fileName(sourceUri, type);
    const dot = sourceName.lastIndexOf('.');
    const extension = dot > 0 ? sourceName.substring(dot) : '';
    const cleanTitle = this.safeFileName(title);
    return extension.length > 0 && !cleanTitle.toLowerCase().endsWith(extension.toLowerCase()) ?
      `${cleanTitle}${extension}` : cleanTitle;
  }

  private fileName(uri: string, type: VaultItemType): string {
    const withoutQuery = uri.split('?')[0];
    const slash = Math.max(withoutQuery.lastIndexOf('/'), withoutQuery.lastIndexOf('\\'));
    let name = slash >= 0 ? withoutQuery.substring(slash + 1) : withoutQuery;
    try { name = decodeURIComponent(name); } catch (_) {}
    if (name.length > 0 && name.indexOf('.') > 0) { return this.safeFileName(name); }
    if (type === VaultItemType.Image) { return '私密图片.jpg'; }
    if (type === VaultItemType.Video) { return '私密视频.mp4'; }
    return '私密文件';
  }

  private async detectMediaType(uri: string): Promise<VaultItemType> {
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
  }

  private safeFileName(name: string): string {
    const cleaned = name.replace(/[\\/:*?"<>|]/g, '_').trim();
    return cleaned.length > 0 ? cleaned : 'PalmVault文件';
  }

  private readMedia(uri: string): Uint8Array {
    let file: fs.File | undefined = undefined;
    try {
      file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      const size = fs.statSync(file.fd).size;
      if (size <= 0) {
        throw new Error('所选媒体文件为空');
      }
      if (size > this.maxImportBytes) {
        throw new Error('暂时支持 256MB 以内的单个文件');
      }
      const buffer = new ArrayBuffer(size);
      const bytesRead = fs.readSync(file.fd, buffer, { length: size });
      if (bytesRead !== size) {
        throw new Error('媒体文件读取不完整');
      }
      return new Uint8Array(buffer);
    } finally {
      if (file) {
        fs.closeSync(file);
      }
    }
  }
}

export const mediaPickerService = new MediaPickerService();
