import image from '@ohos.multimedia.image';
import fs from '@ohos.file.fs';
import util from '@ohos.util';
import media from '@ohos.multimedia.media';
import { AbilityContextHolder } from '../services/AbilityContextHolder';
import { vaultRepository } from '../services/VaultRepository';
import { VaultItemType } from '../models/VaultModels';

@Component
export struct VaultMedia {
  itemId: string = '';
  mediaType: VaultItemType = VaultItemType.Image;
  @State private bitmap?: image.PixelMap = undefined;
  @State private videoSource: string = '';
  @State private message: string = '正在解密媒体…';
  @State private zoom: number = 1;
  @State private ready: boolean = false;
  @State private playing: boolean = false;
  @State private playbackTime: number = 0;
  @State private duration: number = 0;
  private file?: fs.File;
  private surface: XComponentController = new XComponentController();
  private surfaceId: string = '';
  private player?: media.AVPlayer;
  private starting: boolean = false;
  private byteLength: number = 0;
  private disposed: boolean = false;

  aboutToAppear(): void {
    this.load();
  }

  aboutToDisappear(): void {
    this.disposed = true;
    this.releaseVideo();
    this.videoSource = '';
    this.bitmap?.release();
    this.bitmap = undefined;
  }

  private async releaseVideo(): Promise<void> {
    const player = this.player;
    this.player = undefined;
    try { if (player) { await player.release(); } } finally {
      if (this.file) { fs.closeSync(this.file); this.file = undefined; }
    }
  }

  private async prepareVideo(): Promise<void> {
    if (this.starting || !this.file || this.surfaceId.length === 0 || this.disposed) { return; }
    this.starting = true;
    try {
      const player = await media.createAVPlayer();
      if (this.disposed) { await player.release(); return; }
      this.player = player;
      player.on('error', (): void => { this.message = '视频无法播放：文件损坏或编码不受支持'; });
      player.on('timeUpdate', (time: number): void => { this.playbackTime = time; });
      player.on('stateChange', async (state: string): Promise<void> => {
        if (this.disposed) { return; }
        try {
          if (state === 'initialized') {
            player.surfaceId = this.surfaceId;
            await player.prepare();
          } else if (state === 'prepared') {
            this.duration = player.duration;
            this.ready = true;
            this.message = '视频已就绪';
          } else if (state === 'playing') {
            this.playing = true;
            this.message = '正在播放';
          } else if (state === 'paused' || state === 'completed') {
            this.playing = false;
            this.message = state === 'completed' ? '播放结束' : '已暂停';
          }
        } catch (error) { this.message = '视频准备失败，请重新打开'; }
      });
      player.fdSrc = { fd: this.file.fd, offset: 0, length: this.byteLength };
    } catch (error) { this.message = '无法创建视频播放器'; }
  }

  private async togglePlayback(): Promise<void> {
    try {
      if (this.playing) { await this.player?.pause(); } else { await this.player?.play(); }
    } catch (error) { this.message = '播放失败，请重新打开'; }
  }

  private async load(): Promise<void> {
    let data: Uint8Array = new Uint8Array(0);
    try {
      data = await vaultRepository.readAttachment(this.itemId);
      if (this.disposed) { return; }
      if (data.length === 0) { throw new Error('此项目没有媒体附件'); }
      if (this.mediaType === VaultItemType.Image) {
        const source = image.createImageSource(data.buffer as ArrayBuffer);
        try {
          const info = await source.getImageInfo();
          const ratio = Math.min(1, 2048 / Math.max(info.size.width, info.size.height));
          const bitmap = await source.createPixelMap({ desiredSize: {
            width: Math.max(1, Math.round(info.size.width * ratio)),
            height: Math.max(1, Math.round(info.size.height * ratio))
          } });
          if (this.disposed) { await bitmap.release(); return; }
          this.bitmap = bitmap;
        } finally { await source.release(); }
      } else {
        // Unlink immediately: only the open descriptor keeps decrypted data alive.
        const path = `${AbilityContextHolder.getContext().cacheDir}/pv-play-${util.generateRandomUUID()}`;
        const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);
        this.file = file;
        fs.unlinkSync(path);
        let offset = 0;
        while (offset < data.length) {
          const chunk = data.slice(offset, Math.min(offset + 1024 * 1024, data.length));
          try {
            const count = fs.writeSync(file.fd, chunk.buffer as ArrayBuffer);
            if (count <= 0) { throw new Error('无法准备视频'); }
            offset += count;
          } finally { chunk.fill(0); }
        }
        this.byteLength = data.length;
        fs.lseek(file.fd, 0);
        this.videoSource = 'ready';
        this.prepareVideo();
      }
      this.message = '';
    } catch (error) {
      if (!this.disposed) { this.message = '媒体打开失败，请确认文件格式完整且受支持'; }
      if (this.file) { fs.closeSync(this.file); this.file = undefined; }
    } finally { data.fill(0); }
  }

  build() {
    Column({ space: 10 }) {
      if (this.bitmap) {
        Scroll() {
          Image(this.bitmap).objectFit(ImageFit.Contain).width(`${100 * this.zoom}%`).height(300 * this.zoom)
        }.width('100%').height(300).scrollable(ScrollDirection.Free)
        Button(this.zoom === 1 ? '放大图片' : '适应窗口')
          .onClick((): void => { this.zoom = this.zoom === 1 ? 2 : 1; })
      } else if (this.mediaType === VaultItemType.Video) {
        XComponent({ id: 'vaultVideo', type: XComponentType.SURFACE, controller: this.surface })
          .width('100%').height(220)
          .onLoad((): void => { this.surfaceId = this.surface.getXComponentSurfaceId(); this.prepareVideo(); })
        Row({ space: 12 }) {
          Button(this.playing ? '暂停' : '播放').enabled(this.ready)
            .onClick((): void => { this.togglePlayback(); })
          Text(`${Math.floor(this.playbackTime / 1000)} / ${Math.floor(this.duration / 1000)} 秒`).fontColor('#91A9A0')
        }
        Slider({ value: this.playbackTime, min: 0, max: Math.max(1, this.duration) })
          .enabled(this.ready).width('100%')
          .onChange((value: number, mode: SliderChangeMode): void => {
            if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
              this.player?.seek(Math.round(value));
            }
          })
      }
      if (this.message.length > 0) {
        Text(this.message).fontSize(13).fontColor('#91A9A0')
      }
    }.width('100%').padding(10).backgroundColor('#08110F').borderRadius(12)
  }
}
