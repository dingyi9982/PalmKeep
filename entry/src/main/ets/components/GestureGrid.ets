const GESTURE_PRIMARY: string = '#67E8C5';
const GESTURE_MUTED: string = '#527068';
const GESTURE_SURFACE: string = '#142621';

@Component
export struct GestureGrid {
  @Prop hint: string = '请绘制解锁手势';
  @Prop disabled: boolean = false;
  @State private active: number[] = [];
  onComplete: (pattern: number[]) => void = (_: number[]): void => {};

  private contains(point: number): boolean {
    return this.active.indexOf(point) >= 0;
  }

  private appendPoint(x: number, y: number): void {
    if (x < 0 || y < 0 || x >= 252 || y >= 252) {
      return;
    }
    const column = Math.floor(x / 84);
    const row = Math.floor(y / 84);
    const centerX = column * 84 + 42;
    const centerY = row * 84 + 42;
    const deltaX = x - centerX;
    const deltaY = y - centerY;
    if (deltaX * deltaX + deltaY * deltaY > 34 * 34) {
      return;
    }
    const point = row * 3 + column;
    if (!this.contains(point)) {
      this.active = this.active.concat([point]);
    }
  }

  private handleTouch(event: TouchEvent): void {
    if (this.disabled || event.touches.length === 0) {
      return;
    }
    const touch = event.touches[0];
    if (event.type === TouchType.Down) {
      this.active = [];
      this.appendPoint(touch.x, touch.y);
    } else if (event.type === TouchType.Move) {
      this.appendPoint(touch.x, touch.y);
    } else if (event.type === TouchType.Up) {
      this.appendPoint(touch.x, touch.y);
      const result = this.active.slice();
      if (result.length > 0) {
        this.onComplete(result);
      }
    }
  }

  build() {
    Column({ space: 12 }) {
      Text(this.hint)
        .fontSize(13)
        .fontColor(GESTURE_MUTED)
      Grid() {
        ForEach([0, 1, 2, 3, 4, 5, 6, 7, 8], (point: number): void => {
          GridItem() {
            Stack() {
              Circle()
                .width(this.contains(point) ? 42 : 34)
                .height(this.contains(point) ? 42 : 34)
                .fill(this.contains(point) ? '#286F5C' : GESTURE_SURFACE)
                .stroke(this.contains(point) ? GESTURE_PRIMARY : GESTURE_MUTED)
                .strokeWidth(this.contains(point) ? 3 : 2)
              if (this.contains(point)) {
                Text(`${this.active.indexOf(point) + 1}`)
                  .fontSize(12)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(GESTURE_PRIMARY)
              }
            }
            .width('100%')
            .height('100%')
          }
        }, (point: number): string => `${point}`)
      }
      .columnsTemplate('1fr 1fr 1fr')
      .rowsTemplate('1fr 1fr 1fr')
      .width(252)
      .height(252)
      .onTouch((event: TouchEvent): void => { this.handleTouch(event); })
      Text(this.active.length === 0 ? '连接至少 4 个点' : `已连接 ${this.active.length} 个点`)
        .fontSize(12)
        .fontColor(this.active.length >= 4 ? GESTURE_PRIMARY : GESTURE_MUTED)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }
}
