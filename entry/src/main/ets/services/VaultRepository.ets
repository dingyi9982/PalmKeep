import relationalStore from '@ohos.data.relationalStore';
import common from '@ohos.app.ability.common';
import {
  createVaultId,
  VaultGroup,
  VaultItem,
  VaultItemInput,
  VaultItemType
} from '../models/VaultModels';

const DEVELOPMENT_DATABASE_NAME: string = 'palmvault-development-plain.db';

class VaultRepositoryImpl {
  private store?: relationalStore.RdbStore;

  async open(context: common.UIAbilityContext, databaseKey: Uint8Array): Promise<void> {
    if (this.store) {
      databaseKey.fill(0);
      return;
    }
    databaseKey.fill(0);
    const config: relationalStore.StoreConfig = {
      name: DEVELOPMENT_DATABASE_NAME,
      securityLevel: relationalStore.SecurityLevel.S4,
      encrypt: false
    };
    this.store = await relationalStore.getRdbStore(context, config);
    await this.createSchema();
    await this.seedGroups();
  }

  async close(): Promise<void> {
    const current = this.store;
    this.store = undefined;
    if (current) {
      await current.close();
    }
  }

  async listGroups(): Promise<VaultGroup[]> {
    const result = await this.requireStore().querySql(
      'SELECT id, name, color, created_at FROM vault_groups ORDER BY created_at ASC'
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
  }

  async createGroup(name: string, color: string): Promise<number> {
    const cleanName = name.trim();
    if (cleanName.length === 0) {
      throw new Error('分组名称不能为空');
    }
    const values: relationalStore.ValuesBucket = {
      name: cleanName,
      color: color,
      created_at: Date.now()
    };
    return this.requireStore().insert('vault_groups', values);
  }

  async updateGroup(id: number, name: string, color: string): Promise<void> {
    const values: relationalStore.ValuesBucket = { name: name.trim(), color: color };
    const predicates = new relationalStore.RdbPredicates('vault_groups');
    predicates.equalTo('id', id);
    await this.requireStore().update(values, predicates);
  }

  async deleteGroup(id: number): Promise<void> {
    await this.requireStore().executeSql('UPDATE vault_items SET group_id = 0 WHERE group_id = ?', [id]);
    const predicates = new relationalStore.RdbPredicates('vault_groups');
    predicates.equalTo('id', id);
    await this.requireStore().delete(predicates);
  }

  async listItems(search: string = '', groupId: number = -1, includeDeleted: boolean = false): Promise<VaultItem[]> {
    let sql = 'SELECT id, type, group_id, title, username, password, notes, attachment_uri, ocr_text, created_at, updated_at, deleted_at FROM vault_items WHERE 1 = 1';
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
      sql += ' AND (title LIKE ? OR username LIKE ? OR notes LIKE ? OR ocr_text LIKE ?)';
      const pattern = `%${cleanSearch}%`;
      args.push(pattern, pattern, pattern, pattern);
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
  }

  async createItem(input: VaultItemInput): Promise<string> {
    if (input.title.trim().length === 0) {
      throw new Error('项目名称不能为空');
    }
    if ((input.type === VaultItemType.Image || input.type === VaultItemType.Video || input.type === VaultItemType.File) &&
      input.attachmentData.length === 0) {
      throw new Error('请先选择要保存的文件');
    }
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
      attachment_uri: input.attachmentUri,
      attachment_data: input.attachmentData,
      ocr_text: '',
      created_at: now,
      updated_at: now,
      deleted_at: 0
    };
    await this.requireStore().insert('vault_items', values);
    return id;
  }

  async updateItem(item: VaultItem): Promise<void> {
    if (item.title.trim().length === 0) { throw new Error('项目名称不能为空'); }
    await this.saveHistory(item.id);
    const values: relationalStore.ValuesBucket = {
      type: item.type,
      group_id: item.groupId,
      title: item.title.trim(),
      username: item.username.trim(),
      password: item.password,
      notes: item.notes,
      attachment_uri: item.attachmentUri,
      ocr_text: item.ocrText,
      updated_at: Date.now()
    };
    const predicates = new relationalStore.RdbPredicates('vault_items');
    predicates.equalTo('id', item.id);
    await this.requireStore().update(values, predicates);
  }

  async moveToTrash(id: string): Promise<void> {
    await this.requireStore().executeSql(
      'UPDATE vault_items SET deleted_at = ?, updated_at = ? WHERE id = ?',
      [Date.now(), Date.now(), id]
    );
  }

  async restoreFromTrash(id: string): Promise<void> {
    await this.requireStore().executeSql(
      'UPDATE vault_items SET deleted_at = 0, updated_at = ? WHERE id = ?',
      [Date.now(), id]
    );
  }

  async permanentlyDelete(id: string): Promise<void> {
    const store = this.requireStore();
    await store.executeSql('DELETE FROM vault_item_history WHERE item_id = ?', [id]);
    await store.executeSql('DELETE FROM vault_items WHERE id = ?', [id]);
  }

  async readAttachment(id: string): Promise<Uint8Array> {
    const store = this.requireStore();
    const result = await store.querySql('SELECT length(attachment_data) AS size FROM vault_items WHERE id = ? AND deleted_at = 0', [id]);
    let size = 0;
    try { if (result.goToFirstRow()) { size = result.getLong(0); } } finally { result.close(); }
    if (size <= 0) { return new Uint8Array(0); }
    const data = new Uint8Array(size);
    try {
      for (let offset = 0; offset < size; offset += 512 * 1024) {
        const chunk = await store.querySql('SELECT substr(attachment_data, ?, ?) FROM vault_items WHERE id = ? AND deleted_at = 0', [offset + 1, 512 * 1024, id]);
        try {
          if (!chunk.goToFirstRow()) { throw new Error('附件已不可用'); }
          const bytes = chunk.getBlob(0);
          data.set(bytes, offset);
          bytes.fill(0);
        } finally { chunk.close(); }
      }
      return data;
    } catch (error) { data.fill(0); throw new Error('附件读取失败，请重新解锁后再试'); }
  }

  private async createSchema(): Promise<void> {
    const store = this.requireStore();
    await store.executeSql('CREATE TABLE IF NOT EXISTS vault_groups (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE, color TEXT NOT NULL, created_at INTEGER NOT NULL)');
    await store.executeSql('CREATE TABLE IF NOT EXISTS vault_items (id TEXT PRIMARY KEY, type TEXT NOT NULL, group_id INTEGER NOT NULL DEFAULT 0, title TEXT NOT NULL, username TEXT NOT NULL DEFAULT \'\', password TEXT NOT NULL DEFAULT \'\', notes TEXT NOT NULL DEFAULT \'\', attachment_uri TEXT NOT NULL DEFAULT \'\', attachment_data BLOB NOT NULL DEFAULT X\'\', ocr_text TEXT NOT NULL DEFAULT \'\', created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, deleted_at INTEGER NOT NULL DEFAULT 0)');
    await store.executeSql('CREATE TABLE IF NOT EXISTS vault_item_history (id INTEGER PRIMARY KEY AUTOINCREMENT, item_id TEXT NOT NULL, snapshot TEXT NOT NULL, created_at INTEGER NOT NULL)');
    await store.executeSql('CREATE INDEX IF NOT EXISTS idx_vault_items_group ON vault_items(group_id, deleted_at, updated_at)');
  }

  private async seedGroups(): Promise<void> {
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
  }

  private async saveHistory(id: string): Promise<void> {
    const result = await this.requireStore().querySql(
      'SELECT type, group_id, title, username, password, notes, attachment_uri, ocr_text, updated_at FROM vault_items WHERE id = ?',
      [id]
    );
    try {
      if (!result.goToFirstRow()) {
        return;
      }
      const snapshot = JSON.stringify({
        type: result.getString(result.getColumnIndex('type')),
        groupId: result.getLong(result.getColumnIndex('group_id')),
        title: result.getString(result.getColumnIndex('title')),
        username: result.getString(result.getColumnIndex('username')),
        password: result.getString(result.getColumnIndex('password')),
        notes: result.getString(result.getColumnIndex('notes')),
        attachmentUri: result.getString(result.getColumnIndex('attachment_uri')),
        ocrText: result.getString(result.getColumnIndex('ocr_text')),
        updatedAt: result.getLong(result.getColumnIndex('updated_at'))
      });
      await this.requireStore().insert('vault_item_history', {
        item_id: id,
        snapshot: snapshot,
        created_at: Date.now()
      });
    } finally {
      result.close();
    }
  }

  private readItem(result: relationalStore.ResultSet): VaultItem {
    return {
      id: result.getString(result.getColumnIndex('id')),
      type: result.getString(result.getColumnIndex('type')) as VaultItemType,
      groupId: result.getLong(result.getColumnIndex('group_id')),
      title: result.getString(result.getColumnIndex('title')),
      username: result.getString(result.getColumnIndex('username')),
      password: result.getString(result.getColumnIndex('password')),
      notes: result.getString(result.getColumnIndex('notes')),
      attachmentUri: result.getString(result.getColumnIndex('attachment_uri')),
      ocrText: result.getString(result.getColumnIndex('ocr_text')),
      createdAt: result.getLong(result.getColumnIndex('created_at')),
      updatedAt: result.getLong(result.getColumnIndex('updated_at')),
      deletedAt: result.getLong(result.getColumnIndex('deleted_at'))
    };
  }

  private requireStore(): relationalStore.RdbStore {
    if (!this.store) {
      throw new Error('保险库尚未解锁');
    }
    return this.store;
  }
}

export const vaultRepository = new VaultRepositoryImpl();
