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
  name: string;
  ocrText: string;
}

export class MediaPickerService {
  async pickFiles(): Promise<PickedMedia[]> {
    try {
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
          name: this.fileName(uri, VaultItemType.File),
          ocrText: ''
        });
      }
      return picked;
    } catch (error) {
      throw new Error('文件导入失败，请确认所选文件完整且大小受支持');
    }
      } catch (error) {
      if (error instanceof Error) { throw error; }
      throw new Error('系统操作失败');
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
      for (let index = 0; index < result.photoUris.length; index += 1) {
        const uri = result.photoUris[index];
        const type = await this.detectMediaType(uri);
        picked.push({ uri: uri, type: type, name: this.fileName(uri, type), ocrText: '' });
      }
      return picked;
    } catch (error) {
      throw new Error('媒体导入失败，请确认所选文件完整且受支持');
    }
      } catch (error) {
      if (error instanceof Error) { throw error; }
      throw new Error('系统操作失败');
    }
  }

  async saveMediaToGallery(path: string, type: VaultItemType, title: string): Promise<string> {
    try {
    const saved = await this.saveMediaBatchToGallery([path], [type], [title]);
    return saved.length > 0 ? saved[0] : '';
      } catch (error) {
      if (error instanceof Error) { throw error; }
      throw new Error('系统操作失败');
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
      if (error instanceof Error) { throw error; }
      throw new Error('系统操作失败');
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
      if (error instanceof Error) { throw error; }
      throw new Error('系统操作失败');
    }
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
      if (error instanceof Error) { throw error; }
      throw new Error('系统操作失败');
    }
  }

  private safeFileName(name: string): string {
    const cleaned = name.replace(/[\\/:*?"<>|]/g, '_').trim();
    return cleaned.length > 0 ? cleaned : 'PalmVault文件';
  }

  private albumTitle(name: string): string {
    const safe = this.safeFileName(name);
    const dot = safe.lastIndexOf('.');
    return dot > 0 ? safe.substring(0, dot) : safe;
  }

}

export const mediaPickerService = new MediaPickerService();
