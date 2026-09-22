import { camera } from '@kit.CameraKit';
import { PickedMedia } from '../services/MediaPickerService';
import { privateCaptureService } from '../services/PrivateCaptureService';
import {
  PrivateCameraCapabilities, PrivateCameraPermissionState, PrivateCameraService
} from '../services/PrivateCameraService';
import { AbilityContextHolder } from '../services/AbilityContextHolder';
import { VaultThumbnail } from './VaultThumbnail';
import { COLOR_MEDIA_CANVAS, COLOR_ON_DARK, COLOR_OVERLAY, COLOR_PRIMARY_BRIGHT } from './VaultTheme';

@Component
export struct PrivateCameraOverlay {
  onComplete: (media: PickedMedia[]) => void = (_media: PickedMedia[]): void => {};
  onCancel: () => void = (): void => {};
  @StorageLink('vaultAppForeground') @Watch('handleForegroundChange')
  private appForeground: boolean = true;
  @State private permissionState: string = 'idle';
  @State private statusText: string = '正在准备相机…';
  @State private captures: PickedMedia[] = [];
  @State private front: boolean = false;
  @State private flashMode: camera.FlashMode = camera.FlashMode.FLASH_MODE_CLOSE;
  @State private flashModes: camera.FlashMode[] = [];
  @State private minZoom: number = 1;
  @State private maxZoom: number = 1;
  @State private zoom: number = 1;
  @State private ready: boolean = false;
  @State private canSwitchCamera: boolean = false;
  @State private previewIndex: number = -1;
  @State private previewOpen: boolean = false;
  @State private requiresPermissionSettings: boolean = false;
  private controller: XComponentController = new XComponentController();
  private surfaceId: string = '';
  private service: PrivateCameraService = new PrivateCameraService();
  private startVersion: number = 0;
  private handedOff: boolean = false;
  private viewWidth: number = 1;
  private viewHeight: number = 1;
  private pinchStartZoom: number = 1;

  aboutToAppear(): void {
    AbilityContextHolder.setPrivacyMode(true);
    this.preparePermission();
  }

  aboutToDisappear(): void {
    this.startVersion += 1;
    this.service.stop();
    if (!this.handedOff) { privateCaptureService.removeMedia(this.captures); }
    AbilityContextHolder.setPrivacyMode(false);
  }

  private async preparePermission(): Promise<void> {
    const state = this.service.getPermissionState();
    if (state === PrivateCameraPermissionState.GRANTED) {
      this.permissionState = 'granted';
      this.statusText = '正在启动相机…';
      await this.tryStart();
      return;
    }
    if (state === PrivateCameraPermissionState.REQUESTABLE) {
      this.requiresPermissionSettings = false;
      await this.authorize(false);
      return;
    }
    this.requiresPermissionSettings = true;
    this.permissionState = 'denied';
    this.statusText = '相机权限已被拒绝，请前往系统设置允许相机访问';
  }

  private async authorize(fromSettings: boolean): Promise<void> {
    if (this.permissionState === 'requesting') { return; }
    this.permissionState = 'requesting';
    this.statusText = fromSettings ? '正在打开权限设置…' : '正在请求相机权限…';
    const granted = await this.service.requestPermission(fromSettings);
    const state = this.service.getPermissionState();
    this.requiresPermissionSettings = state === PrivateCameraPermissionState.SETTINGS_REQUIRED;
    this.permissionState = granted ? 'granted' : 'denied';
    this.statusText = granted ? '正在启动相机…' :
      (this.requiresPermissionSettings ? '仍未获得相机权限，请前往系统设置允许相机访问' : '授权未完成，请重新授权');
    if (granted) { await this.tryStart(); }
  }

  private async tryStart(): Promise<void> {
    if (!this.appForeground || this.permissionState !== 'granted' || this.surfaceId.length === 0) { return; }
    const version = ++this.startVersion;
    this.ready = false;
    this.statusText = '正在启动相机…';
    try {
      const capabilities = await this.service.start(this.surfaceId, this.front,
        (media: PickedMedia): void => {
          if (this.captures.length >= 50) {
            privateCaptureService.removeMedia([media]);
            return;
          }
          this.captures = this.captures.concat([media]);
          this.previewIndex = this.captures.length - 1;
        }, (message: string): void => {
          this.getUIContext().getPromptAction().showToast({ message: message });
        });
      if (version !== this.startVersion) { await this.service.stop(); return; }
      this.applyCapabilities(capabilities);
      this.ready = true;
      this.statusText = '';
    } catch (error) {
      if (version !== this.startVersion) { await this.service.stop(); return; }
      this.ready = false;
      this.statusText = error instanceof Error ? error.message : '相机启动失败';
    }
  }

  private applyCapabilities(capabilities: PrivateCameraCapabilities): void {
    this.flashModes = capabilities.flashModes;
    this.canSwitchCamera = capabilities.hasFront && capabilities.hasBack;
    this.minZoom = capabilities.minZoom;
    this.maxZoom = capabilities.maxZoom;
    this.zoom = Math.max(this.minZoom, Math.min(this.maxZoom, 1));
    if (this.flashModes.indexOf(this.flashMode) < 0) {
      this.flashMode = this.flashModes.length > 0 ? this.flashModes[0] : camera.FlashMode.FLASH_MODE_CLOSE;
    }
  }

  private async handleForegroundChange(): Promise<void> {
    if (!this.appForeground) {
      this.startVersion += 1;
      this.ready = false;
      await this.service.stop();
      return;
    }
    if (this.permissionState === 'granted') { await this.tryStart(); }
  }

  private async switchCamera(): Promise<void> {
    if (!this.ready) { return; }
    this.front = !this.front;
    await this.tryStart();
  }

  private cycleFlash(): void {
    if (this.flashModes.length <= 1) { return; }
    const index = this.flashModes.indexOf(this.flashMode);
    this.flashMode = this.flashModes[(index + 1) % this.flashModes.length];
  }

  private flashLabel(): string {
    if (this.flashMode === camera.FlashMode.FLASH_MODE_AUTO) { return '闪光 自动'; }
    if (this.flashMode === camera.FlashMode.FLASH_MODE_OPEN) { return '闪光 开'; }
    return '闪光 关';
  }

  private async takePhoto(): Promise<void> {
    if (!this.ready || this.captures.length >= 50) { return; }
    try { await this.service.capture(this.flashMode); }
    catch (error) {
      try { this.getUIContext().getPromptAction().showToast({ message: '拍摄失败，请重试' }); }
      catch (promptError) {}
    }
  }

  private removeCapture(index: number): void {
    if (index < 0 || index >= this.captures.length) { return; }
    privateCaptureService.removeMedia([this.captures[index]]);
    this.captures = this.captures.filter((_item: PickedMedia, itemIndex: number): boolean => itemIndex !== index);
    if (this.captures.length === 0) { this.previewIndex = -1; }
    else { this.previewIndex = Math.min(index, this.captures.length - 1); }
  }

  private finish(): void {
    if (this.captures.length === 0) { return; }
    this.handedOff = true;
    this.onComplete(this.captures.slice());
  }

  private cancel(): void {
    privateCaptureService.removeMedia(this.captures);
    this.captures = [];
    this.handedOff = true;
    this.onCancel();
  }

  private focus(event: GestureEvent): void {
    if (!this.ready || event.fingerList.length === 0) { return; }
    const point = event.fingerList[0];
    this.service.focus(point.localX / this.viewWidth, point.localY / this.viewHeight);
  }

  @Builder
  private permissionPanel(): void {
    Column({ space: 16 }) {
      Text('相机权限').fontSize(22).fontWeight(FontWeight.Bold).fontColor(COLOR_ON_DARK)
      Text(this.statusText).fontSize(14).fontColor('#B9C8C3').textAlign(TextAlign.Center)
      if (this.permissionState === 'denied') {
        Button(this.requiresPermissionSettings ? '前往系统设置' : '重新授权')
          .width(180).height(46).fontColor(COLOR_MEDIA_CANVAS).backgroundColor(COLOR_PRIMARY_BRIGHT)
          .onClick((): void => { this.authorize(this.requiresPermissionSettings); })
      } else {
        LoadingProgress().width(42).height(42).color(COLOR_PRIMARY_BRIGHT)
      }
      Button('取消').width(180).height(42).fontColor(COLOR_ON_DARK).backgroundColor('#263B36')
        .onClick((): void => { this.cancel(); })
    }.width('100%').height('100%').justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      .backgroundColor(COLOR_MEDIA_CANVAS).zIndex(100)
  }

  @Builder
  private captureStrip(): void {
    if (this.captures.length > 0) {
      Scroll() {
        Row({ space: 8 }) {
          ForEach(this.captures, (item: PickedMedia, index: number): void => {
            Stack({ alignContent: Alignment.TopEnd }) {
              VaultThumbnail({ itemId: '', mediaType: item.type, sourceUri: item.uri, thumbnailSize: 58 })
              Text('×').fontSize(14).fontColor(COLOR_ON_DARK).textAlign(TextAlign.Center)
                .width(22).height(22).borderRadius(11).backgroundColor(COLOR_OVERLAY)
                .onClick((): void => { this.removeCapture(index); })
            }
            .width(62).height(62).padding(2).borderRadius(12)
            .border({ width: this.previewIndex === index ? 2 : 0, color: COLOR_PRIMARY_BRIGHT })
            .onClick((): void => { this.previewIndex = index; this.previewOpen = true; })
          }, (item: PickedMedia): string => item.uri)
        }.padding({ left: 14, right: 14 })
      }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
    }
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      XComponent({ id: 'palmvault-private-camera', type: XComponentType.SURFACE, controller: this.controller })
        .width('100%').height('100%')
        .onLoad((): void => {
          this.surfaceId = this.controller.getXComponentSurfaceId();
          this.tryStart();
        })
        .onAreaChange((_oldArea: Area, newArea: Area): void => {
          this.viewWidth = Math.max(1, Number(newArea.width));
          this.viewHeight = Math.max(1, Number(newArea.height));
        })
        .gesture(TapGesture().onAction((event: GestureEvent): void => { this.focus(event); }))
        .gesture(PinchGesture({ fingers: 2, distance: 5 })
          .onActionStart((): void => { this.pinchStartZoom = this.zoom; })
          .onActionUpdate((event: GestureEvent): void => {
            this.zoom = Math.max(this.minZoom, Math.min(this.maxZoom, this.pinchStartZoom * event.scale));
            this.service.setZoom(this.zoom);
          }))
      if (this.permissionState !== 'granted') { this.permissionPanel() }
      else if (!this.ready && this.statusText.length > 0) {
        Column({ space: 12 }) {
          LoadingProgress().width(40).height(40).color(COLOR_PRIMARY_BRIGHT)
          Text(this.statusText).fontSize(13).fontColor(COLOR_ON_DARK).textAlign(TextAlign.Center)
        }.padding(20).backgroundColor(COLOR_OVERLAY).borderRadius(16)
      }
      if (this.permissionState === 'granted') {
        Column() {
          Row() {
            Button('×').width(44).height(44).fontSize(25).fontColor(COLOR_ON_DARK).backgroundColor(COLOR_OVERLAY)
              .borderRadius(22).onClick((): void => { this.cancel(); })
            Blank()
            Text('私密拍摄').fontSize(16).fontWeight(FontWeight.Bold).fontColor(COLOR_ON_DARK)
            Blank()
            Button(this.front ? '前摄' : '后摄').height(40).fontSize(12).fontColor(COLOR_ON_DARK)
              .backgroundColor(COLOR_OVERLAY).enabled(this.ready && this.canSwitchCamera)
              .opacity(this.canSwitchCamera ? 1 : 0.45).onClick((): void => { this.switchCamera(); })
          }.width('100%').padding({ left: 14, right: 14, top: 32 })
          Row() {
            Button(this.flashLabel()).height(36).fontSize(11).fontColor(COLOR_ON_DARK).backgroundColor(COLOR_OVERLAY)
              .enabled(this.ready && this.flashModes.length > 1).onClick((): void => { this.cycleFlash(); })
            Blank()
            Text(`${this.zoom.toFixed(1)}×`).fontSize(12).fontColor(COLOR_ON_DARK)
              .padding({ left: 10, right: 10, top: 7, bottom: 7 }).backgroundColor(COLOR_OVERLAY).borderRadius(16)
          }.width('100%').padding({ left: 16, right: 16, top: 10 })
          Blank()
          this.captureStrip()
          Row() {
            Text(`${this.captures.length}/50`).fontSize(12).fontColor(COLOR_ON_DARK).width(70)
            Blank()
            Button('●').width(76).height(76).fontSize(42).fontColor(COLOR_ON_DARK).backgroundColor('#33FFFFFF')
              .border({ width: 4, color: COLOR_ON_DARK }).borderRadius(38)
              .enabled(this.ready && this.captures.length < 50).onClick((): void => { this.takePhoto(); })
            Blank()
            Button('完成').width(70).height(42).fontSize(14).fontWeight(FontWeight.Bold)
              .fontColor(COLOR_MEDIA_CANVAS).backgroundColor(COLOR_PRIMARY_BRIGHT).borderRadius(21)
              .enabled(this.captures.length > 0).opacity(this.captures.length > 0 ? 1 : 0.45)
              .onClick((): void => { this.finish(); })
          }.width('100%').padding({ left: 16, right: 16, top: 12, bottom: 28 })
        }.width('100%').height('100%')
      }
      if (this.previewOpen && this.previewIndex >= 0 && this.previewIndex < this.captures.length) {
        Stack({ alignContent: Alignment.Center }) {
          VaultThumbnail({
            itemId: '',
            mediaType: this.captures[this.previewIndex].type,
            sourceUri: this.captures[this.previewIndex].uri,
            thumbnailSize: 720,
            fillContainer: true
          })
          Button('×').width(44).height(44).fontSize(25).fontColor(COLOR_ON_DARK).backgroundColor(COLOR_OVERLAY)
            .borderRadius(22).position({ top: 34, right: 14 })
            .onClick((): void => { this.previewOpen = false; })
          Text(`${this.previewIndex + 1} / ${this.captures.length}`).fontSize(12).fontColor(COLOR_ON_DARK)
            .padding({ left: 12, right: 12, top: 7, bottom: 7 }).backgroundColor(COLOR_OVERLAY)
            .borderRadius(15).position({ top: 44, left: 16 })
        }.width('100%').height('100%').backgroundColor(COLOR_MEDIA_CANVAS).zIndex(50)
      }
    }.width('100%').height('100%').backgroundColor(COLOR_MEDIA_CANVAS)
  }
}
