import relationalStore from '@ohos.data.relationalStore';
import { logRecoverableError, normalizeError } from './ErrorUtils';
import {
  DATABASE_SCHEMA_VERSION,
  REQUIRED_SCHEMA_TABLES,
  schemaMigrationStatements
} from './VaultSchemaDefinition';

async function applySchemaMigration(store: relationalStore.RdbStore, version: number): Promise<void> {
  try {
    const statements = schemaMigrationStatements(version);
    for (let index = 0; index < statements.length; index += 1) {
      await store.executeSql(statements[index]);
    }
  } catch (error) {
    throw normalizeError(error);
  }
}

async function hasSchemaColumn(store: relationalStore.RdbStore,
  table: string, column: string): Promise<boolean> {
  try {
    const columns = await store.querySql(`PRAGMA table_info(${table})`);
    try {
      const nameIndex = columns.getColumnIndex('name');
      while (columns.goToNextRow()) {
        if (columns.getString(nameIndex) === column) { return true; }
      }
      return false;
    } finally { columns.close(); }
  } catch (error) {
    throw normalizeError(error);
  }
}

async function finalizeFirstSchema(store: relationalStore.RdbStore): Promise<void> {
  try {
    if (!await hasSchemaColumn(store, 'vault_items', 'website')) {
      await store.executeSql('ALTER TABLE vault_items ADD COLUMN website TEXT NOT NULL DEFAULT \'\'');
    }
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
    for (let index = 0; index < REQUIRED_SCHEMA_TABLES.length; index += 1) {
      const table = REQUIRED_SCHEMA_TABLES[index];
      const result = await store.querySql(
        'SELECT name FROM sqlite_master WHERE type = ? AND name = ?', ['table', table]);
      try {
        if (!result.goToFirstRow()) { throw new Error(`数据库结构不完整：缺少 ${table}`); }
      } finally { result.close(); }
    }
    await requireSchemaColumn(store, 'vault_groups', 'sort_order');
    await requireSchemaColumn(store, 'vault_items', 'ocr_text');
    await requireSchemaColumn(store, 'vault_items', 'website');
    await requireSchemaColumn(store, 'vault_item_attachments', 'storage_name');
    await requireSchemaColumn(store, 'vault_item_attachments', 'size_bytes');
  } catch (error) {
    throw normalizeError(error);
  }
}

async function persistSchemaVersion(store: relationalStore.RdbStore, version: number): Promise<void> {
  try {
    store.version = version;
    return;
  } catch (setterError) {
    // A few HarmonyOS builds return 14800021 from the version property even though
    // all schema writes have committed. PRAGMA writes the same SQLite user_version
    // marker and keeps the migration recoverable on those devices.
    try {
      await store.executeSql(`PRAGMA user_version = ${version}`);
      if (store.version === version) { return; }
    } catch (pragmaError) {
      logRecoverableError('database schema version fallback failed', pragmaError);
    }
    // The schema itself is authoritative for v1. Leaving user_version at zero is
    // safe because every v1 operation is idempotent and will be retried next open.
    logRecoverableError('database schema version marker could not be persisted', setterError);
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
    await finalizeFirstSchema(store);
    await validateSchema(store);
    return;
  }

  let migratingVersion = installedVersion + 1;
  let migrationPhase = '创建数据库结构';
  try {
    // Schema v1 consists only of idempotent CREATE/ALTER operations. Executing the
    // steps directly avoids a platform issue where asynchronous DDL and the legacy
    // transaction API can be dispatched on different RDB connections.
    while (migratingVersion <= DATABASE_SCHEMA_VERSION) {
      await applySchemaMigration(store, migratingVersion);
      migratingVersion += 1;
    }
    migrationPhase = '补全数据库字段';
    await finalizeFirstSchema(store);
    migrationPhase = '校验数据库结构';
    await validateSchema(store);
    migrationPhase = '记录数据库版本';
    await persistSchemaVersion(store, DATABASE_SCHEMA_VERSION);
  } catch (error) {
    const failedVersion = Math.min(migratingVersion, DATABASE_SCHEMA_VERSION);
    throw new Error(`数据库升级到 v${failedVersion} 失败（${migrationPhase}）：${normalizeError(error).message}`);
  }
}
