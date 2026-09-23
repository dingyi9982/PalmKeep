import preferences from '@ohos.data.preferences';
import { VaultItemType } from '../models/VaultModels';
import { BackupStatusRecord } from '../models/VaultBackupModels';
import { AbilityContextHolder } from './AbilityContextHolder';
import { logRecoverableError } from './ErrorUtils';

const UI_PREFERENCES: string = 'palmkeep_ui_preferences';
const KEY_LAST_NEW_ITEM_TYPE: string = 'last_new_item_type';
const KEY_BACKUP_TIME: string = 'last_backup_time';
const KEY_BACKUP_ITEM_COUNT: string = 'last_backup_item_count';
const KEY_BACKUP_TRASH_COUNT: string = 'last_backup_trash_count';
const KEY_BACKUP_ATTACHMENT_COUNT: string = 'last_backup_attachment_count';
const KEY_BACKUP_ATTACHMENT_BYTES: string = 'last_backup_attachment_bytes';
const KEY_BACKUP_DATA_REVISION: string = 'last_backup_data_revision';

class VaultUiPreferences {
  async getLastNewItemType(): Promise<VaultItemType> {
    try {
      const store = await preferences.getPreferences(AbilityContextHolder.getContext(), UI_PREFERENCES);
      const value = store.getSync(KEY_LAST_NEW_ITEM_TYPE, VaultItemType.Image) as string;
      if (value === VaultItemType.Login || value === VaultItemType.Note ||
        value === VaultItemType.Image || value === VaultItemType.Audio || value === VaultItemType.File) {
        return value as VaultItemType;
      }
    } catch (error) {
      logRecoverableError('could not read the last new item type', error);
    }
    return VaultItemType.Image;
  }

  async setLastNewItemType(type: VaultItemType): Promise<void> {
    try {
      const store = await preferences.getPreferences(AbilityContextHolder.getContext(), UI_PREFERENCES);
      store.putSync(KEY_LAST_NEW_ITEM_TYPE, type);
      await store.flush();
    } catch (error) {
      logRecoverableError('could not save the last new item type', error);
    }
  }

  async getBackupStatus(): Promise<BackupStatusRecord | undefined> {
    try {
      const store = await preferences.getPreferences(AbilityContextHolder.getContext(), UI_PREFERENCES);
      const createdAt = store.getSync(KEY_BACKUP_TIME, 0) as number;
      if (createdAt <= 0) { return undefined; }
      return {
        createdAt: createdAt,
        itemCount: store.getSync(KEY_BACKUP_ITEM_COUNT, 0) as number,
        trashCount: store.getSync(KEY_BACKUP_TRASH_COUNT, 0) as number,
        attachmentCount: store.getSync(KEY_BACKUP_ATTACHMENT_COUNT, 0) as number,
        attachmentBytes: store.getSync(KEY_BACKUP_ATTACHMENT_BYTES, 0) as number,
        dataRevision: store.getSync(KEY_BACKUP_DATA_REVISION, 0) as number
      };
    } catch (error) {
      logRecoverableError('could not read backup status', error);
      return undefined;
    }
  }

  async setBackupStatus(status: BackupStatusRecord): Promise<void> {
    try {
      const store = await preferences.getPreferences(AbilityContextHolder.getContext(), UI_PREFERENCES);
      store.putSync(KEY_BACKUP_TIME, status.createdAt);
      store.putSync(KEY_BACKUP_ITEM_COUNT, status.itemCount);
      store.putSync(KEY_BACKUP_TRASH_COUNT, status.trashCount);
      store.putSync(KEY_BACKUP_ATTACHMENT_COUNT, status.attachmentCount);
      store.putSync(KEY_BACKUP_ATTACHMENT_BYTES, status.attachmentBytes);
      store.putSync(KEY_BACKUP_DATA_REVISION, status.dataRevision);
      await store.flush();
    } catch (error) {
      logRecoverableError('could not save backup status', error);
    }
  }

  async clearBackupStatus(): Promise<void> {
    try {
      const store = await preferences.getPreferences(AbilityContextHolder.getContext(), UI_PREFERENCES);
      store.deleteSync(KEY_BACKUP_TIME);
      store.deleteSync(KEY_BACKUP_ITEM_COUNT);
      store.deleteSync(KEY_BACKUP_TRASH_COUNT);
      store.deleteSync(KEY_BACKUP_ATTACHMENT_COUNT);
      store.deleteSync(KEY_BACKUP_ATTACHMENT_BYTES);
      store.deleteSync(KEY_BACKUP_DATA_REVISION);
      await store.flush();
    } catch (error) {
      logRecoverableError('could not clear backup status', error);
    }
  }
}

export const vaultUiPreferences = new VaultUiPreferences();
