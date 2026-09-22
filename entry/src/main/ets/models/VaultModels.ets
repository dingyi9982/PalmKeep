export enum VaultItemType {
  Login = 'login',
  Note = 'note',
  Image = 'image',
  Video = 'video',
  Audio = 'audio',
  File = 'file'
}

export interface VaultGroup {
  id: number;
  name: string;
  color: string;
  createdAt: number;
}

export interface VaultItem {
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

export interface VaultItemInput {
  type: VaultItemType;
  groupId: number;
  title: string;
  username: string;
  password: string;
  website: string;
  notes: string;
}

export interface VaultAttachmentInput {
  type: VaultItemType;
  uri: string;
  sourceUri?: string;
  name: string;
  ocrText: string;
}

export interface VaultAttachmentSummary {
  index: number;
  type: VaultItemType;
  name: string;
  sourceUri: string;
  ocrText: string;
  sizeBytes: number;
}

export interface VaultSearchHit {
  item: VaultItem;
  attachmentIndex: number;
  matchedTextLine: string;
  originalGroupName: string;
}

export interface VaultTrashEntry {
  item: VaultItem;
  originalGroupName: string;
}

export interface VaultStorageStats {
  databaseBytes: number;
  mediaBytes: number;
  audioBytes: number;
  fileBytes: number;
  orphanBytes: number;
  totalBytes: number;
}

export interface VaultHealthReport {
  checkedAt: number;
  databaseOk: boolean;
  activeItemCount: number;
  trashItemCount: number;
  attachmentCount: number;
  missingAttachmentCount: number;
  sizeMismatchCount: number;
  orphanFileCount: number;
  ocrMismatchCount: number;
  repairedOcrCount: number;
  removedOrphanCount: number;
  storage: VaultStorageStats;
}

export function createVaultId(): string {
  return `${Date.now()}-${Math.floor(Math.random() * 1000000000)}`;
}

export function itemTypeLabel(type: VaultItemType): string {
  switch (type) {
    case VaultItemType.Login:
      return '账号';
    case VaultItemType.Note:
      return '笔记';
    case VaultItemType.Image:
      return '媒体';
    case VaultItemType.Video:
      return '媒体';
    case VaultItemType.Audio:
      return '音频';
    case VaultItemType.File:
      return '文件';
    default:
      return '资料';
  }
}

export function itemDisplayTitle(item: VaultItem): string {
  if (item.title.length > 0) { return item.title; }
  if (item.type === VaultItemType.Login) { return item.website; }
  return '';
}

export function itemTypeGlyph(type: VaultItemType): string {
  switch (type) {
    case VaultItemType.Login:
      return '⌘';
    case VaultItemType.Note:
      return '✎';
    case VaultItemType.Image:
      return '▧';
    case VaultItemType.Video:
      return '▶';
    case VaultItemType.Audio:
      return '♪';
    case VaultItemType.File:
      return '▤';
    default:
      return '◆';
  }
}
