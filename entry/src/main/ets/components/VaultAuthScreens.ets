import { GestureGrid } from './GestureGrid';
import {
  COLOR_BG,
  COLOR_BORDER,
  COLOR_DANGER,
  COLOR_MUTED,
  COLOR_PRIMARY,
  COLOR_SURFACE,
  COLOR_SURFACE_2,
  COLOR_TEXT
} from './VaultTheme';

@Builder
function brandMark(size: number): void {
  Image($r('app.media.launcher_icon'))
    .width(size).height(size).objectFit(ImageFit.Cover).borderRadius(size * 0.24)
}

@Component
export struct VaultLoadingScreen {
  build() {
    Column({ space: 18 }) {
      brandMark(66)
      Text('正在开启掌心密匣')
        .fontSize(20).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT)
      LoadingProgress().width(30).height(30).color(COLOR_PRIMARY)
    }
    .width('100%').height('100%').justifyContent(FlexAlign.Center).backgroundColor(COLOR_BG)
  }
}

@Component
export struct VaultSetupScreen {
  @Link masterPassword: string;
  @Link confirmPassword: string;
  @Prop busy: boolean = false;
  @Prop errorMessage: string = '';
  onCreateVault: () => void = (): void => {};

  build() {
    Scroll() {
      Column({ space: 22 }) {
        Row() { brandMark(58) }.width('100%').justifyContent(FlexAlign.Center)
        Column({ space: 7 }) {
          Text('创建你的本地保险库')
            .fontSize(28).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT)
          Text('密码不会离开这台设备，也无法由我们找回。')
            .fontSize(14).fontColor(COLOR_MUTED).textAlign(TextAlign.Center)
        }
        Column({ space: 14 }) {
          TextInput({ placeholder: '至少 8 个字符', text: this.masterPassword })
            .type(InputType.Password).height(52).fontColor(COLOR_TEXT).placeholderColor('#607B72')
            .backgroundColor(COLOR_SURFACE_2).borderRadius(14)
            .onChange((value: string): void => { this.masterPassword = value; })
          TextInput({ placeholder: '再次输入密码', text: this.confirmPassword })
            .type(InputType.Password).height(52).fontColor(COLOR_TEXT).placeholderColor('#607B72')
            .backgroundColor(COLOR_SURFACE_2).borderRadius(14)
            .onChange((value: string): void => { this.confirmPassword = value; })
          if (this.errorMessage.length > 0) {
            Text(this.errorMessage).fontSize(13).fontColor(COLOR_DANGER).width('100%')
          }
          Button(this.busy ? '正在创建…' : '创建本地保险库')
            .width('100%').height(52).fontSize(16).fontWeight(FontWeight.Bold)
            .fontColor(COLOR_BG).backgroundColor(COLOR_PRIMARY).borderRadius(14)
            .enabled(!this.busy).onClick((): void => { this.onCreateVault(); })
        }
        .padding(20).width('100%').backgroundColor(COLOR_SURFACE).borderRadius(22)
        .border({ width: 1, color: COLOR_BORDER })
      }
      .width('100%').padding({ left: 24, right: 24, top: 70, bottom: 40 })
    }
    .width('100%').height('100%').backgroundColor(COLOR_BG)
  }
}

@Component
export struct VaultLockedScreen {
  @Link masterPassword: string;
  @Prop unlockMode: string = 'password';
  @Prop busy: boolean = false;
  @Prop errorMessage: string = '';
  @Prop faceEnabled: boolean = false;
  @Prop fingerprintEnabled: boolean = false;
  @Prop gestureEnabled: boolean = false;
  onSelectMode: (mode: string) => void = (_: string): void => {};
  onUnlockPassword: () => void = (): void => {};
  onUnlockFingerprint: () => void = (): void => {};
  onUnlockFace: () => void = (): void => {};
  onUnlockGesture: (pattern: number[]) => void = (_: number[]): void => {};
  onOpenRecovery: () => void = (): void => {};

  @Builder
  private modeButton(mode: string, label: string): void {
    Button(label)
      .layoutWeight(1).height(40).fontSize(13)
      .fontWeight(this.unlockMode === mode ? FontWeight.Bold : FontWeight.Regular)
      .fontColor(this.unlockMode === mode ? COLOR_BG : COLOR_MUTED)
      .backgroundColor(this.unlockMode === mode ? COLOR_PRIMARY : Color.Transparent)
      .borderRadius(12).enabled(!this.busy)
      .onClick((): void => { this.onSelectMode(mode); })
  }

  build() {
    Scroll() {
      Column({ space: 18 }) {
        brandMark(66)
        Column({ space: 7 }) {
          Text('掌心密匣已锁定').fontSize(28).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT)
          Text(this.unlockMode === 'gesture' ? '绘制手势解锁本地保险库' :
            (this.unlockMode === 'fingerprint' ? '使用指纹验证身份' :
              (this.unlockMode === 'face' ? '使用人脸验证身份' : '输入密码解锁本地保险库')))
            .fontSize(14).fontColor(COLOR_MUTED)
        }
        Column({ space: 12 }) {
          if (this.fingerprintEnabled || this.faceEnabled || this.gestureEnabled) {
            Row({ space: 4 }) {
              if (this.faceEnabled) { this.modeButton('face', '人脸') }
              if (this.fingerprintEnabled) { this.modeButton('fingerprint', '指纹') }
              if (this.gestureEnabled) { this.modeButton('gesture', '手势') }
              this.modeButton('password', '密码')
            }
            .width('100%').padding(4).backgroundColor(COLOR_SURFACE_2).borderRadius(14)
          }
          if (this.unlockMode === 'gesture' && this.gestureEnabled) {
            GestureGrid({
              hint: this.busy ? '正在验证…' : '从任意点开始滑动', disabled: this.busy,
              onComplete: (pattern: number[]): void => { this.onUnlockGesture(pattern); }
            })
          } else if (this.unlockMode === 'fingerprint' && this.fingerprintEnabled) {
            Column({ space: 14 }) {
              Text('◎').fontSize(58).fontColor(COLOR_PRIMARY)
              Button(this.busy ? '正在验证…' : '验证指纹')
                .width('100%').height(52).fontWeight(FontWeight.Bold).fontColor(COLOR_BG)
                .backgroundColor(COLOR_PRIMARY).borderRadius(14).enabled(!this.busy)
                .onClick((): void => { this.onUnlockFingerprint(); })
            }.width('100%').padding({ top: 18, bottom: 8 })
          } else if (this.unlockMode === 'face' && this.faceEnabled) {
            Column({ space: 14 }) {
              Stack() { Text('◉').fontSize(50).fontColor(COLOR_PRIMARY) }.width(66).height(66)
              Button(this.busy ? '正在验证…' : '验证人脸')
                .width('100%').height(52).fontWeight(FontWeight.Bold).fontColor(COLOR_BG)
                .backgroundColor(COLOR_PRIMARY).borderRadius(14).enabled(!this.busy)
                .onClick((): void => { this.onUnlockFace(); })
            }.width('100%').padding({ top: 18, bottom: 8 })
          } else {
            TextInput({ placeholder: '密码', text: this.masterPassword })
              .type(InputType.Password).height(52).fontColor(COLOR_TEXT).placeholderColor('#607B72')
              .backgroundColor(COLOR_SURFACE_2).borderRadius(14)
              .onChange((value: string): void => { this.masterPassword = value; })
              .onSubmit((): void => { this.onUnlockPassword(); })
            Button(this.busy ? '正在验证…' : '使用密码解锁')
              .width('100%').height(52).fontWeight(FontWeight.Bold).fontColor(COLOR_BG)
              .backgroundColor(COLOR_PRIMARY).borderRadius(14).enabled(!this.busy)
              .onClick((): void => { this.onUnlockPassword(); })
          }
          if (this.errorMessage.length > 0) {
            Text(this.errorMessage).fontSize(13).fontColor(COLOR_DANGER).width('100%')
          }
        }.width('100%').padding(16)
        Button('无法解锁？').fontSize(12).fontColor(COLOR_MUTED).backgroundColor(Color.Transparent)
          .enabled(!this.busy).onClick((): void => { this.onOpenRecovery(); })
      }
      .width('100%').padding({ left: 24, right: 24, top: 48, bottom: 36 })
      .justifyContent(FlexAlign.Center)
    }
    .width('100%').height('100%').backgroundColor(COLOR_BG)
  }
}
