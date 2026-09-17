import common from '@ohos.app.ability.common';
import window from '@ohos.window';

export class AbilityContextHolder {
  private static abilityContext?: common.UIAbilityContext;
  private static mainWindow?: window.Window;

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
  }

  static setPrivacyMode(enabled: boolean): void {
    const mainWindow = AbilityContextHolder.mainWindow;
    if (!mainWindow) {
      return;
    }
    mainWindow.setWindowPrivacyMode(enabled).catch((error: Error): void => {
      console.warn(`PalmVault privacy mode warning: ${error.message}`);
    });
  }
}
