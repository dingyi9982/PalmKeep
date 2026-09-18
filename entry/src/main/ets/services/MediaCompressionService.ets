import image from '@ohos.multimedia.image';
import media from '@ohos.multimedia.media';
import fs from '@ohos.file.fs';
import util from '@ohos.util';
import { AbilityContextHolder } from './AbilityContextHolder';
import { VaultItemType } from '../models/VaultModels';

interface VideoDimensions {
  width: number;
  height: number;
}

class MediaCompressionService {
  async compress(uri: string, type: VaultItemType, onProgress?: (progress: number) => void): Promise<string> {
    if (type === VaultItemType.Video) {
      return await this.compressVideo(uri, onProgress);
    }
    if (onProgress) { onProgress(10); }
    const path = await this.compressImage(uri);
    if (onProgress) { onProgress(100); }
    return path;
  }

  removeTemporary(path: string): void {
    try { fs.unlinkSync(path); } catch (error) {}
  }

  private temporaryPath(extension: string): string {
    return `${AbilityContextHolder.getContext().cacheDir}/pv-import-${util.generateRandomUUID()}${extension}`;
  }

  private async compressImage(uri: string): Promise<string> {
    const path = this.temporaryPath('.jpg');
    let input: fs.File | undefined = undefined;
    let output: fs.File | undefined = undefined;
    let source: image.ImageSource | undefined = undefined;
    let packer: image.ImagePacker | undefined = undefined;
    try {
      input = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      source = image.createImageSource(input.fd);
      const info = await source.getImageInfo();
      const ratio = Math.min(1, 2560 / Math.max(info.size.width, info.size.height));
      const pixelMap = await source.createPixelMap({ desiredSize: {
        width: Math.max(1, Math.round(info.size.width * ratio)),
        height: Math.max(1, Math.round(info.size.height * ratio))
      } });
      try {
        packer = image.createImagePacker();
        const packed = await packer.packing(pixelMap, { format: 'image/jpeg', quality: 82 });
        output = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
        fs.writeSync(output.fd, packed);
        fs.fsyncSync(output.fd);
      } finally {
        await pixelMap.release();
      }
      return path;
    } catch (error) {
      this.removeTemporary(path);
      throw new Error('图片压缩失败');
    } finally {
      if (packer) { await packer.release(); }
      if (source) { await source.release(); }
      if (input) { fs.closeSync(input); }
      if (output) { fs.closeSync(output); }
    }
  }

  private async compressVideo(uri: string, onProgress?: (progress: number) => void): Promise<string> {
    const path = this.temporaryPath('.mp4');
    try {
      const dimensions = await this.videoOutputDimensions(uri);
      const transcoded = await this.transcodeVideo(uri, path, dimensions, onProgress);
      if (!transcoded || !await this.isPlayableVideo(path)) { throw new Error('unsupported video'); }
      if (onProgress) { onProgress(100); }
      return path;
    } catch (error) {
      this.removeTemporary(path);
      throw new Error('视频导入失败，请确认文件完整且系统支持该编码');
    }
  }

  private async transcodeVideo(uri: string, path: string, dimensions: VideoDimensions,
    onProgress?: (progress: number) => void): Promise<boolean> {
    let input: fs.File | undefined = undefined;
    let output: fs.File | undefined = undefined;
    let transcoder: media.AVTranscoder | undefined = undefined;
    let succeeded = false;
    try {
      input = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      output = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      transcoder = await media.createAVTranscoder();
      transcoder.fdSrc = { fd: input.fd, offset: 0, length: fs.statSync(input.fd).size };
      transcoder.fdDst = output.fd;
      const config: media.AVTranscoderConfig = {
        fileFormat: media.ContainerFormatType.CFT_MPEG_4,
        videoCodec: media.CodecMimeType.VIDEO_AVC,
        videoBitrate: 2500000,
        audioCodec: media.CodecMimeType.AUDIO_AAC,
        audioBitrate: 96000
      };
      if (dimensions.width >= 240 && dimensions.height >= 240) {
        config.videoFrameWidth = dimensions.width;
        config.videoFrameHeight = dimensions.height;
      }
      await transcoder.prepare(config);
      await new Promise<void>((resolve, reject): void => {
        transcoder?.on('complete', (): void => { resolve(); });
        transcoder?.on('error', (): void => { reject(new Error('视频转码失败')); });
        transcoder?.on('progressUpdate', (progress: number): void => {
          if (onProgress) { onProgress(progress); }
        });
        transcoder?.start().catch((): void => { reject(new Error('视频转码失败')); });
      });
      succeeded = true;
    } catch (error) {
      succeeded = false;
    } finally {
      // The transcoder owns both descriptors until release completes.
      try { if (transcoder) { await transcoder.release(); } } catch (error) {}
      if (succeeded && output) {
        try { fs.fsyncSync(output.fd); } catch (error) { succeeded = false; }
      }
      try { if (input) { fs.closeSync(input); } } catch (error) {}
      try { if (output) { fs.closeSync(output); } } catch (error) {}
    }
    return succeeded;
  }

  private async videoOutputDimensions(uri: string): Promise<VideoDimensions> {
    let file: fs.File | undefined = undefined;
    let extractor: media.AVMetadataExtractor | undefined = undefined;
    try {
      file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      extractor = await media.createAVMetadataExtractor();
      extractor.fdSrc = { fd: file.fd };
      const metadata = await extractor.fetchMetadata();
      const sourceWidth = Number(metadata.videoWidth ? metadata.videoWidth : 0);
      const sourceHeight = Number(metadata.videoHeight ? metadata.videoHeight : 0);
      if (sourceWidth <= 0 || sourceHeight <= 0) { return { width: 0, height: 0 }; }
      const maxWidth = sourceWidth >= sourceHeight ? 1920 : 1080;
      const maxHeight = sourceWidth >= sourceHeight ? 1080 : 1920;
      const scale = Math.min(1, maxWidth / sourceWidth, maxHeight / sourceHeight);
      return {
        width: this.evenDimension(sourceWidth * scale),
        height: this.evenDimension(sourceHeight * scale)
      };
    } catch (error) {
      return { width: 0, height: 0 };
    } finally {
      try { if (extractor) { await extractor.release(); } } catch (error) {}
      try { if (file) { fs.closeSync(file); } } catch (error) {}
    }
  }

  private evenDimension(value: number): number {
    const rounded = Math.max(2, Math.floor(value));
    return rounded % 2 === 0 ? rounded : rounded - 1;
  }

  private async isPlayableVideo(path: string): Promise<boolean> {
    let file: fs.File | undefined = undefined;
    let generator: media.AVImageGenerator | undefined = undefined;
    let frame: image.PixelMap | undefined = undefined;
    try {
      file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      const size = fs.statSync(file.fd).size;
      if (size <= 0) { return false; }
      generator = await media.createAVImageGenerator();
      generator.fdSrc = { fd: file.fd, offset: 0, length: size };
      frame = await generator.fetchFrameByTime(0, media.AVImageQueryOptions.AV_IMAGE_QUERY_NEXT_SYNC,
        { width: 32, height: 32 });
      return frame !== undefined;
    } catch (error) {
      return false;
    } finally {
      try { if (frame) { await frame.release(); } } catch (error) {}
      try { if (generator) { await generator.release(); } } catch (error) {}
      try { if (file) { fs.closeSync(file); } } catch (error) {}
    }
  }
}

export const mediaCompressionService = new MediaCompressionService();
