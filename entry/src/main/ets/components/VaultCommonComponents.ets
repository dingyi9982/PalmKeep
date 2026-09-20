import {
  COLOR_MUTED, COLOR_SURFACE_2, COLOR_TEXT, RADIUS_SM, SIZE_TOUCH_TARGET
} from './VaultTheme';

@Component
export struct VaultDialogHeader {
  title: string = '';
  onClose: () => void = (): void => {};

  build() {
    Row() {
      Text(this.title).fontSize(19).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT)
      Blank()
      Stack() {
        Text('×').fontSize(22).lineHeight(24).fontColor(COLOR_MUTED)
      }
      .width(SIZE_TOUCH_TARGET - 6).height(SIZE_TOUCH_TARGET - 6)
      .backgroundColor(COLOR_SURFACE_2).borderRadius(RADIUS_SM + 1)
      .onClick((): void => { this.onClose(); })
    }
    .width('100%')
  }
}
