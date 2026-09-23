export const DATABASE_SCHEMA_VERSION: number = 1;

export const REQUIRED_SCHEMA_TABLES: string[] = [
  'vault_groups', 'vault_items', 'vault_group_tombstones', 'vault_item_attachments',
  'vault_item_tombstones', 'vault_metadata'
];

export const REVISION_TABLES: string[] = [
  'vault_groups', 'vault_items', 'vault_item_attachments', 'vault_group_tombstones', 'vault_item_tombstones'
];

export function schemaMigrationStatements(version: number): string[] {
  if (version !== 1) { throw new Error(`未定义数据库迁移 v${version}`); }
  const statements: string[] = [
    'CREATE TABLE IF NOT EXISTS vault_groups (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE, color TEXT NOT NULL, created_at INTEGER NOT NULL, sort_order INTEGER NOT NULL DEFAULT 0)',
    'CREATE TABLE IF NOT EXISTS vault_items (id TEXT PRIMARY KEY, type TEXT NOT NULL, group_id INTEGER NOT NULL, title TEXT NOT NULL, username TEXT NOT NULL DEFAULT \'\', password TEXT NOT NULL DEFAULT \'\', website TEXT NOT NULL DEFAULT \'\', notes TEXT NOT NULL DEFAULT \'\', ocr_text TEXT NOT NULL DEFAULT \'\', created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, deleted_at INTEGER NOT NULL DEFAULT 0)',
    'CREATE TABLE IF NOT EXISTS vault_group_tombstones (group_id INTEGER PRIMARY KEY, name TEXT NOT NULL, color TEXT NOT NULL, created_at INTEGER NOT NULL, deleted_at INTEGER NOT NULL)',
    'CREATE TABLE IF NOT EXISTS vault_item_attachments (item_id TEXT NOT NULL, attachment_index INTEGER NOT NULL, type TEXT NOT NULL, name TEXT NOT NULL, source_uri TEXT NOT NULL, ocr_text TEXT NOT NULL DEFAULT \'\', storage_name TEXT NOT NULL, size_bytes INTEGER NOT NULL, PRIMARY KEY (item_id, attachment_index))',
    'CREATE TABLE IF NOT EXISTS vault_item_tombstones (item_id TEXT PRIMARY KEY, deleted_at INTEGER NOT NULL)',
    'CREATE TABLE IF NOT EXISTS vault_metadata (key TEXT PRIMARY KEY, value INTEGER NOT NULL DEFAULT 0)',
    'INSERT OR IGNORE INTO vault_metadata (key, value) VALUES (\'data_revision\', 0)',
    'CREATE INDEX IF NOT EXISTS idx_vault_items_group ON vault_items(group_id, deleted_at, updated_at)',
    'CREATE INDEX IF NOT EXISTS idx_vault_items_type ON vault_items(type, deleted_at, updated_at)',
    'CREATE INDEX IF NOT EXISTS idx_vault_items_deleted ON vault_items(deleted_at)'
  ];
  const actions: string[] = ['INSERT', 'UPDATE', 'DELETE'];
  for (let tableIndex = 0; tableIndex < REVISION_TABLES.length; tableIndex += 1) {
    for (let actionIndex = 0; actionIndex < actions.length; actionIndex += 1) {
      const table = REVISION_TABLES[tableIndex];
      statements.push(`DROP TRIGGER IF EXISTS revision_${table}_${actions[actionIndex].toLowerCase()}`);
    }
  }
  const increment = 'BEGIN UPDATE vault_metadata SET value = value + 1 ' +
    'WHERE key = \'data_revision\'; END';
  statements.push('CREATE TRIGGER revision_vault_groups_insert AFTER INSERT ON vault_groups ' + increment);
  statements.push('CREATE TRIGGER revision_vault_groups_update AFTER UPDATE ON vault_groups ' + increment);
  statements.push('CREATE TRIGGER revision_vault_groups_delete AFTER DELETE ON vault_groups ' + increment);
  statements.push('CREATE TRIGGER revision_vault_items_insert AFTER INSERT ON vault_items ' +
    `WHEN NEW.deleted_at = 0 ${increment}`);
  statements.push('CREATE TRIGGER revision_vault_items_update AFTER UPDATE ON vault_items ' +
    `WHEN OLD.deleted_at = 0 OR NEW.deleted_at = 0 ${increment}`);
  statements.push('CREATE TRIGGER revision_vault_items_delete AFTER DELETE ON vault_items ' +
    `WHEN OLD.deleted_at = 0 ${increment}`);
  statements.push('CREATE TRIGGER revision_vault_item_attachments_insert ' +
    'AFTER INSERT ON vault_item_attachments WHEN EXISTS (SELECT 1 FROM vault_items ' +
    `WHERE id = NEW.item_id AND deleted_at = 0) ${increment}`);
  statements.push('CREATE TRIGGER revision_vault_item_attachments_update ' +
    'AFTER UPDATE ON vault_item_attachments WHEN EXISTS (SELECT 1 FROM vault_items ' +
    'WHERE id = NEW.item_id AND deleted_at = 0) OR EXISTS (SELECT 1 FROM vault_items ' +
    `WHERE id = OLD.item_id AND deleted_at = 0) ${increment}`);
  statements.push('CREATE TRIGGER revision_vault_item_attachments_delete ' +
    'AFTER DELETE ON vault_item_attachments WHEN EXISTS (SELECT 1 FROM vault_items ' +
    `WHERE id = OLD.item_id AND deleted_at = 0) ${increment}`);
  return statements;
}
