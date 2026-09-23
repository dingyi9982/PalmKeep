import {
  BACKUP_FORMAT_VERSION,
  BackupAttachmentRecord,
  BackupFileRecord,
  BackupGroupRecord,
  BackupGroupTombstoneRecord,
  BackupItemRecord,
  BackupManifest,
  VaultBackupDataset
} from '../models/VaultBackupModels';

const DATA_FILE: string = 'vault-data.json';
const MANIFEST_FILE: string = 'manifest.json';

export function validateBackupStorageName(name: string): void {
  if (name.length === 0 || name.indexOf('/') >= 0 || name.indexOf('\\') >= 0 || name.indexOf('..') >= 0 ||
    name === DATA_FILE || name === MANIFEST_FILE) {
    throw new Error('备份中包含不安全的文件名');
  }
}

export function validateBackupManifest(manifest: BackupManifest, maximumDatabaseVersion: number): void {
  if (!manifest || manifest.formatVersion !== BACKUP_FORMAT_VERSION) { throw new Error('备份格式版本无效'); }
  if (manifest.databaseVersion > maximumDatabaseVersion) { throw new Error('备份数据库版本过新'); }
  if (manifest.itemCount === 0) { throw new Error('备份中没有任何资料，无法恢复'); }
  if ((manifest.groupCount !== undefined && manifest.groupCount < 0) ||
    (manifest.groupTombstoneCount !== undefined && manifest.groupTombstoneCount < 0) || manifest.itemCount < 0 ||
    manifest.attachmentCount < 0 || manifest.attachmentBytes < 0 ||
    manifest.files.length !== manifest.attachmentCount) { throw new Error('备份清单无效'); }
  const names = new Set<string>();
  manifest.files.forEach((file: BackupFileRecord): void => {
    validateBackupStorageName(file.storageName);
    if (names.has(file.storageName) || file.sizeBytes <= 0 || file.sha256.length !== 64) {
      throw new Error('备份附件清单无效');
    }
    names.add(file.storageName);
  });
}

export function validateBackupDataset(dataset: VaultBackupDataset, manifest: BackupManifest): void {
  if (!dataset || !dataset.groups || !dataset.items || !dataset.attachments ||
    !dataset.groupTombstones || !dataset.itemTombstones) { throw new Error('备份数据结构不完整'); }
  if (manifest.groupCount !== undefined && dataset.groups.length !== manifest.groupCount) {
    throw new Error(`备份分组数量不一致：清单 ${manifest.groupCount}，实际 ${dataset.groups.length}`);
  }
  if (manifest.groupTombstoneCount !== undefined &&
    dataset.groupTombstones.length !== manifest.groupTombstoneCount) {
    throw new Error(`备份已删除分组数量不一致：清单 ${manifest.groupTombstoneCount}，` +
      `实际 ${dataset.groupTombstones.length}`);
  }
  if (dataset.items.length !== manifest.itemCount) {
    throw new Error(`备份资料数量不一致：清单 ${manifest.itemCount}，实际 ${dataset.items.length}`);
  }
  if (dataset.attachments.length !== manifest.attachmentCount) {
    throw new Error(`备份附件数量不一致：清单 ${manifest.attachmentCount}，` +
      `实际 ${dataset.attachments.length}`);
  }
  const activeGroupIds = new Set<number>();
  dataset.groups.forEach((group: BackupGroupRecord): void => {
    if (activeGroupIds.has(group.id)) { throw new Error('备份中存在重复分组'); }
    activeGroupIds.add(group.id);
  });
  const deletedGroupIds = new Set<number>();
  dataset.groupTombstones.forEach((group: BackupGroupTombstoneRecord): void => {
    if (activeGroupIds.has(group.groupId) || deletedGroupIds.has(group.groupId)) {
      throw new Error('备份中的分组状态冲突');
    }
    deletedGroupIds.add(group.groupId);
  });
  const itemIds = new Set<string>();
  dataset.items.forEach((item: BackupItemRecord): void => {
    if (itemIds.has(item.id)) { throw new Error('备份中存在重复资料'); }
    itemIds.add(item.id);
    if (item.deletedAt === 0 && !activeGroupIds.has(item.groupId)) {
      throw new Error(`资料“${item.title}”缺少对应的分组信息`);
    }
    if (item.deletedAt > 0 && !activeGroupIds.has(item.groupId) && !deletedGroupIds.has(item.groupId)) {
      throw new Error(`回收站资料“${item.title}”缺少原分组信息`);
    }
  });
  const fileNames = new Set<string>();
  const fileHashes = new Map<string, string>();
  manifest.files.forEach((file: BackupFileRecord): void => {
    fileNames.add(file.storageName);
    fileHashes.set(file.storageName, file.sha256);
  });
  dataset.attachments.forEach((attachment: BackupAttachmentRecord): void => {
    if (!fileNames.has(attachment.storageName) || !itemIds.has(attachment.itemId) ||
      attachment.sha256.length !== 64 || fileHashes.get(attachment.storageName) !== attachment.sha256) {
      throw new Error('备份附件引用无效');
    }
  });
}
