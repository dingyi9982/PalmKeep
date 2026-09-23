import { describe, expect, it } from '@ohos/hypium';
import { VaultItemType } from '../main/ets/models/VaultModels';
import {
  BACKUP_FORMAT_VERSION,
  BackupManifest,
  VaultBackupDataset
} from '../main/ets/models/VaultBackupModels';
import {
  validateBackupDataset,
  validateBackupManifest,
  validateBackupStorageName
} from '../main/ets/services/VaultBackupValidation';

const HASH_A: string = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

function capturedError(action: () => void): string {
  try { action(); return ''; }
  catch (error) { return error instanceof Error ? error.message : '未知错误'; }
}

function validManifest(): BackupManifest {
  return {
    formatVersion: BACKUP_FORMAT_VERSION,
    databaseVersion: 1,
    appVersion: '1.0.0',
    createdAt: 100,
    groupCount: 1,
    groupTombstoneCount: 0,
    itemCount: 1,
    trashCount: 0,
    attachmentCount: 1,
    attachmentBytes: 4,
    dataSha256: HASH_A,
    files: [{ storageName: 'attachment.bin', sizeBytes: 4, sha256: HASH_A }]
  };
}

function validDataset(): VaultBackupDataset {
  return {
    groups: [{ id: 1, name: '默认', color: '#000000', createdAt: 1, sortOrder: 0 }],
    items: [{ id: 'item-1', type: VaultItemType.Note, groupId: 1, title: '合同', username: '', password: '',
      website: '', notes: '内容', ocrText: '', createdAt: 2, updatedAt: 2, deletedAt: 0 }],
    attachments: [{ itemId: 'item-1', attachmentIndex: 0, type: VaultItemType.File, name: '合同.pdf',
      ocrText: '', storageName: 'attachment.bin', sizeBytes: 4, sha256: HASH_A }],
    groupTombstones: [],
    itemTombstones: []
  };
}

export default function vaultBackupValidationTest(): void {
  describe('VaultBackupValidation', (): void => {
    it('accepts a consistent manifest and dataset', 0, (): void => {
      const manifest = validManifest();
      expect(capturedError((): void => validateBackupManifest(manifest, 1))).assertEqual('');
      expect(capturedError((): void => validateBackupDataset(validDataset(), manifest))).assertEqual('');
    });

    it('rejects unsupported backup versions', 0, (): void => {
      const manifest = validManifest();
      manifest.formatVersion = BACKUP_FORMAT_VERSION + 1;
      expect(capturedError((): void => validateBackupManifest(manifest, 1))).assertEqual('备份格式版本无效');
      const newerDatabase = validManifest();
      newerDatabase.databaseVersion = 2;
      expect(capturedError((): void => validateBackupManifest(newerDatabase, 1))).assertEqual('备份数据库版本过新');
    });

    it('rejects unsafe and reserved storage names', 0, (): void => {
      expect(capturedError((): void => validateBackupStorageName('../secret'))).assertContain('不安全');
      expect(capturedError((): void => validateBackupStorageName('folder\\secret'))).assertContain('不安全');
      expect(capturedError((): void => validateBackupStorageName('manifest.json'))).assertContain('不安全');
    });

    it('rejects duplicate attachment records in manifest', 0, (): void => {
      const manifest = validManifest();
      manifest.attachmentCount = 2;
      manifest.attachmentBytes = 8;
      manifest.files.push({ storageName: 'attachment.bin', sizeBytes: 4, sha256: HASH_A });
      expect(capturedError((): void => validateBackupManifest(manifest, 1))).assertEqual('备份附件清单无效');
    });

    it('rejects duplicate groups and items', 0, (): void => {
      const groups = validDataset();
      groups.groups.push({ id: 1, name: '重复', color: '#ffffff', createdAt: 2, sortOrder: 1 });
      const groupManifest = validManifest();
      groupManifest.groupCount = 2;
      expect(capturedError((): void => validateBackupDataset(groups, groupManifest))).assertEqual('备份中存在重复分组');

      const items = validDataset();
      items.items.push(items.items[0]);
      const itemManifest = validManifest();
      itemManifest.itemCount = 2;
      expect(capturedError((): void => validateBackupDataset(items, itemManifest))).assertEqual('备份中存在重复资料');
    });

    it('rejects items without their group', 0, (): void => {
      const dataset = validDataset();
      dataset.items[0].groupId = 99;
      expect(capturedError((): void => validateBackupDataset(dataset, validManifest()))).assertContain('缺少对应的分组信息');
    });

    it('rejects attachment hash or item reference mismatch', 0, (): void => {
      const hashMismatch = validDataset();
      hashMismatch.attachments[0].sha256 = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
      expect(capturedError((): void => validateBackupDataset(hashMismatch, validManifest())))
        .assertEqual('备份附件引用无效');
      const missingItem = validDataset();
      missingItem.attachments[0].itemId = 'missing';
      expect(capturedError((): void => validateBackupDataset(missingItem, validManifest())))
        .assertEqual('备份附件引用无效');
    });

  });
}
