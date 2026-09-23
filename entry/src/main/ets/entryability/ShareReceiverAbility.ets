import ShareExtensionAbility from '@ohos.app.ability.ShareExtensionAbility';
import UIExtensionContentSession from '@ohos.app.ability.UIExtensionContentSession';
import Want from '@ohos.app.ability.Want';
import { systemShare } from '@kit.ShareKit';
import { BUNDLE_NAME } from 'BuildProfile';
import { logRecoverableError, normalizeError } from '../services/ErrorUtils';
import { shareImportService } from '../services/ShareImportService';

export default class ShareReceiverAbility extends ShareExtensionAbility {
  onSessionCreate(want: Want, session: UIExtensionContentSession): void {
    AppStorage.setOrCreate<string>('vaultShareReceiveError', '');
    try { session.loadContent('pages/ShareReceiver'); }
    catch (error) {
      logRecoverableError('share-content-load', error as Object);
      session.terminateSelf().catch((terminateError: Error): void => {
        logRecoverableError('share-session-close', terminateError);
      });
      return;
    }
    session.setWindowPrivacyMode(true).catch((error: Error): void => {
      logRecoverableError('share-window-privacy', error);
    });
    this.receive(want, session);
  }

  private async receive(want: Want, session: UIExtensionContentSession): Promise<void> {
    let stagedRequestId = '';
    try {
      const data = await systemShare.getSharedData(want);
      const request = await shareImportService.stage(this.context, data);
      stagedRequestId = request.id;
      await this.context.startAbility({
        bundleName: BUNDLE_NAME,
        moduleName: 'entry',
        abilityName: 'EntryAbility',
        parameters: { pvShareRequestId: request.id }
      });
      await session.terminateSelf();
    } catch (error) {
      if (stagedRequestId.length > 0) {
        shareImportService.discardRequest(this.context, stagedRequestId);
      }
      const message = normalizeError(error).message;
      logRecoverableError('share-receive', error as Object);
      AppStorage.setOrCreate<string>('vaultShareReceiveError', message);
    }
  }
}
