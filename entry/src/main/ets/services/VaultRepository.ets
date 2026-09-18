import relationalStore from '@ohos.data.relationalStore';
import common from '@ohos.app.ability.common';
import fs from '@ohos.file.fs';
import {
  createVaultId,
  VaultAttachmentInput,
  VaultAttachmentSummary,
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
    const store = this.requireStore();
    store.beginTransaction();
    try {
      await store.executeSql(
        'INSERT OR REPLACE INTO vault_group_tombstones (group_id, name, color, created_at, deleted_at) ' +
        'SELECT id, name, color, created_at, ? FROM vault_groups WHERE id = ?',
        [Date.now(), id]
      );
      await store.executeSql(
        'DELETE FROM vault_item_history WHERE item_id IN ' +
        '(SELECT id FROM vault_items WHERE group_id = ? AND deleted_at = 0)',
        [id]
      );
      await store.executeSql(
        'DELETE FROM vault_attachment_chunks WHERE item_id IN ' +
        '(SELECT id FROM vault_items WHERE group_id = ? AND deleted_at = 0)',
        [id]
      );
      await store.executeSql(
        'DELETE FROM vault_attachment_parts WHERE item_id IN ' +
        '(SELECT id FROM vault_items WHERE group_id = ? AND deleted_at = 0)', [id]
      );
      await store.executeSql(
        'DELETE FROM vault_item_attachments WHERE item_id IN ' +
        '(SELECT id FROM vault_items WHERE group_id = ? AND deleted_at = 0)', [id]
      );
      await store.executeSql('DELETE FROM vault_items WHERE group_id = ? AND deleted_at = 0', [id]);
      await store.executeSql('DELETE FROM vault_groups WHERE id = ?', [id]);
      store.commit();
    } catch (error) {
      store.rollBack();
      throw new Error('删除分组失败，数据未更改');
    }
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
    if (input.title.trim().length === 0 && input.type !== VaultItemType.Image && input.type !== VaultItemType.Video) {
      throw new Error('名称不能为空');
    }
    if ((input.type === VaultItemType.Image || input.type === VaultItemType.Video || input.type === VaultItemType.File) &&
      input.attachmentData.length === 0 && input.attachmentUri.length === 0) {
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
    if (input.attachmentData.length === 0 && input.attachmentUri.length > 0 &&
      (input.type === VaultItemType.Image || input.type === VaultItemType.Video || input.type === VaultItemType.File)) {
      await this.importAttachmentChunks(id, input.attachmentUri);
    }
    return id;
  }

  async createItems(inputs: VaultItemInput[]): Promise<void> {
    if (inputs.length === 0) {
      return;
    }
    const store = this.requireStore();
    store.beginTransaction();
    try {
      for (let index = 0; index < inputs.length; index += 1) {
        await this.createItem(inputs[index]);
      }
      store.commit();
    } catch (error) {
      store.rollBack();
      throw new Error('批量导入失败，未保存任何媒体');
    }
  }

  async createItemWithAttachments(input: VaultItemInput, attachments: VaultAttachmentInput[],
    onProgress?: (completed: number, total: number) => void): Promise<void> {
    if (attachments.length === 0) { throw new Error('请先选择附件'); }
    const store = this.requireStore();
    store.beginTransaction();
    try {
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
        attachment_uri: '',
        attachment_data: new Uint8Array(0),
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
          source_uri: attachment.sourceUri ? attachment.sourceUri : attachment.uri
        });
        await this.importAttachmentParts(id, index, attachment.uri);
        if (onProgress) { onProgress(index + 1, attachments.length); }
      }
      store.commit();
    } catch (error) {
      store.rollBack();
      throw new Error('资料保存失败，未写入任何附件');
    }
  }

  async listItemAttachments(itemId: string): Promise<VaultAttachmentSummary[]> {
    const result = await this.requireStore().querySql(
      'SELECT attachment_index, type, name, source_uri FROM vault_item_attachments WHERE item_id = ? ORDER BY attachment_index ASC',
      [itemId]
    );
    const attachments: VaultAttachmentSummary[] = [];
    try {
      while (result.goToNextRow()) {
        attachments.push({
          index: result.getLong(0),
          type: result.getString(1) as VaultItemType,
          name: result.getString(2),
          sourceUri: result.getString(3)
        });
      }
    } finally { result.close(); }
    return attachments;
  }

  async replaceItemAttachments(itemId: string, attachments: VaultAttachmentInput[],
    onProgress?: (completed: number, total: number) => void): Promise<void> {
    if (attachments.length === 0) { throw new Error('请先选择媒体'); }
    const store = this.requireStore();
    store.beginTransaction();
    try {
      await store.executeSql('DELETE FROM vault_attachment_parts WHERE item_id = ?', [itemId]);
      await store.executeSql('DELETE FROM vault_item_attachments WHERE item_id = ?', [itemId]);
      await store.executeSql('DELETE FROM vault_attachment_chunks WHERE item_id = ?', [itemId]);
      for (let index = 0; index < attachments.length; index += 1) {
        const attachment = attachments[index];
        await store.insert('vault_item_attachments', {
          item_id: itemId,
          attachment_index: index,
          type: attachment.type,
          name: attachment.name,
          source_uri: attachment.sourceUri ? attachment.sourceUri : attachment.uri
        });
        await this.importAttachmentParts(itemId, index, attachment.uri);
        if (onProgress) { onProgress(index + 1, attachments.length); }
      }
      await store.executeSql(
        'UPDATE vault_items SET type = ?, attachment_uri = ?, attachment_data = ?, updated_at = ? WHERE id = ?',
        [VaultItemType.Image, '', new Uint8Array(0), Date.now(), itemId]
      );
      store.commit();
    } catch (error) {
      store.rollBack();
      throw new Error('媒体修改失败，原有媒体未更改');
    }
  }

  async appendItemAttachments(itemId: string, attachments: VaultAttachmentInput[],
    onProgress?: (completed: number, total: number) => void): Promise<void> {
    if (attachments.length === 0) { return; }
    const existing = await this.listItemAttachments(itemId);
    const startIndex = existing.length > 0 ? existing[existing.length - 1].index + 1 : 0;
    const store = this.requireStore();
    store.beginTransaction();
    try {
      for (let index = 0; index < attachments.length; index += 1) {
        const attachment = attachments[index];
        const attachmentIndex = startIndex + index;
        await store.insert('vault_item_attachments', {
          item_id: itemId,
          attachment_index: attachmentIndex,
          type: attachment.type,
          name: attachment.name,
          source_uri: attachment.sourceUri ? attachment.sourceUri : attachment.uri
        });
        await this.importAttachmentParts(itemId, attachmentIndex, attachment.uri);
        if (onProgress) { onProgress(index + 1, attachments.length); }
      }
      await store.executeSql('UPDATE vault_items SET updated_at = ? WHERE id = ?', [Date.now(), itemId]);
      store.commit();
    } catch (error) {
      store.rollBack();
      throw new Error('媒体导入失败，原有媒体未更改');
    }
  }

  async updateAttachmentSourceUri(itemId: string, attachmentIndex: number, sourceUri: string): Promise<void> {
    await this.requireStore().executeSql(
      'UPDATE vault_item_attachments SET source_uri = ? WHERE item_id = ? AND attachment_index = ?',
      [sourceUri, itemId, attachmentIndex]
    );
  }

  async deleteItemAttachments(itemId: string, attachmentIndexes: number[]): Promise<void> {
    if (attachmentIndexes.length === 0) { return; }
    const existing = await this.listItemAttachments(itemId);
    const selected = new Set<number>(attachmentIndexes);
    const remaining = existing.filter((attachment: VaultAttachmentSummary): boolean => !selected.has(attachment.index));
    if (remaining.length === 0) { throw new Error('至少需要保留一个媒体'); }
    const store = this.requireStore();
    store.beginTransaction();
    try {
      for (let index = 0; index < attachmentIndexes.length; index += 1) {
        const attachmentIndex = attachmentIndexes[index];
        await store.executeSql(
          'DELETE FROM vault_attachment_parts WHERE item_id = ? AND attachment_index = ?',
          [itemId, attachmentIndex]
        );
        await store.executeSql(
          'DELETE FROM vault_item_attachments WHERE item_id = ? AND attachment_index = ?',
          [itemId, attachmentIndex]
        );
      }
      await store.executeSql(
        'UPDATE vault_item_attachments SET attachment_index = -attachment_index - 1 WHERE item_id = ?', [itemId]
      );
      await store.executeSql(
        'UPDATE vault_attachment_parts SET attachment_index = -attachment_index - 1 WHERE item_id = ?', [itemId]
      );
      for (let index = 0; index < remaining.length; index += 1) {
        const temporaryIndex = -remaining[index].index - 1;
        await store.executeSql(
          'UPDATE vault_item_attachments SET attachment_index = ? WHERE item_id = ? AND attachment_index = ?',
          [index, itemId, temporaryIndex]
        );
        await store.executeSql(
          'UPDATE vault_attachment_parts SET attachment_index = ? WHERE item_id = ? AND attachment_index = ?',
          [index, itemId, temporaryIndex]
        );
      }
      await store.executeSql('UPDATE vault_items SET updated_at = ? WHERE id = ?', [Date.now(), itemId]);
      store.commit();
    } catch (error) {
      store.rollBack();
      throw new Error('删除媒体失败，数据未更改');
    }
  }

  async updateItem(item: VaultItem): Promise<void> {
    if (item.title.trim().length === 0 && item.type !== VaultItemType.Image && item.type !== VaultItemType.Video) {
      throw new Error('名称不能为空');
    }
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
    const store = this.requireStore();
    store.beginTransaction();
    try {
      const itemResult = await store.querySql('SELECT group_id FROM vault_items WHERE id = ?', [id]);
      let groupId = 0;
      try {
        if (itemResult.goToFirstRow()) {
          groupId = itemResult.getLong(0);
        }
      } finally {
        itemResult.close();
      }
      if (groupId > 0) {
        const groupResult = await store.querySql('SELECT id FROM vault_groups WHERE id = ?', [groupId]);
        let groupExists = false;
        try { groupExists = groupResult.goToFirstRow(); } finally { groupResult.close(); }
        if (!groupExists) {
          groupId = await this.restoreDeletedGroup(store, groupId);
        }
      }
      await store.executeSql(
        'UPDATE vault_items SET group_id = ?, deleted_at = 0, updated_at = ? WHERE id = ?',
        [groupId, Date.now(), id]
      );
      store.commit();
    } catch (error) {
      store.rollBack();
      throw new Error('恢复资料失败，数据未更改');
    }
  }

  async permanentlyDelete(id: string): Promise<void> {
    const store = this.requireStore();
    await store.executeSql('DELETE FROM vault_item_history WHERE item_id = ?', [id]);
    await store.executeSql('DELETE FROM vault_attachment_parts WHERE item_id = ?', [id]);
    await store.executeSql('DELETE FROM vault_item_attachments WHERE item_id = ?', [id]);
    await store.executeSql('DELETE FROM vault_attachment_chunks WHERE item_id = ?', [id]);
    await store.executeSql('DELETE FROM vault_items WHERE id = ?', [id]);
  }

  async readAttachment(id: string, attachmentIndex: number = 0): Promise<Uint8Array> {
    const store = this.requireStore();
    const partSizeResult = await store.querySql(
      'SELECT COALESCE(SUM(length(data)), 0) FROM vault_attachment_parts WHERE item_id = ? AND attachment_index = ?',
      [id, attachmentIndex]
    );
    let partSize = 0;
    try { if (partSizeResult.goToFirstRow()) { partSize = partSizeResult.getLong(0); } } finally { partSizeResult.close(); }
    if (partSize > 0) {
      const partData = new Uint8Array(partSize);
      let partOffset = 0;
      const parts = await store.querySql(
        'SELECT data FROM vault_attachment_parts WHERE item_id = ? AND attachment_index = ? ORDER BY chunk_index ASC',
        [id, attachmentIndex]
      );
      try {
        while (parts.goToNextRow()) {
          const bytes = parts.getBlob(0);
          partData.set(bytes, partOffset);
          partOffset += bytes.length;
          bytes.fill(0);
        }
      } finally { parts.close(); }
      return partData;
    }
    const result = await store.querySql('SELECT length(attachment_data) AS size FROM vault_items WHERE id = ? AND deleted_at = 0', [id]);
    let size = 0;
    try { if (result.goToFirstRow()) { size = result.getLong(0); } } finally { result.close(); }
    if (size <= 0) {
      const chunkSize = await store.querySql(
        'SELECT COALESCE(SUM(length(data)), 0) FROM vault_attachment_chunks WHERE item_id = ?', [id]
      );
      try { if (chunkSize.goToFirstRow()) { size = chunkSize.getLong(0); } } finally { chunkSize.close(); }
    }
    if (size <= 0) { return new Uint8Array(0); }
    const data = new Uint8Array(size);
    try {
      let offset = 0;
      const chunks = await store.querySql(
        'SELECT data FROM vault_attachment_chunks WHERE item_id = ? ORDER BY chunk_index ASC', [id]
      );
      try {
        while (chunks.goToNextRow()) {
          const bytes = chunks.getBlob(0);
          data.set(bytes, offset);
          offset += bytes.length;
          bytes.fill(0);
        }
      } finally { chunks.close(); }
      if (offset === 0) {
        for (offset = 0; offset < size; offset += 512 * 1024) {
          const chunk = await store.querySql('SELECT substr(attachment_data, ?, ?) FROM vault_items WHERE id = ? AND deleted_at = 0', [offset + 1, 512 * 1024, id]);
          try {
            if (!chunk.goToFirstRow()) { throw new Error('附件已不可用'); }
            const bytes = chunk.getBlob(0);
            data.set(bytes, offset);
            bytes.fill(0);
          } finally { chunk.close(); }
        }
      }
      return data;
    } catch (error) { data.fill(0); throw new Error('附件读取失败，请重新解锁后再试'); }
  }

  async writeAttachmentToFd(id: string, targetFd: number, attachmentIndex: number = 0): Promise<number> {
    const store = this.requireStore();
    let total = 0;
    const attachmentParts = await store.querySql(
      'SELECT data FROM vault_attachment_parts WHERE item_id = ? AND attachment_index = ? ORDER BY chunk_index ASC',
      [id, attachmentIndex]
    );
    try {
      while (attachmentParts.goToNextRow()) {
        const bytes = attachmentParts.getBlob(0);
        try {
          total += this.writeAllToFd(targetFd, bytes);
        } finally { bytes.fill(0); }
      }
    } finally { attachmentParts.close(); }
    if (total > 0) { return total; }
    const chunks = await store.querySql(
      'SELECT data FROM vault_attachment_chunks WHERE item_id = ? ORDER BY chunk_index ASC', [id]
    );
    try {
      while (chunks.goToNextRow()) {
        const bytes = chunks.getBlob(0);
        try {
          total += this.writeAllToFd(targetFd, bytes);
        } finally { bytes.fill(0); }
      }
    } finally { chunks.close(); }
    if (total > 0) { return total; }
    const sizeResult = await store.querySql(
      'SELECT length(attachment_data) FROM vault_items WHERE id = ? AND deleted_at = 0', [id]
    );
    let size = 0;
    try { if (sizeResult.goToFirstRow()) { size = sizeResult.getLong(0); } } finally { sizeResult.close(); }
    for (let offset = 0; offset < size; offset += 1024 * 1024) {
      const chunk = await store.querySql(
        'SELECT substr(attachment_data, ?, ?) FROM vault_items WHERE id = ? AND deleted_at = 0',
        [offset + 1, 1024 * 1024, id]
      );
      try {
        if (!chunk.goToFirstRow()) { throw new Error('附件已不可用'); }
        const bytes = chunk.getBlob(0);
        try {
          total += this.writeAllToFd(targetFd, bytes);
        } finally { bytes.fill(0); }
      } finally { chunk.close(); }
    }
    if (size > 0 && total !== size) { throw new Error('附件写入不完整'); }
    return total;
  }

  private writeAllToFd(targetFd: number, bytes: Uint8Array): number {
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
  }

  private async createSchema(): Promise<void> {
    const store = this.requireStore();
    await store.executeSql('CREATE TABLE IF NOT EXISTS vault_groups (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE, color TEXT NOT NULL, created_at INTEGER NOT NULL)');
    await store.executeSql('CREATE TABLE IF NOT EXISTS vault_items (id TEXT PRIMARY KEY, type TEXT NOT NULL, group_id INTEGER NOT NULL DEFAULT 0, title TEXT NOT NULL, username TEXT NOT NULL DEFAULT \'\', password TEXT NOT NULL DEFAULT \'\', notes TEXT NOT NULL DEFAULT \'\', attachment_uri TEXT NOT NULL DEFAULT \'\', attachment_data BLOB NOT NULL DEFAULT X\'\', ocr_text TEXT NOT NULL DEFAULT \'\', created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, deleted_at INTEGER NOT NULL DEFAULT 0)');
    await store.executeSql('CREATE TABLE IF NOT EXISTS vault_item_history (id INTEGER PRIMARY KEY AUTOINCREMENT, item_id TEXT NOT NULL, snapshot TEXT NOT NULL, created_at INTEGER NOT NULL)');
    await store.executeSql('CREATE TABLE IF NOT EXISTS vault_group_tombstones (group_id INTEGER PRIMARY KEY, name TEXT NOT NULL, color TEXT NOT NULL, created_at INTEGER NOT NULL, deleted_at INTEGER NOT NULL)');
    await store.executeSql('CREATE TABLE IF NOT EXISTS vault_attachment_chunks (item_id TEXT NOT NULL, chunk_index INTEGER NOT NULL, data BLOB NOT NULL, PRIMARY KEY (item_id, chunk_index))');
    await store.executeSql('CREATE TABLE IF NOT EXISTS vault_item_attachments (item_id TEXT NOT NULL, attachment_index INTEGER NOT NULL, type TEXT NOT NULL, name TEXT NOT NULL, source_uri TEXT NOT NULL, PRIMARY KEY (item_id, attachment_index))');
    await store.executeSql('CREATE TABLE IF NOT EXISTS vault_attachment_parts (item_id TEXT NOT NULL, attachment_index INTEGER NOT NULL, chunk_index INTEGER NOT NULL, data BLOB NOT NULL, PRIMARY KEY (item_id, attachment_index, chunk_index))');
    await store.executeSql('CREATE INDEX IF NOT EXISTS idx_vault_items_group ON vault_items(group_id, deleted_at, updated_at)');
  }

  private async importAttachmentChunks(itemId: string, uri: string): Promise<void> {
    let file: fs.File | undefined = undefined;
    try {
      file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      const size = fs.statSync(file.fd).size;
      if (size <= 0) { throw new Error('所选附件为空'); }
      let offset = 0;
      let chunkIndex = 0;
      while (offset < size) {
        const length = Math.min(1024 * 1024, size - offset);
        const buffer = new ArrayBuffer(length);
        const bytesRead = fs.readSync(file.fd, buffer, { length: length });
        if (bytesRead <= 0) { throw new Error('附件读取不完整'); }
        const bytes = new Uint8Array(buffer, 0, bytesRead);
        await this.requireStore().insert('vault_attachment_chunks', {
          item_id: itemId,
          chunk_index: chunkIndex,
          data: bytes
        });
        bytes.fill(0);
        offset += bytesRead;
        chunkIndex += 1;
      }
    } finally {
      if (file) { fs.closeSync(file); }
    }
  }

  private async importAttachmentParts(itemId: string, attachmentIndex: number, uri: string): Promise<void> {
    let file: fs.File | undefined = undefined;
    try {
      file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      const size = fs.statSync(file.fd).size;
      if (size <= 0) { throw new Error('所选附件为空'); }
      let offset = 0;
      let chunkIndex = 0;
      while (offset < size) {
        const length = Math.min(1024 * 1024, size - offset);
        const buffer = new ArrayBuffer(length);
        const bytesRead = fs.readSync(file.fd, buffer, { length: length });
        if (bytesRead <= 0) { throw new Error('附件读取不完整'); }
        const bytes = new Uint8Array(buffer, 0, bytesRead);
        await this.requireStore().insert('vault_attachment_parts', {
          item_id: itemId,
          attachment_index: attachmentIndex,
          chunk_index: chunkIndex,
          data: bytes
        });
        bytes.fill(0);
        offset += bytesRead;
        chunkIndex += 1;
      }
    } finally {
      if (file) { fs.closeSync(file); }
    }
  }

  private async restoreDeletedGroup(store: relationalStore.RdbStore, deletedGroupId: number): Promise<number> {
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
    await store.executeSql(
      'INSERT INTO vault_groups (id, name, color, created_at) VALUES (?, ?, ?, ?)',
      [deletedGroupId, name, color, createdAt]
    );
    await store.executeSql('DELETE FROM vault_group_tombstones WHERE group_id = ?', [deletedGroupId]);
    return deletedGroupId;
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
