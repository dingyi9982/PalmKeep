import { abilityAccessCtrl, Permissions } from '@kit.AbilityKit';
import { camera } from '@kit.CameraKit';
import { BusinessError } from '@kit.BasicServicesKit';
import image from '@ohos.multimedia.image';
import fs from '@ohos.file.fs';
import { AbilityContextHolder } from './AbilityContextHolder';
import { normalizeError } from './ErrorUtils';
import { privateCaptureService } from './PrivateCaptureService';
import { PickedMedia } from './MediaPickerService';

export interface PrivateCameraCapabilities {
  hasFront: boolean;
  hasBack: boolean;
  flashModes: camera.FlashMode[];
  minZoom: number;
  maxZoom: number;
}

export enum PrivateCameraPermissionState {
  GRANTED = 0,
  REQUESTABLE = 1,
  SETTINGS_REQUIRED = 2
}

export class PrivateCameraService {
  private manager?: camera.CameraManager = undefined;
  private input?: camera.CameraInput = undefined;
  private preview?: camera.PreviewOutput = undefined;
  private photo?: camera.PhotoOutput = undefined;
  private session?: camera.PhotoSession = undefined;
  private capturedCallback: (media: PickedMedia) => void = (_media: PickedMedia): void => {};
  private errorCallback: (message: string) => void = (_message: string): void => {};
  private captureSequence: number = 0;
  private running: boolean = false;
  private captureBusy: boolean = false;
  private front: boolean = false;
  private generation: number = 0;

  getPermissionState(): PrivateCameraPermissionState {
    const permission = 'ohos.permission.CAMERA' as Permissions;
    try {
      const status = abilityAccessCtrl.createAtManager().getSelfPermissionStatus(permission);
      if (status === abilityAccessCtrl.PermissionStatus.GRANTED) {
        return PrivateCameraPermissionState.GRANTED;
      }
      if (status === abilityAccessCtrl.PermissionStatus.NOT_DETERMINED) {
        return PrivateCameraPermissionState.REQUESTABLE;
      }
      return PrivateCameraPermissionState.SETTINGS_REQUIRED;
    } catch (error) {
      return PrivateCameraPermissionState.REQUESTABLE;
    }
  }

  async requestPermission(fromSettings: boolean = false): Promise<boolean> {
    const permission = 'ohos.permission.CAMERA' as Permissions;
    const manager = abilityAccessCtrl.createAtManager();
    const context = AbilityContextHolder.getContext();
    if (this.getPermissionState() === PrivateCameraPermissionState.GRANTED) { return true; }
    try {
      if (fromSettings) {
        const statuses = await manager.requestPermissionOnSetting(context, [permission]);
        return statuses.length > 0 && statuses[0] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
      }
      const result = await manager.requestPermissionsFromUser(context, [permission]);
      return result.authResults.length > 0 && result.authResults[0] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
    } catch (error) {
      try {
        return manager.checkAccessTokenSync(context.applicationInfo.accessTokenId, permission) ===
          abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
      } catch (checkError) {
        return false;
      }
    }
  }

  async start(surfaceId: string, front: boolean, onCaptured: (media: PickedMedia) => void,
    onError: (message: string) => void): Promise<PrivateCameraCapabilities> {
    await this.stop();
    const generation = this.generation;
    this.front = front;
    this.capturedCallback = onCaptured;
    this.errorCallback = onError;
    try {
      this.manager = camera.getCameraManager(AbilityContextHolder.getContext());
      const devices = this.manager.getSupportedCameras();
      const back = devices.find((device: camera.CameraDevice): boolean =>
        device.cameraPosition === camera.CameraPosition.CAMERA_POSITION_BACK);
      const frontDevice = devices.find((device: camera.CameraDevice): boolean =>
        device.cameraPosition === camera.CameraPosition.CAMERA_POSITION_FRONT);
      const selected = front ? frontDevice : back;
      const device = selected ?? back ?? frontDevice;
      if (!device) { throw new Error('当前设备没有可用相机'); }
      const capability = this.manager.getSupportedOutputCapability(device, camera.SceneMode.NORMAL_PHOTO);
      const photoProfile = this.choosePhotoProfile(capability.photoProfiles);
      const previewProfile = this.choosePreviewProfile(capability.previewProfiles, photoProfile);
      this.input = this.manager.createCameraInput(device);
      await this.input.open();
      this.preview = this.manager.createPreviewOutput(previewProfile, surfaceId);
      this.photo = this.manager.createPhotoOutput(photoProfile);
      this.photo.on('photoAvailable', (error: BusinessError, value: camera.Photo): void => {
        if (generation !== this.generation) {
          if (value) { value.release(); }
          return;
        }
        if (error || !value) {
          this.captureBusy = false;
          this.errorCallback('拍摄失败，请重试');
          return;
        }
        this.storePhoto(value);
      });
      this.session = this.manager.createSession<camera.PhotoSession>(camera.SceneMode.NORMAL_PHOTO);
      this.session.beginConfig();
      this.session.addInput(this.input);
      this.session.addOutput(this.preview);
      this.session.addOutput(this.photo);
      await this.session.commitConfig();
      const flashModes = this.supportedFlashModes(this.session);
      const zoomRange = this.session.getZoomRatioRange();
      if (this.session.isFocusModeSupported(camera.FocusMode.FOCUS_MODE_CONTINUOUS_AUTO)) {
        this.session.setFocusMode(camera.FocusMode.FOCUS_MODE_CONTINUOUS_AUTO);
      }
      await this.session.start();
      this.running = true;
      return {
        hasFront: frontDevice !== undefined,
        hasBack: back !== undefined,
        flashModes: flashModes,
        minZoom: zoomRange.length > 0 ? zoomRange[0] : 1,
        maxZoom: zoomRange.length > 1 ? zoomRange[1] : 1
      };
    } catch (error) {
      await this.stop();
      throw new Error(`无法启动相机：${normalizeError(error).message}`);
    }
  }

  async capture(flashMode: camera.FlashMode): Promise<void> {
    if (!this.running || !this.photo || this.captureBusy) { return; }
    this.captureBusy = true;
    try {
      if (this.session && this.session.isFlashModeSupported(flashMode)) {
        this.session.setFlashMode(flashMode);
      }
      const setting: camera.PhotoCaptureSetting = {
        quality: camera.QualityLevel.QUALITY_LEVEL_HIGH,
        rotation: this.photo.getPhotoRotation(0)
      };
      if (this.front && this.photo.isMirrorSupported()) { setting.mirror = true; }
      await this.photo.capture(setting);
    } catch (error) {
      this.captureBusy = false;
      throw normalizeError(error);
    }
  }

  setZoom(value: number): void {
    if (!this.session || !this.running) { return; }
    try {
      const range = this.session.getZoomRatioRange();
      const minimum = range.length > 0 ? range[0] : 1;
      const maximum = range.length > 1 ? range[1] : minimum;
      this.session.setZoomRatio(Math.max(minimum, Math.min(maximum, value)));
    } catch (error) {
      // Unsupported zoom must not interrupt capture.
    }
  }

  focus(x: number, y: number): void {
    if (!this.session || !this.running) { return; }
    try {
      if (!this.session.isFocusModeSupported(camera.FocusMode.FOCUS_MODE_AUTO)) { return; }
      this.session.setFocusMode(camera.FocusMode.FOCUS_MODE_AUTO);
      this.session.setFocusPoint({ x: Math.max(0, Math.min(1, x)), y: Math.max(0, Math.min(1, y)) });
    } catch (error) {
      // Unsupported focus must not interrupt capture.
    }
  }

  async stop(): Promise<void> {
    this.generation += 1;
    this.running = false;
    this.captureBusy = false;
    const session = this.session;
    const photo = this.photo;
    const preview = this.preview;
    const input = this.input;
    this.session = undefined;
    this.photo = undefined;
    this.preview = undefined;
    this.input = undefined;
    try { if (session) { await session.stop(); } } catch (error) {}
    try { if (session) { await session.release(); } } catch (error) {}
    try { if (photo) { await photo.release(); } } catch (error) {}
    try { if (preview) { await preview.release(); } } catch (error) {}
    try { if (input) { await input.close(); } } catch (error) {}
  }

  private async storePhoto(photo: camera.Photo): Promise<void> {
    const path = privateCaptureService.createCapturePath();
    let file: fs.File | undefined = undefined;
    let completed = false;
    try {
      const component = await photo.main.getComponent(image.ComponentType.JPEG);
      if (component.byteBuffer.byteLength <= 0) { throw new Error('相机没有返回图片数据'); }
      file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, component.byteBuffer, { length: component.byteBuffer.byteLength });
      fs.fsyncSync(file.fd);
      if (fs.statSync(file.fd).size <= 0) { throw new Error('拍摄结果写入失败'); }
      completed = true;
      this.captureSequence += 1;
      this.capturedCallback(privateCaptureService.captureMedia(path, this.captureSequence));
    } catch (error) {
      this.errorCallback(normalizeError(error).message);
    } finally {
      if (file) {
        try { fs.closeSync(file); } catch (error) {}
      }
      try { await photo.release(); } catch (error) {}
      if (!completed) { privateCaptureService.removeMedia([privateCaptureService.captureMedia(path, 0)]); }
      this.captureBusy = false;
    }
  }

  private choosePhotoProfile(profiles: camera.Profile[]): camera.Profile {
    const jpeg = profiles.filter((profile: camera.Profile): boolean =>
      profile.format === camera.CameraFormat.CAMERA_FORMAT_JPEG);
    const candidates = jpeg.length > 0 ? jpeg : profiles;
    if (candidates.length === 0) { throw new Error('相机没有可用拍照规格'); }
    const preferred = candidates.filter((profile: camera.Profile): boolean => {
      const pixels = profile.size.width * profile.size.height;
      const ratio = Math.max(profile.size.width, profile.size.height) / Math.min(profile.size.width, profile.size.height);
      return pixels <= 12000000 && Math.abs(ratio - 4 / 3) < 0.08;
    });
    if (preferred.length > 0) {
      return preferred.reduce((best: camera.Profile, current: camera.Profile): camera.Profile =>
        current.size.width * current.size.height > best.size.width * best.size.height ? current : best);
    }
    return candidates.reduce((best: camera.Profile, current: camera.Profile): camera.Profile =>
      current.size.width * current.size.height < best.size.width * best.size.height ? current : best);
  }

  private choosePreviewProfile(profiles: camera.Profile[], photoProfile: camera.Profile): camera.Profile {
    if (profiles.length === 0) { throw new Error('相机没有可用预览规格'); }
    const targetRatio = photoProfile.size.width / photoProfile.size.height;
    const fitting = profiles.filter((profile: camera.Profile): boolean =>
      profile.size.width <= 1920 && profile.size.height <= 1920);
    const pool = fitting.length > 0 ? fitting : profiles;
    return pool.reduce((best: camera.Profile, current: camera.Profile): camera.Profile => {
      const bestDiff = Math.abs(best.size.width / best.size.height - targetRatio);
      const currentDiff = Math.abs(current.size.width / current.size.height - targetRatio);
      if (currentDiff < bestDiff - 0.01) { return current; }
      if (Math.abs(currentDiff - bestDiff) <= 0.01 &&
        current.size.width * current.size.height > best.size.width * best.size.height) { return current; }
      return best;
    });
  }

  private supportedFlashModes(session: camera.PhotoSession): camera.FlashMode[] {
    const modes = [camera.FlashMode.FLASH_MODE_CLOSE, camera.FlashMode.FLASH_MODE_AUTO,
      camera.FlashMode.FLASH_MODE_OPEN];
    return modes.filter((mode: camera.FlashMode): boolean => {
      try { return session.isFlashModeSupported(mode); } catch (error) { return false; }
    });
  }
}
