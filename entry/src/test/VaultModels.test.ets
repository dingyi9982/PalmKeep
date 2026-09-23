import { describe, expect, it } from '@ohos/hypium';
import {
  itemDisplayTitle,
  itemTypeGlyph,
  itemTypeLabel,
  VaultItem,
  VaultItemType
} from '../main/ets/models/VaultModels';

function item(type: VaultItemType, title: string, website: string): VaultItem {
  return { id: 'id', type: type, groupId: 1, title: title, username: '', password: '', website: website,
    notes: '', ocrText: '', createdAt: 1, updatedAt: 1, deletedAt: 0 };
}

export default function vaultModelsTest(): void {
  describe('VaultModels', (): void => {
    it('uses website as fallback title only for logins', 0, (): void => {
      expect(itemDisplayTitle(item(VaultItemType.Login, '', 'example.com'))).assertEqual('example.com');
      expect(itemDisplayTitle(item(VaultItemType.Note, '', 'example.com'))).assertEqual('');
      expect(itemDisplayTitle(item(VaultItemType.File, '合同', ''))).assertEqual('合同');
    });

    it('groups images and videos under media label', 0, (): void => {
      expect(itemTypeLabel(VaultItemType.Image)).assertEqual('媒体');
      expect(itemTypeLabel(VaultItemType.Video)).assertEqual('媒体');
      expect(itemTypeLabel(VaultItemType.Audio)).assertEqual('音频');
    });

    it('provides stable glyphs for core types', 0, (): void => {
      expect(itemTypeGlyph(VaultItemType.Login)).assertEqual('⌘');
      expect(itemTypeGlyph(VaultItemType.Note)).assertEqual('✎');
      expect(itemTypeGlyph(VaultItemType.Video)).assertEqual('▶');
      expect(itemTypeGlyph(VaultItemType.Audio)).assertEqual('♪');
      expect(itemTypeGlyph(VaultItemType.File)).assertEqual('▤');
    });
  });
}
