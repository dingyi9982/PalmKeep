import image from '@ohos.multimedia.image';
import fs from '@ohos.file.fs';
import util from '@ohos.util';
import media from '@ohos.multimedia.media';
import { AbilityContextHolder } from '../services/AbilityContextHolder';
import { vaultRepository } from '../services/VaultRepository';
import { logRecoverableError, normalizeError } from '../services/ErrorUtils';
import { VaultItemType } from '../models/VaultModels';
import { VaultThumbnail } from './VaultThumbnail';
import {
  COLOR_DANGER, COLOR_MEDIA_CANVAS, COLOR_MEDIA_CONTROL, COLOR_MEDIA_SURFACE, COLOR_MUTED,
  COLOR_ON_DARK, COLOR_OVERLAY, COLOR_OVERLAY_PRESSED, COLOR_PRIMARY_BRIGHT
} from './VaultTheme';

@Component
export struct VaultMedia {
  itemId: string = '';
  mediaType: VaultItemType = VaultItemType.Image;
  attachmentIndex: number = 0;
  fullScreenMode: boolean = false;
  initialPlaybackTime: number = 0;
  autoPlay: boolean = false;
  requestFullScreen?: (playbackTime: number, playing: boolean) => void = undefined;
  onPlaybackStateChange?: (playbackTime: number, playing: boolean) => void = undefined;
  @State private bitmap?: image.PixelMap = undefined;
  @State private videoSource: string = '';
  @State private message: string = '';
  @State private showFullScreen: boolean = false;
  @State private ready: boolean = false;
  @State private playing: boolean = false;
  @State private playbackTime: number = 0;
  @State private duration: number = 0;
  private file?: fs.File;
  private videoPath: string = '';
  private surface: XComponentController = new XComponentController();
  private surfaceId: string = '';
  private player?: media.AVPlayer;
  private starting: boolean = false;
  private retryCount: number = 0;
  private byteLength: number = 0;
  private disposed: boolean = false;

  aboutToAppear(): void {
    this.load();
  }

  aboutToDisappear(): void {
    this.disposed = true;
    this.showFullScreen = false;
    this.releaseVideo();
    this.videoSource = '';
    this.bitmap?.release();
    this.bitmap = undefined;
  }

  private async releaseVideo(): Promise<void> {
    try {
    const player = this.player;
    this.player = undefined;
    try { if (player) { await player.release(); } } finally {
      if (this.file) { fs.closeSync(this.file); this.file = undefined; }
      if (this.videoPath.length > 0) {
        try { fs.unlinkSync(this.videoPath); }
        catch (error) { logRecoverableError('could not remove media playback file', error); }
        this.videoPath = '';
      }
    }
      } catch (error) {
      throw normalizeError(error);
    }
  }

  private async prepareVideo(): Promise<void> {
    try {
    if (this.starting || !this.file || this.surfaceId.length === 0 || this.disposed) { return; }
    this.starting = true;
    try {
      // onLoad can fire before the native surface is fully available to the media
      // service. Waiting one frame avoids an intermittent prepare failure.
      await this.waitForSurface(60);
      if (this.disposed || !this.file || this.surfaceId.length === 0) {
        this.starting = false;
        return;
      }
      const player = await media.createAVPlayer();
      if (this.disposed) { await player.release(); return; }
      this.player = player;
      player.on('error', async (): Promise<void> => { await this.handlePlayerError(player); });
      player.on('timeUpdate', (time: number): void => {
        if (this.player === player && !this.disposed) {
          this.playbackTime = time;
          if (this.onPlaybackStateChange) { this.onPlaybackStateChange(time, this.playing); }
        }
      });
      player.on('stateChange', async (state: string): Promise<void> => {
        if (this.disposed || this.player !== player) { return; }
        try {
          if (state === 'initialized') {
            player.surfaceId = this.surfaceId;
            await player.prepare();
          } else if (state === 'prepared') {
            player.videoScaleType = media.VideoScaleType.VIDEO_SCALE_TYPE_SCALED_ASPECT;
            this.duration = player.duration;
            this.ready = true;
            this.starting = false;
            this.message = '';
            if (this.initialPlaybackTime > 0) {
              player.seek(Math.min(this.initialPlaybackTime, Math.max(0, player.duration - 250)));
              this.playbackTime = this.initialPlaybackTime;
            }
            if (this.autoPlay) {
              setTimeout((): void => {
                if (!this.disposed && this.player === player) { player.play(); }
              }, 100);
            }
          } else if (state === 'playing') {
            this.playing = true;
            this.message = '';
            if (this.onPlaybackStateChange) {
              this.onPlaybackStateChange(this.playbackTime, true);
            }
          } else if (state === 'paused' || state === 'completed') {
            this.playing = false;
            this.message = '';
            if (this.onPlaybackStateChange) {
              this.onPlaybackStateChange(this.playbackTime, false);
            }
          }
        } catch (error) { await this.handlePlayerError(player); }
      });
      if (this.disposed || this.player !== player || !this.file) {
        await player.release();
        return;
      }
      player.fdSrc = { fd: this.file.fd, offset: 0, length: this.byteLength };
    } catch (error) {
      this.starting = false;
      if (!this.disposed) { this.message = '无法创建视频播放器'; }
    }
      } catch (error) {
      throw normalizeError(error);
    }
  }

  private async handlePlayerError(failedPlayer: media.AVPlayer): Promise<void> {
    try {
    if (this.disposed || this.player !== failedPlayer) { return; }
    this.player = undefined;
    this.ready = false;
    this.playing = false;
    this.starting = false;
    try { await failedPlayer.release(); }
    catch (error) { logRecoverableError('could not release failed media player', error); }
    if (this.disposed) { return; }
    if (this.retryCount < 1) {
      this.retryCount += 1;
      this.message = '';
      await this.waitForSurface(180);
      if (!this.disposed) { this.prepareVideo(); }
      return;
    }
    this.message = '视频暂时无法播放，请切换后重试';
      } catch (error) {
      throw normalizeError(error);
    }
  }

  private async waitForSurface(milliseconds: number): Promise<void> {
    try {
    await new Promise<void>((resolve): void => {
      setTimeout((): void => { resolve(); }, milliseconds);
    });
      } catch (error) {
      throw normalizeError(error);
    }
  }

  private async togglePlayback(): Promise<void> {
    try {
    try {
      if (this.playing) { await this.player?.pause(); } else { await this.player?.play(); }
    } catch (error) { this.message = '播放失败，请重新打开'; }
      } catch (error) {
      throw normalizeError(error);
    }
  }

  private async openVideoFullScreen(): Promise<void> {
    try {
    if (!this.ready || !this.requestFullScreen) { return; }
    const resumePlaying = this.playing;
    const resumeTime = this.playbackTime;
    try {
      if (resumePlaying) { await this.player?.pause(); }
    } catch (error) {
      // Fullscreen can still resume from the last reported position.
    }
    this.requestFullScreen(resumeTime, resumePlaying);
      } catch (error) {
      throw normalizeError(error);
    }
  }

  private formatTime(milliseconds: number): string {
    const seconds = Math.max(0, Math.floor(milliseconds / 1000));
    const minute = Math.floor(seconds / 60);
    const second = seconds % 60;
    return `${minute}:${second < 10 ? '0' : ''}${second}`;
  }

  private async load(): Promise<void> {
    try {
    let data: Uint8Array = new Uint8Array(0);
    try {
      if (this.mediaType === VaultItemType.Image) {
        data = await vaultRepository.readAttachment(this.itemId, this.attachmentIndex);
        if (this.disposed) { return; }
        if (data.length === 0) { throw new Error('此资料没有媒体附件'); }
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
        const path = `${AbilityContextHolder.getContext().cacheDir}/pv-play-${util.generateRandomUUID()}`;
        this.videoPath = path;
        const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);
        this.file = file;
        this.byteLength = await vaultRepository.writeAttachmentToFd(this.itemId, file.fd, this.attachmentIndex);
        if (this.byteLength <= 0) { throw new Error('此资料没有媒体附件'); }
        fs.fsyncSync(file.fd);
        fs.lseek(file.fd, 0);
        this.videoSource = 'ready';
        this.prepareVideo();
      }
      this.message = '';
    } catch (error) {
      if (!this.disposed) { this.message = '媒体打开失败，请确认文件格式完整且受支持'; }
      if (this.file) { fs.closeSync(this.file); this.file = undefined; }
      if (this.videoPath.length > 0) {
        try { fs.unlinkSync(this.videoPath); }
        catch (error) { logRecoverableError('could not remove media playback file', error); }
        this.videoPath = '';
      }
    } finally { data.fill(0); }
      } catch (error) {
      throw normalizeError(error);
    }
  }

  @Builder
  private fullScreenImage(): void {
    Stack({ alignContent: Alignment.TopEnd }) {
      if (this.bitmap) {
        Image(this.bitmap)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Contain)
      }
      Stack() {
        Text('×').fontSize(28).fontColor(COLOR_ON_DARK)
      }
      .width(42).height(42)
      .margin({ top: 18, right: 16 })
      .backgroundColor(COLOR_OVERLAY)
      .borderRadius(21)
      .onClick((): void => { this.showFullScreen = false; })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(COLOR_MEDIA_CANVAS)
  }

  build() {
    Column({ space: 8 }) {
      if (this.mediaType === VaultItemType.Image) {
        Stack({ alignContent: Alignment.BottomEnd }) {
          if (this.bitmap) {
            Image(this.bitmap)
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Contain)
          } else if (this.message.length === 0) {
            LoadingProgress().width(34).height(34).color(COLOR_PRIMARY_BRIGHT)
              .align(Alignment.Center)
          }
          if (this.bitmap && !this.fullScreenMode) {
            Text('⛶')
              .fontSize(19)
              .fontColor(COLOR_ON_DARK)
              .width(38).height(38)
              .textAlign(TextAlign.Center)
              .margin(10)
              .backgroundColor(COLOR_OVERLAY)
              .borderRadius(19)
          }
        }
        .width('100%')
        .height(this.fullScreenMode ? '100%' : 286)
        .borderRadius(this.fullScreenMode ? 0 : 15)
        .clip(true)
        .backgroundColor(this.fullScreenMode ? COLOR_MEDIA_CANVAS : COLOR_MEDIA_SURFACE)
        .onClick((): void => {
          if (this.bitmap) {
            if (this.requestFullScreen) { this.requestFullScreen(0, false); } else { this.showFullScreen = true; }
          }
        })
      } else if (this.mediaType === VaultItemType.Video) {
        Stack({ alignContent: Alignment.Center }) {
          XComponent({
            id: `vaultVideo-${this.itemId}-${this.attachmentIndex}-${this.fullScreenMode}`,
            type: XComponentType.SURFACE,
            controller: this.surface
          })
            .width('100%').height('100%')
            .onLoad((): void => { this.surfaceId = this.surface.getXComponentSurfaceId(); this.prepareVideo(); })
          if (!this.playing && this.playbackTime === 0) {
            VaultThumbnail({ itemId: this.itemId, mediaType: VaultItemType.Video,
              attachmentIndex: this.attachmentIndex, fillContainer: true })
              .hitTestBehavior(HitTestMode.None)
          }
          if (!this.ready && this.message.length === 0) {
            Progress({ value: 35, total: 100, type: ProgressType.Ring })
              .width(34).height(34).color(COLOR_PRIMARY_BRIGHT)
          }
          if (this.ready && !this.playing) {
            Text('▶').fontSize(25).fontColor(COLOR_ON_DARK).textAlign(TextAlign.Center)
              .width(58).height(58).padding({ left: 4 })
              .backgroundColor(COLOR_OVERLAY_PRESSED).borderRadius(29)
              .onClick((): void => { this.togglePlayback(); })
          }
        }
        .width('100%').height(this.fullScreenMode ? '76%' : 236)
        .borderRadius(this.fullScreenMode ? 0 : 15).clip(true).backgroundColor(COLOR_MEDIA_CANVAS)
        Row({ space: 8 }) {
          Text(this.playing ? 'Ⅱ' : '▶').fontSize(this.playing ? 18 : 16).fontColor(COLOR_ON_DARK)
            .textAlign(TextAlign.Center).width(36).height(36).padding({ left: this.playing ? 0 : 2 })
            .backgroundColor(COLOR_MEDIA_CONTROL).borderRadius(18).opacity(this.ready ? 1 : 0.4)
            .onClick((): void => { if (this.ready) { this.togglePlayback(); } })
          Slider({ value: this.playbackTime, min: 0, max: Math.max(1, this.duration) })
            .enabled(this.ready).layoutWeight(1).trackThickness(3).selectedColor(COLOR_PRIMARY_BRIGHT)
            .onChange((value: number, mode: SliderChangeMode): void => {
              if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
                this.player?.seek(Math.round(value));
              }
            })
          Text(`${this.formatTime(this.playbackTime)} / ${this.formatTime(this.duration)}`)
            .fontSize(10).fontColor(COLOR_MUTED)
          if (!this.fullScreenMode) {
            Text('⛶').fontSize(19).fontColor(COLOR_ON_DARK).textAlign(TextAlign.Center)
              .width(36).height(36).backgroundColor(COLOR_MEDIA_CONTROL).borderRadius(18).opacity(this.ready ? 1 : 0.4)
              .onClick((): void => {
                this.openVideoFullScreen();
              })
          }
        }.width('100%').padding({ left: 3, right: 3 })
      }
      if (this.message.length > 0) {
        Text(this.message).fontSize(12).fontColor(COLOR_DANGER).padding({ left: 4, right: 4 })
      }
    }
    .width('100%')
    .padding(this.fullScreenMode ? 0 : 6)
    .backgroundColor(this.fullScreenMode ? COLOR_MEDIA_CANVAS : COLOR_MEDIA_SURFACE)
    .borderRadius(this.fullScreenMode ? 0 : 17)
    .bindContentCover(this.showFullScreen, this.fullScreenImage)
  }
}
