import relationalStore from '@ohos.data.relationalStore';
import { logRecoverableError, normalizeError } from './ErrorUtils';

const DATABASE_SCHEMA_VERSION: number = 1;

async function applySchemaMigration(store: relationalStore.RdbStore, version: number): Promise<void> {
  try {
    if (version === 1) {
      await store.executeSql('CREATE TABLE IF NOT EXISTS vault_groups (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE, color TEXT NOT NULL, created_at INTEGER NOT NULL, sort_order INTEGER NOT NULL DEFAULT 0)');
      await store.executeSql('CREATE TABLE IF NOT EXISTS vault_items (id TEXT PRIMARY KEY, type TEXT NOT NULL, group_id INTEGER NOT NULL DEFAULT 0, title TEXT NOT NULL, username TEXT NOT NULL DEFAULT \'\', password TEXT NOT NULL DEFAULT \'\', notes TEXT NOT NULL DEFAULT \'\', ocr_text TEXT NOT NULL DEFAULT \'\', created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, deleted_at INTEGER NOT NULL DEFAULT 0)');
      await store.executeSql('CREATE TABLE IF NOT EXISTS vault_group_tombstones (group_id INTEGER PRIMARY KEY, name TEXT NOT NULL, color TEXT NOT NULL, created_at INTEGER NOT NULL, deleted_at INTEGER NOT NULL)');
      await store.executeSql('CREATE TABLE IF NOT EXISTS vault_item_attachments (item_id TEXT NOT NULL, attachment_index INTEGER NOT NULL, type TEXT NOT NULL, name TEXT NOT NULL, source_uri TEXT NOT NULL, ocr_text TEXT NOT NULL DEFAULT \'\', storage_name TEXT NOT NULL, size_bytes INTEGER NOT NULL, PRIMARY KEY (item_id, attachment_index))');
      await store.executeSql('CREATE TABLE IF NOT EXISTS vault_item_tombstones (item_id TEXT PRIMARY KEY, deleted_at INTEGER NOT NULL)');
      await store.executeSql('CREATE INDEX IF NOT EXISTS idx_vault_items_group ON vault_items(group_id, deleted_at, updated_at)');
      await store.executeSql('CREATE INDEX IF NOT EXISTS idx_vault_items_type ON vault_items(type, deleted_at, updated_at)');
      await store.executeSql('CREATE INDEX IF NOT EXISTS idx_vault_items_deleted ON vault_items(deleted_at)');
      return;
    }
    throw new Error(`未定义数据库迁移 v${version}`);
  } catch (error) {
    throw normalizeError(error);
  }
}

async function requireSchemaColumn(store: relationalStore.RdbStore,
  table: string, requiredColumn: string): Promise<void> {
  try {
    const columns = await store.querySql(`PRAGMA table_info(${table})`);
    try {
      const nameIndex = columns.getColumnIndex('name');
      while (columns.goToNextRow()) {
        if (columns.getString(nameIndex) === requiredColumn) { return; }
      }
    } finally { columns.close(); }
    throw new Error(`数据库结构不完整：${table} 缺少 ${requiredColumn}`);
  } catch (error) {
    throw normalizeError(error);
  }
}

async function validateSchema(store: relationalStore.RdbStore): Promise<void> {
  try {
    const requiredTables: string[] = [
      'vault_groups', 'vault_items', 'vault_group_tombstones', 'vault_item_attachments', 'vault_item_tombstones'
    ];
    for (let index = 0; index < requiredTables.length; index += 1) {
      const table = requiredTables[index];
      const result = await store.querySql(
        'SELECT name FROM sqlite_master WHERE type = ? AND name = ?', ['table', table]);
      try {
        if (!result.goToFirstRow()) { throw new Error(`数据库结构不完整：缺少 ${table}`); }
      } finally { result.close(); }
    }
    await requireSchemaColumn(store, 'vault_groups', 'sort_order');
    await requireSchemaColumn(store, 'vault_items', 'ocr_text');
    await requireSchemaColumn(store, 'vault_item_attachments', 'storage_name');
    await requireSchemaColumn(store, 'vault_item_attachments', 'size_bytes');
  } catch (error) {
    throw normalizeError(error);
  }
}

export async function migrateVaultDatabase(store: relationalStore.RdbStore): Promise<void> {
  const installedVersion = store.version;
  if (installedVersion > DATABASE_SCHEMA_VERSION) {
    throw new Error(`数据库版本 ${installedVersion} 高于当前应用支持的版本 ${DATABASE_SCHEMA_VERSION}`);
  }
  if (installedVersion < 0) { throw new Error('数据库版本无效'); }
  if (installedVersion === DATABASE_SCHEMA_VERSION) {
    // The app is still on its first public schema. Keep CREATE IF NOT EXISTS idempotent
    // so development builds with an earlier v1 database receive newly finalized v1 tables.
    await applySchemaMigration(store, DATABASE_SCHEMA_VERSION);
    await validateSchema(store);
    return;
  }

  let transactionStarted = false;
  let migratingVersion = installedVersion + 1;
  try {
    store.beginTransaction();
    transactionStarted = true;
    while (migratingVersion <= DATABASE_SCHEMA_VERSION) {
      await applySchemaMigration(store, migratingVersion);
      migratingVersion += 1;
    }
    store.commit();
    transactionStarted = false;
    // HarmonyOS may serve schema queries from another connection which cannot
    // observe uncommitted DDL. Validate only after the migration transaction is visible.
    await validateSchema(store);
    store.version = DATABASE_SCHEMA_VERSION;
  } catch (error) {
    if (transactionStarted) {
      try { store.rollBack(); }
      catch (rollbackError) { logRecoverableError('database migration rollback failed', rollbackError); }
    }
    const failedVersion = Math.min(migratingVersion, DATABASE_SCHEMA_VERSION);
    throw new Error(`数据库升级到 v${failedVersion} 失败：${normalizeError(error).message}`);
  }
}
