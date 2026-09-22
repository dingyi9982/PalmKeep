import { PickedMedia } from '../services/MediaPickerService';
import {
  audioRecordingService, AudioRecordingPermissionState, AudioRecordingSnapshot
} from '../services/AudioRecordingService';
import { AbilityContextHolder } from '../services/AbilityContextHolder';
import {
  COLOR_DANGER, COLOR_MEDIA_CANVAS, COLOR_MUTED_ON_DARK, COLOR_ON_DARK,
  COLOR_OVERLAY, COLOR_PRIMARY_BRIGHT
} from './VaultTheme';

@Component
export struct AudioRecorderOverlay {
  onComplete: (audio: PickedMedia) => void = (_audio: PickedMedia): void => {};
  onCancel: () => void = (): void => {};
  @State private permissionState: string = 'idle';
  @State private requiresSettings: boolean = false;
  @State private recorderState: string = 'idle';
  @State private elapsedMs: number = 0;
  @State private amplitude: number = 0;
  @State private message: string = '';
  @State private busy: boolean = false;
  private delivered: boolean = false;
  private listener = (snapshot: AudioRecordingSnapshot): void => { this.applySnapshot(snapshot); };

  aboutToAppear(): void {
    AbilityContextHolder.setPrivacyMode(true);
    audioRecordingService.attach(this.listener);
    this.prepare();
  }

  aboutToDisappear(): void {
    audioRecordingService.detach(this.listener);
    AbilityContextHolder.setPrivacyMode(false);
  }

  private async prepare(): Promise<void> {
    if (audioRecordingService.isActive()) {
      this.permissionState = 'granted';
      this.applySnapshot(audioRecordingService.snapshot());
      return;
    }
    const completed = audioRecordingService.takeCompleted();
    if (completed.length > 0) {
      this.deliver(completed[completed.length - 1]);
      return;
    }
    const state = audioRecordingService.getPermissionState();
    if (state === AudioRecordingPermissionState.GRANTED) {
      this.permissionState = 'granted';
      await this.start();
    } else if (state === AudioRecordingPermissionState.REQUESTABLE) {
      await this.authorize(false);
    } else {
      this.permissionState = 'denied';
      this.requiresSettings = true;
      this.message = '麦克风权限已被拒绝，请前往系统设置允许访问';
    }
  }

  private async authorize(fromSettings: boolean): Promise<void> {
    if (this.busy) { return; }
    this.busy = true;
    this.permissionState = 'requesting';
    this.message = fromSettings ? '正在打开权限设置…' : '正在请求麦克风权限…';
    const granted = await audioRecordingService.requestPermission(fromSettings);
    const state = audioRecordingService.getPermissionState();
    this.requiresSettings = state === AudioRecordingPermissionState.SETTINGS_REQUIRED;
    this.busy = false;
    if (!granted) {
      this.permissionState = 'denied';
      this.message = this.requiresSettings ? '仍未获得麦克风权限，请前往系统设置允许访问' :
        '授权未完成，请重新授权';
      return;
    }
    this.permissionState = 'granted';
    await this.start();
  }

  private async start(): Promise<void> {
    if (this.busy || audioRecordingService.isActive()) { return; }
    this.busy = true;
    this.message = '正在准备录音…';
    try {
      await audioRecordingService.start();
    } catch (error) {
      this.message = error instanceof Error ? error.message : '无法开始录音';
    } finally {
      this.busy = false;
    }
  }

  private applySnapshot(snapshot: AudioRecordingSnapshot): void {
    this.recorderState = snapshot.state;
    this.elapsedMs = snapshot.elapsedMs;
    this.amplitude = snapshot.amplitude;
    this.message = snapshot.message;
    if (snapshot.state === 'completed' && !this.delivered) {
      const completed = audioRecordingService.takeCompleted();
      if (completed.length > 0) { this.deliver(completed[completed.length - 1]); }
    }
  }

  private deliver(audio: PickedMedia): void {
    if (this.delivered) { return; }
    this.delivered = true;
    this.onComplete(audio);
  }

  private async togglePause(): Promise<void> {
    if (this.busy) { return; }
    this.busy = true;
    try {
      if (this.recorderState === 'paused') { await audioRecordingService.resume(); }
      else { await audioRecordingService.pause(); }
    } catch (error) {
      this.message = '录音状态切换失败';
    } finally { this.busy = false; }
  }

  private async finish(): Promise<void> {
    if (this.busy) { return; }
    this.busy = true;
    try {
      const result = await audioRecordingService.finish();
      const completed = audioRecordingService.takeCompleted();
      if (result) { this.deliver(result); }
      else if (completed.length > 0) { this.deliver(completed[completed.length - 1]); }
    } catch (error) {
      this.message = '录音保存失败，请重试';
    } finally { this.busy = false; }
  }

  private async requestExit(): Promise<void> {
    if (!audioRecordingService.isActive()) { this.onCancel(); return; }
    try {
      const result = await this.getUIContext().getPromptAction().showDialog({
        title: '退出录音？',
        message: '可以结束并保留当前录音，或放弃这段录音。',
        buttons: [
          { text: '继续录音', color: COLOR_MUTED_ON_DARK },
          { text: '结束并保留', color: COLOR_PRIMARY_BRIGHT },
          { text: '放弃录音', color: COLOR_DANGER }
        ]
      });
      if (result.index === 1) { await this.finish(); }
      else if (result.index === 2) { await audioRecordingService.cancel(); this.onCancel(); }
    } catch (error) {}
  }

  private formatTime(milliseconds: number): string {
    const seconds = Math.max(0, Math.floor(milliseconds / 1000));
    const minute = Math.floor(seconds / 60);
    const second = seconds % 60;
    return `${minute.toString().padStart(2, '0')}:${second.toString().padStart(2, '0')}`;
  }

  @Builder
  private permissionPanel(): void {
    Column({ space: 16 }) {
      Text('麦克风权限').fontSize(22).fontWeight(FontWeight.Bold).fontColor(COLOR_ON_DARK)
      Text(this.message).fontSize(14).fontColor(COLOR_MUTED_ON_DARK).textAlign(TextAlign.Center)
      if (this.permissionState === 'denied') {
        Button(this.requiresSettings ? '前往系统设置' : '重新授权')
          .width(190).height(46).fontColor(COLOR_MEDIA_CANVAS).backgroundColor(COLOR_PRIMARY_BRIGHT)
          .borderRadius(23).onClick((): void => { this.authorize(this.requiresSettings); })
      } else {
        LoadingProgress().width(42).height(42).color(COLOR_PRIMARY_BRIGHT)
      }
      Button('取消').width(190).height(42).fontColor(COLOR_ON_DARK).backgroundColor('#263B36')
        .borderRadius(21).onClick((): void => { this.onCancel(); })
    }.width('100%').height('100%').justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
  }

  @Builder
  private levelBars(): void {
    Row({ space: 5 }) {
      ForEach([0.04, 0.09, 0.15, 0.22, 0.30, 0.39, 0.49, 0.60, 0.71, 0.81, 0.90, 0.97],
        (threshold: number, index: number): void => {
          Column()
            .width(5)
            .height(14 + Math.abs(5.5 - index) * 4.5)
            .backgroundColor(this.amplitude >= threshold ? COLOR_PRIMARY_BRIGHT : '#65706D')
            .opacity(this.amplitude >= threshold ? 1 : 0.55)
            .borderRadius(3)
        }, (threshold: number): string => `${threshold}`)
    }.height(54).alignItems(VerticalAlign.Center)
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.permissionState !== 'granted') {
        this.permissionPanel()
      } else {
        Column() {
          Row() {
            Button('×').width(44).height(44).fontSize(24).fontColor(COLOR_ON_DARK)
              .backgroundColor(COLOR_OVERLAY).borderRadius(22).onClick((): void => { this.requestExit(); })
            Blank()
            Text('密匣录音').fontSize(18).fontWeight(FontWeight.Bold).fontColor(COLOR_ON_DARK)
            Blank()
            Text('最长10分钟').fontSize(11).fontColor(COLOR_MUTED_ON_DARK)
              .width(82).textAlign(TextAlign.End)
          }.width('100%').padding({ left: 18, right: 18, top: 30 })
          Blank()
          Column({ space: 18 }) {
            Stack({ alignContent: Alignment.Center }) {
              Circle().width(178).height(178).fill('#162A25').stroke('#315A50').strokeWidth(2)
              Circle().width(122 + this.amplitude * 34).height(122 + this.amplitude * 34)
                .fill('#243F38').opacity(0.85)
              Circle().width(84).height(84).fill(this.recorderState === 'paused' ? '#F3C969' : '#FF6B6B')
              Text(this.recorderState === 'paused' ? 'Ⅱ' : '●').fontSize(30).fontColor(COLOR_ON_DARK)
            }.width(190).height(190)
            Text(this.formatTime(this.elapsedMs)).fontSize(42).fontWeight(FontWeight.Bold)
              .fontColor(COLOR_ON_DARK).fontFamily('monospace')
            this.levelBars()
            Text(this.recorderState === 'paused' ? '录音已暂停' : '正在录音 · 可切换应用或锁屏')
              .fontSize(13).fontColor(COLOR_MUTED_ON_DARK)
            if (this.message.length > 0) {
              Text(this.message).fontSize(12).fontColor(COLOR_DANGER).textAlign(TextAlign.Center)
            }
          }.alignItems(HorizontalAlign.Center)
          Blank()
          Row({ space: 16 }) {
            Button(this.recorderState === 'paused' ? '继续' : '暂停')
              .layoutWeight(1).height(52).fontSize(15).fontColor(COLOR_ON_DARK)
              .backgroundColor('#2A403A').borderRadius(26).enabled(!this.busy)
              .onClick((): void => { this.togglePause(); })
            Button('完成')
              .layoutWeight(1).height(52).fontSize(15).fontWeight(FontWeight.Bold)
              .fontColor(COLOR_MEDIA_CANVAS).backgroundColor(COLOR_PRIMARY_BRIGHT).borderRadius(26)
              .enabled(!this.busy).onClick((): void => { this.finish(); })
          }.width('100%').padding({ left: 22, right: 22, bottom: 32 })
        }.width('100%').height('100%')
      }
    }.width('100%').height('100%').backgroundColor(COLOR_MEDIA_CANVAS)
  }
}
