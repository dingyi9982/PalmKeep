import AbilityConstant from '@ohos.app.ability.AbilityConstant';
import UIAbility from '@ohos.app.ability.UIAbility';
import Want from '@ohos.app.ability.Want';
import window from '@ohos.window';
import { AbilityContextHolder } from '../services/AbilityContextHolder';
import { vaultRepository } from '../services/VaultRepository';

export default class EntryAbility extends UIAbility {
  private backgroundAt: number = 0;

  onCreate(_want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    AbilityContextHolder.setContext(this.context);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    AbilityContextHolder.setContext(this.context);
    windowStage.getMainWindow().then((mainWindow: window.Window): void => {
      mainWindow.setWindowPrivacyMode(true).catch((error: Error): void => {
        console.warn(`PalmVault privacy mode warning: ${error.message}`);
      });
    });
    windowStage.loadContent('pages/Index').catch((error: Error): void => {
      console.error(`Failed to load PalmVault: ${error.message}`);
    });
  }

  onBackground(): void {
    this.backgroundAt = Date.now();
  }

  onForeground(): void {
    if (this.backgroundAt === 0) {
      return;
    }
    const backgroundDuration = Date.now() - this.backgroundAt;
    this.backgroundAt = 0;
    if (backgroundDuration < 10 * 60 * 1000) {
      return;
    }
    AppStorage.setOrCreate<boolean>('vaultLockedByLifecycle', true);
    vaultRepository.close().catch((error: Error): void => {
      console.warn(`PalmVault close warning: ${error.message}`);
    });
  }
}
