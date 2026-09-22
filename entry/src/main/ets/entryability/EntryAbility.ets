import AbilityConstant from '@ohos.app.ability.AbilityConstant';
import UIAbility from '@ohos.app.ability.UIAbility';
import Want from '@ohos.app.ability.Want';
import window from '@ohos.window';
import { AbilityContextHolder } from '../services/AbilityContextHolder';
import { vaultRepository } from '../services/VaultRepository';

export default class EntryAbility extends UIAbility {
  private backgroundAt: number = 0;

  onCreate(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    AbilityContextHolder.setContext(this.context);
    AppStorage.setOrCreate<number>('vaultAutoLockMinutes', 10);
    AppStorage.setOrCreate<boolean>('vaultLifecycleSuppressed', false);
    AppStorage.setOrCreate<boolean>('vaultAppForeground', true);
    AppStorage.setOrCreate<string>('vaultShareRequestId', '');
    this.publishShareRequest(want);
  }

  onNewWant(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    this.publishShareRequest(want);
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
    AppStorage.setOrCreate<boolean>('vaultAppForeground', false);
    if (AppStorage.get<boolean>('vaultLifecycleSuppressed') ?? false) {
      this.backgroundAt = 0;
      return;
    }
    const autoLockMinutes = AppStorage.get<number>('vaultAutoLockMinutes') ?? 10;
    if (autoLockMinutes === 0) {
      this.lockForLifecycle();
      this.backgroundAt = 0;
      return;
    }
    this.backgroundAt = Date.now();
  }

  onForeground(): void {
    AppStorage.setOrCreate<boolean>('vaultAppForeground', true);
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

  private publishShareRequest(want: Want): void {
    const value = want.parameters ? want.parameters['pvShareRequestId'] : undefined;
    if (typeof value === 'string' && value.length > 0) {
      AppStorage.setOrCreate<string>('vaultShareRequestId', value);
    }
  }
}
