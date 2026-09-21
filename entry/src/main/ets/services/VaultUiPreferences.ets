import preferences from '@ohos.data.preferences';
import { VaultItemType } from '../models/VaultModels';
import { AbilityContextHolder } from './AbilityContextHolder';
import { logRecoverableError } from './ErrorUtils';

const UI_PREFERENCES: string = 'palmvault_ui_preferences';
const KEY_LAST_NEW_ITEM_TYPE: string = 'last_new_item_type';

class VaultUiPreferences {
  async getLastNewItemType(): Promise<VaultItemType> {
    try {
      const store = await preferences.getPreferences(AbilityContextHolder.getContext(), UI_PREFERENCES);
      const value = store.getSync(KEY_LAST_NEW_ITEM_TYPE, VaultItemType.Note) as string;
      if (value === VaultItemType.Login || value === VaultItemType.Note ||
        value === VaultItemType.Image || value === VaultItemType.File) {
        return value as VaultItemType;
      }
    } catch (error) {
      logRecoverableError('could not read the last new item type', error);
    }
    return VaultItemType.Note;
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
}

export const vaultUiPreferences = new VaultUiPreferences();
