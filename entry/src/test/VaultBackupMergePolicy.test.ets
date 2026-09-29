import { describe, expect, it } from '@ohos/hypium';
import { BackupItemRecord } from '../main/ets/models/VaultBackupModels';
import { VaultItemType } from '../main/ets/models/VaultModels';
import {
  BackupComparisonContext, BackupMergeDecision, planBackupItemMerge
} from '../main/ets/services/VaultBackupMergePolicy';

function item(id: string, deletedAt: number = 0, updatedAt: number = 10): BackupItemRecord {
  return { id: id, type: VaultItemType.Note, groupId: 1, title: '资料', username: '', password: '',
    website: '', notes: '', ocrText: '', createdAt: 1, updatedAt: updatedAt, deletedAt: deletedAt };
}

function comparison(current: BackupItemRecord[]): BackupComparisonContext {
  const currentItems = new Map<string, BackupItemRecord>();
  current.forEach((entry: BackupItemRecord): void => { currentItems.set(entry.id, entry); });
  return { currentItems: currentItems, currentSignatures: new Map<string, string>(),
    incomingSignatures: new Map<string, string>([['item-1', 'backup-content']]),
    conflictSignatures: new Map<string, string>([['item-1', 'conflict-content']]) };
}

export default function vaultBackupMergePolicyTest(): void {
  describe('VaultBackupMergePolicy', (): void => {
    it('adds a missing item under its original ID', 0, (): void => {
      const plan = planBackupItemMerge(item('item-1'), comparison([]), new Set<string>());
      expect(plan.decision).assertEqual(BackupMergeDecision.Add);
      expect(plan.targetId).assertEqual('item-1');
    });

    it('restores beside the original trash item', 0, (): void => {
      const context = comparison([item('item-1', 20)]);
      const plan = planBackupItemMerge(item('item-1'), context, new Set<string>());
      expect(plan.decision).assertEqual(BackupMergeDecision.RestoreBesideTrash);
      expect((plan.targetId ?? '').startsWith('restored-item-1-10-')).assertEqual(true);
    });

    it('keeps a trashed copy and allocates a new ID for a repeated restore', 0, (): void => {
      const original = item('item-1', 20);
      const context = comparison([original]);
      const first = planBackupItemMerge(item('item-1'), context, new Set<string>());
      const baseId = first.targetId ?? '';
      context.currentItems.set(baseId, item(baseId, 30));
      context.currentSignatures.set(baseId, 'trashed-content');
      const second = planBackupItemMerge(item('item-1'), context, new Set<string>());
      expect(second.decision).assertEqual(BackupMergeDecision.RestoreBesideTrash);
      expect(second.targetId).assertEqual(`${baseId}-2`);
      context.currentItems.set(second.targetId ?? '', item(second.targetId ?? ''));
      context.currentSignatures.set(second.targetId ?? '', 'backup-content');
      const third = planBackupItemMerge(item('item-1'), context, new Set<string>());
      expect(third.decision).assertEqual(BackupMergeDecision.Unchanged);
      expect(third.targetId).assertEqual(second.targetId);
      context.currentItems.set(second.targetId ?? '', item(second.targetId ?? '', 40));
      context.currentSignatures.set(second.targetId ?? '', 'trashed-again');
      const fourth = planBackupItemMerge(item('item-1'), context, new Set<string>());
      expect(fourth.decision).assertEqual(BackupMergeDecision.RestoreBesideTrash);
      expect(fourth.targetId).assertEqual(`${baseId}-3`);
    });

    it('does not overwrite a changed conflict copy', 0, (): void => {
      const context = comparison([item('item-1')]);
      context.currentSignatures.set('item-1', 'local-content');
      const first = planBackupItemMerge(item('item-1'), context, new Set<string>());
      const baseId = first.targetId ?? '';
      expect(first.decision).assertEqual(BackupMergeDecision.Conflict);
      context.currentItems.set(baseId, item(baseId));
      context.currentSignatures.set(baseId, 'changed-conflict-content');
      const second = planBackupItemMerge(item('item-1'), context, new Set<string>());
      expect(second.decision).assertEqual(BackupMergeDecision.Conflict);
      expect(second.targetId).assertEqual(`${baseId}-2`);
      context.currentItems.set(second.targetId ?? '', item(second.targetId ?? ''));
      context.currentSignatures.set(second.targetId ?? '', 'conflict-content');
      const third = planBackupItemMerge(item('item-1'), context, new Set<string>());
      expect(third.decision).assertEqual(BackupMergeDecision.Unchanged);
    });
  });
}
