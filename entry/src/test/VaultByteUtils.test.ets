import { describe, expect, it } from '@ohos/hypium';
import { constantTimeBytesEqual, isZeroByteArray } from '../main/ets/services/VaultByteUtils';

export default function vaultByteUtilsTest(): void {
  describe('VaultByteUtils', (): void => {
    it('compares password and backup authentication bytes', 0, (): void => {
      expect(constantTimeBytesEqual(new Uint8Array([1, 2, 3]), new Uint8Array([1, 2, 3]))).assertEqual(true);
      expect(constantTimeBytesEqual(new Uint8Array([1, 2, 3]), new Uint8Array([1, 2, 4]))).assertEqual(false);
      expect(constantTimeBytesEqual(new Uint8Array([1]), new Uint8Array([1, 0]))).assertEqual(false);
    });

    it('detects zero-filled backup header regions', 0, (): void => {
      expect(isZeroByteArray(new Uint8Array([0, 0, 0]))).assertEqual(true);
      expect(isZeroByteArray(new Uint8Array([0, 1, 0]))).assertEqual(false);
    });
  });
}
