import { abilityAccessCtrl, Permissions, wantAgent } from '@kit.AbilityKit';
import backgroundTaskManager from '@ohos.resourceschedule.backgroundTaskManager';
import fs from '@ohos.file.fs';
import media from '@ohos.multimedia.media';
import util from '@ohos.util';
import { AbilityContextHolder } from './AbilityContextHolder';
import { normalizeError } from './ErrorUtils';
import { PickedMedia } from './MediaPickerService';
import { MAX_RECORDING_DURATION_MS } from './VaultLimits';
import { VaultItemType } from '../models/VaultModels';

export enum AudioRecordingPermissionState {
  GRANTED = 0,
  REQUESTABLE = 1,
  SETTINGS_REQUIRED = 2
}

export interface AudioRecordingSnapshot {
  state: string;
  elapsedMs: number;
  amplitude: number;
  message: string;
}

type RecordingListener = (snapshot: AudioRecordingSnapshot) => void;

class AudioRecordingService {
  private recorder?: media.AVRecorder = undefined;
  private output?: fs.File = undefined;
  private outputPath: string = '';
  private startedAt: number = 0;
  private pausedAt: number = 0;
  private pausedTotal: number = 0;
  private timer: number = -1;
  private state: string = 'idle';
  private amplitude: number = 0;
  private message: string = '';
  private listener?: RecordingListener = undefined;
  private completionListener?: (audio: PickedMedia) => void = undefined;
  private completed: PickedMedia[] = [];
  private finishing: boolean = false;
  private backgroundRunning: boolean = false;
  private permissionRequested: boolean = false;

  getPermissionState(): AudioRecordingPermissionState {
    const permission = 'ohos.permission.MICROPHONE' as Permissions;
    try {
      const context = AbilityContextHolder.getContext();
      const status = abilityAccessCtrl.createAtManager()
        .checkAccessTokenSync(context.applicationInfo.accessTokenId, permission);
      if (status === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
        this.permissionRequested = false;
        return AudioRecordingPermissionState.GRANTED;
      }
      return this.permissionRequested ? AudioRecordingPermissionState.SETTINGS_REQUIRED :
        AudioRecordingPermissionState.REQUESTABLE;
    } catch (error) {
      return AudioRecordingPermissionState.REQUESTABLE;
    }
  }

  async requestPermission(fromSettings: boolean = false): Promise<boolean> {
    const permission = 'ohos.permission.MICROPHONE' as Permissions;
    const manager = abilityAccessCtrl.createAtManager();
    const context = AbilityContextHolder.getContext();
    if (this.getPermissionState() === AudioRecordingPermissionState.GRANTED) { return true; }
    try {
      if (fromSettings) {
        const statuses = await manager.requestPermissionOnSetting(context, [permission]);
        const granted = statuses.length > 0 && statuses[0] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
        this.permissionRequested = !granted;
        return granted;
      }
      const result = await manager.requestPermissionsFromUser(context, [permission]);
      const granted = result.authResults.length > 0 && result.authResults[0] ===
        abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
      this.permissionRequested = !granted;
      return granted;
    } catch (error) {
      try {
        const granted = manager.checkAccessTokenSync(context.applicationInfo.accessTokenId, permission) ===
          abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
        this.permissionRequested = !granted;
        return granted;
      } catch (checkError) {
        this.permissionRequested = true;
        return false;
      }
    }
  }

  attach(listener: RecordingListener): void {
    this.listener = listener;
    this.notify();
  }

  detach(listener: RecordingListener): void {
    if (this.listener === listener) { this.listener = undefined; }
  }

  setCompletionListener(listener: (audio: PickedMedia) => void): void {
    this.completionListener = listener;
  }

  snapshot(): AudioRecordingSnapshot {
    return { state: this.state, elapsedMs: this.elapsed(), amplitude: this.amplitude, message: this.message };
  }

  isActive(): boolean {
    return this.state === 'recording' || this.state === 'paused' || this.state === 'starting';
  }

  takeCompleted(): PickedMedia[] {
    const result = this.completed.slice();
    this.completed = [];
    return result;
  }

  cleanupTemporaryFiles(force: boolean = false): number {
    let removed = 0;
    try {
      const cacheDir = AbilityContextHolder.getContext().cacheDir;
      fs.listFileSync(cacheDir).forEach((name: string): void => {
        if (!name.startsWith('pv-record-')) { return; }
        const path = `${cacheDir}/${name}`;
        if (path === this.outputPath || this.completed.some((item: PickedMedia): boolean => item.uri === path)) {
          return;
        }
        if (!force && Date.now() - fs.statSync(path).mtime < 24 * 60 * 60 * 1000) { return; }
        try { fs.unlinkSync(path); removed += 1; } catch (error) {}
      });
    } catch (error) {}
    return removed;
  }

  async start(): Promise<void> {
    if (this.isActive()) { return; }
    if (this.getPermissionState() !== AudioRecordingPermissionState.GRANTED) {
      throw new Error('尚未获得麦克风权限');
    }
    this.state = 'starting';
    this.message = '';
    this.notify();
    this.outputPath = `${AbilityContextHolder.getContext().cacheDir}/pv-record-${util.generateRandomUUID()}.m4a`;
    try {
      this.output = fs.openSync(this.outputPath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      const recorder = await media.createAVRecorder();
      this.recorder = recorder;
      recorder.on('error', (): void => { this.finishAfterInterruption('录音被系统中断'); });
      recorder.on('stateChange', (state: media.AVRecorderState): void => {
        if (state === 'stopped' && !this.finishing && this.isActive()) {
          this.finishAfterInterruption('录音已达到最长时长');
        }
      });
      const config: media.AVRecorderConfig = {
        audioSourceType: media.AudioSourceType.AUDIO_SOURCE_TYPE_MIC,
        profile: {
          audioBitrate: 96000,
          audioChannels: 1,
          audioCodec: media.CodecMimeType.AUDIO_AAC,
          audioSampleRate: 48000,
          fileFormat: media.ContainerFormatType.CFT_MPEG_4A
        },
        url: `fd://${this.output.fd}`,
        maxDuration: Math.floor(MAX_RECORDING_DURATION_MS / 1000)
      };
      await recorder.prepare(config);
      await this.startBackgroundTask();
      await recorder.start();
      this.startedAt = Date.now();
      this.pausedAt = 0;
      this.pausedTotal = 0;
      this.state = 'recording';
      this.startTimer();
      this.notify();
    } catch (error) {
      await this.release(false);
      throw new Error(`无法开始录音：${normalizeError(error).message}`);
    }
  }

  async pause(): Promise<void> {
    if (this.state !== 'recording' || !this.recorder) { return; }
    try {
      await this.recorder.pause();
    } catch (error) {
      throw normalizeError(error);
    }
    this.pausedAt = Date.now();
    this.state = 'paused';
    this.notify();
  }

  async resume(): Promise<void> {
    if (this.state !== 'paused' || !this.recorder) { return; }
    try {
      await this.recorder.resume();
    } catch (error) {
      throw normalizeError(error);
    }
    if (this.pausedAt > 0) { this.pausedTotal += Date.now() - this.pausedAt; }
    this.pausedAt = 0;
    this.state = 'recording';
    this.notify();
  }

  async finish(): Promise<PickedMedia | undefined> {
    if (!this.isActive() || this.finishing) { return undefined; }
    this.finishing = true;
    const elapsedMs = this.elapsed();
    try {
      if (this.recorder && this.recorder.state !== 'stopped') { await this.recorder.stop(); }
      const path = this.outputPath;
      await this.release(true);
      if (elapsedMs < 500 || path.length === 0 || !fs.accessSync(path) || fs.statSync(path).size <= 0) {
        this.removePath(path);
        this.state = 'idle';
        this.message = '录音时间太短，请重新录制';
        this.notify();
        return undefined;
      }
      const result: PickedMedia = {
        uri: path,
        sourceUri: '',
        type: VaultItemType.Audio,
        name: `录音-${this.timestamp()}.m4a`,
        ocrText: ''
      };
      this.completed.push(result);
      this.state = 'completed';
      this.message = '';
      this.notify();
      if (!this.listener && this.completionListener) { this.completionListener(result); }
      return result;
    } catch (error) {
      throw normalizeError(error);
    } finally {
      this.finishing = false;
    }
  }

  async cancel(): Promise<void> {
    if (this.finishing) { return; }
    this.finishing = true;
    const path = this.outputPath;
    try {
      if (this.recorder && (this.recorder.state === 'started' || this.recorder.state === 'paused')) {
        try { await this.recorder.stop(); } catch (error) {}
      }
      await this.release(false);
      this.removePath(path);
      this.state = 'idle';
      this.message = '';
      this.notify();
    } finally {
      this.finishing = false;
    }
  }

  private async release(keepPath: boolean): Promise<void> {
    this.stopTimer();
    const recorder = this.recorder;
    this.recorder = undefined;
    if (recorder) {
      try { await recorder.release(); } catch (error) {}
    }
    if (this.output) {
      try { fs.fsyncSync(this.output.fd); } catch (error) {}
      try { fs.closeSync(this.output); } catch (error) {}
      this.output = undefined;
    }
    await this.stopBackgroundTask();
    if (!keepPath) { this.removePath(this.outputPath); }
    this.outputPath = '';
    this.amplitude = 0;
  }

  private async startBackgroundTask(): Promise<void> {
    if (canIUse('SystemCapability.ResourceSchedule.BackgroundTaskManager.ContinuousTask')) {
      try {
        const context = AbilityContextHolder.getContext();
        const agent = await wantAgent.getWantAgent({
          wants: [{ bundleName: context.abilityInfo.bundleName, abilityName: context.abilityInfo.name }],
          actionType: wantAgent.OperationType.START_ABILITY,
          requestCode: 7201,
          actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
        });
        // API 21 tags the namespace with Core while the concrete API uses ContinuousTask.
        // API 12 devices may expose only the concrete capability, so fall back to it.
        let backgroundTaskCapability =
          'SystemCapability.ResourceSchedule.BackgroundTaskManager.Core';
        if (!canIUse(backgroundTaskCapability)) {
          backgroundTaskCapability =
            'SystemCapability.ResourceSchedule.BackgroundTaskManager.ContinuousTask';
        }
        if (canIUse(backgroundTaskCapability)) {
          await backgroundTaskManager.startBackgroundRunning(context,
            backgroundTaskManager.BackgroundMode.AUDIO_RECORDING, agent);
          this.backgroundRunning = true;
          return;
        }
      } catch (error) {
        throw normalizeError(error);
      }
    }
    throw new Error('当前设备不支持后台录音');
  }

  private async stopBackgroundTask(): Promise<void> {
    if (!this.backgroundRunning) { return; }
    this.backgroundRunning = false;
    if (canIUse('SystemCapability.ResourceSchedule.BackgroundTaskManager.ContinuousTask')) {
      try {
        let backgroundTaskCapability =
          'SystemCapability.ResourceSchedule.BackgroundTaskManager.Core';
        if (!canIUse(backgroundTaskCapability)) {
          backgroundTaskCapability =
            'SystemCapability.ResourceSchedule.BackgroundTaskManager.ContinuousTask';
        }
        if (canIUse(backgroundTaskCapability)) {
          await backgroundTaskManager.stopBackgroundRunning(AbilityContextHolder.getContext());
        }
      } catch (error) {}
    }
  }

  private startTimer(): void {
    this.stopTimer();
    this.timer = setInterval((): void => {
      if (!this.isActive()) { return; }
      if (this.state === 'recording' && this.recorder) {
        this.recorder.getAudioCapturerMaxAmplitude().then((value: number): void => {
          const ratio = Math.max(0, Math.min(1, value > 1 ? value / 32767 : value));
          const decibels = ratio > 0 ? 20 * Math.log10(ratio) : -96;
          const level = Math.max(0, Math.min(1, (decibels + 32) / 24));
          this.amplitude = this.amplitude * 0.35 + level * 0.65;
          if (this.amplitude < 0.025) { this.amplitude = 0; }
          this.notify();
        }).catch((): void => { this.notify(); });
      } else {
        this.amplitude = 0;
        this.notify();
      }
      if (this.elapsed() >= MAX_RECORDING_DURATION_MS) { this.finish(); }
    }, 250);
  }

  private stopTimer(): void {
    if (this.timer >= 0) { clearInterval(this.timer); this.timer = -1; }
  }

  private elapsed(): number {
    if (this.startedAt <= 0) { return 0; }
    const end = this.pausedAt > 0 ? this.pausedAt : Date.now();
    return Math.max(0, Math.min(MAX_RECORDING_DURATION_MS, end - this.startedAt - this.pausedTotal));
  }

  private finishAfterInterruption(message: string): void {
    this.message = message;
    this.finish().catch((): void => {
      this.state = 'error';
      this.message = '录音中断，未能保存当前内容';
      this.notify();
    });
  }

  private notify(): void {
    if (this.listener) { this.listener(this.snapshot()); }
  }

  private removePath(path: string): void {
    try { if (path.length > 0 && fs.accessSync(path)) { fs.unlinkSync(path); } } catch (error) {}
  }

  private timestamp(): string {
    const date = new Date();
    const two = (value: number): string => value.toString().padStart(2, '0');
    return `${date.getFullYear()}${two(date.getMonth() + 1)}${two(date.getDate())}-` +
      `${two(date.getHours())}${two(date.getMinutes())}${two(date.getSeconds())}`;
  }
}

export const audioRecordingService = new AudioRecordingService();
