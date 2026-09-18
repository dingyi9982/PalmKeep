export enum VaultItemType {
  Login = 'login',
  Note = 'note',
  Image = 'image',
  Video = 'video',
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
  notes: string;
  attachmentUri: string;
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
  notes: string;
  attachmentUri: string;
  attachmentData: Uint8Array;
}

export interface VaultAttachmentInput {
  type: VaultItemType;
  uri: string;
  sourceUri?: string;
  name: string;
  data: Uint8Array;
}

export interface VaultAttachmentSummary {
  index: number;
  type: VaultItemType;
  name: string;
  sourceUri: string;
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
    case VaultItemType.File:
      return '文件';
    default:
      return '资料';
  }
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
    case VaultItemType.File:
      return '▤';
    default:
      return '◆';
  }
}
