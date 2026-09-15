export enum VaultItemType {
  Login = 'login',
  Note = 'note',
  Image = 'image',
  Video = 'video',
  File = 'file',
  Identity = 'identity'
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

export function createVaultId(): string {
  return `${Date.now()}-${Math.floor(Math.random() * 1000000000)}`;
}

export function itemTypeLabel(type: VaultItemType): string {
  switch (type) {
    case VaultItemType.Login:
      return '账号密码';
    case VaultItemType.Note:
      return '私密笔记';
    case VaultItemType.Image:
      return '图片';
    case VaultItemType.Video:
      return '视频';
    case VaultItemType.File:
      return '文件';
    case VaultItemType.Identity:
      return '身份信息';
    default:
      return '项目';
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
    case VaultItemType.Identity:
      return '◇';
    default:
      return '◆';
  }
}
