import { describe, expect, it } from '@ohos/hypium';
import { BackupStatusRecord } from '../main/ets/models/VaultBackupModels';
import {
  backupReminderDue, localBackupReminderDay, shouldPresentBackupReminder
} from '../main/ets/services/VaultBackupReminderPolicy';

const DAY_MS: number = 24 * 60 * 60 * 1000;

function status(createdAt: number, revision: number): BackupStatusRecord {
  return { createdAt: createdAt, dataRevision: revision, itemCount: 1, trashCount: 0,
    attachmentCount: 0, attachmentBytes: 0 };
}

export default function vaultBackupReminderPolicyTest(): void {
  describe('VaultBackupReminderPolicy', (): void => {
    it('reminds immediately for the first unbacked item but not an empty vault', 0, (): void => {
      expect(backupReminderDue(7, 1, undefined, 1, 100)).assertEqual(true);
      expect(backupReminderDue(7, 0, undefined, 0, 100)).assertEqual(false);
    });

    it('requires both elapsed interval and unbacked changes', 0, (): void => {
      const now = new Date(2026, 0, 20, 12).getTime();
      expect(backupReminderDue(7, 1, status(now - 6 * DAY_MS, 1), 2, now)).assertEqual(false);
      expect(backupReminderDue(7, 1, status(now - 7 * DAY_MS, 1), 1, now)).assertEqual(false);
      expect(backupReminderDue(7, 1, status(now - 7 * DAY_MS, 1), 2, now)).assertEqual(true);
      expect(backupReminderDue(30, 1, status(now - 7 * DAY_MS, 1), 2, now)).assertEqual(false);
      expect(backupReminderDue(30, 1, status(now - 30 * DAY_MS, 1), 2, now)).assertEqual(true);
      expect(backupReminderDue(0, 1, undefined, 2, now)).assertEqual(false);
    });

    it('shows only once per local day and retries the next day after Later', 0, (): void => {
      const today = new Date(2026, 0, 20, 12).getTime();
      const shownDay = localBackupReminderDay(today);
      expect(shouldPresentBackupReminder(true, '', today)).assertEqual(true);
      expect(shouldPresentBackupReminder(true, shownDay, today)).assertEqual(false);
      expect(shouldPresentBackupReminder(true, shownDay, today + DAY_MS)).assertEqual(true);
    });

    it('stops prompting after a successful backup and keeps a cancelled export due', 0, (): void => {
      const now = new Date(2026, 0, 20, 12).getTime();
      const oldBackup = status(now - 8 * DAY_MS, 1);
      expect(backupReminderDue(7, 1, oldBackup, 2, now)).assertEqual(true);
      expect(shouldPresentBackupReminder(true, localBackupReminderDay(now), now)).assertEqual(false);
      expect(backupReminderDue(7, 1, oldBackup, 2, now + DAY_MS)).assertEqual(true);
      expect(backupReminderDue(7, 1, status(now, 2), 2, now + DAY_MS)).assertEqual(false);
    });
  });
}
