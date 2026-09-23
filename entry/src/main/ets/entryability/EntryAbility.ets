import AbilityConstant from '@ohos.app.ability.AbilityConstant';
import UIAbility from '@ohos.app.ability.UIAbility';
import Want from '@ohos.app.ability.Want';
import window from '@ohos.window';
import { AbilityContextHolder } from '../services/AbilityContextHolder';
import { logRecoverableError } from '../services/ErrorUtils';
import { vaultRepository } from '../services/VaultRepository';
import { audioRecordingService } from '../services/AudioRecordingService';

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

  onDestroy(): void {
    if (audioRecordingService.isActive()) {
      audioRecordingService.finish().catch((error: Error): void => {
        logRecoverableError('recording-finalize', error);
      });
    }
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
        logRecoverableError('window-obtain', error);
      });
    } catch (error) {
      logRecoverableError('window-request', error as Object);
    }
    windowStage.loadContent('pages/Index').catch((error: Error): void => {
      logRecoverableError('content-load', error);
    });
  }

  onBackground(): void {
    AbilityContextHolder.setBackgroundPrivacyMode(true);
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
      AbilityContextHolder.setBackgroundPrivacyMode(false);
      return;
    }
    const backgroundDuration = Date.now() - this.backgroundAt;
    this.backgroundAt = 0;
    const autoLockMinutes = AppStorage.get<number>('vaultAutoLockMinutes') ?? 10;
    if (autoLockMinutes < 0 || backgroundDuration < autoLockMinutes * 60 * 1000) {
      AbilityContextHolder.setBackgroundPrivacyMode(false);
      return;
    }
    this.lockForLifecycle();
  }

  private lockForLifecycle(): void {
    AppStorage.setOrCreate<boolean>('vaultLockedByLifecycle', true);
    vaultRepository.close().catch((error: Error): void => {
      logRecoverableError('vault-close', error);
    });
  }

  private publishShareRequest(want: Want): void {
    const value = want.parameters ? want.parameters['pvShareRequestId'] : undefined;
    if (typeof value === 'string' && value.length > 0) {
      AppStorage.setOrCreate<string>('vaultShareRequestId', value);
    }
  }
}
