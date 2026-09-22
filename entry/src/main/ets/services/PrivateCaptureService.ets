import fs from '@ohos.file.fs';
import util from '@ohos.util';
import { AbilityContextHolder } from './AbilityContextHolder';
import { logRecoverableError, normalizeError } from './ErrorUtils';
import { PickedMedia } from './MediaPickerService';
import { VaultItemType } from '../models/VaultModels';

const CAPTURE_PREFIX: string = 'pv-capture-';
const SCAN_PREFIX: string = 'pv-scan-';

class PrivateCaptureService {
  private cachePath(prefix: string): string {
    return `${AbilityContextHolder.getContext().cacheDir}/${prefix}${util.generateRandomUUID()}.jpg`;
  }

  createCapturePath(): string { return this.cachePath(CAPTURE_PREFIX); }

  async copyScannedPages(uris: string[]): Promise<PickedMedia[]> {
    const pages: PickedMedia[] = [];
    try {
      for (let index = 0; index < uris.length; index += 1) {
        const path = this.cachePath(SCAN_PREFIX);
        let source: fs.File | undefined = undefined;
        let target: fs.File | undefined = undefined;
        let completed = false;
        try {
          source = fs.openSync(uris[index], fs.OpenMode.READ_ONLY);
          const size = fs.statSync(source.fd).size;
          if (size <= 0) { throw new Error('扫描页内容为空'); }
          target = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
          await fs.copyFile(source.fd, target.fd);
          fs.fsyncSync(target.fd);
          if (fs.statSync(target.fd).size !== size) { throw new Error('扫描页复制不完整'); }
          completed = true;
          pages.push({
            uri: path,
            sourceUri: '',
            type: VaultItemType.Image,
            name: `文档扫描-${this.timestamp()}-${index + 1}.jpg`,
            ocrText: ''
          });
        } finally {
          if (target) { fs.closeSync(target); }
          if (source) { fs.closeSync(source); }
          if (!completed) { this.removePath(path); }
        }
      }
      return pages;
    } catch (error) {
      this.removeMedia(pages);
      throw normalizeError(error);
    }
  }

  captureMedia(path: string, sequence: number): PickedMedia {
    return {
      uri: path,
      sourceUri: '',
      type: VaultItemType.Image,
      name: `私密拍摄-${this.timestamp()}-${sequence}.jpg`,
      ocrText: ''
    };
  }

  removeMedia(items: PickedMedia[]): void {
    items.forEach((item: PickedMedia): void => {
      if (item.sourceUri === '' && this.isOwnedPath(item.uri)) { this.removePath(item.uri); }
    });
  }

  cleanupTemporaryFiles(): number {
    let removed = 0;
    try {
      const cacheDir = AbilityContextHolder.getContext().cacheDir;
      const names = fs.listFileSync(cacheDir);
      names.forEach((name: string): void => {
        if (name.startsWith(CAPTURE_PREFIX) || name.startsWith(SCAN_PREFIX)) {
          try {
            fs.unlinkSync(`${cacheDir}/${name}`);
            removed += 1;
          } catch (error) {
            logRecoverableError(`could not remove private capture temporary file ${name}`, error);
          }
        }
      });
    } catch (error) {
      logRecoverableError('could not inspect private capture temporary files', error);
    }
    return removed;
  }

  private isOwnedPath(path: string): boolean {
    const cacheDir = AbilityContextHolder.getContext().cacheDir;
    return path.startsWith(`${cacheDir}/${CAPTURE_PREFIX}`) || path.startsWith(`${cacheDir}/${SCAN_PREFIX}`);
  }

  private removePath(path: string): void {
    try { fs.unlinkSync(path); }
    catch (error) { logRecoverableError(`could not remove private capture ${path}`, error); }
  }

  private timestamp(): string {
    const date = new Date();
    const two = (value: number): string => value.toString().padStart(2, '0');
    return `${date.getFullYear()}${two(date.getMonth() + 1)}${two(date.getDate())}-` +
      `${two(date.getHours())}${two(date.getMinutes())}${two(date.getSeconds())}`;
  }
}

export const privateCaptureService = new PrivateCaptureService();
