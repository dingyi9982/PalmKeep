import { COLOR_BORDER, COLOR_MUTED, COLOR_PRIMARY } from './VaultTheme';

@Component
export struct VaultBottomNavigation {
  @Prop activeTab: number = 0;
  onSelectTab: (index: number) => void = (_: number): void => {};
  onNewItem: () => void = (): void => {};

  @Builder
  private navItem(index: number, icon: Resource, label: string): void {
    Column({ space: 5 }) {
      Image(icon).width(24).height(24)
        .fillColor(this.activeTab === index ? COLOR_PRIMARY : COLOR_MUTED)
      Text(label).width('100%').height(18).lineHeight(18).fontSize(11).textAlign(TextAlign.Center)
        .fontColor(this.activeTab === index ? COLOR_PRIMARY : COLOR_MUTED)
    }
    .layoutWeight(1).height('100%').justifyContent(FlexAlign.Center).padding({ top: 6, bottom: 4 })
    .onClick((): void => { this.onSelectTab(index); })
  }

  build() {
    Row() {
      this.navItem(0, $r('app.media.nav_home'), '首页')
      this.navItem(1, $r('app.media.nav_category'), '分类')
      Column() {
        Stack() { Text('+').fontSize(28).fontWeight(FontWeight.Medium).fontColor('#FFFFFF') }
          .width(48).height(48).borderRadius(16).backgroundColor(COLOR_PRIMARY)
      }
      .layoutWeight(1).height('100%').justifyContent(FlexAlign.Center).translate({ y: -4 })
      .onClick((): void => { this.onNewItem(); })
      this.navItem(2, $r('app.media.nav_trash'), '回收站')
      this.navItem(3, $r('app.media.nav_settings'), '设置')
    }
    .width('100%').height(76).padding({ top: 6, bottom: 2 })
    .backgroundColor('#FAFFFFFF').border({ width: { top: 1 }, color: COLOR_BORDER })
  }
}
