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
    AppStorage.setOrCreate<number>('vaultAutoLockMinutes', 10);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    AbilityContextHolder.setContext(this.context);
    try {
      windowStage.getMainWindow().then((mainWindow: window.Window): void => {
        AbilityContextHolder.setMainWindow(mainWindow);
        AbilityContextHolder.setPrivacyMode(false);
      }).catch((error: Error): void => {
        console.error(`Failed to obtain PalmVault window: ${error.message}`);
      });
    } catch (error) {
      console.error(`Failed to request PalmVault window: ${error}`);
    }
    windowStage.loadContent('pages/Index').catch((error: Error): void => {
      console.error(`Failed to load PalmVault: ${error.message}`);
    });
  }

  onBackground(): void {
    const autoLockMinutes = AppStorage.get<number>('vaultAutoLockMinutes') ?? 10;
    if (autoLockMinutes === 0) {
      this.lockForLifecycle();
      this.backgroundAt = 0;
      return;
    }
    this.backgroundAt = Date.now();
  }

  onForeground(): void {
    if (this.backgroundAt === 0) {
      return;
    }
    const backgroundDuration = Date.now() - this.backgroundAt;
    this.backgroundAt = 0;
    const autoLockMinutes = AppStorage.get<number>('vaultAutoLockMinutes') ?? 10;
    if (autoLockMinutes < 0 || backgroundDuration < autoLockMinutes * 60 * 1000) {
      return;
    }
    this.lockForLifecycle();
  }

  private lockForLifecycle(): void {
    AppStorage.setOrCreate<boolean>('vaultLockedByLifecycle', true);
    vaultRepository.close().catch((error: Error): void => {
      console.warn(`PalmVault close warning: ${error.message}`);
    });
  }
}
