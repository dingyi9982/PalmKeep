import { VaultItemType } from '../models/VaultModels';
import {
  MAX_FILE_ATTACHMENT_BYTES,
  MAX_IMPORTED_AUDIO_BYTES,
  MAX_IMPORTED_IMAGE_BYTES,
  MAX_IMPORTED_VIDEO_BYTES
} from './VaultLimits';

export function validateVaultItemFields(type: VaultItemType, title: string, username: string,
  password: string, website: string, notes: string): void {
  if (type === VaultItemType.Note && title.trim().length === 0) {
    throw new Error('名称不能为空');
  }
  if (type === VaultItemType.Login) {
    if (title.trim().length === 0 && website.trim().length === 0) {
      throw new Error('名称和网址至少填写一个');
    }
    if (username.trim().length === 0) { throw new Error('账号不能为空'); }
  }
  if (type === VaultItemType.Note && notes.trim().length === 0) {
    throw new Error('内容不能为空');
  }
}

export function validateImportedAttachmentSize(type: VaultItemType, size: number, name: string): void {
  if (size <= 0) { throw new Error(`“${name}”内容为空`); }
  validateStoredAttachmentSize(type, size, name);
  if (type === VaultItemType.Audio && size > MAX_IMPORTED_AUDIO_BYTES) {
    throw new Error(`音频“${name}”超过 10 MB，请选择较小的文件`);
  }
}

export function validateStoredAttachmentSize(type: VaultItemType, size: number, name: string): void {
  if (size <= 0) { throw new Error(`“${name}”内容为空`); }
  if (type === VaultItemType.File && size > MAX_FILE_ATTACHMENT_BYTES) {
    throw new Error(`文件“${name}”超过 10 MB，请选择较小的文件`);
  }
  if (type === VaultItemType.Image && size > MAX_IMPORTED_IMAGE_BYTES) {
    throw new Error(`图片“${name}”超过 64 MB，请选择较小的图片`);
  }
  if (type === VaultItemType.Video && size > MAX_IMPORTED_VIDEO_BYTES) {
    throw new Error(`视频“${name}”超过 500 MB，请选择较小的视频`);
  }
}

export function checkedTotalBytes(currentBytes: number, addedBytes: number,
  maximumBytes: number, errorMessage: string): number {
  if (currentBytes < 0 || addedBytes < 0 || maximumBytes < 0 || currentBytes > maximumBytes - addedBytes) {
    throw new Error(errorMessage);
  }
  return currentBytes + addedBytes;
}

export function isSupportedAudioFileName(name: string): boolean {
  const lower = name.toLowerCase();
  return ['.mp3', '.m4a', '.aac', '.wav', '.amr', '.flac', '.ogg']
    .some((extension: string): boolean => lower.endsWith(extension));
}
