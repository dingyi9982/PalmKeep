import {
  COLOR_DARK_ACTION, COLOR_MUTED, COLOR_PRIMARY, COLOR_PRIMARY_TINT, COLOR_SURFACE_2, COLOR_TEXT,
  RADIUS_SM, SIZE_TOUCH_TARGET
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

@Component
export struct VaultPasswordEyeButton {
  revealed: boolean = false;
  controlHeight: number = 44;
  onToggle: () => void = (): void => {};

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Stack({ alignContent: Alignment.Center }) {
        Stack()
          .width(22).height(14)
          .border({ width: 2, color: COLOR_PRIMARY })
          .borderRadius(9)
        Circle({ width: 6, height: 6 }).fill(COLOR_PRIMARY)
      }
      if (!this.revealed) {
        Divider().width(27).strokeWidth(2).color(COLOR_PRIMARY).borderRadius(1)
          .rotate({ angle: -42 })
      }
    }
    .width(46).height(this.controlHeight)
    .backgroundColor(COLOR_PRIMARY_TINT).borderRadius(11)
    .onClick((): void => { this.onToggle(); })
  }
}

@Component
export struct VaultScreenshotProtectionHint {
  build() {
    Row({ space: 5 }) {
      Text('✓').fontSize(11).fontWeight(FontWeight.Bold).fontColor(COLOR_PRIMARY)
      Text('已禁止截屏').fontSize(11).fontColor(COLOR_PRIMARY)
    }
    .padding({ left: 10, right: 10, top: 6, bottom: 6 })
    .backgroundColor(COLOR_DARK_ACTION)
    .borderRadius(12)
    .alignSelf(ItemAlign.Start)
  }
}
