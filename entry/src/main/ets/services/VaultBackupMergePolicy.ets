import { BackupItemRecord } from '../models/VaultBackupModels';

export enum BackupMergeDecision {
  Add = 'add',
  Update = 'update',
  RestoreBesideTrash = 'restore_beside_trash',
  RetainNewer = 'retain_newer',
  Conflict = 'conflict',
  Unchanged = 'unchanged'
}

export interface BackupMergePlan {
  decision: BackupMergeDecision;
  targetId?: string;
}

export interface BackupComparisonContext {
  currentItems: Map<string, BackupItemRecord>;
  currentSignatures: Map<string, string>;
  incomingSignatures: Map<string, string>;
  conflictSignatures: Map<string, string>;
}

function contentHash(value: string): string {
  let hash = 2166136261;
  for (let index = 0; index < value.length; index += 1) {
    hash ^= value.charCodeAt(index);
    hash = Math.imul(hash, 16777619);
  }
  return (hash >>> 0).toString(16);
}

function isCopyId(id: string, baseId: string): boolean {
  if (id === baseId) { return true; }
  if (!id.startsWith(`${baseId}-`)) { return false; }
  const suffix = id.substring(baseId.length + 1);
  return suffix !== '1' && /^[1-9][0-9]*$/.test(suffix);
}

function chooseCopy(baseId: string, signature: string, comparison: BackupComparisonContext,
  reservedIds: Set<string>, decision: BackupMergeDecision): BackupMergePlan {
  let matchingActiveCopyId: string | undefined = undefined;
  comparison.currentItems.forEach((item: BackupItemRecord, id: string): void => {
    if (isCopyId(id, baseId) && item.deletedAt === 0 &&
      comparison.currentSignatures.get(id) === signature) {
      matchingActiveCopyId = id;
    }
  });
  if (matchingActiveCopyId !== undefined) {
    return { decision: BackupMergeDecision.Unchanged, targetId: matchingActiveCopyId };
  }
  let targetId = baseId;
  let suffix = 2;
  while (comparison.currentItems.has(targetId) || reservedIds.has(targetId)) {
    targetId = `${baseId}-${suffix}`;
    suffix += 1;
  }
  return { decision: decision, targetId: targetId };
}

export function planBackupItemMerge(incoming: BackupItemRecord, comparison: BackupComparisonContext,
  reservedIds: Set<string>): BackupMergePlan {
  const current = comparison.currentItems.get(incoming.id);
  if (!current) { return { decision: BackupMergeDecision.Add, targetId: incoming.id }; }
  const incomingSignature = comparison.incomingSignatures.get(incoming.id) ?? '';
  if (incoming.deletedAt === 0 && current.deletedAt > 0) {
    const baseId = `restored-${incoming.id}-${incoming.updatedAt}-${contentHash(incomingSignature)}`;
    return chooseCopy(baseId, incomingSignature, comparison, reservedIds,
      BackupMergeDecision.RestoreBesideTrash);
  }
  if (incoming.deletedAt > 0 && current.deletedAt === 0) {
    return { decision: BackupMergeDecision.RetainNewer };
  }
  if (comparison.currentSignatures.get(current.id) === incomingSignature) {
    return { decision: BackupMergeDecision.Unchanged, targetId: current.id };
  }
  if (incoming.updatedAt > current.updatedAt) {
    return { decision: BackupMergeDecision.Update, targetId: incoming.id };
  }
  if (current.updatedAt > incoming.updatedAt) {
    return { decision: BackupMergeDecision.RetainNewer };
  }
  const baseId = `backup-${incoming.id}-${incoming.updatedAt}-${contentHash(incomingSignature)}`;
  return chooseCopy(baseId, comparison.conflictSignatures.get(incoming.id) ?? '', comparison,
    reservedIds, BackupMergeDecision.Conflict);
}
