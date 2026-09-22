import ShareExtensionAbility from '@ohos.app.ability.ShareExtensionAbility';
import UIExtensionContentSession from '@ohos.app.ability.UIExtensionContentSession';
import Want from '@ohos.app.ability.Want';
import { systemShare } from '@kit.ShareKit';
import { normalizeError } from '../services/ErrorUtils';
import { shareImportService } from '../services/ShareImportService';

export default class ShareReceiverAbility extends ShareExtensionAbility {
  onSessionCreate(want: Want, session: UIExtensionContentSession): void {
    AppStorage.setOrCreate<string>('vaultShareReceiveError', '');
    try { session.loadContent('pages/ShareReceiver'); }
    catch (error) {
      console.error(`Failed to load share receiver: ${normalizeError(error).message}`);
      session.terminateSelf().catch((terminateError: Error): void => {
        console.warn(`Failed to close share receiver: ${terminateError.message}`);
      });
      return;
    }
    session.setWindowPrivacyMode(true).catch((error: Error): void => {
      console.warn(`Share receiver privacy warning: ${error.message}`);
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
        bundleName: 'com.palmvault.app',
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
      console.error(`Failed to receive shared content: ${message}`);
      AppStorage.setOrCreate<string>('vaultShareReceiveError', message);
    }
  }
}
