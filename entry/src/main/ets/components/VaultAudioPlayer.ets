import fs from '@ohos.file.fs';
import media from '@ohos.multimedia.media';
import util from '@ohos.util';
import { AbilityContextHolder } from '../services/AbilityContextHolder';
import { vaultRepository } from '../services/VaultRepository';
import { logRecoverableError } from '../services/ErrorUtils';
import {
  COLOR_DANGER, COLOR_MUTED, COLOR_PRIMARY, COLOR_PRIMARY_DARK, COLOR_PRIMARY_TINT,
  COLOR_SURFACE_2, COLOR_TEXT_DARK
} from './VaultTheme';

@Component
export struct VaultAudioPlayer {
  itemId: string = '';
  sourceUri: string = '';
  attachmentIndex: number = 0;
  @State private ready: boolean = false;
  @State private playing: boolean = false;
  @State private playbackTime: number = 0;
  @State private duration: number = 0;
  @State private message: string = '';
  private player?: media.AVPlayer = undefined;
  private file?: fs.File = undefined;
  private path: string = '';
  private disposed: boolean = false;

  aboutToAppear(): void { this.load(); }

  aboutToDisappear(): void {
    this.disposed = true;
    this.release();
  }

  private async load(): Promise<void> {
    try {
      this.path = `${AbilityContextHolder.getContext().cacheDir}/pv-play-audio-${util.generateRandomUUID()}`;
      this.file = fs.openSync(this.path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      let size = 0;
      if (this.sourceUri.length > 0) {
        const source = fs.openSync(this.sourceUri, fs.OpenMode.READ_ONLY);
        try { size = fs.statSync(source.fd).size; await fs.copyFile(source.fd, this.file.fd); }
        finally { fs.closeSync(source); }
      } else {
        size = await vaultRepository.writeAttachmentToFd(this.itemId, this.file.fd, this.attachmentIndex);
      }
      if (size <= 0) { throw new Error('音频内容为空'); }
      fs.fsyncSync(this.file.fd);
      fs.lseek(this.file.fd, 0);
      const player = await media.createAVPlayer();
      this.player = player;
      player.on('error', (): void => {
        if (!this.disposed) { this.ready = false; this.playing = false; this.message = '音频无法播放'; }
      });
      player.on('timeUpdate', (time: number): void => {
        if (!this.disposed && this.player === player) { this.playbackTime = time; }
      });
      player.on('stateChange', async (state: string): Promise<void> => {
        if (this.disposed || this.player !== player) { return; }
        if (state === 'initialized') { await player.prepare(); }
        else if (state === 'prepared') {
          this.duration = player.duration;
          this.ready = true;
          this.message = '';
        } else if (state === 'playing') { this.playing = true; }
        else if (state === 'paused') { this.playing = false; }
        else if (state === 'completed') {
          this.playing = false;
          this.playbackTime = 0;
          player.seek(0);
        }
      });
      player.fdSrc = { fd: this.file.fd, offset: 0, length: size };
    } catch (error) {
      this.message = '音频打开失败，请确认文件完整且格式受支持';
      await this.release();
    }
  }

  private async release(): Promise<void> {
    const player = this.player;
    this.player = undefined;
    if (player) { try { await player.release(); } catch (error) {} }
    if (this.file) { try { fs.closeSync(this.file); } catch (error) {} this.file = undefined; }
    if (this.path.length > 0) {
      try { if (fs.accessSync(this.path)) { fs.unlinkSync(this.path); } }
      catch (error) { logRecoverableError('could not remove audio playback file', error); }
      this.path = '';
    }
  }

  private async toggle(): Promise<void> {
    if (!this.ready || !this.player) { return; }
    try { if (this.playing) { await this.player.pause(); } else { await this.player.play(); } }
    catch (error) { this.message = '播放失败，请重新打开'; }
  }

  private formatTime(milliseconds: number): string {
    const seconds = Math.max(0, Math.floor(milliseconds / 1000));
    const minute = Math.floor(seconds / 60);
    const second = seconds % 60;
    return `${minute}:${second.toString().padStart(2, '0')}`;
  }

  build() {
    Column({ space: 9 }) {
      Row({ space: 10 }) {
        Stack({ alignContent: Alignment.Center }) {
          Circle({ width: 48, height: 48 }).fill(COLOR_PRIMARY_TINT)
          Text(this.playing ? 'Ⅱ' : '▶')
            .fontSize(this.playing ? 18 : 20).fontWeight(FontWeight.Bold).fontColor(COLOR_PRIMARY_DARK)
            .textAlign(TextAlign.Center).width(30).height(30)
            .translate({ x: this.playing ? 0 : 1 })
        }
        .width(52).height(52)
        .enabled(this.ready).opacity(this.ready ? 1 : 0.45)
        .onClick((): void => { this.toggle(); })
        Column({ space: 4 }) {
          Slider({ value: this.playbackTime, min: 0, max: Math.max(1, this.duration) })
            .width('100%').trackThickness(3).selectedColor(COLOR_PRIMARY).enabled(this.ready)
            .onChange((value: number, mode: SliderChangeMode): void => {
              if ((mode === SliderChangeMode.End || mode === SliderChangeMode.Click) && this.player) {
                this.player.seek(Math.round(value));
              }
            })
          Row() {
            Text(this.formatTime(this.playbackTime)).fontSize(10).fontColor(COLOR_MUTED)
            Blank()
            Text(this.formatTime(this.duration)).fontSize(10).fontColor(COLOR_MUTED)
          }.width('100%')
        }.layoutWeight(1)
      }.width('100%')
      if (!this.ready && this.message.length === 0) {
        Progress({ value: 35, total: 100, type: ProgressType.Linear }).width('100%').height(3).color(COLOR_PRIMARY)
      }
      if (this.message.length > 0) { Text(this.message).fontSize(11).fontColor(COLOR_DANGER).width('100%') }
    }.width('100%').padding(11).backgroundColor(COLOR_SURFACE_2).borderRadius(14)
  }
}
