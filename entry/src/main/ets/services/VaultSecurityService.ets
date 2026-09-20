import preferences from '@ohos.data.preferences';
import cryptoFramework from '@ohos.security.cryptoFramework';
import huks from '@ohos.security.huks';
import userAuth from '@ohos.userIAM.userAuth';
import util from '@ohos.util';
import { normalizeError } from './ErrorUtils';
import common from '@ohos.app.ability.common';
import { BusinessError } from '@ohos.base';

const SECURITY_STORE: string = 'palmvault_security';
const KEY_INITIALIZED: string = 'initialized';
const KEY_SALT: string = 'master_salt';
const KEY_VERIFIER: string = 'master_verifier';
const KEY_GESTURE_SALT: string = 'gesture_salt';
const KEY_GESTURE_VERIFIER: string = 'gesture_verifier';
const KEY_GESTURE_WRAPPED: string = 'gesture_wrapped_key';
const KEY_FINGERPRINT_NONCE: string = 'fingerprint_nonce';
const KEY_FINGERPRINT_WRAPPED: string = 'fingerprint_wrapped_key';
const KEY_FACE_NONCE: string = 'face_nonce';
const KEY_FACE_WRAPPED: string = 'face_wrapped_key';
const KEY_PASSWORD_FAILURES: string = 'password_failures';
const KEY_PASSWORD_LOCKOUT_UNTIL: string = 'password_lockout_until';
const KEY_PASSWORD_LOCKOUT_LEVEL: string = 'password_lockout_level';
const KEY_GESTURE_FAILURES: string = 'gesture_failures';
const KEY_GESTURE_LOCKOUT_UNTIL: string = 'gesture_lockout_until';
const KEY_PREFERRED_UNLOCK_MODE: string = 'preferred_unlock_mode';
const KEY_AUTO_LOCK_MINUTES: string = 'auto_lock_minutes';
const FINGERPRINT_KEY_ALIAS: string = 'PalmVault.Fingerprint.DatabaseKey.v1';
const BIOMETRIC_AAD: Uint8Array = new Uint8Array([80, 97, 108, 109, 86, 97, 117, 108, 116]);
const PBKDF_ITERATIONS: number = 210000;

export interface QuickUnlockStatus {
  gestureEnabled: boolean;
  fingerprintEnabled: boolean;
  fingerprintAvailable: boolean;
  faceEnabled: boolean;
  faceAvailable: boolean;
  preferredUnlockMode: string;
  autoLockMinutes: number;
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
      throw normalizeError(error);
    }
  }

  async getQuickUnlockStatus(): Promise<QuickUnlockStatus> {
    try {
    const store = await preferences.getPreferences(this.context, SECURITY_STORE);
    const gestureEnabled = (store.getSync(KEY_GESTURE_WRAPPED, '') as string).length > 0;
    const fingerprintEnabled = (store.getSync(KEY_FINGERPRINT_WRAPPED, '') as string).length > 0;
    const faceEnabled = (store.getSync(KEY_FACE_WRAPPED, '') as string).length > 0;
    const defaultMode = fingerprintEnabled ? 'fingerprint' : (faceEnabled ? 'face' :
      (gestureEnabled ? 'gesture' : 'password'));
    return {
      gestureEnabled: gestureEnabled,
      fingerprintEnabled: fingerprintEnabled,
      fingerprintAvailable: this.isBiometricAvailable(userAuth.UserAuthType.FINGERPRINT),
      faceEnabled: faceEnabled,
      faceAvailable: this.isBiometricAvailable(userAuth.UserAuthType.FACE),
      preferredUnlockMode: store.getSync(KEY_PREFERRED_UNLOCK_MODE, defaultMode) as string,
      autoLockMinutes: store.getSync(KEY_AUTO_LOCK_MINUTES, 10) as number
    };
      } catch (error) {
      throw normalizeError(error);
    }
  }

  async createMasterPassword(password: string): Promise<Uint8Array> {
    try {
    if (password.length === 0) {
      throw new Error('密码不能为空');
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
      throw normalizeError(error);
    }
  }

  async unlock(password: string): Promise<Uint8Array | undefined> {
    try {
    const store = await preferences.getPreferences(this.context, SECURITY_STORE);
    const lockoutUntil = store.getSync(KEY_PASSWORD_LOCKOUT_UNTIL, 0) as number;
    if (lockoutUntil > Date.now()) {
      throw new Error(`密码尝试次数过多，请在 ${Math.ceil((lockoutUntil - Date.now()) / 1000)} 秒后重试`);
    }
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
      const failures = (store.getSync(KEY_PASSWORD_FAILURES, 0) as number) + 1;
      if (failures >= 5) {
        const level = Math.min((store.getSync(KEY_PASSWORD_LOCKOUT_LEVEL, 0) as number) + 1, 5);
        const cooldownSeconds = Math.min(30 * Math.pow(2, level - 1), 300);
        await store.put(KEY_PASSWORD_FAILURES, 0);
        await store.put(KEY_PASSWORD_LOCKOUT_LEVEL, level);
        await store.put(KEY_PASSWORD_LOCKOUT_UNTIL, Date.now() + cooldownSeconds * 1000);
        await store.flush();
        throw new Error(`密码错误次数过多，请在 ${cooldownSeconds} 秒后重试`);
      } else {
        await store.put(KEY_PASSWORD_FAILURES, failures);
      }
      await store.flush();
      return undefined;
    }
    await store.put(KEY_PASSWORD_FAILURES, 0);
    await store.put(KEY_PASSWORD_LOCKOUT_LEVEL, 0);
    await store.put(KEY_PASSWORD_LOCKOUT_UNTIL, 0);
    await store.flush();
    return databaseKey;
      } catch (error) {
      throw normalizeError(error);
    }
  }

  async verifyPassword(password: string): Promise<boolean> {
    try {
      const key = await this.unlock(password);
      if (!key) { return false; }
      key.fill(0);
      return true;
    } catch (error) {
      throw normalizeError(error);
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
    const preferredMode = store.getSync(KEY_PREFERRED_UNLOCK_MODE, 'password') as string;
    if (preferredMode !== 'face' && preferredMode !== 'fingerprint') {
      await store.put(KEY_PREFERRED_UNLOCK_MODE, 'gesture');
    }
    await store.flush();
    material.fill(0);
    wrappingKey.fill(0);
    verifier.fill(0);
    wrapped.fill(0);
    salt.fill(0);
      } catch (error) {
      throw normalizeError(error);
    }
  }

  async unlockWithGesture(pattern: number[]): Promise<Uint8Array | undefined> {
    try {
    const store = await preferences.getPreferences(this.context, SECURITY_STORE);
    const lockoutUntil = store.getSync(KEY_GESTURE_LOCKOUT_UNTIL, 0) as number;
    if (lockoutUntil > Date.now()) {
      throw new Error(`手势尝试次数过多，请在 ${Math.ceil((lockoutUntil - Date.now()) / 1000)} 秒后重试`);
    }
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
    let lockedOut = false;
    if (accepted) {
      databaseKey = this.xor(wrapped, wrappingKey);
      await store.put(KEY_GESTURE_FAILURES, 0);
      await store.put(KEY_GESTURE_LOCKOUT_UNTIL, 0);
      await store.flush();
    } else {
      const failures = (store.getSync(KEY_GESTURE_FAILURES, 0) as number) + 1;
      if (failures >= 5) {
        await store.put(KEY_GESTURE_FAILURES, 0);
        await store.put(KEY_GESTURE_LOCKOUT_UNTIL, Date.now() + 30000);
        await store.flush();
        lockedOut = true;
      } else {
        await store.put(KEY_GESTURE_FAILURES, failures);
      }
      await store.flush();
    }
    material.fill(0);
    wrappingKey.fill(0);
    actual.fill(0);
    expected.fill(0);
    wrapped.fill(0);
    salt.fill(0);
    if (lockedOut) { throw new Error('手势错误次数过多，请在 30 秒后重试'); }
    return databaseKey;
      } catch (error) {
      throw normalizeError(error);
    }
  }

  async disableGesture(): Promise<void> {
    try {
    const store = await preferences.getPreferences(this.context, SECURITY_STORE);
    await store.delete(KEY_GESTURE_SALT);
    await store.delete(KEY_GESTURE_VERIFIER);
    await store.delete(KEY_GESTURE_WRAPPED);
    await store.delete(KEY_GESTURE_FAILURES);
    await store.delete(KEY_GESTURE_LOCKOUT_UNTIL);
    if ((store.getSync(KEY_PREFERRED_UNLOCK_MODE, '') as string) === 'gesture') {
      const faceEnabled = (store.getSync(KEY_FACE_WRAPPED, '') as string).length > 0;
      const fingerprintEnabled = (store.getSync(KEY_FINGERPRINT_WRAPPED, '') as string).length > 0;
      await store.put(KEY_PREFERRED_UNLOCK_MODE, faceEnabled ? 'face' :
        (fingerprintEnabled ? 'fingerprint' : 'password'));
    }
    await store.flush();
      } catch (error) {
      throw normalizeError(error);
    }
  }

  async enableFingerprint(databaseKey: Uint8Array): Promise<void> {
    try {
    if (!this.isBiometricAvailable(userAuth.UserAuthType.FINGERPRINT)) {
      throw new Error('当前设备未录入指纹或不支持指纹认证');
    }
    await this.authenticateBiometric('启用指纹登录', userAuth.UserAuthType.FINGERPRINT);
    await this.ensureFingerprintKey();
    const nonce = cryptoFramework.createRandom().generateRandomSync(12).data;
    const wrapped = await this.huksCrypt(databaseKey, nonce, true);
    const store = await preferences.getPreferences(this.context, SECURITY_STORE);
    await store.put(KEY_FINGERPRINT_NONCE, this.base64.encodeToStringSync(nonce));
    await store.put(KEY_FINGERPRINT_WRAPPED, this.base64.encodeToStringSync(wrapped));
    if ((store.getSync(KEY_PREFERRED_UNLOCK_MODE, 'password') as string) !== 'face') {
      await store.put(KEY_PREFERRED_UNLOCK_MODE, 'fingerprint');
    }
    await store.flush();
    nonce.fill(0);
    wrapped.fill(0);
      } catch (error) {
      throw normalizeError(error);
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
    if (!this.isBiometricAvailable(userAuth.UserAuthType.FINGERPRINT)) {
      throw new Error('当前设备未录入指纹或不支持指纹认证');
    }
    await this.authenticateBiometric('解锁掌心密匣', userAuth.UserAuthType.FINGERPRINT);
    const nonce = this.base64.decodeSync(nonceText);
    const wrapped = this.base64.decodeSync(wrappedText);
    try {
      return await this.huksCrypt(wrapped, nonce, false);
    } catch (_) {
      await this.disableFingerprint();
      throw new Error('指纹登录凭据已失效，请使用密码登录后重新启用');
    } finally {
      nonce.fill(0);
      wrapped.fill(0);
    }
      } catch (error) {
      throw normalizeError(error);
    }
  }

  async disableFingerprint(): Promise<void> {
    try {
    const store = await preferences.getPreferences(this.context, SECURITY_STORE);
    await store.delete(KEY_FINGERPRINT_NONCE);
    await store.delete(KEY_FINGERPRINT_WRAPPED);
    if ((store.getSync(KEY_PREFERRED_UNLOCK_MODE, '') as string) === 'fingerprint') {
      const faceEnabled = (store.getSync(KEY_FACE_WRAPPED, '') as string).length > 0;
      const gestureEnabled = (store.getSync(KEY_GESTURE_WRAPPED, '') as string).length > 0;
      await store.put(KEY_PREFERRED_UNLOCK_MODE, faceEnabled ? 'face' :
        (gestureEnabled ? 'gesture' : 'password'));
    }
    await store.flush();
    if ((store.getSync(KEY_FACE_WRAPPED, '') as string).length === 0 && await this.fingerprintKeyExists()) {
      await huks.deleteKeyItem(FINGERPRINT_KEY_ALIAS, {});
    }
      } catch (error) {
      throw normalizeError(error);
    }
  }

  async enableFace(databaseKey: Uint8Array): Promise<void> {
    try {
      if (!this.isBiometricAvailable(userAuth.UserAuthType.FACE)) {
        throw new Error('当前设备未录入或不支持人脸认证');
      }
      await this.authenticateBiometric('启用人脸登录', userAuth.UserAuthType.FACE);
      await this.ensureFingerprintKey();
      const nonce = cryptoFramework.createRandom().generateRandomSync(12).data;
      const wrapped = await this.huksCrypt(databaseKey, nonce, true);
      const store = await preferences.getPreferences(this.context, SECURITY_STORE);
      await store.put(KEY_FACE_NONCE, this.base64.encodeToStringSync(nonce));
      await store.put(KEY_FACE_WRAPPED, this.base64.encodeToStringSync(wrapped));
      await store.put(KEY_PREFERRED_UNLOCK_MODE, 'face');
      await store.flush();
      nonce.fill(0);
      wrapped.fill(0);
    } catch (error) {
      throw normalizeError(error);
    }
  }

  async unlockWithFace(): Promise<Uint8Array> {
    try {
      const store = await preferences.getPreferences(this.context, SECURITY_STORE);
      const nonceText = store.getSync(KEY_FACE_NONCE, '') as string;
      const wrappedText = store.getSync(KEY_FACE_WRAPPED, '') as string;
      if (nonceText.length === 0 || wrappedText.length === 0) { throw new Error('尚未启用人脸登录'); }
      if (!this.isBiometricAvailable(userAuth.UserAuthType.FACE)) {
        throw new Error('当前设备未录入或不支持人脸认证');
      }
      await this.authenticateBiometric('解锁掌心密匣', userAuth.UserAuthType.FACE);
      const nonce = this.base64.decodeSync(nonceText);
      const wrapped = this.base64.decodeSync(wrappedText);
      try {
        return await this.huksCrypt(wrapped, nonce, false);
      } catch (_) {
        await this.disableFace();
        throw new Error('人脸登录凭据已失效，请使用密码登录后重新启用');
      } finally {
        nonce.fill(0);
        wrapped.fill(0);
      }
    } catch (error) {
      throw normalizeError(error);
    }
  }

  async disableFace(): Promise<void> {
    try {
      const store = await preferences.getPreferences(this.context, SECURITY_STORE);
      await store.delete(KEY_FACE_NONCE);
      await store.delete(KEY_FACE_WRAPPED);
      if ((store.getSync(KEY_PREFERRED_UNLOCK_MODE, '') as string) === 'face') {
        const fingerprintEnabled = (store.getSync(KEY_FINGERPRINT_WRAPPED, '') as string).length > 0;
        const gestureEnabled = (store.getSync(KEY_GESTURE_WRAPPED, '') as string).length > 0;
        await store.put(KEY_PREFERRED_UNLOCK_MODE, fingerprintEnabled ? 'fingerprint' :
          (gestureEnabled ? 'gesture' : 'password'));
      }
      await store.flush();
      if ((store.getSync(KEY_FINGERPRINT_WRAPPED, '') as string).length === 0 && await this.fingerprintKeyExists()) {
        await huks.deleteKeyItem(FINGERPRINT_KEY_ALIAS, {});
      }
    } catch (error) {
      throw normalizeError(error);
    }
  }

  async changePassword(currentPassword: string, newPassword: string): Promise<Uint8Array> {
    try {
      const currentKey = await this.unlock(currentPassword);
      if (!currentKey) { throw new Error('当前密码不正确'); }
      return await this.replacePassword(currentKey, newPassword);
    } catch (error) {
      throw normalizeError(error);
    }
  }

  async resetPasswordWithAuthenticatedKey(authenticatedKey: Uint8Array, newPassword: string): Promise<Uint8Array> {
    try {
      if (authenticatedKey.length !== 32) { throw new Error('恢复凭据无效，请重新验证身份'); }
      return await this.replacePassword(authenticatedKey, newPassword);
    } catch (error) {
      authenticatedKey.fill(0);
      throw normalizeError(error);
    }
  }

  async resetSecurity(): Promise<void> {
    try {
      const store = await preferences.getPreferences(this.context, SECURITY_STORE);
      await store.clear();
      await store.flush();
      try {
        if (await this.fingerprintKeyExists()) { await huks.deleteKeyItem(FINGERPRINT_KEY_ALIAS, {}); }
      } catch (_) {
        // Preferences are authoritative; stale hardware credentials can no longer be reached.
      }
    } catch (error) {
      throw normalizeError(error);
    }
  }

  async setPreferredUnlockMode(mode: string): Promise<void> {
    try {
      if (mode !== 'password' && mode !== 'fingerprint' && mode !== 'face' && mode !== 'gesture') {
        throw new Error('不支持的登录方式');
      }
      const status = await this.getQuickUnlockStatus();
      if ((mode === 'fingerprint' && !status.fingerprintEnabled) ||
        (mode === 'face' && !status.faceEnabled) || (mode === 'gesture' && !status.gestureEnabled)) {
        throw new Error('请先启用该登录方式');
      }
      const store = await preferences.getPreferences(this.context, SECURITY_STORE);
      await store.put(KEY_PREFERRED_UNLOCK_MODE, mode);
      await store.flush();
    } catch (error) {
      throw normalizeError(error);
    }
  }

  async setAutoLockMinutes(minutes: number): Promise<void> {
    try {
      if (minutes !== -1 && minutes !== 0 && minutes !== 5 && minutes !== 10 && minutes !== 30) {
        throw new Error('不支持的自动锁定时间');
      }
      const store = await preferences.getPreferences(this.context, SECURITY_STORE);
      await store.put(KEY_AUTO_LOCK_MINUTES, minutes);
      await store.flush();
    } catch (error) {
      throw normalizeError(error);
    }
  }

  private isBiometricAvailable(type: userAuth.UserAuthType): boolean {
    try {
      userAuth.getAvailableStatus(type, userAuth.AuthTrustLevel.ATL2);
      return true;
    } catch (_) {
      return false;
    }
  }

  private async replacePassword(authenticatedKey: Uint8Array, newPassword: string): Promise<Uint8Array> {
    try {
      authenticatedKey.fill(0);
      if (newPassword.length === 0) { throw new Error('新密码不能为空'); }
      const salt = cryptoFramework.createRandom().generateRandomSync(16).data;
      const material = this.derive(newPassword, salt);
      const databaseKey = material.slice(0, 32);
      const verifier = material.slice(32, 64);
      material.fill(0);
      const store = await preferences.getPreferences(this.context, SECURITY_STORE);
      await store.put(KEY_SALT, this.base64.encodeToStringSync(salt));
      await store.put(KEY_VERIFIER, this.base64.encodeToStringSync(verifier));
      await store.delete(KEY_GESTURE_SALT);
      await store.delete(KEY_GESTURE_VERIFIER);
      await store.delete(KEY_GESTURE_WRAPPED);
      await store.delete(KEY_GESTURE_FAILURES);
      await store.delete(KEY_GESTURE_LOCKOUT_UNTIL);
      await store.delete(KEY_FINGERPRINT_NONCE);
      await store.delete(KEY_FINGERPRINT_WRAPPED);
      await store.delete(KEY_FACE_NONCE);
      await store.delete(KEY_FACE_WRAPPED);
      await store.put(KEY_PREFERRED_UNLOCK_MODE, 'password');
      await store.put(KEY_PASSWORD_FAILURES, 0);
      await store.put(KEY_PASSWORD_LOCKOUT_LEVEL, 0);
      await store.put(KEY_PASSWORD_LOCKOUT_UNTIL, 0);
      await store.flush();
      try {
        if (await this.fingerprintKeyExists()) { await huks.deleteKeyItem(FINGERPRINT_KEY_ALIAS, {}); }
      } catch (_) {
        // A stale key alias does not invalidate the successfully changed password.
      }
      salt.fill(0);
      verifier.fill(0);
      return databaseKey;
    } catch (error) {
      authenticatedKey.fill(0);
      throw normalizeError(error);
    }
  }

  private authenticateBiometric(title: string, type: userAuth.UserAuthType): Promise<Uint8Array> {
    try {
    const challenge = cryptoFramework.createRandom().generateRandomSync(32).data;
    return new Promise<Uint8Array>((resolve, reject): void => {
      const instance = userAuth.getUserAuthInstance({
        challenge: challenge,
        authType: [type],
        authTrustLevel: userAuth.AuthTrustLevel.ATL2,
        skipLockedBiometricAuth: false
      }, {
        title: title,
        navigationButtonText: '使用密码'
      });
      let settled = false;
      let timeoutId = -1;
      const callback: userAuth.IAuthCallback = {
        onResult: (result: userAuth.UserAuthResult): void => {
          if (settled) { return; }
          settled = true;
          if (timeoutId >= 0) { clearTimeout(timeoutId); }
          instance.off('result', callback);
          challenge.fill(0);
          if (result.result === userAuth.UserAuthResultCode.SUCCESS && result.token) {
            const token = result.token;
            // The system authentication window disappears asynchronously after the success callback.
            // Resolve after its touch-intercepting layer has had time to leave the window.
            setTimeout((): void => resolve(token), 1500);
          } else if (result.result === userAuth.UserAuthResultCode.CANCELED) {
            reject(new Error(type === userAuth.UserAuthType.FACE ? '已取消人脸认证' : '已取消指纹认证'));
          } else if (result.result === userAuth.UserAuthResultCode.LOCKED) {
            reject(new Error(type === userAuth.UserAuthType.FACE ?
              '人脸认证已被系统锁定，请使用密码解锁设备后重试' :
              '指纹认证已被系统锁定，请使用密码解锁设备后重试'));
          } else if (result.result === userAuth.UserAuthResultCode.TIMEOUT) {
            reject(new Error('认证已超时，请重试或改用密码'));
          } else if (result.result === userAuth.UserAuthResultCode.BUSY) {
            reject(new Error('系统认证服务正忙，请稍后重试'));
          } else {
            reject(new Error(type === userAuth.UserAuthType.FACE ? '人脸认证未通过' : '指纹认证未通过'));
          }
        }
      };
      instance.on('result', callback);
      timeoutId = setTimeout((): void => {
        if (settled) { return; }
        settled = true;
        instance.off('result', callback);
        try { instance.cancel(); } catch (_) { }
        challenge.fill(0);
        reject(new Error('系统认证暂时无响应，请改用密码或稍后重试'));
      }, 12000);
      try {
        instance.start();
      } catch (error) {
        settled = true;
        if (timeoutId >= 0) { clearTimeout(timeoutId); }
        instance.off('result', callback);
        challenge.fill(0);
        const businessError = error as BusinessError;
        if (businessError.code === userAuth.UserAuthResultCode.LOCKED) {
          reject(new Error(type === userAuth.UserAuthType.FACE ?
            '人脸认证已被系统锁定，请使用密码解锁设备后重试' :
            '指纹认证已被系统锁定，请使用密码解锁设备后重试'));
        } else if (businessError.code === userAuth.UserAuthResultCode.BUSY) {
          reject(new Error('系统认证服务正忙，请稍后重试'));
        } else {
          reject(error);
        }
      }
    });
      } catch (error) {
      throw normalizeError(error);
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
      throw normalizeError(error);
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
      throw new Error('生物认证凭据已损坏，请使用密码登录后重新启用');
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
      throw normalizeError(error);
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
      throw normalizeError(error);
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
