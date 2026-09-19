import { textRecognition } from '@kit.CoreVisionKit';
import image from '@ohos.multimedia.image';
import fs from '@ohos.file.fs';
import { VaultItemType } from '../models/VaultModels';

export interface OcrMediaInput {
  uri: string;
  type: VaultItemType;
}

class MediaOcrService {
  private readonly maxDimension: number = 2560;

  async recognizeBatch(items: OcrMediaInput[], onProgress?: (completed: number, total: number) => void): Promise<string[]> {
    try {
    const results: string[] = items.map((): string => '');
    const imageCount = items.filter((item: OcrMediaInput): boolean => item.type === VaultItemType.Image).length;
    if (imageCount === 0) { return results; }
    let initialized = false;
    let completed = 0;
    try {
      initialized = await textRecognition.init();
      if (!initialized) { return results; }
      for (let index = 0; index < items.length; index += 1) {
        if (items[index].type !== VaultItemType.Image) { continue; }
        try {
          results[index] = await this.recognizeImage(items[index].uri);
        } catch (error) {
          results[index] = '';
        }
        completed += 1;
        if (onProgress) { onProgress(completed, imageCount); }
      }
    } catch (error) {
      // OCR failures are intentionally silent and must not block saving.
    } finally {
      if (initialized) {
        try { await textRecognition.release(); } catch (error) {}
      }
    }
    return results;
      } catch (error) {
      if (error instanceof Error) { throw error; }
      throw new Error('系统操作失败');
    }
  }

  private async recognizeImage(uri: string): Promise<string> {
    try {
    let file: fs.File | undefined = undefined;
    let source: image.ImageSource | undefined = undefined;
    let pixelMap: image.PixelMap | undefined = undefined;
    try {
      file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      source = image.createImageSource(file.fd);
      const info = await source.getImageInfo();
      const longest = Math.max(info.size.width, info.size.height);
      const scale = longest > this.maxDimension ? this.maxDimension / longest : 1;
      pixelMap = await source.createPixelMap({ desiredSize: {
        width: Math.max(1, Math.round(info.size.width * scale)),
        height: Math.max(1, Math.round(info.size.height * scale))
      } });
      const result = await textRecognition.recognizeText({ pixelMap: pixelMap }, {
        isDirectionDetectionSupported: true
      });
      return result.value.trim();
    } finally {
      if (pixelMap) { await pixelMap.release(); }
      if (source) { await source.release(); }
      if (file) { fs.closeSync(file); }
    }
      } catch (error) {
      if (error instanceof Error) { throw error; }
      throw new Error('系统操作失败');
    }
  }
}

export const mediaOcrService = new MediaOcrService();
