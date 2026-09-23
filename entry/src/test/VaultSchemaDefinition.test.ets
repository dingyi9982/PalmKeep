import { describe, expect, it } from '@ohos/hypium';
import {
  DATABASE_SCHEMA_VERSION,
  REQUIRED_SCHEMA_TABLES,
  REVISION_TABLES,
  schemaMigrationStatements
} from '../main/ets/services/VaultSchemaDefinition';

function capturedError(action: () => void): string {
  try { action(); return ''; }
  catch (error) { return error instanceof Error ? error.message : '未知错误'; }
}

export default function vaultSchemaDefinitionTest(): void {
  describe('VaultSchemaDefinition', (): void => {
    it('keeps the first schema version explicit', 0, (): void => {
      expect(DATABASE_SCHEMA_VERSION).assertEqual(1);
    });

    it('creates every required table', 0, (): void => {
      const sql = schemaMigrationStatements(1).join('\n');
      REQUIRED_SCHEMA_TABLES.forEach((table: string): void => {
        expect(sql).assertContain(`CREATE TABLE IF NOT EXISTS ${table}`);
      });
    });

    it('creates revision triggers for mutable data', 0, (): void => {
      const sql = schemaMigrationStatements(1).join('\n');
      REVISION_TABLES.forEach((table: string): void => {
        expect(sql).assertContain(`revision_${table}_insert`);
        expect(sql).assertContain(`revision_${table}_update`);
        expect(sql).assertContain(`revision_${table}_delete`);
      });
      expect(sql).assertContain("WHERE key = 'data_revision'");
    });

    it('keeps required attachment and item columns', 0, (): void => {
      const sql = schemaMigrationStatements(1).join('\n');
      expect(sql).assertContain('website TEXT NOT NULL');
      expect(sql).assertContain('source_uri TEXT NOT NULL');
      expect(sql).assertContain('storage_name TEXT NOT NULL');
      expect(sql).assertContain('size_bytes INTEGER NOT NULL');
    });

    it('rejects undefined migration versions', 0, (): void => {
      expect(capturedError((): void => { schemaMigrationStatements(2); })).assertEqual('未定义数据库迁移 v2');
    });
  });
}
