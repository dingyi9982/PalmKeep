import common from '@ohos.app.ability.common';
import privacyManager from '@hms.core.appgalleryservice.privacyManager';
import { logRecoverableError } from './ErrorUtils';

class HostedPrivacyPolicyService {
  async open(context: common.UIAbilityContext): Promise<void> {
    let privacyPolicyUrl: string = '';
    try {
      const privacyInfo = privacyManager.getAppPrivacyMgmtInfo();
      for (let index = 0; index < privacyInfo.privacyInfo.length; index += 1) {
        const privacyLink = privacyInfo.privacyInfo[index];
        if (privacyLink.type === privacyManager.AppPrivacyLinkType.PRIVACY_STATEMENT_LINK) {
          privacyPolicyUrl = privacyLink.url;
          break;
        }
      }
    } catch (error) {
      logRecoverableError('could not get hosted privacy policy', error);
      throw new Error('当前安装来源未提供隐私政策页面');
    }
    if (privacyPolicyUrl.length === 0) {
      throw new Error('当前安装来源未提供隐私政策页面');
    }
    await context.openLink(privacyPolicyUrl, { appLinkingOnly: false });
  }
}

export const hostedPrivacyPolicyService = new HostedPrivacyPolicyService();
