import { VaultItemType } from './VaultModels';

export const BACKUP_FORMAT_VERSION: number = 1;

export interface BackupGroupRecord {
  id: number;
  name: string;
  color: string;
  createdAt: number;
  sortOrder: number;
}

export interface BackupItemRecord {
  id: string;
  type: VaultItemType;
  groupId: number;
  title: string;
  username: string;
  password: string;
  website: string;
  notes: string;
  ocrText: string;
  createdAt: number;
  updatedAt: number;
  deletedAt: number;
}

export interface BackupAttachmentRecord {
  itemId: string;
  attachmentIndex: number;
  type: VaultItemType;
  name: string;
  ocrText: string;
  storageName: string;
  sizeBytes: number;
  sha256: string;
}

export interface BackupGroupTombstoneRecord {
  groupId: number;
  name: string;
  color: string;
  createdAt: number;
  deletedAt: number;
}

export interface BackupItemTombstoneRecord {
  itemId: string;
  deletedAt: number;
}

export interface VaultBackupDataset {
  groups: BackupGroupRecord[];
  items: BackupItemRecord[];
  attachments: BackupAttachmentRecord[];
  groupTombstones: BackupGroupTombstoneRecord[];
  itemTombstones: BackupItemTombstoneRecord[];
}

export interface BackupFileRecord {
  storageName: string;
  sizeBytes: number;
  sha256: string;
}

export interface BackupManifest {
  formatVersion: number;
  databaseVersion: number;
  appVersion: string;
  createdAt: number;
  groupCount?: number;
  groupTombstoneCount?: number;
  itemCount: number;
  trashCount: number;
  attachmentCount: number;
  attachmentBytes: number;
  dataSha256: string;
  files: BackupFileRecord[];
}

export interface BackupSummary {
  createdAt: number;
  itemCount: number;
  trashCount: number;
  attachmentCount: number;
  attachmentBytes: number;
}

export interface BackupStatusRecord extends BackupSummary {
  dataRevision: number;
}

export interface BackupProgress {
  phase: string;
  completed: number;
  total: number;
}

export interface BackupRestorePreview extends BackupSummary {
  addedCount: number;
  updatedCount: number;
  retainedCount: number;
  newerCount: number;
  conflictCount: number;
  unchangedCount: number;
  deletedCount: number;
}

export interface BackupRestoreResult {
  addedCount: number;
  updatedCount: number;
  retainedCount: number;
  newerCount: number;
  conflictCount: number;
  unchangedCount: number;
  deletedCount: number;
}
