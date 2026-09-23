import { describe, expect, it } from '@ohos/hypium';
import { VaultItemType } from '../main/ets/models/VaultModels';
import {
  checkedTotalBytes,
  isSupportedAudioFileName,
  validateImportedAttachmentSize,
  validateStoredAttachmentSize,
  validateVaultItemFields
} from '../main/ets/services/VaultCorePolicy';
import {
  MAX_FILE_ATTACHMENT_BYTES,
  MAX_IMPORTED_AUDIO_BYTES,
  MAX_IMPORTED_IMAGE_BYTES,
  MAX_IMPORTED_VIDEO_BYTES,
  MAX_MEDIA_IMPORT_BATCH_BYTES
} from '../main/ets/services/VaultLimits';

function capturedError(action: () => void): string {
  try { action(); return ''; }
  catch (error) { return error instanceof Error ? error.message : '未知错误'; }
}

export default function vaultCorePolicyTest(): void {
  describe('VaultCorePolicy', (): void => {
    it('accepts valid note and login fields', 0, (): void => {
      expect(capturedError((): void => validateVaultItemFields(
        VaultItemType.Note, '合同', '', '', '', '装修合同内容'))).assertEqual('');
      expect(capturedError((): void => validateVaultItemFields(
        VaultItemType.Login, '', 'user', 'secret', 'https://example.com', ''))).assertEqual('');
      expect(capturedError((): void => validateVaultItemFields(
        VaultItemType.Login, '银行卡', 'user', '', '', ''))).assertEqual('');
    });

    it('rejects incomplete notes', 0, (): void => {
      expect(capturedError((): void => validateVaultItemFields(
        VaultItemType.Note, ' ', '', '', '', '内容'))).assertEqual('名称不能为空');
      expect(capturedError((): void => validateVaultItemFields(
        VaultItemType.Note, '标题', '', '', '', ' '))).assertEqual('内容不能为空');
    });

    it('rejects incomplete login records', 0, (): void => {
      expect(capturedError((): void => validateVaultItemFields(
        VaultItemType.Login, '', 'user', 'secret', '', ''))).assertEqual('名称和网址至少填写一个');
      expect(capturedError((): void => validateVaultItemFields(
        VaultItemType.Login, '银行', ' ', 'secret', '', ''))).assertEqual('账号不能为空');
    });

    it('accepts attachment sizes at exact boundaries', 0, (): void => {
      expect(capturedError((): void => validateImportedAttachmentSize(
        VaultItemType.File, MAX_FILE_ATTACHMENT_BYTES, '合同.pdf'))).assertEqual('');
      expect(capturedError((): void => validateImportedAttachmentSize(
        VaultItemType.Audio, MAX_IMPORTED_AUDIO_BYTES, '录音.m4a'))).assertEqual('');
      expect(capturedError((): void => validateImportedAttachmentSize(
        VaultItemType.Image, MAX_IMPORTED_IMAGE_BYTES, '照片.jpg'))).assertEqual('');
      expect(capturedError((): void => validateImportedAttachmentSize(
        VaultItemType.Video, MAX_IMPORTED_VIDEO_BYTES, '视频.mp4'))).assertEqual('');
    });

    it('rejects oversized imported attachments', 0, (): void => {
      expect(capturedError((): void => validateImportedAttachmentSize(
        VaultItemType.File, MAX_FILE_ATTACHMENT_BYTES + 1, '合同.pdf'))).assertContain('超过 10 MB');
      expect(capturedError((): void => validateImportedAttachmentSize(
        VaultItemType.Audio, MAX_IMPORTED_AUDIO_BYTES + 1, '录音.m4a'))).assertContain('超过 10 MB');
      expect(capturedError((): void => validateImportedAttachmentSize(
        VaultItemType.Image, MAX_IMPORTED_IMAGE_BYTES + 1, '照片.jpg'))).assertContain('超过 64 MB');
      expect(capturedError((): void => validateImportedAttachmentSize(
        VaultItemType.Video, MAX_IMPORTED_VIDEO_BYTES + 1, '视频.mp4'))).assertContain('超过 500 MB');
    });

    it('allows large in-app recordings at repository boundary', 0, (): void => {
      expect(capturedError((): void => validateStoredAttachmentSize(
        VaultItemType.Audio, MAX_IMPORTED_AUDIO_BYTES + 1, '在线录音.m4a'))).assertEqual('');
    });

    it('rejects empty attachments', 0, (): void => {
      expect(capturedError((): void => validateImportedAttachmentSize(
        VaultItemType.Image, 0, '空.jpg'))).assertEqual('“空.jpg”内容为空');
    });

    it('enforces aggregate media limit without overflow', 0, (): void => {
      expect(checkedTotalBytes(MAX_MEDIA_IMPORT_BATCH_BYTES - 1, 1,
        MAX_MEDIA_IMPORT_BATCH_BYTES, '超限')).assertEqual(MAX_MEDIA_IMPORT_BATCH_BYTES);
      expect(capturedError((): void => {
        checkedTotalBytes(MAX_MEDIA_IMPORT_BATCH_BYTES, 1, MAX_MEDIA_IMPORT_BATCH_BYTES, '超限');
      })).assertEqual('超限');
    });

    it('recognizes supported audio extensions case-insensitively', 0, (): void => {
      expect(isSupportedAudioFileName('VOICE.M4A')).assertEqual(true);
      expect(isSupportedAudioFileName('music.flac')).assertEqual(true);
      expect(isSupportedAudioFileName('script.exe')).assertEqual(false);
    });
  });
}
