import {
  COLOR_MUTED, COLOR_PRIMARY, COLOR_PRIMARY_TINT, COLOR_SURFACE_2, COLOR_TEXT, COLOR_WARNING
} from './VaultTheme';
import { VaultScreenshotProtectionHint } from './VaultCommonComponents';

@Component
export struct VaultLoginFieldsEditor {
  @Link username: string;
  @Link password: string;
  @Link revealPassword: boolean;
  allowUtilities: boolean = false;
  onCopy: (value: string, label: string) => void = (): void => {};
  onPasswordVisibilityChange: (visible: boolean) => void = (): void => {};

  private passwordStrength(): string {
    if (this.password.length === 0) { return ''; }
    let score = this.password.length >= 12 ? 1 : 0;
    if (this.password.length >= 16) { score += 1; }
    if (/[a-z]/.test(this.password) && /[A-Z]/.test(this.password)) { score += 1; }
    if (/[0-9]/.test(this.password)) { score += 1; }
    if (/[^A-Za-z0-9]/.test(this.password)) { score += 1; }
    if (score >= 4) { return '强密码'; }
    if (score >= 2) { return '密码强度一般'; }
    return '密码较弱';
  }

  @Builder
  private utilityButton(label: string, enabled: boolean, action: () => void): void {
    Button(label).height(42).fontSize(11).fontColor(enabled ? COLOR_PRIMARY : COLOR_MUTED)
      .backgroundColor(COLOR_PRIMARY_TINT).borderRadius(11).enabled(enabled)
      .onClick(action)
  }

  build() {
    Column({ space: 8 }) {
      Row({ space: 7 }) {
        TextInput({ placeholder: '账号', text: this.username })
          .layoutWeight(1).fontColor(COLOR_TEXT).backgroundColor(COLOR_SURFACE_2)
          .height(44).borderRadius(11)
          .onChange((value: string): void => { this.username = value; })
        if (this.allowUtilities) {
          this.utilityButton('复制', this.username.length > 0,
            (): void => { this.onCopy(this.username, '账号'); })
        }
      }.width('100%')
      Row({ space: 7 }) {
        TextInput({ placeholder: '密码', text: this.password })
          .type(InputType.Password).showPassword(this.revealPassword)
          .layoutWeight(1).fontColor(COLOR_TEXT).backgroundColor(COLOR_SURFACE_2)
          .height(44).borderRadius(11)
          .onChange((value: string): void => { this.password = value; })
          .onSecurityStateChange((visible: boolean): void => {
            this.revealPassword = visible;
            this.onPasswordVisibilityChange(visible);
          })
      }.width('100%')
      if (this.revealPassword) {
        VaultScreenshotProtectionHint()
      }
      if (this.password.length > 0) {
        Text(this.passwordStrength()).fontSize(10).width('100%')
          .fontColor(this.passwordStrength() === '强密码' ? COLOR_PRIMARY : COLOR_WARNING)
      }
    }.width('100%')
  }
}
