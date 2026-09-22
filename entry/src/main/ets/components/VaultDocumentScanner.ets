import {
  DocType, DocumentScanner, DocumentScannerConfig, EditTab, FilterId, SaveOption, ShootingMode
} from '@kit.VisionKit';
import { PickedMedia } from '../services/MediaPickerService';
import { privateCaptureService } from '../services/PrivateCaptureService';
import { AbilityContextHolder } from '../services/AbilityContextHolder';
import { COLOR_MEDIA_CANVAS, COLOR_ON_DARK, COLOR_OVERLAY } from './VaultTheme';

@Component
export struct VaultDocumentScanner {
  onComplete: (media: PickedMedia[]) => void = (_media: PickedMedia[]): void => {};
  onCancel: () => void = (): void => {};
  onUnavailable: () => void = (): void => {};
  @State private busy: boolean = false;
  @State private statusText: string = '';
  private resolved: boolean = false;
  private config: DocumentScannerConfig = {
    maxShotCount: 20,
    supportType: [DocType.DOC],
    isGallerySupported: false,
    defaultFilterId: FilterId.STRENGTHEN,
    editTabs: [EditTab.ROTATE_TAB, EditTab.DELETE_TAB, EditTab.RESHOOT_TAB],
    defaultShootingMode: ShootingMode.MANUAL,
    isShareable: false,
    saveOptions: [SaveOption.JPG]
  };

  aboutToAppear(): void { AbilityContextHolder.setPrivacyMode(true); }

  aboutToDisappear(): void { AbilityContextHolder.setPrivacyMode(false); }

  private async handleResult(code: number, saveType: SaveOption, uris: string[]): Promise<void> {
    if (this.resolved) { return; }
    if (code === -1) {
      this.resolved = true;
      this.onCancel();
      return;
    }
    if (code !== 200 || saveType !== SaveOption.JPG || uris.length === 0) {
      this.resolved = true;
      this.onUnavailable();
      return;
    }
    this.busy = true;
    this.statusText = `正在整理扫描页 0/${uris.length}`;
    try {
      const media = await privateCaptureService.copyScannedPages(uris);
      this.statusText = `已整理 ${media.length}/${media.length}`;
      this.resolved = true;
      this.onComplete(media);
    } catch (error) {
      this.resolved = true;
      this.onUnavailable();
    } finally {
      this.busy = false;
    }
  }

  build() {
    Stack() {
      DocumentScanner({
        scannerConfig: this.config,
        onResult: (code: number, saveType: SaveOption, uris: string[]): void => {
          this.handleResult(code, saveType, uris);
        }
      }).width('100%').height('100%')
      if (this.busy) {
        Column({ space: 12 }) {
          LoadingProgress().width(42).height(42).color('#2DD6A6')
          Text(this.statusText).fontSize(14).fontColor(COLOR_ON_DARK)
        }.width('100%').height('100%').justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
          .backgroundColor(COLOR_OVERLAY)
      }
    }.width('100%').height('100%').backgroundColor(COLOR_MEDIA_CANVAS)
  }
}
