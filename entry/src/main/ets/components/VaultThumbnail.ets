import image from '@ohos.multimedia.image';
import media from '@ohos.multimedia.media';
import fs from '@ohos.file.fs';
import util from '@ohos.util';
import { VaultItemType } from '../models/VaultModels';
import { AbilityContextHolder } from '../services/AbilityContextHolder';
import { vaultRepository } from '../services/VaultRepository';

@Component
export struct VaultThumbnail {
  itemId: string = '';
  mediaType: VaultItemType = VaultItemType.Image;
  attachmentIndex: number = 0;
  sourceData?: Uint8Array = undefined;
  sourceUri: string = '';
  thumbnailSize: number = 40;
  fillContainer: boolean = false;
  @State private bitmap?: image.PixelMap = undefined;
  private disposed: boolean = false;

  aboutToAppear(): void {
    this.disposed = false;
    this.load();
  }

  aboutToDisappear(): void {
    this.disposed = true;
    this.bitmap?.release();
    this.bitmap = undefined;
  }

  private async imageThumbnail(data: Uint8Array): Promise<image.PixelMap> {
    try {
    const source = image.createImageSource(data.buffer as ArrayBuffer);
    try {
      return await source.createPixelMap({ desiredSize: { width: 160, height: 160 } });
    } finally {
      await source.release();
    }
      } catch (error) {
      if (error instanceof Error) { throw error; }
      throw new Error('系统操作失败');
    }
  }

  private async videoThumbnail(data: Uint8Array): Promise<image.PixelMap> {
    try {
    const path = `${AbilityContextHolder.getContext().cacheDir}/pv-thumb-${util.generateRandomUUID()}`;
    const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);
    let generator: media.AVImageGenerator | undefined = undefined;
    try {
      fs.unlinkSync(path);
      let offset = 0;
      while (offset < data.length) {
        const chunk = data.slice(offset, Math.min(offset + 1024 * 1024, data.length));
        try {
          const count = fs.writeSync(file.fd, chunk.buffer as ArrayBuffer);
          if (count <= 0) {
            throw new Error('无法生成视频缩略图');
          }
          offset += count;
        } finally {
          chunk.fill(0);
        }
      }
      fs.lseek(file.fd, 0);
      generator = await media.createAVImageGenerator();
      generator.fdSrc = { fd: file.fd, offset: 0, length: data.length };
      return await generator.fetchFrameByTime(0, media.AVImageQueryOptions.AV_IMAGE_QUERY_NEXT_SYNC,
        { width: 160, height: 160 });
    } finally {
      if (generator) {
        await generator.release();
      }
      fs.closeSync(file);
    }
      } catch (error) {
      if (error instanceof Error) { throw error; }
      throw new Error('系统操作失败');
    }
  }

  private async uriThumbnail(uri: string): Promise<image.PixelMap> {
    try {
    const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    let generator: media.AVImageGenerator | undefined = undefined;
    let source: image.ImageSource | undefined = undefined;
    try {
      if (this.mediaType === VaultItemType.Video) {
        generator = await media.createAVImageGenerator();
        generator.fdSrc = { fd: file.fd, offset: 0, length: fs.statSync(file.fd).size };
        return await generator.fetchFrameByTime(0, media.AVImageQueryOptions.AV_IMAGE_QUERY_NEXT_SYNC,
          { width: 160, height: 160 });
      }
      source = image.createImageSource(file.fd);
      return await source.createPixelMap({ desiredSize: { width: 160, height: 160 } });
    } finally {
      if (generator) { await generator.release(); }
      if (source) { await source.release(); }
      fs.closeSync(file);
    }
      } catch (error) {
      if (error instanceof Error) { throw error; }
      throw new Error('系统操作失败');
    }
  }

  private async storedVideoThumbnail(): Promise<image.PixelMap> {
    try {
    const path = `${AbilityContextHolder.getContext().cacheDir}/pv-thumb-${util.generateRandomUUID()}`;
    const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);
    let generator: media.AVImageGenerator | undefined = undefined;
    try {
      fs.unlinkSync(path);
      const length = await vaultRepository.writeAttachmentToFd(this.itemId, file.fd, this.attachmentIndex);
      if (length <= 0) { throw new Error('视频附件不可用'); }
      fs.lseek(file.fd, 0);
      generator = await media.createAVImageGenerator();
      generator.fdSrc = { fd: file.fd, offset: 0, length: length };
      return await generator.fetchFrameByTime(0, media.AVImageQueryOptions.AV_IMAGE_QUERY_NEXT_SYNC,
        { width: 160, height: 160 });
    } finally {
      if (generator) { await generator.release(); }
      fs.closeSync(file);
    }
      } catch (error) {
      if (error instanceof Error) { throw error; }
      throw new Error('系统操作失败');
    }
  }

  private async load(): Promise<void> {
    try {
    let data = new Uint8Array(0);
    let ownsData = false;
    try {
      if (this.mediaType === VaultItemType.File) { return; }
      if (this.sourceUri.length > 0) {
        const bitmap = await this.uriThumbnail(this.sourceUri);
        if (this.disposed) { await bitmap.release(); return; }
        this.bitmap = bitmap;
        return;
      }
      if (this.mediaType === VaultItemType.Video) {
        const bitmap = await this.storedVideoThumbnail();
        if (this.disposed) { await bitmap.release(); return; }
        this.bitmap = bitmap;
        return;
      }
      if (this.sourceData && this.sourceData.length > 0) {
        data = this.sourceData;
      } else {
        data = await vaultRepository.readAttachment(this.itemId, this.attachmentIndex);
        ownsData = true;
      }
      if (data.length === 0) {
        return;
      }
      const bitmap = await this.imageThumbnail(data);
      if (this.disposed) {
        await bitmap.release();
        return;
      }
      this.bitmap = bitmap;
    } catch (error) {
      // Keep the compact media placeholder when the format cannot produce a thumbnail.
    } finally {
      if (ownsData) {
        data.fill(0);
      }
    }
      } catch (error) {
      if (error instanceof Error) { throw error; }
      throw new Error('系统操作失败');
    }
  }

  build() {
    Stack() {
      if (this.bitmap) {
        Image(this.bitmap).width('100%').height('100%').objectFit(ImageFit.Cover)
      } else {
        Text(this.mediaType === VaultItemType.Video ? '▶' : (this.mediaType === VaultItemType.File ? '▤' : '▧'))
          .fontSize(15).fontColor('#24B88A')
      }
      if (this.mediaType === VaultItemType.Video && this.bitmap) {
        Stack() {
          Text('▶').fontSize(10).fontColor('#FFFFFF')
        }
        .width(22).height(22).borderRadius(11).backgroundColor('#99000000')
      }
    }
    .width(this.fillContainer ? '100%' : this.thumbnailSize)
    .height(this.fillContainer ? '100%' : this.thumbnailSize)
    .borderRadius(10).clip(true).backgroundColor('#E8F7F2')
  }
}
