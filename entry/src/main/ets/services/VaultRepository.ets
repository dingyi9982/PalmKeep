import relationalStore from '@ohos.data.relationalStore';
import common from '@ohos.app.ability.common';
import fs from '@ohos.file.fs';
import cryptoFramework from '@ohos.security.cryptoFramework';
import { logRecoverableError, normalizeError } from './ErrorUtils';
import { migrateVaultDatabase } from './VaultDatabaseMigrations';
import { MAX_FILE_ATTACHMENT_BYTES } from './VaultLimits';
import {
  createVaultId,
  VaultAttachmentInput,
  VaultAttachmentSummary,
  VaultGroup,
  VaultItem,
  VaultItemInput,
  VaultSearchHit,
  VaultTrashEntry,
  VaultItemType
} from '../models/VaultModels';
import {
  BackupAttachmentRecord,
  BackupGroupRecord,
  BackupGroupTombstoneRecord,
  BackupItemRecord,
  BackupItemTombstoneRecord,
  BackupRestorePreview,
  BackupRestoreResult,
  VaultBackupDataset
} from '../models/VaultBackupModels';

// Keep this file name stable. Future database changes must use schema migrations.
const DATABASE_NAME: string = 'palmvault.db';
const ATTACHMENT_DIRECTORY_NAME: string = 'palmvault-attachments';

enum BackupMergeDecision {
  Add = 'add',
  Update = 'update',
  RestoreBesideTrash = 'restore_beside_trash',
  RetainNewer = 'retain_newer',
  Conflict = 'conflict',
  Unchanged = 'unchanged'
}

interface StoredAttachment {
  storageName: string;
  sizeBytes: number;
}

interface BackupComparisonContext {
  currentItems: Map<string, BackupItemRecord>;
  currentSignatures: Map<string, string>;
  incomingSignatures: Map<string, string>;
  conflictSignatures: Map<string, string>;
}

class VaultRepositoryImpl {
  private store?: relationalStore.RdbStore;
  private attachmentRoot: string = '';

  async open(context: common.UIAbilityContext, databaseKey: Uint8Array): Promise<void> {
    try {
      if (this.store) {
        databaseKey.fill(0);
        return;
      }
      databaseKey.fill(0);
      this.attachmentRoot = `${context.filesDir}/${ATTACHMENT_DIRECTORY_NAME}`;
      this.ensureAttachmentDirectory();
      const config: relationalStore.StoreConfig = {
        name: DATABASE_NAME,
        securityLevel: relationalStore.SecurityLevel.S4,
        encrypt: false
      };
      this.store = await relationalStore.getRdbStore(context, config);
      await migrateVaultDatabase(this.requireStore());
      await this.seedGroups();
      await this.cleanupOrphanedAttachments();
    } catch (error) {
      databaseKey.fill(0);
      const failedStore = this.store;
      this.store = undefined;
      if (failedStore) {
        try { await failedStore.close(); }
        catch (closeError) { logRecoverableError('could not close failed database connection', closeError); }
      }
      this.attachmentRoot = '';
      if (error instanceof Error) { throw error; }
      throw new Error('打开本地数据库失败');
    }
  }

  async close(): Promise<void> {
    try {
    const current = this.store;
    this.store = undefined;
    if (current) {
      await current.close();
    }
      } catch (error) {
      throw normalizeError(error);
    }
  }

  async destroy(context: common.UIAbilityContext): Promise<void> {
    try {
      await this.close();
      await relationalStore.deleteRdbStore(context, DATABASE_NAME);
      this.deleteAttachmentDirectory();
    } catch (error) {
      if (error instanceof Error) { throw error; }
      throw new Error('清除本地数据失败');
    }
  }

  async listGroups(): Promise<VaultGroup[]> {
    try {
    const result = await this.requireStore().querySql(
      'SELECT id, name, color, created_at FROM vault_groups ORDER BY sort_order ASC, created_at ASC'
    );
    const groups: VaultGroup[] = [];
    try {
      while (result.goToNextRow()) {
        groups.push({
          id: result.getLong(result.getColumnIndex('id')),
          name: result.getString(result.getColumnIndex('name')),
          color: result.getString(result.getColumnIndex('color')),
          createdAt: result.getLong(result.getColumnIndex('created_at'))
        });
      }
    } finally {
      result.close();
    }
    return groups;
      } catch (error) {
      throw normalizeError(error);
    }
  }

  async createGroup(name: string, color: string): Promise<number> {
    try {
    const cleanName = name.trim();
    if (cleanName.length === 0) {
      throw new Error('分组名称不能为空');
    }
    const orderResult = await this.requireStore().querySql(
      'SELECT COALESCE(MAX(sort_order), -1) + 1 FROM vault_groups');
    let sortOrder = 0;
    try { if (orderResult.goToFirstRow()) { sortOrder = orderResult.getLong(0); } } finally { orderResult.close(); }
    const values: relationalStore.ValuesBucket = {
      name: cleanName,
      color: color,
      created_at: Date.now(),
      sort_order: sortOrder
    };
    return this.requireStore().insert('vault_groups', values);
      } catch (error) {
      throw normalizeError(error);
    }
  }

  async reorderGroups(groupIds: number[]): Promise<void> {
    try {
    if (groupIds.length === 0) { return; }
    const store = this.requireStore();
    store.beginTransaction();
    try {
      for (let index = 0; index < groupIds.length; index += 1) {
        await store.executeSql('UPDATE vault_groups SET sort_order = ? WHERE id = ?', [index, groupIds[index]]);
      }
      store.commit();
    } catch (error) {
      store.rollBack();
      throw new Error('调整分组顺序失败');
    }
      } catch (error) {
      throw normalizeError(error);
    }
  }

  async updateGroup(id: number, name: string, color: string): Promise<void> {
    try {
    const values: relationalStore.ValuesBucket = { name: name.trim(), color: color };
    const predicates = new relationalStore.RdbPredicates('vault_groups');
    predicates.equalTo('id', id);
    await this.requireStore().update(values, predicates);
      } catch (error) {
      throw normalizeError(error);
    }
  }

  async deleteGroup(id: number): Promise<void> {
    try {
    const store = this.requireStore();
    const storageNames: string[] = [];
    const attachmentResult = await store.querySql(
      'SELECT storage_name FROM vault_item_attachments WHERE item_id IN ' +
      '(SELECT id FROM vault_items WHERE group_id = ? AND deleted_at = 0)', [id]);
    try {
      while (attachmentResult.goToNextRow()) { storageNames.push(attachmentResult.getString(0)); }
    } finally { attachmentResult.close(); }
    store.beginTransaction();
    try {
      await store.executeSql(
        'INSERT OR REPLACE INTO vault_group_tombstones (group_id, name, color, created_at, deleted_at) ' +
        'SELECT id, name, color, created_at, ? FROM vault_groups WHERE id = ?',
        [Date.now(), id]
      );
      await store.executeSql(
        'INSERT OR REPLACE INTO vault_item_tombstones (item_id, deleted_at) ' +
        'SELECT id, ? FROM vault_items WHERE group_id = ? AND deleted_at = 0', [Date.now(), id]
      );
      await store.executeSql(
        'DELETE FROM vault_item_attachments WHERE item_id IN ' +
        '(SELECT id FROM vault_items WHERE group_id = ? AND deleted_at = 0)', [id]
      );
      await store.executeSql('DELETE FROM vault_items WHERE group_id = ? AND deleted_at = 0', [id]);
      await store.executeSql('DELETE FROM vault_groups WHERE id = ?', [id]);
      store.commit();
      this.deleteStoredAttachments(storageNames);
    } catch (error) {
      store.rollBack();
      throw new Error('删除分组失败，数据未更改');
    }
      } catch (error) {
      throw normalizeError(error);
    }
  }

  async listItems(search: string = '', groupId: number = -1, includeDeleted: boolean = false): Promise<VaultItem[]> {
    try {
    let sql = 'SELECT id, type, group_id, title, username, password, notes, ocr_text, created_at, updated_at, deleted_at FROM vault_items WHERE 1 = 1';
    const args: relationalStore.ValueType[] = [];
    if (!includeDeleted) {
      sql += ' AND deleted_at = 0';
    }
    if (groupId >= 0) {
      sql += ' AND group_id = ?';
      args.push(groupId);
    }
    const cleanSearch = search.trim();
    if (cleanSearch.length > 0) {
      sql += ' AND (title LIKE ? OR username LIKE ? OR notes LIKE ? OR ocr_text LIKE ? OR EXISTS (' +
        'SELECT 1 FROM vault_item_attachments search_attachment ' +
        'WHERE search_attachment.item_id = vault_items.id AND search_attachment.ocr_text LIKE ?))';
      const pattern = `%${cleanSearch}%`;
      args.push(pattern, pattern, pattern, pattern, pattern);
    }
    sql += ' ORDER BY updated_at DESC';
    const result = await this.requireStore().querySql(sql, args);
    const items: VaultItem[] = [];
    try {
      while (result.goToNextRow()) {
        items.push(this.readItem(result));
      }
    } finally {
      result.close();
    }
    return items;
      } catch (error) {
      throw normalizeError(error);
    }
  }

  async searchItems(search: string): Promise<VaultSearchHit[]> {
    try {
    const cleanSearch = search.trim();
    if (cleanSearch.length === 0) { return []; }
    const pattern = `%${cleanSearch}%`;
    const fields = 'vault_items.id AS id, vault_items.type AS type, vault_items.group_id AS group_id, ' +
      'vault_items.title AS title, vault_items.username AS username, vault_items.password AS password, ' +
      'vault_items.notes AS notes, vault_items.ocr_text AS ocr_text, ' +
      'vault_items.created_at AS created_at, vault_items.updated_at AS updated_at, vault_items.deleted_at AS deleted_at, ' +
      'COALESCE(vault_groups.name, vault_group_tombstones.name, \'未分组\') AS original_group_name';
    const sql = 'SELECT ' + fields + ', search_attachment.attachment_index AS matched_attachment_index, ' +
      'search_attachment.ocr_text AS matched_ocr_text ' +
      'FROM vault_items JOIN vault_item_attachments search_attachment ON search_attachment.item_id = vault_items.id ' +
      'LEFT JOIN vault_groups ON vault_groups.id = vault_items.group_id ' +
      'LEFT JOIN vault_group_tombstones ON vault_group_tombstones.group_id = vault_items.group_id ' +
      'WHERE search_attachment.type = ? AND search_attachment.ocr_text LIKE ? ' +
      'UNION ALL SELECT ' + fields + ', -1 AS matched_attachment_index, \'\' AS matched_ocr_text FROM vault_items ' +
      'LEFT JOIN vault_groups ON vault_groups.id = vault_items.group_id ' +
      'LEFT JOIN vault_group_tombstones ON vault_group_tombstones.group_id = vault_items.group_id ' +
      'WHERE (title LIKE ? OR username LIKE ? OR notes LIKE ? OR ocr_text LIKE ?) ' +
      'AND NOT EXISTS (SELECT 1 FROM vault_item_attachments search_attachment ' +
      'WHERE search_attachment.item_id = vault_items.id AND search_attachment.type = ? ' +
      'AND search_attachment.ocr_text LIKE ?) ORDER BY updated_at DESC, matched_attachment_index ASC';
    const result = await this.requireStore().querySql(sql,
      [VaultItemType.Image, pattern, pattern, pattern, pattern, pattern, VaultItemType.Image, pattern]);
    const hits: VaultSearchHit[] = [];
    try {
      while (result.goToNextRow()) {
        const matchedOcrText = result.getString(result.getColumnIndex('matched_ocr_text'));
        hits.push({
          item: this.readItem(result),
          attachmentIndex: result.getLong(result.getColumnIndex('matched_attachment_index')),
          matchedTextLine: this.findMatchingTextLine(matchedOcrText, cleanSearch),
          originalGroupName: result.getString(result.getColumnIndex('original_group_name'))
        });
      }
    } finally { result.close(); }
    return hits;
      } catch (error) {
      throw normalizeError(error);
    }
  }

  async listTrashEntries(type?: VaultItemType): Promise<VaultTrashEntry[]> {
    try {
    let sql = 'SELECT vault_items.id, vault_items.type, vault_items.group_id, vault_items.title, ' +
      'vault_items.username, vault_items.password, vault_items.notes, ' +
      'vault_items.ocr_text, vault_items.created_at, vault_items.updated_at, vault_items.deleted_at, ' +
      'COALESCE(vault_groups.name, vault_group_tombstones.name, \'未分组\') AS original_group_name ' +
      'FROM vault_items LEFT JOIN vault_groups ON vault_groups.id = vault_items.group_id ' +
      'LEFT JOIN vault_group_tombstones ON vault_group_tombstones.group_id = vault_items.group_id ' +
      'WHERE vault_items.deleted_at > 0';
    const args: relationalStore.ValueType[] = [];
    if (type) {
      if (type === VaultItemType.Image) {
        sql += ' AND vault_items.type IN (?, ?)';
        args.push(VaultItemType.Image, VaultItemType.Video);
      } else {
        sql += ' AND vault_items.type = ?';
        args.push(type);
      }
    }
    sql += ' ORDER BY vault_items.deleted_at DESC';
    const result = await this.requireStore().querySql(sql, args);
    const entries: VaultTrashEntry[] = [];
    try {
      while (result.goToNextRow()) {
        entries.push({
          item: this.readItem(result),
          originalGroupName: result.getString(result.getColumnIndex('original_group_name'))
        });
      }
    } finally { result.close(); }
    return entries;
      } catch (error) {
      throw normalizeError(error);
    }
  }

  private findMatchingTextLine(text: string, search: string): string {
    if (text.length === 0) { return ''; }
    const normalizedSearch = search.toLowerCase();
    const lines = text.split('\n');
    for (let index = 0; index < lines.length; index += 1) {
      const line = lines[index].trim();
      if (line.toLowerCase().indexOf(normalizedSearch) >= 0) { return line; }
    }
    return text.trim();
  }

  private validateItemFields(type: VaultItemType, title: string, username: string,
    password: string, notes: string): void {
    const titleRequired = type === VaultItemType.Login || type === VaultItemType.Note;
    if (titleRequired && title.trim().length === 0) {
      throw new Error('名称不能为空');
    }
    if (type === VaultItemType.Login) {
      if (username.trim().length === 0) { throw new Error('账号不能为空'); }
      if (password.trim().length === 0) { throw new Error('密码不能为空'); }
    }
    if (type === VaultItemType.Note && notes.trim().length === 0) {
      throw new Error('内容不能为空');
    }
  }

  async createItem(input: VaultItemInput): Promise<string> {
    try {
    this.validateItemFields(input.type, input.title, input.username, input.password, input.notes);
    const now = Date.now();
    const id = createVaultId();
    const values: relationalStore.ValuesBucket = {
      id: id,
      type: input.type,
      group_id: input.groupId,
      title: input.title.trim(),
      username: input.username.trim(),
      password: input.password,
      notes: input.notes,
      ocr_text: '',
      created_at: now,
      updated_at: now,
      deleted_at: 0
    };
    await this.requireStore().insert('vault_items', values);
    return id;
      } catch (error) {
      throw normalizeError(error);
    }
  }

  async createItemWithAttachments(input: VaultItemInput, attachments: VaultAttachmentInput[],
    onProgress?: (completed: number, total: number) => void): Promise<string> {
    try {
    this.validateItemFields(input.type, input.title, input.username, input.password, input.notes);
    if (attachments.length === 0) { throw new Error('请先选择附件'); }
    const storedAttachments = await this.storeAttachments(attachments, onProgress);
    const store = this.requireStore();
    try {
      store.beginTransaction();
      const id = createVaultId();
      const now = Date.now();
      await store.insert('vault_items', {
        id: id,
        type: input.type,
        group_id: input.groupId,
        title: input.title.trim(),
        username: input.username.trim(),
        password: input.password,
        notes: input.notes,
        ocr_text: '',
        created_at: now,
        updated_at: now,
        deleted_at: 0
      });
      for (let index = 0; index < attachments.length; index += 1) {
        const attachment = attachments[index];
        await store.insert('vault_item_attachments', {
          item_id: id,
          attachment_index: index,
          type: attachment.type,
          name: attachment.name,
          source_uri: attachment.sourceUri ? attachment.sourceUri : attachment.uri,
          ocr_text: attachment.ocrText,
          storage_name: storedAttachments[index].storageName,
          size_bytes: storedAttachments[index].sizeBytes
        });
      }
      await this.refreshItemOcrText(id);
      store.commit();
      return id;
    } catch (error) {
      store.rollBack();
      this.deleteStoredAttachments(storedAttachments.map((item: StoredAttachment): string => item.storageName));
      throw new Error(`资料保存失败：${normalizeError(error).message}`);
    }
      } catch (error) {
      throw normalizeError(error);
    }
  }

  async listItemAttachments(itemId: string): Promise<VaultAttachmentSummary[]> {
    try {
    const result = await this.requireStore().querySql(
      `SELECT a.attachment_index, a.type, a.name, a.source_uri, a.ocr_text, a.size_bytes
        FROM vault_item_attachments a WHERE a.item_id = ? ORDER BY a.attachment_index ASC`,
      [itemId]
    );
    const attachments: VaultAttachmentSummary[] = [];
    try {
      while (result.goToNextRow()) {
        attachments.push({
          index: result.getLong(0),
          type: result.getString(1) as VaultItemType,
          name: result.getString(2),
          sourceUri: result.getString(3),
          ocrText: result.getString(4),
          sizeBytes: result.getLong(5)
        });
      }
    } finally { result.close(); }
    return attachments;
      } catch (error) {
      throw normalizeError(error);
    }
  }

  async replaceItemAttachments(itemId: string, attachments: VaultAttachmentInput[],
    onProgress?: (completed: number, total: number) => void): Promise<void> {
    try {
    if (attachments.length === 0) { throw new Error('请先选择媒体'); }
    const oldStorageNames = await this.listAttachmentStorageNames(itemId);
    const storedAttachments = await this.storeAttachments(attachments, onProgress);
    const store = this.requireStore();
    try {
      store.beginTransaction();
      await store.executeSql('DELETE FROM vault_item_attachments WHERE item_id = ?', [itemId]);
      for (let index = 0; index < attachments.length; index += 1) {
        const attachment = attachments[index];
        await store.insert('vault_item_attachments', {
          item_id: itemId,
          attachment_index: index,
          type: attachment.type,
          name: attachment.name,
          source_uri: attachment.sourceUri ? attachment.sourceUri : attachment.uri,
          ocr_text: attachment.ocrText,
          storage_name: storedAttachments[index].storageName,
          size_bytes: storedAttachments[index].sizeBytes
        });
      }
      await store.executeSql('UPDATE vault_items SET type = ?, updated_at = ? WHERE id = ?',
        [VaultItemType.Image, Date.now(), itemId]);
      await this.refreshItemOcrText(itemId);
      store.commit();
      this.deleteStoredAttachments(oldStorageNames);
    } catch (error) {
      store.rollBack();
      this.deleteStoredAttachments(storedAttachments.map((item: StoredAttachment): string => item.storageName));
      throw new Error(`媒体修改失败：${normalizeError(error).message}`);
    }
      } catch (error) {
      throw normalizeError(error);
    }
  }

  async appendItemAttachments(itemId: string, attachments: VaultAttachmentInput[],
    onProgress?: (completed: number, total: number) => void): Promise<void> {
    try {
    if (attachments.length === 0) { return; }
    const existing = await this.listItemAttachments(itemId);
    const startIndex = existing.length > 0 ? existing[existing.length - 1].index + 1 : 0;
    const storedAttachments = await this.storeAttachments(attachments, onProgress);
    const store = this.requireStore();
    try {
      store.beginTransaction();
      for (let index = 0; index < attachments.length; index += 1) {
        const attachment = attachments[index];
        const attachmentIndex = startIndex + index;
        await store.insert('vault_item_attachments', {
          item_id: itemId,
          attachment_index: attachmentIndex,
          type: attachment.type,
          name: attachment.name,
          source_uri: attachment.sourceUri ? attachment.sourceUri : attachment.uri,
          ocr_text: attachment.ocrText,
          storage_name: storedAttachments[index].storageName,
          size_bytes: storedAttachments[index].sizeBytes
        });
      }
      await store.executeSql('UPDATE vault_items SET updated_at = ? WHERE id = ?', [Date.now(), itemId]);
      await this.refreshItemOcrText(itemId);
      store.commit();
    } catch (error) {
      store.rollBack();
      this.deleteStoredAttachments(storedAttachments.map((item: StoredAttachment): string => item.storageName));
      throw new Error(`附件导入失败：${normalizeError(error).message}`);
    }
      } catch (error) {
      throw normalizeError(error);
    }
  }

  async updateAttachmentSourceUri(itemId: string, attachmentIndex: number, sourceUri: string): Promise<void> {
    try {
    await this.requireStore().executeSql(
      'UPDATE vault_item_attachments SET source_uri = ? WHERE item_id = ? AND attachment_index = ?',
      [sourceUri, itemId, attachmentIndex]
    );
      } catch (error) {
      throw normalizeError(error);
    }
  }

  async deleteItemAttachments(itemId: string, attachmentIndexes: number[]): Promise<void> {
    try {
    if (attachmentIndexes.length === 0) { return; }
    const existing = await this.listItemAttachments(itemId);
    const selected = new Set<number>(attachmentIndexes);
    const remaining = existing.filter((attachment: VaultAttachmentSummary): boolean => !selected.has(attachment.index));
    if (remaining.length === 0) { throw new Error('至少需要保留一个附件'); }
    const store = this.requireStore();
    const storageNames: string[] = [];
    for (let index = 0; index < attachmentIndexes.length; index += 1) {
      const pathResult = await store.querySql(
        'SELECT storage_name FROM vault_item_attachments WHERE item_id = ? AND attachment_index = ?',
        [itemId, attachmentIndexes[index]]);
      try { if (pathResult.goToFirstRow()) { storageNames.push(pathResult.getString(0)); } } finally { pathResult.close(); }
    }
    store.beginTransaction();
    try {
      for (let index = 0; index < attachmentIndexes.length; index += 1) {
        const attachmentIndex = attachmentIndexes[index];
        await store.executeSql(
          'DELETE FROM vault_item_attachments WHERE item_id = ? AND attachment_index = ?',
          [itemId, attachmentIndex]
        );
      }
      await store.executeSql(
        'UPDATE vault_item_attachments SET attachment_index = -attachment_index - 1 WHERE item_id = ?', [itemId]
      );
      for (let index = 0; index < remaining.length; index += 1) {
        const temporaryIndex = -remaining[index].index - 1;
        await store.executeSql(
          'UPDATE vault_item_attachments SET attachment_index = ? WHERE item_id = ? AND attachment_index = ?',
          [index, itemId, temporaryIndex]
        );
      }
      await store.executeSql('UPDATE vault_items SET updated_at = ? WHERE id = ?', [Date.now(), itemId]);
      await this.refreshItemOcrText(itemId);
      store.commit();
      this.deleteStoredAttachments(storageNames);
    } catch (error) {
      store.rollBack();
      throw new Error('删除附件失败，数据未更改');
    }
      } catch (error) {
      throw normalizeError(error);
    }
  }

  async updateItem(item: VaultItem): Promise<void> {
    try {
    this.validateItemFields(item.type, item.title, item.username, item.password, item.notes);
    const values: relationalStore.ValuesBucket = {
      type: item.type,
      group_id: item.groupId,
      title: item.title.trim(),
      username: item.username.trim(),
      password: item.password,
      notes: item.notes,
      updated_at: Date.now()
    };
    const predicates = new relationalStore.RdbPredicates('vault_items');
    predicates.equalTo('id', item.id);
    await this.requireStore().update(values, predicates);
      } catch (error) {
      throw normalizeError(error);
    }
  }

  async moveToTrash(id: string): Promise<void> {
    try {
    await this.requireStore().executeSql(
      'UPDATE vault_items SET deleted_at = ?, updated_at = ? WHERE id = ?',
      [Date.now(), Date.now(), id]
    );
      } catch (error) {
      throw normalizeError(error);
    }
  }

  async restoreFromTrash(id: string): Promise<void> {
    try {
    await this.restoreTrashItems([id]);
      } catch (error) {
      throw normalizeError(error);
    }
  }

  async restoreTrashItems(ids: string[]): Promise<void> {
    try {
    if (ids.length === 0) { return; }
    const store = this.requireStore();
    store.beginTransaction();
    try {
      for (let index = 0; index < ids.length; index += 1) {
        const id = ids[index];
        const itemResult = await store.querySql(
          'SELECT group_id FROM vault_items WHERE id = ? AND deleted_at > 0', [id]);
        let groupId = 0;
        let exists = false;
        try {
          if (itemResult.goToFirstRow()) {
            exists = true;
            groupId = itemResult.getLong(0);
          }
        } finally { itemResult.close(); }
        if (!exists) { continue; }
        if (groupId > 0) {
          const groupResult = await store.querySql('SELECT id FROM vault_groups WHERE id = ?', [groupId]);
          let groupExists = false;
          try { groupExists = groupResult.goToFirstRow(); } finally { groupResult.close(); }
          if (!groupExists) { groupId = await this.restoreDeletedGroup(store, groupId); }
        }
        await store.executeSql(
          'UPDATE vault_items SET group_id = ?, deleted_at = 0, updated_at = ? WHERE id = ?',
          [groupId, Date.now(), id]
        );
      }
      await store.executeSql(
        'DELETE FROM vault_group_tombstones WHERE group_id NOT IN ' +
        '(SELECT DISTINCT group_id FROM vault_items WHERE deleted_at > 0)'
      );
      store.commit();
    } catch (error) {
      store.rollBack();
      throw new Error('批量恢复失败，数据未更改');
    }
      } catch (error) {
      throw normalizeError(error);
    }
  }

  async permanentlyDelete(id: string): Promise<void> {
    try {
    await this.permanentlyDeleteItems([id]);
      } catch (error) {
      throw normalizeError(error);
    }
  }

  async permanentlyDeleteItems(ids: string[]): Promise<void> {
    try {
    if (ids.length === 0) { return; }
    const store = this.requireStore();
    const storageNames: string[] = [];
    store.beginTransaction();
    try {
      for (let index = 0; index < ids.length; index += 1) {
        const deletedNames = await this.permanentlyDeleteTrashItem(store, ids[index]);
        storageNames.push(...deletedNames);
      }
      await store.executeSql(
        'DELETE FROM vault_group_tombstones WHERE group_id NOT IN ' +
        '(SELECT DISTINCT group_id FROM vault_items WHERE deleted_at > 0)'
      );
      store.commit();
      this.deleteStoredAttachments(storageNames);
    } catch (error) {
      store.rollBack();
      throw new Error('永久删除失败，数据未更改');
    }
      } catch (error) {
      throw normalizeError(error);
    }
  }

  async emptyTrash(): Promise<void> {
    try {
    const store = this.requireStore();
    const storageNames: string[] = [];
    store.beginTransaction();
    try {
      const result = await store.querySql('SELECT id FROM vault_items WHERE deleted_at > 0');
      const ids: string[] = [];
      try { while (result.goToNextRow()) { ids.push(result.getString(0)); } } finally { result.close(); }
      for (let index = 0; index < ids.length; index += 1) {
        const deletedNames = await this.permanentlyDeleteTrashItem(store, ids[index]);
        storageNames.push(...deletedNames);
      }
      await store.executeSql('DELETE FROM vault_group_tombstones');
      store.commit();
      this.deleteStoredAttachments(storageNames);
    } catch (error) {
      store.rollBack();
      throw new Error('清空回收站失败，数据未更改');
    }
      } catch (error) {
      throw normalizeError(error);
    }
  }

  async exportBackupDataset(): Promise<VaultBackupDataset> {
    try {
      const store = this.requireStore();
      const groups: BackupGroupRecord[] = [];
      const groupResult = await store.querySql(
        'SELECT id, name, color, created_at, sort_order FROM vault_groups ORDER BY sort_order ASC');
      try {
        while (groupResult.goToNextRow()) {
          groups.push({ id: groupResult.getLong(0), name: groupResult.getString(1),
            color: groupResult.getString(2), createdAt: groupResult.getLong(3), sortOrder: groupResult.getLong(4) });
        }
      } finally { groupResult.close(); }

      const items: BackupItemRecord[] = [];
      const itemResult = await store.querySql(
        'SELECT id, type, group_id, title, username, password, notes, ocr_text, created_at, updated_at, deleted_at ' +
        'FROM vault_items WHERE deleted_at = 0 ORDER BY created_at ASC');
      try {
        while (itemResult.goToNextRow()) {
          items.push({ id: itemResult.getString(0), type: itemResult.getString(1) as VaultItemType,
            groupId: itemResult.getLong(2), title: itemResult.getString(3), username: itemResult.getString(4),
            password: itemResult.getString(5), notes: itemResult.getString(6), ocrText: itemResult.getString(7),
            createdAt: itemResult.getLong(8), updatedAt: itemResult.getLong(9), deletedAt: itemResult.getLong(10) });
        }
      } finally { itemResult.close(); }

      const attachments: BackupAttachmentRecord[] = [];
      const attachmentResult = await store.querySql(
        'SELECT a.item_id, a.attachment_index, a.type, a.name, a.ocr_text, a.storage_name, a.size_bytes ' +
        'FROM vault_item_attachments a INNER JOIN vault_items i ON i.id = a.item_id ' +
        'WHERE i.deleted_at = 0 ORDER BY a.item_id, a.attachment_index');
      try {
        while (attachmentResult.goToNextRow()) {
          attachments.push({ itemId: attachmentResult.getString(0), attachmentIndex: attachmentResult.getLong(1),
            type: attachmentResult.getString(2) as VaultItemType, name: attachmentResult.getString(3),
            ocrText: attachmentResult.getString(4), storageName: attachmentResult.getString(5),
            sizeBytes: attachmentResult.getLong(6), sha256: '' });
        }
      } finally { attachmentResult.close(); }

      // Backups intentionally contain active user data only. Trash entries and
      // deletion tombstones must not be able to delete data during a later merge.
      const groupTombstones: BackupGroupTombstoneRecord[] = [];
      const itemTombstones: BackupItemTombstoneRecord[] = [];
      return { groups: groups, items: items, attachments: attachments,
        groupTombstones: groupTombstones, itemTombstones: itemTombstones };
    } catch (error) {
      throw normalizeError(error);
    }
  }

  backupAttachmentPath(storageName: string): string {
    return this.storedAttachmentPath(storageName);
  }

  async previewBackupRestore(dataset: VaultBackupDataset): Promise<BackupRestorePreview> {
    const comparison = await this.buildBackupComparisonContext(dataset);
    return this.backupRestorePreview(dataset, comparison);
  }

  private backupRestorePreview(dataset: VaultBackupDataset,
    comparison: BackupComparisonContext): BackupRestorePreview {
    const currentItems = comparison.currentItems;
    let addedCount = 0;
    let updatedCount = 0;
    let retainedCount = 0;
    let newerCount = 0;
    let conflictCount = 0;
    let unchangedCount = 0;
    let deletedCount = 0;
    for (let index = 0; index < dataset.items.length; index += 1) {
      const incoming = dataset.items[index];
      const current = currentItems.get(incoming.id);
      const decision = this.backupMergeDecision(current, incoming, comparison);
      if (decision === BackupMergeDecision.Add) { addedCount += 1; }
      else if (decision === BackupMergeDecision.Update || decision === BackupMergeDecision.RestoreBesideTrash) {
        updatedCount += 1;
      }
      else if (decision === BackupMergeDecision.RetainNewer) { newerCount += 1; }
      else if (decision === BackupMergeDecision.Conflict) { conflictCount += 1; }
      else { unchangedCount += 1; }
    }
    const incomingItemIds = new Set<string>();
    dataset.items.forEach((item: BackupItemRecord): void => { incomingItemIds.add(item.id); });
    currentItems.forEach((item: BackupItemRecord, id: string): void => {
      if (item.deletedAt === 0 && !incomingItemIds.has(id)) { retainedCount += 1; }
    });
    for (let index = 0; index < dataset.itemTombstones.length; index += 1) {
      const tombstone = dataset.itemTombstones[index];
      const current = currentItems.get(tombstone.itemId);
      if (current && tombstone.deletedAt >= current.updatedAt) {
        deletedCount += 1;
        if (!incomingItemIds.has(tombstone.itemId) && retainedCount > 0) {
          retainedCount -= 1;
        }
      }
    }
    const trashCount = dataset.items.filter((item: BackupItemRecord): boolean => item.deletedAt > 0).length;
    let attachmentBytes = 0;
    dataset.attachments.forEach((item: BackupAttachmentRecord): void => { attachmentBytes += item.sizeBytes; });
    return { createdAt: 0, itemCount: dataset.items.length, trashCount: trashCount,
      attachmentCount: dataset.attachments.length, attachmentBytes: attachmentBytes,
      addedCount: addedCount, updatedCount: updatedCount, retainedCount: retainedCount,
      newerCount: newerCount, conflictCount: conflictCount, unchangedCount: unchangedCount,
      deletedCount: deletedCount };
  }

  async applyBackupDataset(dataset: VaultBackupDataset, extractedRoot: string): Promise<BackupRestoreResult> {
    try {
      const store = this.requireStore();
      const comparison = await this.buildBackupComparisonContext(dataset);
      const preview = this.backupRestorePreview(dataset, comparison);
      const currentItems = comparison.currentItems;
      const decisions = new Map<string, BackupMergeDecision>();
      const restoredTargets = new Map<string, string>();
      dataset.items.forEach((incoming: BackupItemRecord): void => {
        const current = currentItems.get(incoming.id);
        const decision = this.backupMergeDecision(current, incoming, comparison);
        decisions.set(incoming.id, decision);
        if (decision === BackupMergeDecision.Add || decision === BackupMergeDecision.Update) {
          restoredTargets.set(incoming.id, incoming.id);
        } else if (decision === BackupMergeDecision.RestoreBesideTrash) {
          restoredTargets.set(incoming.id, this.restoredItemId(incoming,
            comparison.incomingSignatures.get(incoming.id) ?? ''));
        } else if (decision === BackupMergeDecision.Conflict) {
          restoredTargets.set(incoming.id, this.conflictItemId(incoming,
            comparison.incomingSignatures.get(incoming.id) ?? ''));
        }
      });

      const copiedNames: string[] = [];
      const importedAttachmentsByItem = new Map<string, BackupAttachmentRecord[]>();
      try {
        for (let index = 0; index < dataset.attachments.length; index += 1) {
          const attachment = dataset.attachments[index];
          const targetItemId = restoredTargets.get(attachment.itemId);
          if (targetItemId === undefined) { continue; }
          const sourcePath = `${extractedRoot}/${attachment.storageName}`;
          const actualSize = fs.statSync(sourcePath).size;
          if (actualSize !== attachment.sizeBytes) { throw new Error(`附件 ${attachment.name} 不完整`); }
          const newStorageName = `restore-${createVaultId()}-${index}`;
          await this.copyFilePath(sourcePath, this.storedAttachmentPath(newStorageName));
          copiedNames.push(newStorageName);
          const importedAttachment: BackupAttachmentRecord = {
            itemId: targetItemId, attachmentIndex: attachment.attachmentIndex,
            type: attachment.type, name: attachment.name, ocrText: attachment.ocrText,
            storageName: newStorageName, sizeBytes: attachment.sizeBytes, sha256: attachment.sha256
          };
          const itemAttachments = importedAttachmentsByItem.get(targetItemId) ?? [];
          itemAttachments.push(importedAttachment);
          importedAttachmentsByItem.set(targetItemId, itemAttachments);
        }
      } catch (error) {
        this.deleteStoredAttachments(copiedNames);
        throw normalizeError(error);
      }

      const oldStorageNames: string[] = [];
      store.beginTransaction();
      try {
        const groupMap = await this.mergeBackupGroups(store, dataset);
        for (let index = 0; index < dataset.items.length; index += 1) {
          const item = dataset.items[index];
          const targetItemId = restoredTargets.get(item.id);
          if (targetItemId === undefined) { continue; }
          const decision = decisions.get(item.id);
          if (decision === BackupMergeDecision.Update && currentItems.has(item.id)) {
            const oldResult = await store.querySql(
              'SELECT storage_name FROM vault_item_attachments WHERE item_id = ?', [item.id]);
            try { while (oldResult.goToNextRow()) { oldStorageNames.push(oldResult.getString(0)); } }
            finally { oldResult.close(); }
            await store.executeSql('DELETE FROM vault_item_attachments WHERE item_id = ?', [item.id]);
            await store.executeSql('DELETE FROM vault_items WHERE id = ?', [item.id]);
          }
          await store.executeSql('DELETE FROM vault_item_tombstones WHERE item_id = ?', [targetItemId]);
          const mappedGroupId = groupMap.get(item.groupId);
          if (mappedGroupId === undefined) {
            throw new Error(`资料“${item.title}”对应的分组信息缺失`);
          }
          const restoredTitle = decision === BackupMergeDecision.Conflict ? this.conflictTitle(item.title) : item.title;
          await store.insert('vault_items', { id: targetItemId, type: item.type,
            group_id: mappedGroupId,
            title: restoredTitle, username: item.username, password: item.password, notes: item.notes,
            ocr_text: item.ocrText, created_at: item.createdAt, updated_at: item.updatedAt, deleted_at: item.deletedAt });
          const itemAttachments = importedAttachmentsByItem.get(targetItemId) ?? [];
          for (let attachmentIndex = 0; attachmentIndex < itemAttachments.length; attachmentIndex += 1) {
            const attachment = itemAttachments[attachmentIndex];
            await store.insert('vault_item_attachments', { item_id: targetItemId,
              attachment_index: attachment.attachmentIndex, type: attachment.type, name: attachment.name,
              source_uri: '', ocr_text: attachment.ocrText, storage_name: attachment.storageName,
              size_bytes: attachment.sizeBytes });
          }
        }
        // Restore is deliberately non-destructive. Deletion tombstones from old
        // test backups must never remove current active or trash data.
        store.commit();
      } catch (error) {
        store.rollBack();
        this.deleteStoredAttachments(copiedNames);
        throw normalizeError(error);
      }
      // The database transaction is already committed here. Cleanup is best-effort:
      // leftovers are harmless orphans and will be removed the next time the store opens.
      // Never report a committed restore as if the original data were unchanged.
      try {
        this.deleteStoredAttachments(oldStorageNames);
        await this.cleanupOrphanedAttachments();
      } catch (error) {
        console.error(`PalmVault deferred post-restore attachment cleanup: ${normalizeError(error).message}`);
      }
      return { addedCount: preview.addedCount, updatedCount: preview.updatedCount,
        retainedCount: preview.retainedCount, newerCount: preview.newerCount,
        conflictCount: preview.conflictCount, unchangedCount: preview.unchangedCount,
        deletedCount: preview.deletedCount };
    } catch (error) {
      throw new Error(`恢复失败，原有资料未被修改：${normalizeError(error).message}`);
    }
  }

  async readAttachment(id: string, attachmentIndex: number = 0): Promise<Uint8Array> {
    try {
    const stored = await this.getStoredAttachment(id, attachmentIndex);
    if (!stored || stored.sizeBytes <= 0) { return new Uint8Array(0); }
    const data = new Uint8Array(stored.sizeBytes);
    let file: fs.File | undefined = undefined;
    try {
      let offset = 0;
      file = fs.openSync(this.storedAttachmentPath(stored.storageName), fs.OpenMode.READ_ONLY);
      while (offset < stored.sizeBytes) {
        const length = Math.min(1024 * 1024, stored.sizeBytes - offset);
        const chunkBuffer = new ArrayBuffer(length);
        const bytesRead = fs.readSync(file.fd, chunkBuffer, { length: length });
        if (bytesRead <= 0) { throw new Error('附件数据不完整'); }
        const bytes = new Uint8Array(chunkBuffer, 0, bytesRead);
        data.set(bytes, offset);
        bytes.fill(0);
        offset += bytesRead;
      }
      return data;
    } catch (error) {
      data.fill(0);
      throw new Error(`附件读取失败：${normalizeError(error).message}`);
    } finally {
      if (file) { fs.closeSync(file); }
    }
      } catch (error) {
      throw normalizeError(error);
    }
  }

  async writeAttachmentToFd(id: string, targetFd: number, attachmentIndex: number = 0): Promise<number> {
    try {
    const stored = await this.getStoredAttachment(id, attachmentIndex);
    if (!stored) { return 0; }
    let source: fs.File | undefined = undefined;
    let total = 0;
    try {
      source = fs.openSync(this.storedAttachmentPath(stored.storageName), fs.OpenMode.READ_ONLY);
      while (total < stored.sizeBytes) {
        const length = Math.min(1024 * 1024, stored.sizeBytes - total);
        const buffer = new ArrayBuffer(length);
        const bytesRead = fs.readSync(source.fd, buffer, { length: length });
        if (bytesRead <= 0) { throw new Error('附件数据不完整'); }
        const bytes = new Uint8Array(buffer, 0, bytesRead);
        try {
          total += this.writeAllToFd(targetFd, bytes);
        } finally { bytes.fill(0); }
      }
      if (total !== stored.sizeBytes) { throw new Error('附件写入不完整'); }
    } finally {
      if (source) { fs.closeSync(source); }
    }
    return total;
      } catch (error) {
      throw normalizeError(error);
    }
  }

  private writeAllToFd(targetFd: number, bytes: Uint8Array): number {
    try {
    let offset = 0;
    while (offset < bytes.length) {
      const remaining = bytes.slice(offset);
      try {
        const written = fs.writeSync(targetFd, remaining.buffer as ArrayBuffer, { length: remaining.length });
        if (written <= 0) { throw new Error('附件写入失败'); }
        offset += written;
      } finally { remaining.fill(0); }
    }
    return offset;
      } catch (error) {
      throw normalizeError(error);
    }
  }

  private async refreshItemOcrText(itemId: string): Promise<void> {
    try {
    const result = await this.requireStore().querySql(
      'SELECT ocr_text FROM vault_item_attachments WHERE item_id = ? AND type = ? ORDER BY attachment_index ASC',
      [itemId, VaultItemType.Image]
    );
    const values: string[] = [];
    try {
      while (result.goToNextRow()) {
        const value = result.getString(0).trim();
        if (value.length > 0) { values.push(value); }
      }
    } finally { result.close(); }
    await this.requireStore().executeSql('UPDATE vault_items SET ocr_text = ? WHERE id = ?',
      [values.join('\n'), itemId]);
      } catch (error) {
      throw normalizeError(error);
    }
  }

  private async storeAttachments(attachments: VaultAttachmentInput[],
    onProgress?: (completed: number, total: number) => void): Promise<StoredAttachment[]> {
    const stored: StoredAttachment[] = [];
    try {
      for (let index = 0; index < attachments.length; index += 1) {
        stored.push(await this.storeAttachment(attachments[index]));
        if (onProgress) { onProgress(index + 1, attachments.length); }
      }
      return stored;
    } catch (error) {
      this.deleteStoredAttachments(stored.map((item: StoredAttachment): string => item.storageName));
      throw normalizeError(error);
    }
  }

  private async storeAttachment(attachment: VaultAttachmentInput): Promise<StoredAttachment> {
    const storageName = createVaultId();
    const targetPath = this.storedAttachmentPath(storageName);
    let source: fs.File | undefined = undefined;
    let target: fs.File | undefined = undefined;
    let completed = false;
    try {
      source = fs.openSync(attachment.uri, fs.OpenMode.READ_ONLY);
      const size = fs.statSync(source.fd).size;
      if (size <= 0) { throw new Error('所选附件为空'); }
      if (attachment.type === VaultItemType.File && size > MAX_FILE_ATTACHMENT_BYTES) {
        throw new Error(`文件“${attachment.name}”超过 10 MB，请选择较小的文件`);
      }
      target = fs.openSync(targetPath, fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      await fs.copyFile(source.fd, target.fd);
      fs.fsyncSync(target.fd);
      if (fs.statSync(target.fd).size !== size) { throw new Error('附件复制不完整'); }
      completed = true;
      return { storageName: storageName, sizeBytes: size };
    } catch (error) {
      throw normalizeError(error);
    } finally {
      this.closeFile(target);
      this.closeFile(source);
      if (!completed) {
        try { fs.unlinkSync(targetPath); }
        catch (cleanupError) { logRecoverableError('could not remove incomplete attachment', cleanupError); }
      }
    }
  }

  private async listAttachmentStorageNames(itemId: string): Promise<string[]> {
    try {
    const result = await this.requireStore().querySql(
      'SELECT storage_name FROM vault_item_attachments WHERE item_id = ?', [itemId]);
    const names: string[] = [];
    try { while (result.goToNextRow()) { names.push(result.getString(0)); } } finally { result.close(); }
    return names;
    } catch (error) {
      throw normalizeError(error);
    }
  }

  private async getStoredAttachment(itemId: string, attachmentIndex: number): Promise<StoredAttachment | undefined> {
    try {
    const result = await this.requireStore().querySql(
      'SELECT storage_name, size_bytes FROM vault_item_attachments WHERE item_id = ? AND attachment_index = ?',
      [itemId, attachmentIndex]);
    try {
      if (!result.goToFirstRow()) { return undefined; }
      return { storageName: result.getString(0), sizeBytes: result.getLong(1) };
    } finally { result.close(); }
    } catch (error) {
      throw normalizeError(error);
    }
  }

  private storedAttachmentPath(storageName: string): string {
    if (this.attachmentRoot.length === 0 || storageName.length === 0) { throw new Error('附件目录尚未初始化'); }
    return `${this.attachmentRoot}/${storageName}`;
  }

  private ensureAttachmentDirectory(): void {
    let pathExists = false;
    try {
      const stat = fs.statSync(this.attachmentRoot);
      pathExists = true;
      if (stat.isDirectory()) { return; }
    } catch (error) {
      logRecoverableError('attachment directory does not exist yet', error);
    }
    if (pathExists) { throw new Error('附件存储路径不是目录'); }
    try {
      fs.mkdirSync(this.attachmentRoot, true);
    } catch (error) {
      // Another initialization may have created the directory between stat and mkdir.
      try {
        if (fs.statSync(this.attachmentRoot).isDirectory()) { return; }
      } catch (validationError) {
        logRecoverableError('could not validate attachment directory after creation failure', validationError);
      }
      throw normalizeError(error);
    }
  }

  private deleteStoredAttachments(storageNames: string[]): void {
    storageNames.forEach((storageName: string): void => {
      try { fs.unlinkSync(this.storedAttachmentPath(storageName)); }
      catch (error) { logRecoverableError(`could not delete attachment ${storageName}`, error); }
    });
  }

  private closeFile(file?: fs.File): void {
    if (!file) { return; }
    try { fs.closeSync(file); }
    catch (error) { logRecoverableError('could not close attachment file', error); }
  }

  private deleteAttachmentDirectory(): void {
    if (this.attachmentRoot.length === 0) { return; }
    try {
      const names = fs.listFileSync(this.attachmentRoot);
      this.deleteStoredAttachments(names);
      fs.rmdirSync(this.attachmentRoot);
    } catch (error) {
      logRecoverableError('could not delete attachment directory', error);
    }
    this.attachmentRoot = '';
  }

  private async cleanupOrphanedAttachments(): Promise<void> {
    try {
    const referenced = new Set<string>();
    const result = await this.requireStore().querySql('SELECT storage_name FROM vault_item_attachments');
    try { while (result.goToNextRow()) { referenced.add(result.getString(0)); } } finally { result.close(); }
    const names = fs.listFileSync(this.attachmentRoot);
    names.forEach((name: string): void => {
      if (!referenced.has(name)) {
        try { fs.unlinkSync(this.storedAttachmentPath(name)); }
        catch (error) { logRecoverableError(`could not delete orphan attachment ${name}`, error); }
      }
    });
    } catch (error) {
      throw normalizeError(error);
    }
  }

  private async restoreDeletedGroup(store: relationalStore.RdbStore, deletedGroupId: number): Promise<number> {
    try {
    const tombstone = await store.querySql(
      'SELECT name, color, created_at FROM vault_group_tombstones WHERE group_id = ?',
      [deletedGroupId]
    );
    let name = '';
    let color = '#67E8C5';
    let createdAt = Date.now();
    try {
      if (!tombstone.goToFirstRow()) {
        return 0;
      }
      name = tombstone.getString(0);
      color = tombstone.getString(1);
      createdAt = tombstone.getLong(2);
    } finally {
      tombstone.close();
    }
    const sameName = await store.querySql('SELECT id FROM vault_groups WHERE name = ?', [name]);
    try {
      if (sameName.goToFirstRow()) {
        return sameName.getLong(0);
      }
    } finally {
      sameName.close();
    }
    const orderResult = await store.querySql('SELECT COALESCE(MAX(sort_order), -1) + 1 FROM vault_groups');
    let sortOrder = 0;
    try { if (orderResult.goToFirstRow()) { sortOrder = orderResult.getLong(0); } } finally { orderResult.close(); }
    await store.executeSql(
      'INSERT INTO vault_groups (id, name, color, created_at, sort_order) VALUES (?, ?, ?, ?, ?)',
      [deletedGroupId, name, color, createdAt, sortOrder]
    );
    await store.executeSql('DELETE FROM vault_group_tombstones WHERE group_id = ?', [deletedGroupId]);
    return deletedGroupId;
      } catch (error) {
      throw normalizeError(error);
    }
  }

  private async permanentlyDeleteTrashItem(store: relationalStore.RdbStore, id: string): Promise<string[]> {
    try {
    const result = await store.querySql('SELECT id FROM vault_items WHERE id = ? AND deleted_at > 0', [id]);
    let exists = false;
    try { exists = result.goToFirstRow(); } finally { result.close(); }
    if (!exists) { return []; }
    const pathResult = await store.querySql(
      'SELECT storage_name FROM vault_item_attachments WHERE item_id = ?', [id]);
    const storageNames: string[] = [];
    try { while (pathResult.goToNextRow()) { storageNames.push(pathResult.getString(0)); } } finally { pathResult.close(); }
    await store.executeSql(
      'INSERT OR REPLACE INTO vault_item_tombstones (item_id, deleted_at) VALUES (?, ?)', [id, Date.now()]);
    await store.executeSql('DELETE FROM vault_item_attachments WHERE item_id = ?', [id]);
    await store.executeSql('DELETE FROM vault_items WHERE id = ?', [id]);
    return storageNames;
      } catch (error) {
      throw normalizeError(error);
    }
  }

  private async seedGroups(): Promise<void> {
    try {
    const result = await this.requireStore().querySql('SELECT COUNT(*) AS count_value FROM vault_groups');
    let count: number = 0;
    try {
      if (result.goToFirstRow()) {
        count = result.getLong(result.getColumnIndex('count_value'));
      }
    } finally {
      result.close();
    }
    if (count > 0) {
      return;
    }
    await this.createGroup('账号密码', '#67E8C5');
    await this.createGroup('个人信息', '#75D7FF');
    await this.createGroup('家庭资料', '#F3C969');
      } catch (error) {
      throw normalizeError(error);
    }
  }

  private async currentItemsById(): Promise<Map<string, BackupItemRecord>> {
    try {
    const items = new Map<string, BackupItemRecord>();
    const result = await this.requireStore().querySql(
      'SELECT id, type, group_id, title, username, password, notes, ocr_text, created_at, updated_at, deleted_at ' +
      'FROM vault_items');
    try {
      while (result.goToNextRow()) {
        const item: BackupItemRecord = { id: result.getString(0), type: result.getString(1) as VaultItemType,
          groupId: result.getLong(2), title: result.getString(3), username: result.getString(4),
          password: result.getString(5), notes: result.getString(6), ocrText: result.getString(7),
          createdAt: result.getLong(8), updatedAt: result.getLong(9), deletedAt: result.getLong(10) };
        items.set(item.id, item);
      }
    } finally { result.close(); }
    return items;
    } catch (error) {
      throw normalizeError(error);
    }
  }

  private backupMergeDecision(current: BackupItemRecord | undefined, incoming: BackupItemRecord,
    comparison: BackupComparisonContext): BackupMergeDecision {
    if (!current) { return BackupMergeDecision.Add; }
    const incomingSignature = comparison.incomingSignatures.get(incoming.id) ?? '';
    if (incoming.deletedAt === 0 && current.deletedAt > 0) {
      const restoredId = this.restoredItemId(incoming, incomingSignature);
      const restored = comparison.currentItems.get(restoredId);
      return restored && comparison.currentSignatures.get(restoredId) === incomingSignature ?
        BackupMergeDecision.Unchanged : BackupMergeDecision.RestoreBesideTrash;
    }
    if (incoming.deletedAt > 0 && current.deletedAt === 0) { return BackupMergeDecision.RetainNewer; }
    if (comparison.currentSignatures.get(current.id) === incomingSignature) {
      return BackupMergeDecision.Unchanged;
    }
    if (incoming.updatedAt > current.updatedAt) { return BackupMergeDecision.Update; }
    if (current.updatedAt > incoming.updatedAt) { return BackupMergeDecision.RetainNewer; }
    const conflictId = this.conflictItemId(incoming, incomingSignature);
    const existingConflict = comparison.currentItems.get(conflictId);
    if (existingConflict && comparison.currentSignatures.get(conflictId) ===
      comparison.conflictSignatures.get(incoming.id)) {
      return BackupMergeDecision.Unchanged;
    }
    return BackupMergeDecision.Conflict;
  }

  private conflictTitle(title: string): string {
    return title.length > 0 ? `${title}（备份）` : '（备份）';
  }

  private conflictItemId(item: BackupItemRecord, signature: string): string {
    return `backup-${item.id}-${item.updatedAt}-${this.contentHash(signature)}`;
  }

  private restoredItemId(item: BackupItemRecord, signature: string): string {
    return `restored-${item.id}-${item.updatedAt}-${this.contentHash(signature)}`;
  }

  private contentHash(value: string): string {
    let hash = 2166136261;
    for (let index = 0; index < value.length; index += 1) {
      hash ^= value.charCodeAt(index);
      hash = Math.imul(hash, 16777619);
    }
    return (hash >>> 0).toString(16);
  }

  private async buildBackupComparisonContext(dataset: VaultBackupDataset): Promise<BackupComparisonContext> {
    try {
    const currentItems = await this.currentItemsById();
    const currentGroupNames = new Map<number, string>();
    const groupResult = await this.requireStore().querySql('SELECT id, name FROM vault_groups');
    try {
      while (groupResult.goToNextRow()) {
        currentGroupNames.set(groupResult.getLong(0), groupResult.getString(1));
      }
    } finally { groupResult.close(); }

    const incomingGroupNames = new Map<number, string>();
    dataset.groups.forEach((group: BackupGroupRecord): void => {
      incomingGroupNames.set(group.id, group.name);
    });
    const currentAttachmentParts = new Map<string, string>();
    const attachmentResult = await this.requireStore().querySql(
      'SELECT item_id, attachment_index, type, name, ocr_text, storage_name, size_bytes ' +
      'FROM vault_item_attachments ORDER BY item_id, attachment_index');
    try {
      while (attachmentResult.goToNextRow()) {
        const itemId = attachmentResult.getString(0);
        const hash = await this.sha256StoredAttachment(attachmentResult.getString(5));
        const part = this.attachmentSignaturePart(attachmentResult.getLong(1),
          attachmentResult.getString(2), attachmentResult.getString(3), attachmentResult.getString(4),
          attachmentResult.getLong(6), hash);
        currentAttachmentParts.set(itemId, `${currentAttachmentParts.get(itemId) ?? ''}${part}`);
      }
    } finally { attachmentResult.close(); }

    const incomingAttachmentParts = new Map<string, string>();
    dataset.attachments.forEach((attachment: BackupAttachmentRecord): void => {
      const part = this.attachmentSignaturePart(attachment.attachmentIndex, attachment.type, attachment.name,
        attachment.ocrText, attachment.sizeBytes, attachment.sha256);
      incomingAttachmentParts.set(attachment.itemId,
        `${incomingAttachmentParts.get(attachment.itemId) ?? ''}${part}`);
    });

    const currentSignatures = new Map<string, string>();
    currentItems.forEach((item: BackupItemRecord): void => {
      currentSignatures.set(item.id, this.itemSignature(item, currentGroupNames.get(item.groupId) ?? '',
        currentAttachmentParts.get(item.id) ?? '', item.title));
    });
    const incomingSignatures = new Map<string, string>();
    const conflictSignatures = new Map<string, string>();
    dataset.items.forEach((item: BackupItemRecord): void => {
      const groupName = incomingGroupNames.get(item.groupId) ?? '';
      const attachments = incomingAttachmentParts.get(item.id) ?? '';
      incomingSignatures.set(item.id, this.itemSignature(item, groupName, attachments, item.title));
      conflictSignatures.set(item.id,
        this.itemSignature(item, groupName, attachments, this.conflictTitle(item.title)));
    });
    return { currentItems: currentItems, currentSignatures: currentSignatures,
      incomingSignatures: incomingSignatures, conflictSignatures: conflictSignatures };
    } catch (error) {
      throw normalizeError(error);
    }
  }

  private itemSignature(item: BackupItemRecord, groupName: string, attachments: string, title: string): string {
    return this.signatureField(item.type) + this.signatureField(groupName) + this.signatureField(title) +
      this.signatureField(item.username) + this.signatureField(item.password) + this.signatureField(item.notes) +
      this.signatureField(item.ocrText) + this.signatureField(item.deletedAt.toString()) +
      this.signatureField(attachments);
  }

  private attachmentSignaturePart(index: number, type: string, name: string, ocrText: string,
    sizeBytes: number, sha256: string): string {
    return this.signatureField(index.toString()) + this.signatureField(type) + this.signatureField(name) +
      this.signatureField(ocrText) + this.signatureField(sizeBytes.toString()) + this.signatureField(sha256);
  }

  private signatureField(value: string): string {
    return `${value.length}:${value}`;
  }

  private async sha256StoredAttachment(storageName: string): Promise<string> {
    try {
    const digest = cryptoFramework.createMd('SHA256');
    let file: fs.File | undefined = undefined;
    try {
      file = fs.openSync(this.storedAttachmentPath(storageName), fs.OpenMode.READ_ONLY);
      const size = fs.statSync(file.fd).size;
      let offset = 0;
      while (offset < size) {
        const length = Math.min(1024 * 1024, size - offset);
        const buffer = new ArrayBuffer(length);
        const read = fs.readSync(file.fd, buffer, { length: length });
        if (read <= 0) { throw new Error('附件内容校验失败'); }
        await digest.update({ data: new Uint8Array(buffer, 0, read) });
        offset += read;
      }
      const data = (await digest.digest()).data;
      let output = '';
      for (let index = 0; index < data.length; index += 1) {
        output += data[index].toString(16).padStart(2, '0');
      }
      return output;
    } finally {
      if (file) { fs.closeSync(file); }
    }
    } catch (error) {
      throw normalizeError(error);
    }
  }

  private async mergeBackupGroups(store: relationalStore.RdbStore,
    dataset: VaultBackupDataset): Promise<Map<number, number>> {
    try {
    const mapping = new Map<number, number>();
    const names = new Map<string, number>();
    const activeResult = await store.querySql('SELECT id, name FROM vault_groups');
    try { while (activeResult.goToNextRow()) { names.set(activeResult.getString(1), activeResult.getLong(0)); } }
    finally { activeResult.close(); }
    let nextGroupId = 1;
    const maxResult = await store.querySql(
      'SELECT MAX(group_id) FROM (SELECT id AS group_id FROM vault_groups UNION ALL ' +
      'SELECT group_id FROM vault_group_tombstones)');
    try { if (maxResult.goToFirstRow() && !maxResult.isColumnNull(0)) { nextGroupId = maxResult.getLong(0) + 1; } }
    finally { maxResult.close(); }

    for (let index = 0; index < dataset.groups.length; index += 1) {
      const group = dataset.groups[index];
      let targetId = names.get(group.name);
      if (!targetId) {
        targetId = nextGroupId++;
        await store.executeSql(
          'INSERT INTO vault_groups (id, name, color, created_at, sort_order) VALUES (?, ?, ?, ?, ?)',
          [targetId, group.name, group.color, group.createdAt, group.sortOrder]);
        names.set(group.name, targetId);
      }
      mapping.set(group.id, targetId);
    }
    for (let index = 0; index < dataset.groupTombstones.length; index += 1) {
      const tombstone = dataset.groupTombstones[index];
      let targetId = names.get(tombstone.name);
      if (!targetId) {
        const existing = await store.querySql('SELECT group_id FROM vault_group_tombstones WHERE name = ?',
          [tombstone.name]);
        try { if (existing.goToFirstRow()) { targetId = existing.getLong(0); } } finally { existing.close(); }
      }
      if (!targetId) { targetId = nextGroupId++; }
      mapping.set(tombstone.groupId, targetId);
      if (!names.has(tombstone.name)) {
        await store.executeSql(
          'INSERT OR REPLACE INTO vault_group_tombstones (group_id, name, color, created_at, deleted_at) ' +
          'VALUES (?, ?, ?, ?, ?)',
          [targetId, tombstone.name, tombstone.color, tombstone.createdAt, tombstone.deletedAt]);
      }
    }
    return mapping;
    } catch (error) {
      throw normalizeError(error);
    }
  }

  private async copyFilePath(sourcePath: string, targetPath: string): Promise<void> {
    try {
    let source: fs.File | undefined = undefined;
    let target: fs.File | undefined = undefined;
    try {
      source = fs.openSync(sourcePath, fs.OpenMode.READ_ONLY);
      target = fs.openSync(targetPath, fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      await fs.copyFile(source.fd, target.fd);
      fs.fsyncSync(target.fd);
    } finally {
      this.closeFile(target);
      this.closeFile(source);
    }
    } catch (error) {
      throw normalizeError(error);
    }
  }

  private readItem(result: relationalStore.ResultSet): VaultItem {
    try {
    return {
      id: result.getString(result.getColumnIndex('id')),
      type: result.getString(result.getColumnIndex('type')) as VaultItemType,
      groupId: result.getLong(result.getColumnIndex('group_id')),
      title: result.getString(result.getColumnIndex('title')),
      username: result.getString(result.getColumnIndex('username')),
      password: result.getString(result.getColumnIndex('password')),
      notes: result.getString(result.getColumnIndex('notes')),
      ocrText: result.getString(result.getColumnIndex('ocr_text')),
      createdAt: result.getLong(result.getColumnIndex('created_at')),
      updatedAt: result.getLong(result.getColumnIndex('updated_at')),
      deletedAt: result.getLong(result.getColumnIndex('deleted_at'))
    };
      } catch (error) {
      throw normalizeError(error);
    }
  }

  private requireStore(): relationalStore.RdbStore {
    if (!this.store) {
      throw new Error('保险库尚未解锁');
    }
    return this.store;
  }
}

export const vaultRepository = new VaultRepositoryImpl();
