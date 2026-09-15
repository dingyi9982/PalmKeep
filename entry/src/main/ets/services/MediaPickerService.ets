import photoAccessHelper from '@ohos.file.photoAccessHelper';
import fs from '@ohos.file.fs';
import picker from '@ohos.file.picker';
import { VaultItemType } from '../models/VaultModels';

export interface PickedMedia {
  uri: string;
  type: VaultItemType;
  data: Uint8Array;
}

export class MediaPickerService {
  private readonly maxImportBytes: number = 64 * 1024 * 1024;

  async pickFile(type: VaultItemType): Promise<PickedMedia | undefined> {
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 1;
    options.fileSuffixFilters = type === VaultItemType.Video ? ['视频|.mp4,.mov,.mkv'] : ['图片|.png,.jpg,.jpeg,.webp,.heic'];
    const uris = await new picker.DocumentViewPicker().select(options);
    if (uris.length === 0) { return undefined; }
    return { uri: uris[0], type: type, data: this.readMedia(uris[0]) };
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
      data: this.readMedia(uri)
    };
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
        throw new Error('阶段 1 暂时支持 64MB 以内的媒体文件');
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
