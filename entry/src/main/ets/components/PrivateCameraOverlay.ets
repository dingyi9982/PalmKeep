import { camera } from '@kit.CameraKit';
import { PickedMedia } from '../services/MediaPickerService';
import { privateCaptureService } from '../services/PrivateCaptureService';
import {
  PrivateCameraCapabilities, PrivateCameraPermissionState, PrivateCameraService
} from '../services/PrivateCameraService';
import { AbilityContextHolder } from '../services/AbilityContextHolder';
import { VaultThumbnail } from './VaultThumbnail';
import {
  COLOR_MEDIA_CANVAS, COLOR_MUTED_ON_DARK, COLOR_ON_DARK, COLOR_OVERLAY,
  COLOR_PRIMARY_BRIGHT
} from './VaultTheme';

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
    this.service.setFlashMode(this.flashMode);
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
    this.service.setFlashMode(this.flashMode);
  }

  private flashLabel(): string {
    if (this.flashMode === camera.FlashMode.FLASH_MODE_AUTO) { return '⚡ 自动'; }
    if (this.flashMode === camera.FlashMode.FLASH_MODE_OPEN) { return '⚡ 开启'; }
    return '⚡ 关闭';
  }

  private flashColor(): string {
    return this.flashMode === camera.FlashMode.FLASH_MODE_CLOSE ? COLOR_ON_DARK : '#FFD86B';
  }

  private zoomLabel(): string {
    const rounded = Math.round(this.zoom);
    return Math.abs(this.zoom - rounded) < 0.05 ? `${rounded}×` : `${this.zoom.toFixed(1)}×`;
  }

  private cycleZoom(): void {
    if (!this.ready || this.maxZoom <= this.minZoom + 0.05) { return; }
    const source: number[] = [this.minZoom, 1, 2, 3, 5, this.maxZoom];
    const candidates: number[] = [];
    source.forEach((value: number): void => {
      const bounded = Math.max(this.minZoom, Math.min(this.maxZoom, value));
      if (!candidates.some((candidate: number): boolean => Math.abs(candidate - bounded) < 0.05)) {
        candidates.push(bounded);
      }
    });
    candidates.sort((left: number, right: number): number => left - right);
    let next = candidates[0];
    for (let index = 0; index < candidates.length; index += 1) {
      if (candidates[index] > this.zoom + 0.08) {
        next = candidates[index];
        break;
      }
    }
    this.zoom = next;
    this.service.setZoom(this.zoom);
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
              Text('×').fontSize(13).fontColor(COLOR_ON_DARK).textAlign(TextAlign.Center)
                .width(22).height(22).borderRadius(11).backgroundColor('#CC1D2523')
                .onClick((): void => { this.removeCapture(index); })
            }
            .width(64).height(64).padding(3).borderRadius(14).backgroundColor('#332DD6A6')
            .border({ width: this.previewIndex === index ? 2 : 0, color: COLOR_PRIMARY_BRIGHT })
            .onClick((): void => { this.previewIndex = index; this.previewOpen = true; })
          }, (item: PickedMedia): string => item.uri)
        }.padding({ left: 16, right: 16 })
      }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
    }
  }

  @Builder
  private cameraGuides(): void {
    Stack() {
      Row() {
        Blank().layoutWeight(1)
        Column() {}.width(1).height('100%').backgroundColor('#55FFFFFF')
        Blank().layoutWeight(1)
        Column() {}.width(1).height('100%').backgroundColor('#55FFFFFF')
        Blank().layoutWeight(1)
      }.width('100%').height('100%')
      Column() {
        Blank().layoutWeight(1)
        Row() {}.width('100%').height(1).backgroundColor('#55FFFFFF')
        Blank().layoutWeight(1)
        Row() {}.width('100%').height(1).backgroundColor('#55FFFFFF')
        Blank().layoutWeight(1)
      }.width('100%').height('100%')
    }.width('100%').height('100%').padding({ top: 154, bottom: 230, left: 10, right: 10 })
      .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private cameraTopBar(): void {
    Column({ space: 12 }) {
      Row() {
        Button('×').width(44).height(44).fontSize(24).fontColor(COLOR_ON_DARK)
          .backgroundColor(COLOR_OVERLAY).borderRadius(22).onClick((): void => { this.cancel(); })
        Blank()
        Column({ space: 2 }) {
          Text('密匣相机').fontSize(17).fontWeight(FontWeight.Bold).fontColor(COLOR_ON_DARK)
          Text('仅保存到掌心密匣').fontSize(10).fontColor(COLOR_MUTED_ON_DARK)
        }.alignItems(HorizontalAlign.Center)
        Blank()
        Button('切换').width(60).height(40).fontSize(12).fontColor(COLOR_ON_DARK)
          .backgroundColor(COLOR_OVERLAY).borderRadius(20).enabled(this.ready && this.canSwitchCamera)
          .opacity(this.canSwitchCamera ? 1 : 0.45).onClick((): void => { this.switchCamera(); })
      }.width('100%')
      Row() {
        Button(this.flashLabel()).height(40).fontSize(12).fontWeight(FontWeight.Medium)
          .fontColor(this.flashColor()).backgroundColor(COLOR_OVERLAY).borderRadius(20)
          .enabled(this.ready && this.flashModes.length > 1).onClick((): void => { this.cycleFlash(); })
        Blank()
        Button(this.zoomLabel()).width(58).height(40).fontSize(13).fontWeight(FontWeight.Bold)
          .fontColor(COLOR_ON_DARK).backgroundColor(COLOR_OVERLAY).borderRadius(20)
          .enabled(this.ready && this.maxZoom > this.minZoom + 0.05)
          .opacity(this.maxZoom > this.minZoom + 0.05 ? 1 : 0.45)
          .onClick((): void => { this.cycleZoom(); })
      }.width('100%')
    }.width('100%').padding({ left: 16, right: 16, top: 30, bottom: 8 })
  }

  @Builder
  private shutterButton(): void {
    Stack({ alignContent: Alignment.Center }) {
      Circle().width(82).height(82).fill(Color.Transparent).stroke(COLOR_ON_DARK).strokeWidth(3)
      Circle().width(68).height(68).fill(this.ready && this.captures.length < 50 ? COLOR_ON_DARK : '#88FFFFFF')
      Circle().width(52).height(52).fill(this.ready && this.captures.length < 50 ? '#F3FFF9' : '#66FFFFFF')
    }.width(88).height(88).enabled(this.ready && this.captures.length < 50)
      .onClick((): void => { this.takePhoto(); })
  }

  @Builder
  private cameraBottomBar(): void {
    Column({ space: 12 }) {
      this.captureStrip()
      Text('轻触对焦 · 双指缩放').fontSize(11).fontColor(COLOR_MUTED_ON_DARK)
      Row() {
        Column({ space: 1 }) {
          Text(`${this.captures.length}`).fontSize(20).fontWeight(FontWeight.Bold).fontColor(COLOR_ON_DARK)
          Text('/ 50 张').fontSize(10).fontColor(COLOR_MUTED_ON_DARK)
        }.width(72).alignItems(HorizontalAlign.Start)
        Blank()
        this.shutterButton()
        Blank()
        Button('完成').width(72).height(44).fontSize(14).fontWeight(FontWeight.Bold)
          .fontColor(COLOR_MEDIA_CANVAS).backgroundColor(COLOR_PRIMARY_BRIGHT).borderRadius(22)
          .enabled(this.captures.length > 0).opacity(this.captures.length > 0 ? 1 : 0.4)
          .onClick((): void => { this.finish(); })
      }.width('100%').alignItems(VerticalAlign.Center)
    }.width('100%').padding({ left: 18, right: 18, top: 14, bottom: 26 })
      .backgroundColor('#D90A1210').borderRadius({ topLeft: 28, topRight: 28 })
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      XComponent({ id: 'palmkeep-private-camera', type: XComponentType.SURFACE, controller: this.controller })
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
        if (this.ready) { this.cameraGuides() }
        Column() {
          this.cameraTopBar()
          Blank()
          this.cameraBottomBar()
        }.width('100%').height('100%').hitTestBehavior(HitTestMode.Transparent)
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
