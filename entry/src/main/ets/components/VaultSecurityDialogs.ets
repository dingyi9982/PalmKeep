import { GestureGrid } from './GestureGrid';
import {
  COLOR_BG, COLOR_BORDER, COLOR_DANGER, COLOR_MUTED, COLOR_PRIMARY,
  COLOR_SURFACE, COLOR_SURFACE_2, COLOR_TEXT
} from './VaultTheme';

@Builder
function dialogHeader(title: string, closeAction: () => void): void {
  Row() {
    Text(title).fontSize(19).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT)
    Blank()
    Stack() { Text('×').fontSize(22).lineHeight(24).fontColor(COLOR_MUTED) }
      .width(38).height(38).backgroundColor(COLOR_SURFACE_2).borderRadius(11).onClick(closeAction)
  }.width('100%')
}

@Component
export struct ChangePasswordDialog {
  @Link currentPassword: string;
  @Link newPassword: string;
  @Link confirmPassword: string;
  @Prop busy: boolean = false;
  onClose: () => void = (): void => {};
  onConfirm: () => void = (): void => {};

  build() {
    Column() {
      Column({ space: 10 }) {
        dialogHeader('修改密码', this.onClose)
        TextInput({ placeholder: '当前密码', text: this.currentPassword })
          .type(InputType.Password).height(48).backgroundColor(COLOR_SURFACE_2).borderRadius(12)
          .onChange((value: string): void => { this.currentPassword = value; })
        TextInput({ placeholder: '新密码（至少 8 个字符）', text: this.newPassword })
          .type(InputType.Password).height(48).backgroundColor(COLOR_SURFACE_2).borderRadius(12)
          .onChange((value: string): void => { this.newPassword = value; })
        TextInput({ placeholder: '再次输入新密码', text: this.confirmPassword })
          .type(InputType.Password).height(48).backgroundColor(COLOR_SURFACE_2).borderRadius(12)
          .onChange((value: string): void => { this.confirmPassword = value; })
        Button(this.busy ? '正在修改…' : '确认修改')
          .width('100%').height(48).fontWeight(FontWeight.Bold).fontColor(COLOR_BG)
          .backgroundColor(COLOR_PRIMARY).borderRadius(12).enabled(!this.busy)
          .onClick((): void => { this.onConfirm(); })
      }.width('88%').padding(18).backgroundColor(COLOR_SURFACE).borderRadius(22)
    }
    .width('100%').height('100%').justifyContent(FlexAlign.Center).backgroundColor('#99000000')
  }
}

@Component
export struct RecoveryCenterDialog {
  @Link newPassword: string;
  @Link confirmPassword: string;
  @Prop faceEnabled: boolean = false;
  @Prop fingerprintEnabled: boolean = false;
  @Prop authenticated: boolean = false;
  @Prop authLabel: string = '';
  @Prop busy: boolean = false;
  onClose: () => void = (): void => {};
  onAuthenticateFace: () => void = (): void => {};
  onAuthenticateFingerprint: () => void = (): void => {};
  onResetPassword: () => void = (): void => {};
  onClearVault: () => void = (): void => {};

  build() {
    Column() {
      Scroll() {
        Column({ space: 10 }) {
          dialogHeader('恢复访问', this.onClose)
          if (!this.authenticated) {
            Text('使用已启用的本机生物认证验证身份，然后重设密码。')
              .fontSize(13).fontColor(COLOR_MUTED).lineHeight(20).width('100%')
            if (this.faceEnabled) {
              Button(this.busy ? '正在验证…' : '使用人脸验证')
                .width('100%').height(48).fontWeight(FontWeight.Bold).fontColor(COLOR_BG)
                .backgroundColor(COLOR_PRIMARY).borderRadius(12).enabled(!this.busy)
                .onClick((): void => { this.onAuthenticateFace(); })
            }
            if (this.fingerprintEnabled) {
              Button(this.busy ? '正在验证…' : '使用指纹验证')
                .width('100%').height(48).fontWeight(FontWeight.Bold).fontColor(COLOR_BG)
                .backgroundColor(COLOR_PRIMARY).borderRadius(12).enabled(!this.busy)
                .onClick((): void => { this.onAuthenticateFingerprint(); })
            }
            if (!this.faceEnabled && !this.fingerprintEnabled) {
              Text('没有已启用的生物认证，当前无法无损重设密码。')
                .fontSize(13).fontColor(COLOR_MUTED).lineHeight(20).width('100%')
                .padding(12).backgroundColor(COLOR_SURFACE_2).borderRadius(12)
            }
          } else {
            Text(`已通过${this.authLabel}验证`).fontSize(13).fontColor(COLOR_PRIMARY).width('100%')
            TextInput({ placeholder: '新密码（至少 8 个字符）', text: this.newPassword })
              .type(InputType.Password).height(48).backgroundColor(COLOR_SURFACE_2).borderRadius(12)
              .onChange((value: string): void => { this.newPassword = value; })
            TextInput({ placeholder: '再次输入新密码', text: this.confirmPassword })
              .type(InputType.Password).height(48).backgroundColor(COLOR_SURFACE_2).borderRadius(12)
              .onChange((value: string): void => { this.confirmPassword = value; })
            Button(this.busy ? '正在重设…' : '重设密码并进入保险库')
              .width('100%').height(48).fontWeight(FontWeight.Bold).fontColor(COLOR_BG)
              .backgroundColor(COLOR_PRIMARY).borderRadius(12).enabled(!this.busy)
              .onClick((): void => { this.onResetPassword(); })
          }
          Divider().color(COLOR_BORDER).margin({ top: 4, bottom: 2 })
          Text('无法通过上述方式恢复？').fontSize(12).fontColor(COLOR_MUTED).width('100%')
          Button('永久清除本地保险库').width('100%').height(44).fontSize(13).fontColor(COLOR_DANGER)
            .backgroundColor('#FDEDEF').borderRadius(12).enabled(!this.busy)
            .onClick((): void => { this.onClearVault(); })
        }.width('100%').padding(18)
      }
      .width('88%').constraintSize({ maxHeight: '88%' }).scrollBar(BarState.Off)
      .backgroundColor(COLOR_SURFACE).borderRadius(22)
    }
    .width('100%').height('100%').justifyContent(FlexAlign.Center).backgroundColor('#99000000')
  }
}

@Component
export struct ResetVaultDialog {
  @Link confirmation: string;
  @Prop busy: boolean = false;
  onClose: () => void = (): void => {};
  onConfirm: () => void = (): void => {};

  build() {
    Column() {
      Column({ space: 10 }) {
        dialogHeader('清除本地保险库', this.onClose)
        Text('此操作会永久删除全部资料、附件、分组和登录设置，且无法恢复。')
          .fontSize(13).fontColor(COLOR_DANGER).lineHeight(20).width('100%')
        Text('请输入“清除全部数据”以确认').fontSize(12).fontColor(COLOR_MUTED).width('100%')
        TextInput({ placeholder: '清除全部数据', text: this.confirmation })
          .height(48).backgroundColor(COLOR_SURFACE_2).borderRadius(12)
          .onChange((value: string): void => { this.confirmation = value; })
        Button(this.busy ? '正在清除…' : '永久清除全部数据')
          .width('100%').height(48).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
          .backgroundColor(COLOR_DANGER).borderRadius(12)
          .enabled(!this.busy && this.confirmation === '清除全部数据')
          .onClick((): void => { this.onConfirm(); })
      }.width('88%').padding(18).backgroundColor(COLOR_SURFACE).borderRadius(22)
    }
    .width('100%').height('100%').justifyContent(FlexAlign.Center).backgroundColor('#99000000')
  }
}

@Component
export struct GestureSetupDialog {
  @Prop step: number = 1;
  @Prop hint: string = '';
  onClose: () => void = (): void => {};
  onComplete: (pattern: number[]) => void = (_: number[]): void => {};

  build() {
    Column() {
      Blank().onClick((): void => { this.onClose(); })
      Column({ space: 10 }) {
        dialogHeader('设置手势登录', this.onClose)
        Text(this.step === 1 ? '第一步，共两步' : '第二步，共两步')
          .fontSize(12).fontColor(COLOR_PRIMARY).width('100%')
        GestureGrid({ hint: this.hint, onComplete: this.onComplete })
        Text('手势只用于快捷登录，密码仍可随时解锁。')
          .fontSize(12).fontColor(COLOR_MUTED).textAlign(TextAlign.Center).width('100%')
      }
      .padding(20).width('100%').backgroundColor(COLOR_SURFACE)
      .borderRadius({ topLeft: 24, topRight: 24 })
    }.width('100%').height('100%').backgroundColor('#99000000')
  }
}
