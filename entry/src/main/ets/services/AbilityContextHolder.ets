import common from '@ohos.app.ability.common';

export class AbilityContextHolder {
  private static abilityContext?: common.UIAbilityContext;

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
}
