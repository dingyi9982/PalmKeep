import preferences from '@ohos.data.preferences';
import cryptoFramework from '@ohos.security.cryptoFramework';
import huks from '@ohos.security.huks';
import userAuth from '@ohos.userIAM.userAuth';
import util from '@ohos.util';
import common from '@ohos.app.ability.common';

const SECURITY_STORE: string = 'palmvault_security';
const KEY_INITIALIZED: string = 'initialized';
const KEY_SALT: string = 'master_salt';
const KEY_VERIFIER: string = 'master_verifier';
const KEY_GESTURE_SALT: string = 'gesture_salt';
const KEY_GESTURE_VERIFIER: string = 'gesture_verifier';
const KEY_GESTURE_WRAPPED: string = 'gesture_wrapped_key';
const KEY_FINGERPRINT_NONCE: string = 'fingerprint_nonce';
const KEY_FINGERPRINT_WRAPPED: string = 'fingerprint_wrapped_key';
const FINGERPRINT_KEY_ALIAS: string = 'PalmVault.Fingerprint.DatabaseKey.v1';
const BIOMETRIC_AAD: Uint8Array = new Uint8Array([80, 97, 108, 109, 86, 97, 117, 108, 116]);
const PBKDF_ITERATIONS: number = 210000;

export interface QuickUnlockStatus {
  gestureEnabled: boolean;
  fingerprintEnabled: boolean;
  fingerprintAvailable: boolean;
}

export class VaultSecurityService {
  private readonly context: common.UIAbilityContext;
  private readonly base64: util.Base64Helper = new util.Base64Helper();

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  async isInitialized(): Promise<boolean> {
    try {
    const store = await preferences.getPreferences(this.context, SECURITY_STORE);
    return store.getSync(KEY_INITIALIZED, false) as boolean;
      } catch (error) {
      if (error instanceof Error) { throw error; }
      throw new Error('系统操作失败');
    }
  }

  async getQuickUnlockStatus(): Promise<QuickUnlockStatus> {
    try {
    const store = await preferences.getPreferences(this.context, SECURITY_STORE);
    const gestureEnabled = (store.getSync(KEY_GESTURE_WRAPPED, '') as string).length > 0;
    const fingerprintEnabled = (store.getSync(KEY_FINGERPRINT_WRAPPED, '') as string).length > 0;
    return {
      gestureEnabled: gestureEnabled,
      fingerprintEnabled: fingerprintEnabled,
      fingerprintAvailable: this.isFingerprintAvailable()
    };
      } catch (error) {
      if (error instanceof Error) { throw error; }
      throw new Error('系统操作失败');
    }
  }

  async createMasterPassword(password: string): Promise<Uint8Array> {
    try {
    if (password.length < 8) {
      throw new Error('密码至少需要 8 个字符');
    }
    const salt = cryptoFramework.createRandom().generateRandomSync(16).data;
    const material = this.derive(password, salt);
    const databaseKey = material.slice(0, 32);
    const verifier = material.slice(32, 64);
    material.fill(0);
    const store = await preferences.getPreferences(this.context, SECURITY_STORE);
    await store.put(KEY_SALT, this.base64.encodeToStringSync(salt));
    await store.put(KEY_VERIFIER, this.base64.encodeToStringSync(verifier));
    await store.put(KEY_INITIALIZED, true);
    await store.flush();
    verifier.fill(0);
    salt.fill(0);
    return databaseKey;
      } catch (error) {
      if (error instanceof Error) { throw error; }
      throw new Error('系统操作失败');
    }
  }

  async unlock(password: string): Promise<Uint8Array | undefined> {
    try {
    const store = await preferences.getPreferences(this.context, SECURITY_STORE);
    const saltText = store.getSync(KEY_SALT, '') as string;
    const expectedText = store.getSync(KEY_VERIFIER, '') as string;
    if (saltText.length === 0 || expectedText.length === 0) {
      return undefined;
    }
    const salt = this.base64.decodeSync(saltText);
    const expected = this.base64.decodeSync(expectedText);
    const material = this.derive(password, salt);
    const databaseKey = material.slice(0, 32);
    const actual = material.slice(32, 64);
    const accepted = this.constantTimeEquals(actual, expected);
    material.fill(0);
    actual.fill(0);
    expected.fill(0);
    salt.fill(0);
    if (!accepted) {
      databaseKey.fill(0);
      return undefined;
    }
    return databaseKey;
      } catch (error) {
      if (error instanceof Error) { throw error; }
      throw new Error('系统操作失败');
    }
  }

  async enableGesture(pattern: number[], databaseKey: Uint8Array): Promise<void> {
    try {
    this.validatePattern(pattern);
    const salt = cryptoFramework.createRandom().generateRandomSync(16).data;
    const material = this.derive(this.patternText(pattern), salt);
    const wrappingKey = material.slice(0, 32);
    const verifier = material.slice(32, 64);
    const wrapped = this.xor(databaseKey, wrappingKey);
    const store = await preferences.getPreferences(this.context, SECURITY_STORE);
    await store.put(KEY_GESTURE_SALT, this.base64.encodeToStringSync(salt));
    await store.put(KEY_GESTURE_VERIFIER, this.base64.encodeToStringSync(verifier));
    await store.put(KEY_GESTURE_WRAPPED, this.base64.encodeToStringSync(wrapped));
    await store.flush();
    material.fill(0);
    wrappingKey.fill(0);
    verifier.fill(0);
    wrapped.fill(0);
    salt.fill(0);
      } catch (error) {
      if (error instanceof Error) { throw error; }
      throw new Error('系统操作失败');
    }
  }

  async unlockWithGesture(pattern: number[]): Promise<Uint8Array | undefined> {
    try {
    const store = await preferences.getPreferences(this.context, SECURITY_STORE);
    const saltText = store.getSync(KEY_GESTURE_SALT, '') as string;
    const verifierText = store.getSync(KEY_GESTURE_VERIFIER, '') as string;
    const wrappedText = store.getSync(KEY_GESTURE_WRAPPED, '') as string;
    if (saltText.length === 0 || verifierText.length === 0 || wrappedText.length === 0) {
      return undefined;
    }
    const salt = this.base64.decodeSync(saltText);
    const expected = this.base64.decodeSync(verifierText);
    const wrapped = this.base64.decodeSync(wrappedText);
    const material = this.derive(this.patternText(pattern), salt);
    const wrappingKey = material.slice(0, 32);
    const actual = material.slice(32, 64);
    const accepted = this.constantTimeEquals(actual, expected);
    let databaseKey: Uint8Array | undefined = undefined;
    if (accepted) {
      databaseKey = this.xor(wrapped, wrappingKey);
    }
    material.fill(0);
    wrappingKey.fill(0);
    actual.fill(0);
    expected.fill(0);
    wrapped.fill(0);
    salt.fill(0);
    return databaseKey;
      } catch (error) {
      if (error instanceof Error) { throw error; }
      throw new Error('系统操作失败');
    }
  }

  async disableGesture(): Promise<void> {
    try {
    const store = await preferences.getPreferences(this.context, SECURITY_STORE);
    await store.delete(KEY_GESTURE_SALT);
    await store.delete(KEY_GESTURE_VERIFIER);
    await store.delete(KEY_GESTURE_WRAPPED);
    await store.flush();
      } catch (error) {
      if (error instanceof Error) { throw error; }
      throw new Error('系统操作失败');
    }
  }

  async enableFingerprint(databaseKey: Uint8Array): Promise<void> {
    try {
    if (!this.isFingerprintAvailable()) {
      throw new Error('当前设备未录入指纹或不支持指纹认证');
    }
    await this.authenticateFingerprint('启用指纹登录');
    await this.ensureFingerprintKey();
    const nonce = cryptoFramework.createRandom().generateRandomSync(12).data;
    const wrapped = await this.huksCrypt(databaseKey, nonce, true);
    const store = await preferences.getPreferences(this.context, SECURITY_STORE);
    await store.put(KEY_FINGERPRINT_NONCE, this.base64.encodeToStringSync(nonce));
    await store.put(KEY_FINGERPRINT_WRAPPED, this.base64.encodeToStringSync(wrapped));
    await store.flush();
    nonce.fill(0);
    wrapped.fill(0);
      } catch (error) {
      if (error instanceof Error) { throw error; }
      throw new Error('系统操作失败');
    }
  }

  async unlockWithFingerprint(): Promise<Uint8Array> {
    try {
    const store = await preferences.getPreferences(this.context, SECURITY_STORE);
    const nonceText = store.getSync(KEY_FINGERPRINT_NONCE, '') as string;
    const wrappedText = store.getSync(KEY_FINGERPRINT_WRAPPED, '') as string;
    if (nonceText.length === 0 || wrappedText.length === 0) {
      throw new Error('尚未启用指纹登录');
    }
    if (!this.isFingerprintAvailable()) {
      throw new Error('当前设备未录入指纹或不支持指纹认证');
    }
    await this.authenticateFingerprint('解锁掌心密匣');
    const nonce = this.base64.decodeSync(nonceText);
    const wrapped = this.base64.decodeSync(wrappedText);
    try {
      return await this.huksCrypt(wrapped, nonce, false);
    } finally {
      nonce.fill(0);
      wrapped.fill(0);
    }
      } catch (error) {
      if (error instanceof Error) { throw error; }
      throw new Error('系统操作失败');
    }
  }

  async disableFingerprint(): Promise<void> {
    try {
    const store = await preferences.getPreferences(this.context, SECURITY_STORE);
    await store.delete(KEY_FINGERPRINT_NONCE);
    await store.delete(KEY_FINGERPRINT_WRAPPED);
    await store.flush();
    if (await this.fingerprintKeyExists()) {
      await huks.deleteKeyItem(FINGERPRINT_KEY_ALIAS, {});
    }
      } catch (error) {
      if (error instanceof Error) { throw error; }
      throw new Error('系统操作失败');
    }
  }

  private isFingerprintAvailable(): boolean {
    try {
      userAuth.getAvailableStatus(userAuth.UserAuthType.FINGERPRINT, userAuth.AuthTrustLevel.ATL2);
      return true;
    } catch (_) {
      return false;
    }
  }

  private authenticateFingerprint(title: string): Promise<Uint8Array> {
    try {
    const challenge = cryptoFramework.createRandom().generateRandomSync(32).data;
    return new Promise<Uint8Array>((resolve, reject): void => {
      const instance = userAuth.getUserAuthInstance({
        challenge: challenge,
        authType: [userAuth.UserAuthType.FINGERPRINT],
        authTrustLevel: userAuth.AuthTrustLevel.ATL2,
        skipLockedBiometricAuth: true
      }, {
        title: title,
        navigationButtonText: '使用密码'
      });
      const callback: userAuth.IAuthCallback = {
        onResult: (result: userAuth.UserAuthResult): void => {
          instance.off('result', callback);
          challenge.fill(0);
          if (result.result === userAuth.UserAuthResultCode.SUCCESS && result.token) {
            const token = result.token;
            // The system authentication window disappears asynchronously after the success callback.
            // Resolve after its touch-intercepting layer has had time to leave the window.
            setTimeout((): void => resolve(token), 1500);
          } else if (result.result === userAuth.UserAuthResultCode.CANCELED) {
            reject(new Error('已取消指纹认证'));
          } else {
            reject(new Error('指纹认证未通过'));
          }
        }
      };
      instance.on('result', callback);
      try {
        instance.start();
      } catch (error) {
        instance.off('result', callback);
        challenge.fill(0);
        reject(error);
      }
    });
      } catch (error) {
      if (error instanceof Error) { throw error; }
      throw new Error('系统操作失败');
    }
  }

  private async ensureFingerprintKey(): Promise<void> {
    try {
    if (await this.fingerprintKeyExists()) {
      return;
    }
    await huks.generateKeyItem(FINGERPRINT_KEY_ALIAS, {
      properties: [
        { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
        { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE, value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256 },
        { tag: huks.HuksTag.HUKS_TAG_PURPOSE,
          value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT | huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT },
        { tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE, value: huks.HuksCipherMode.HUKS_MODE_GCM },
        { tag: huks.HuksTag.HUKS_TAG_PADDING, value: huks.HuksKeyPadding.HUKS_PADDING_NONE }
      ]
    });
      } catch (error) {
      if (error instanceof Error) { throw error; }
      throw new Error('系统操作失败');
    }
  }

  private async fingerprintKeyExists(): Promise<boolean> {
    try {
      return await huks.isKeyItemExist(FINGERPRINT_KEY_ALIAS, { properties: [] });
    } catch (_) {
      // Some HarmonyOS builds report 12000011 instead of returning false for a missing alias.
      return false;
    }
  }

  private async huksCrypt(input: Uint8Array, nonce: Uint8Array, encrypt: boolean): Promise<Uint8Array> {
    try {
    const authenticationTagLength = 16;
    if (!encrypt && input.length <= authenticationTagLength) {
      throw new Error('指纹凭据已损坏，请使用密码登录后重新启用指纹');
    }
    const operationInput = encrypt ? input : input.slice(0, input.length - authenticationTagLength);
    const authenticationTag = encrypt ? new Uint8Array(0) : input.slice(input.length - authenticationTagLength);
    const properties: huks.HuksParam[] = [
      { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
      { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE, value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256 },
      { tag: huks.HuksTag.HUKS_TAG_PURPOSE, value: encrypt ?
        huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT : huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT },
      { tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE, value: huks.HuksCipherMode.HUKS_MODE_GCM },
      { tag: huks.HuksTag.HUKS_TAG_PADDING, value: huks.HuksKeyPadding.HUKS_PADDING_NONE },
      { tag: huks.HuksTag.HUKS_TAG_NONCE, value: nonce },
      { tag: huks.HuksTag.HUKS_TAG_ASSOCIATED_DATA, value: BIOMETRIC_AAD }
    ];
    if (!encrypt) {
      properties.push({ tag: huks.HuksTag.HUKS_TAG_AE_TAG, value: authenticationTag });
    }
    const options: huks.HuksOptions = { properties: properties, inData: operationInput };
    try {
      const session = await huks.initSession(FINGERPRINT_KEY_ALIAS, options);
      const result = await huks.finishSession(session.handle, options);
      if (!result.outData || result.outData.length === 0) {
        throw new Error('本机安全密钥处理失败');
      }
      return result.outData;
    } finally {
      if (!encrypt) {
        operationInput.fill(0);
        authenticationTag.fill(0);
      }
    }
      } catch (error) {
      if (error instanceof Error) { throw error; }
      throw new Error('系统操作失败');
    }
  }

  private validatePattern(pattern: number[]): void {
    if (pattern.length < 4) {
      throw new Error('手势至少需要连接 4 个点');
    }
    const seen: boolean[] = [false, false, false, false, false, false, false, false, false];
    for (let index: number = 0; index < pattern.length; index += 1) {
      const point = pattern[index];
      if (point < 0 || point > 8 || seen[point]) {
        throw new Error('手势路径无效');
      }
      seen[point] = true;
    }
  }

  private patternText(pattern: number[]): string {
    return `PalmVault.Gesture.v1:${pattern.join('-')}`;
  }

  private xor(left: Uint8Array, right: Uint8Array): Uint8Array {
    if (left.length !== right.length) {
      throw new Error('凭据长度无效');
    }
    const output = new Uint8Array(left.length);
    for (let index: number = 0; index < left.length; index += 1) {
      output[index] = left[index] ^ right[index];
    }
    return output;
  }

  private derive(password: string, salt: Uint8Array): Uint8Array {
    try {
    const kdf = cryptoFramework.createKdf('PBKDF2|SHA256');
    const spec: cryptoFramework.PBKDF2Spec = {
      algName: 'PBKDF2',
      password: password,
      salt: salt,
      iterations: PBKDF_ITERATIONS,
      keySize: 64
    };
    return kdf.generateSecretSync(spec).data;
      } catch (error) {
      if (error instanceof Error) { throw error; }
      throw new Error('系统操作失败');
    }
  }

  private constantTimeEquals(left: Uint8Array, right: Uint8Array): boolean {
    if (left.length !== right.length) {
      return false;
    }
    let difference: number = 0;
    for (let index: number = 0; index < left.length; index += 1) {
      difference |= left[index] ^ right[index];
    }
    return difference === 0;
  }
}
