import common from '@ohos.app.ability.common';
import window from '@ohos.window';
import { logRecoverableError } from './ErrorUtils';

export class AbilityContextHolder {
  private static abilityContext?: common.UIAbilityContext;
  private static mainWindow?: window.Window;
  private static contentPrivacyEnabled: boolean = false;
  private static backgroundPrivacyEnabled: boolean = false;

  static setContext(context: common.UIAbilityContext): void {
    AbilityContextHolder.abilityContext = context;
  }

  static getContext(): common.UIAbilityContext {
    const context = AbilityContextHolder.abilityContext;
    if (!context) {
      throw new Error('PalmVault ability context is not ready');
    }
    return context;
  }

  static setMainWindow(mainWindow: window.Window): void {
    AbilityContextHolder.mainWindow = mainWindow;
    AbilityContextHolder.applyPrivacyMode();
  }

  static setPrivacyMode(enabled: boolean): Promise<void> {
    AbilityContextHolder.contentPrivacyEnabled = enabled;
    return AbilityContextHolder.applyPrivacyMode();
  }

  static setBackgroundPrivacyMode(enabled: boolean): Promise<void> {
    AbilityContextHolder.backgroundPrivacyEnabled = enabled;
    return AbilityContextHolder.applyPrivacyMode();
  }

  private static applyPrivacyMode(): Promise<void> {
    const mainWindow = AbilityContextHolder.mainWindow;
    if (!mainWindow) {
      return Promise.resolve();
    }
    const enabled = AbilityContextHolder.contentPrivacyEnabled || AbilityContextHolder.backgroundPrivacyEnabled;
    return mainWindow.setWindowPrivacyMode(enabled).catch((error: Error): void => {
      logRecoverableError('window-privacy', error);
    });
  }
}
