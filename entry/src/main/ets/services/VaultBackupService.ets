import common from '@ohos.app.ability.common';
import fs from '@ohos.file.fs';
import picker from '@ohos.file.picker';
import zlib from '@ohos.zlib';
import cryptoFramework from '@ohos.security.cryptoFramework';
import util from '@ohos.util';
import { logRecoverableError, normalizeError } from './ErrorUtils';
import { vaultRepository } from './VaultRepository';
import {
  BACKUP_FORMAT_VERSION,
  BackupAttachmentRecord,
  BackupFileRecord,
  BackupGroupRecord,
  BackupGroupTombstoneRecord,
  BackupItemRecord,
  BackupManifest,
  BackupProgress,
  BackupRestorePreview,
  BackupRestoreResult,
  BackupSummary,
  VaultBackupDataset
} from '../models/VaultBackupModels';

const HEADER_SIZE: number = 64;
const MAGIC: Uint8Array = new Uint8Array([80, 65, 76, 77, 86, 76, 84, 49]); // PALMVLT1
const SALT_SIZE: number = 16;
const IV_SIZE: number = 12;
const TAG_SIZE: number = 16;
const PASSWORD_CHECK_SIZE: number = 4;
const HEADER_LAYOUT_VERSION: number = 1;
const KDF_ITERATIONS: number = 210000;
const CHUNK_SIZE: number = 1024 * 1024;
const DATABASE_VERSION: number = 1;
const DATA_FILE: string = 'vault-data.json';
const MANIFEST_FILE: string = 'manifest.json';

export interface PreparedVaultBackup {
  workspacePath: string;
  extractedPath: string;
  manifest: BackupManifest;
  dataset: VaultBackupDataset;
  preview: BackupRestorePreview;
}

export class VaultBackupService {
  private readonly context: common.UIAbilityContext;
  private readonly encoder: util.TextEncoder = new util.TextEncoder();

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  async chooseBackupFile(): Promise<string | undefined> {
    try {
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      options.fileSuffixFilters = ['掌心密匣备份|.palmvault'];
      const uris = await new picker.DocumentViewPicker(this.context).select(options);
      return uris.length > 0 ? uris[0] : undefined;
    } catch (error) {
      if (this.isCancelled(error)) { return undefined; }
      throw new Error('无法选择备份文件');
    }
  }

  async createBackup(password: string, appVersion: string,
    onProgress?: (progress: BackupProgress) => void): Promise<boolean> {
    const workspace = this.createWorkspace();
    try {
      this.progress(onProgress, '准备资料', 0, 1);
      const dataset = await vaultRepository.exportBackupDataset();
      if (dataset.items.length === 0) {
        throw new Error('保险库中没有任何资料，无需创建备份');
      }
      const files: BackupFileRecord[] = [];
      let attachmentBytes = 0;
      const archiveInputs: string[] = [];
      for (let index = 0; index < dataset.attachments.length; index += 1) {
        const attachment = dataset.attachments[index];
        const sourcePath = vaultRepository.backupAttachmentPath(attachment.storageName);
        const path = `${workspace}/${attachment.storageName}`;
        await this.copyFile(sourcePath, path);
        const size = fs.statSync(path).size;
        if (size !== attachment.sizeBytes) { throw new Error(`附件 ${attachment.name} 不完整`); }
        const sha256 = await this.sha256(path);
        attachment.sha256 = sha256;
        files.push({ storageName: attachment.storageName, sizeBytes: size, sha256: sha256 });
        attachmentBytes += size;
        archiveInputs.push(path);
        this.progress(onProgress, '校验附件', index + 1, dataset.attachments.length);
      }
      const dataPath = `${workspace}/${DATA_FILE}`;
      this.writeText(dataPath, JSON.stringify(dataset));
      archiveInputs.unshift(dataPath);
      const manifest: BackupManifest = {
        formatVersion: BACKUP_FORMAT_VERSION,
        databaseVersion: DATABASE_VERSION,
        appVersion: appVersion,
        createdAt: Date.now(),
        groupCount: dataset.groups.length,
        groupTombstoneCount: dataset.groupTombstones.length,
        itemCount: dataset.items.length,
        trashCount: 0,
        attachmentCount: dataset.attachments.length,
        attachmentBytes: attachmentBytes,
        dataSha256: await this.sha256(dataPath),
        files: files
      };
      this.validateDataset(dataset, manifest);
      const manifestPath = `${workspace}/${MANIFEST_FILE}`;
      this.writeText(manifestPath, JSON.stringify(manifest));
      archiveInputs.push(manifestPath);

      this.progress(onProgress, '整理备份', 0, 1);
      const zipPath = `${workspace}/payload.zip`;
      await zlib.compressFiles(archiveInputs, zipPath,
        { level: zlib.CompressLevel.COMPRESS_LEVEL_BEST_SPEED });
      const encryptedPath = `${workspace}/PalmVault.palmvault`;
      this.progress(onProgress, '加密备份', 0, 1);
      await this.encryptFile(zipPath, encryptedPath, password, onProgress);

      // Never offer a backup for saving until this device can decrypt it again.
      // This catches crypto/header regressions before the user trusts the file.
      this.progress(onProgress, '验证加密备份', 0, 1);
      const verificationZipPath = `${workspace}/verification.zip`;
      await this.decryptFile(encryptedPath, verificationZipPath, password);
      if (await this.sha256(zipPath) !== await this.sha256(verificationZipPath)) {
        throw new Error('加密备份自检失败，未生成可供恢复的文件');
      }
      try { fs.unlinkSync(verificationZipPath); }
      catch (error) { logRecoverableError('could not remove backup verification file', error); }

      const saveOptions = new picker.DocumentSaveOptions();
      saveOptions.newFileNames = [this.backupFileName()];
      saveOptions.fileSuffixChoices = ['掌心密匣备份|.palmvault'];
      let targets: string[] = [];
      try {
        targets = await new picker.DocumentViewPicker(this.context).save(saveOptions);
      } catch (error) {
        if (this.isCancelled(error)) { return false; }
        throw normalizeError(error);
      }
      if (targets.length === 0) { return false; }
      this.progress(onProgress, '保存备份', 0, 1);
      await this.copyFile(encryptedPath, targets[0]);
      this.progress(onProgress, '校验已保存文件', 0, 1);
      const savedCopyPath = `${workspace}/saved-copy.palmvault`;
      await this.copyFile(targets[0], savedCopyPath);
      if (await this.sha256(encryptedPath) !== await this.sha256(savedCopyPath)) {
        throw new Error('已保存的备份文件校验失败，请更换保存位置后重试');
      }
      this.progress(onProgress, '备份完成', 1, 1);
      return true;
    } catch (error) {
      throw new Error(`创建备份失败：${normalizeError(error).message}`);
    } finally {
      this.removeDirectory(workspace);
    }
  }

  async inspectBackup(uri: string, password: string,
    onProgress?: (progress: BackupProgress) => void, freshInstall: boolean = false): Promise<PreparedVaultBackup> {
    const workspace = this.createWorkspace();
    const encryptedPath = `${workspace}/selected.palmvault`;
    const zipPath = `${workspace}/payload.zip`;
    const extractedPath = `${workspace}/extracted`;
    let stage = '读取选中的备份文件';
    try {
      fs.mkdirSync(extractedPath, true);
      this.progress(onProgress, '读取备份', 0, 1);
      await this.copyFile(uri, encryptedPath);
      stage = '解密与完整性认证';
      await this.decryptFile(encryptedPath, zipPath, password, onProgress);
      stage = '读取压缩包信息';
      const originalSize = await zlib.getOriginalSize(zipPath);
      if (originalSize <= 0 || originalSize > 50 * 1024 * 1024 * 1024) {
        throw new Error('备份解压大小异常');
      }
      this.progress(onProgress, '解压备份', 0, 1);
      stage = '解压备份内容';
      await zlib.decompressFile(zipPath, extractedPath,
        { level: zlib.CompressLevel.COMPRESS_LEVEL_DEFAULT_COMPRESSION });
      const manifestPath = `${extractedPath}/${MANIFEST_FILE}`;
      const dataPath = `${extractedPath}/${DATA_FILE}`;
      stage = '读取备份清单';
      const manifest = JSON.parse(fs.readTextSync(manifestPath)) as BackupManifest;
      stage = '校验备份版本和清单';
      this.validateManifest(manifest);
      stage = '校验资料数据';
      if (await this.sha256(dataPath) !== manifest.dataSha256) {
        throw new Error('备份内容校验失败');
      }
      stage = '校验备份附件';
      for (let index = 0; index < manifest.files.length; index += 1) {
        const file = manifest.files[index];
        this.validateStorageName(file.storageName);
        const path = `${extractedPath}/${file.storageName}`;
        if (fs.statSync(path).size !== file.sizeBytes || await this.sha256(path) !== file.sha256) {
          throw new Error('备份中的附件不完整');
        }
        this.progress(onProgress, '校验附件', index + 1, manifest.files.length);
      }
      stage = '读取资料索引';
      const dataset = JSON.parse(fs.readTextSync(dataPath)) as VaultBackupDataset;
      stage = '校验资料索引';
      this.validateDataset(dataset, manifest);
      const restoreDataset = this.activeRestoreDataset(dataset);
      let restoreAttachmentBytes = 0;
      restoreDataset.attachments.forEach((attachment: BackupAttachmentRecord): void => {
        restoreAttachmentBytes += attachment.sizeBytes;
      });
      const restoreManifest: BackupManifest = {
        formatVersion: manifest.formatVersion, databaseVersion: manifest.databaseVersion,
        appVersion: manifest.appVersion, createdAt: manifest.createdAt,
        groupCount: restoreDataset.groups.length, groupTombstoneCount: 0,
        itemCount: restoreDataset.items.length, trashCount: 0,
        attachmentCount: restoreDataset.attachments.length, attachmentBytes: restoreAttachmentBytes,
        dataSha256: manifest.dataSha256, files: manifest.files
      };
      stage = '生成恢复预览';
      const preview = freshInstall ? this.freshPreview(restoreDataset, restoreManifest) :
        await vaultRepository.previewBackupRestore(restoreDataset);
      preview.createdAt = restoreManifest.createdAt;
      return { workspacePath: workspace, extractedPath: extractedPath,
        manifest: restoreManifest, dataset: restoreDataset, preview: preview };
    } catch (error) {
      this.removeDirectory(workspace);
      const detail = normalizeError(error).message;
      console.error(`PalmVault backup inspection failed at ${stage}: ${detail}`);
      throw new Error(this.describeInspectionFailure(stage, detail));
    }
  }

  async applyPreparedBackup(prepared: PreparedVaultBackup,
    onProgress?: (progress: BackupProgress) => void): Promise<BackupRestoreResult> {
    try {
      this.progress(onProgress, '合并资料', 0, 1);
      const result = await vaultRepository.applyBackupDataset(prepared.dataset, prepared.extractedPath);
      this.progress(onProgress, '恢复完成', 1, 1);
      return result;
    } finally {
      this.disposePreparedBackup(prepared);
    }
  }

  disposePreparedBackup(prepared?: PreparedVaultBackup): void {
    if (prepared) { this.removeDirectory(prepared.workspacePath); }
  }

  summary(manifest: BackupManifest): BackupSummary {
    return { createdAt: manifest.createdAt, itemCount: manifest.itemCount, trashCount: manifest.trashCount,
      attachmentCount: manifest.attachmentCount, attachmentBytes: manifest.attachmentBytes };
  }

  private async encryptFile(sourcePath: string, targetPath: string, password: string,
    onProgress?: (progress: BackupProgress) => void): Promise<void> {
    try {
    const salt = cryptoFramework.createRandom().generateRandomSync(SALT_SIZE).data;
    const iv = cryptoFramework.createRandom().generateRandomSync(IV_SIZE).data;
    const keyBytes = this.deriveKey(password, salt);
    const passwordCheck = this.passwordCheck(keyBytes, salt);
    const header = this.createHeader(salt, iv, passwordCheck);
    const key = cryptoFramework.createSymKeyGenerator('AES256').convertKeySync({ data: keyBytes });
    const params: cryptoFramework.GcmParamsSpec = { algName: 'GcmParamsSpec', iv: { data: iv },
      aad: { data: header }, authTag: { data: new Uint8Array(TAG_SIZE) } };
    const cipher = cryptoFramework.createCipher('AES256|GCM');
    cipher.initSync(cryptoFramework.CryptoMode.ENCRYPT_MODE, key, params);
    const sourceSize = fs.statSync(sourcePath).size;
    let source: fs.File | undefined = undefined;
    let target: fs.File | undefined = undefined;
    try {
      source = fs.openSync(sourcePath, fs.OpenMode.READ_ONLY);
      target = fs.openSync(targetPath, fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      this.writeAll(target.fd, header);
      let completed = 0;
      while (completed < sourceSize) {
        const length = Math.min(CHUNK_SIZE, sourceSize - completed);
        const buffer = new ArrayBuffer(length);
        const read = fs.readSync(source.fd, buffer, { length: length });
        if (read <= 0) { throw new Error('备份数据读取不完整'); }
        const encryptedResult = cipher.updateSync({ data: new Uint8Array(buffer, 0, read) }) as
          cryptoFramework.DataBlob | null;
        const encrypted = encryptedResult ? encryptedResult.data : new Uint8Array(0);
        if (encrypted.length > 0) { this.writeAll(target.fd, encrypted); }
        completed += read;
        this.progress(onProgress, '加密备份', completed, sourceSize);
      }
      const tagResult = cipher.doFinalSync(null) as cryptoFramework.DataBlob | null;
      if (!tagResult) { throw new Error('备份完整性标签生成失败'); }
      const tag = tagResult.data;
      if (tag.length !== TAG_SIZE) { throw new Error('备份完整性标签生成失败'); }
      // Append the tag sequentially. Do not seek back into the header: document
      // providers and platform releases differ in random-write offset behavior.
      this.writeAll(target.fd, tag);
      fs.fsyncSync(target.fd);
    } finally {
      if (target) { fs.closeSync(target); }
      if (source) { fs.closeSync(source); }
      keyBytes.fill(0);
      salt.fill(0);
      iv.fill(0);
    }
    } catch (error) {
      throw normalizeError(error);
    }
  }

  private async decryptFile(sourcePath: string, targetPath: string, password: string,
    onProgress?: (progress: BackupProgress) => void): Promise<void> {
    try {
    const sourceSize = fs.statSync(sourcePath).size;
    if (sourceSize <= HEADER_SIZE + TAG_SIZE) { throw new Error('备份文件不完整'); }
    let source: fs.File | undefined = undefined;
    let target: fs.File | undefined = undefined;
    let keyBytes = new Uint8Array(0);
    try {
      source = fs.openSync(sourcePath, fs.OpenMode.READ_ONLY);
      const header = this.readExact(source.fd, HEADER_SIZE, '备份文件头不完整');
      this.validateHeader(header);
      const salt = header.slice(16, 32);
      const iv = header.slice(32, 44);
      fs.lseek(source.fd, sourceSize - TAG_SIZE, fs.WhenceType.SEEK_SET);
      const tag = this.readExact(source.fd, TAG_SIZE, '备份完整性标签缺失');
      if (this.isZeroBytes(tag)) { throw new Error('备份完整性标签缺失'); }
      const cipherSize = sourceSize - HEADER_SIZE - TAG_SIZE;
      keyBytes = this.deriveKey(password, salt);
      const storedPasswordCheck = header.slice(60, 64);
      if (!this.constantTimeEquals(storedPasswordCheck, this.passwordCheck(keyBytes, salt))) {
        throw new Error('备份密码不正确');
      }
      const key = cryptoFramework.createSymKeyGenerator('AES256').convertKeySync({ data: keyBytes });
      const params: cryptoFramework.GcmParamsSpec = { algName: 'GcmParamsSpec', iv: { data: iv },
        aad: { data: header }, authTag: { data: tag } };
      const cipher = cryptoFramework.createCipher('AES256|GCM');
      cipher.initSync(cryptoFramework.CryptoMode.DECRYPT_MODE, key, params);
      target = fs.openSync(targetPath, fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.lseek(source.fd, HEADER_SIZE, fs.WhenceType.SEEK_SET);
      let completed = 0;
      while (completed < cipherSize) {
        const length = Math.min(CHUNK_SIZE, cipherSize - completed);
        const buffer = new ArrayBuffer(length);
        const read = fs.readSync(source.fd, buffer, { length: length });
        if (read <= 0) { throw new Error('备份密文读取不完整'); }
        const decryptedResult = cipher.updateSync({ data: new Uint8Array(buffer, 0, read) }) as
          cryptoFramework.DataBlob | null;
        const decrypted = decryptedResult ? decryptedResult.data : new Uint8Array(0);
        if (decrypted.length > 0) { this.writeAll(target.fd, decrypted); }
        completed += read;
        this.progress(onProgress, '解密并校验', completed, cipherSize);
      }
      let finalResult: cryptoFramework.DataBlob | null = null;
      try {
        finalResult = cipher.doFinalSync(null) as cryptoFramework.DataBlob | null;
      } catch (_) {
        throw new Error('备份密文完整性认证失败，文件内容已改变');
      }
      const finalData = finalResult ? finalResult.data : new Uint8Array(0);
      if (finalData.length > 0) { this.writeAll(target.fd, finalData); }
      fs.fsyncSync(target.fd);
    } finally {
      if (target) { fs.closeSync(target); }
      if (source) { fs.closeSync(source); }
      keyBytes.fill(0);
    }
    } catch (error) {
      throw normalizeError(error);
    }
  }

  private createHeader(salt: Uint8Array, iv: Uint8Array, passwordCheck: Uint8Array): Uint8Array {
    const header = new Uint8Array(HEADER_SIZE);
    header.set(MAGIC, 0);
    header[8] = BACKUP_FORMAT_VERSION;
    header[9] = HEADER_LAYOUT_VERSION;
    header[12] = KDF_ITERATIONS & 255;
    header[13] = (KDF_ITERATIONS >>> 8) & 255;
    header[14] = (KDF_ITERATIONS >>> 16) & 255;
    header[15] = (KDF_ITERATIONS >>> 24) & 255;
    header.set(salt, 16);
    header.set(iv, 32);
    header.set(passwordCheck, 60);
    return header;
  }

  private passwordCheck(keyBytes: Uint8Array, salt: Uint8Array): Uint8Array {
    try {
      const digest = cryptoFramework.createMd('SHA256');
      digest.updateSync({ data: keyBytes });
      digest.updateSync({ data: salt });
      digest.updateSync({ data: MAGIC });
      return digest.digestSync().data.slice(0, PASSWORD_CHECK_SIZE);
    } catch (error) {
      throw normalizeError(error);
    }
  }

  private constantTimeEquals(left: Uint8Array, right: Uint8Array): boolean {
    if (left.length !== right.length) { return false; }
    let difference = 0;
    for (let index = 0; index < left.length; index += 1) { difference |= left[index] ^ right[index]; }
    return difference === 0;
  }

  private validateHeader(header: Uint8Array): void {
    for (let index = 0; index < MAGIC.length; index += 1) {
      if (header[index] !== MAGIC[index]) { throw new Error('不是掌心密匣备份文件'); }
    }
    if (header[8] > BACKUP_FORMAT_VERSION) { throw new Error('备份版本高于当前应用支持的版本'); }
    if (header[8] !== BACKUP_FORMAT_VERSION) { throw new Error('备份格式版本无效'); }
    if (header[9] !== HEADER_LAYOUT_VERSION || !this.isZeroBytes(header.slice(10, 12)) ||
      !this.isZeroBytes(header.slice(44, 60))) { throw new Error('备份文件头布局无效'); }
    const iterations = header[12] | (header[13] << 8) | (header[14] << 16) | (header[15] << 24);
    if (iterations !== KDF_ITERATIONS) { throw new Error('备份密码参数无效'); }
  }

  private deriveKey(password: string, salt: Uint8Array): Uint8Array {
    try {
    if (password.length === 0) { throw new Error('密码不能为空'); }
    const kdf = cryptoFramework.createKdf('PBKDF2|SHA256');
    return kdf.generateSecretSync({ algName: 'PBKDF2', password: password, salt: salt,
      iterations: KDF_ITERATIONS, keySize: 32 } as cryptoFramework.PBKDF2Spec).data;
    } catch (error) {
      throw normalizeError(error);
    }
  }

  private async sha256(path: string): Promise<string> {
    try {
    const digest = cryptoFramework.createMd('SHA256');
    let file: fs.File | undefined = undefined;
    try {
      file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      const size = fs.statSync(file.fd).size;
      let completed = 0;
      while (completed < size) {
        const length = Math.min(CHUNK_SIZE, size - completed);
        const buffer = new ArrayBuffer(length);
        const read = fs.readSync(file.fd, buffer, { length: length });
        if (read <= 0) { throw new Error('文件校验失败'); }
        await digest.update({ data: new Uint8Array(buffer, 0, read) });
        completed += read;
      }
      return this.hex((await digest.digest()).data);
    } finally {
      if (file) { fs.closeSync(file); }
    }
    } catch (error) {
      throw normalizeError(error);
    }
  }

  private validateManifest(manifest: BackupManifest): void {
    if (!manifest || manifest.formatVersion !== BACKUP_FORMAT_VERSION) { throw new Error('备份格式版本无效'); }
    if (manifest.databaseVersion > DATABASE_VERSION) { throw new Error('备份数据库版本过新'); }
    if (manifest.itemCount === 0) { throw new Error('备份中没有任何资料，无法恢复'); }
    if ((manifest.groupCount !== undefined && manifest.groupCount < 0) ||
      (manifest.groupTombstoneCount !== undefined && manifest.groupTombstoneCount < 0) || manifest.itemCount < 0 ||
      manifest.attachmentCount < 0 || manifest.attachmentBytes < 0 ||
      manifest.files.length !== manifest.attachmentCount) { throw new Error('备份清单无效'); }
    const names = new Set<string>();
    manifest.files.forEach((file: BackupFileRecord): void => {
      this.validateStorageName(file.storageName);
      if (names.has(file.storageName) || file.sizeBytes <= 0 || file.sha256.length !== 64) {
        throw new Error('备份附件清单无效');
      }
      names.add(file.storageName);
    });
  }

  private validateDataset(dataset: VaultBackupDataset, manifest: BackupManifest): void {
    if (!dataset || !dataset.groups || !dataset.items || !dataset.attachments ||
      !dataset.groupTombstones || !dataset.itemTombstones) { throw new Error('备份数据结构不完整'); }
    if (manifest.groupCount !== undefined && dataset.groups.length !== manifest.groupCount) {
      throw new Error(`备份分组数量不一致：清单 ${manifest.groupCount}，实际 ${dataset.groups.length}`);
    }
    if (manifest.groupTombstoneCount !== undefined &&
      dataset.groupTombstones.length !== manifest.groupTombstoneCount) {
      throw new Error(`备份已删除分组数量不一致：清单 ${manifest.groupTombstoneCount}，` +
        `实际 ${dataset.groupTombstones.length}`);
    }
    if (dataset.items.length !== manifest.itemCount) {
      throw new Error(`备份资料数量不一致：清单 ${manifest.itemCount}，实际 ${dataset.items.length}`);
    }
    if (dataset.attachments.length !== manifest.attachmentCount) {
      throw new Error(`备份附件数量不一致：清单 ${manifest.attachmentCount}，` +
        `实际 ${dataset.attachments.length}`);
    }
    const activeGroupIds = new Set<number>();
    dataset.groups.forEach((group: BackupGroupRecord): void => {
      if (activeGroupIds.has(group.id)) { throw new Error('备份中存在重复分组'); }
      activeGroupIds.add(group.id);
    });
    const deletedGroupIds = new Set<number>();
    dataset.groupTombstones.forEach((group: BackupGroupTombstoneRecord): void => {
      if (activeGroupIds.has(group.groupId) || deletedGroupIds.has(group.groupId)) {
        throw new Error('备份中的分组状态冲突');
      }
      deletedGroupIds.add(group.groupId);
    });
    const itemIds = new Set<string>();
    dataset.items.forEach((item: BackupItemRecord): void => {
      if (itemIds.has(item.id)) { throw new Error('备份中存在重复资料'); }
      itemIds.add(item.id);
      if (item.deletedAt === 0 && !activeGroupIds.has(item.groupId)) {
        throw new Error(`资料“${item.title}”缺少对应的分组信息`);
      }
      if (item.deletedAt > 0 && !activeGroupIds.has(item.groupId) && !deletedGroupIds.has(item.groupId)) {
        throw new Error(`回收站资料“${item.title}”缺少原分组信息`);
      }
    });
    const fileNames = new Set<string>();
    manifest.files.forEach((file: BackupFileRecord): void => { fileNames.add(file.storageName); });
    const fileHashes = new Map<string, string>();
    manifest.files.forEach((file: BackupFileRecord): void => { fileHashes.set(file.storageName, file.sha256); });
    dataset.attachments.forEach((attachment): void => {
      if (!fileNames.has(attachment.storageName) || !itemIds.has(attachment.itemId) ||
        attachment.sha256.length !== 64 || fileHashes.get(attachment.storageName) !== attachment.sha256) {
        throw new Error('备份附件引用无效');
      }
    });
  }

  private freshPreview(dataset: VaultBackupDataset, manifest: BackupManifest): BackupRestorePreview {
    return { createdAt: manifest.createdAt, itemCount: manifest.itemCount, trashCount: manifest.trashCount,
      attachmentCount: manifest.attachmentCount, attachmentBytes: manifest.attachmentBytes,
      addedCount: dataset.items.length, updatedCount: 0, retainedCount: 0,
      newerCount: 0, conflictCount: 0, unchangedCount: 0, deletedCount: 0 };
  }

  private activeRestoreDataset(dataset: VaultBackupDataset): VaultBackupDataset {
    const activeItemIds = new Set<string>();
    const items = dataset.items.filter((item: BackupItemRecord): boolean => {
      if (item.deletedAt !== 0) { return false; }
      activeItemIds.add(item.id);
      return true;
    });
    const attachments = dataset.attachments.filter((attachment: BackupAttachmentRecord): boolean =>
      activeItemIds.has(attachment.itemId));
    return { groups: dataset.groups, items: items, attachments: attachments,
      groupTombstones: [], itemTombstones: [] };
  }

  private validateStorageName(name: string): void {
    if (name.length === 0 || name.indexOf('/') >= 0 || name.indexOf('\\') >= 0 || name.indexOf('..') >= 0 ||
      name === DATA_FILE || name === MANIFEST_FILE) {
      throw new Error('备份中包含不安全的文件名');
    }
  }

  private createWorkspace(): string {
    try {
    const path = `${this.context.tempDir}/palmvault-backup-${Date.now()}-${Math.floor(Math.random() * 1000000)}`;
    fs.mkdirSync(path, true);
    return path;
    } catch (error) {
      throw normalizeError(error);
    }
  }

  private writeText(path: string, value: string): void {
    try {
    let file: fs.File | undefined = undefined;
    try {
      file = fs.openSync(path, fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      this.writeAll(file.fd, this.encoder.encodeInto(value));
      fs.fsyncSync(file.fd);
    } finally { if (file) { fs.closeSync(file); } }
    } catch (error) {
      throw normalizeError(error);
    }
  }

  private async copyFile(sourcePath: string, targetPath: string): Promise<void> {
    try {
    let source: fs.File | undefined = undefined;
    let target: fs.File | undefined = undefined;
    try {
      source = fs.openSync(sourcePath, fs.OpenMode.READ_ONLY);
      target = fs.openSync(targetPath, fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      await fs.copyFile(source.fd, target.fd);
      fs.fsyncSync(target.fd);
    } finally {
      if (target) { fs.closeSync(target); }
      if (source) { fs.closeSync(source); }
    }
    } catch (error) {
      throw normalizeError(error);
    }
  }

  private writeAll(fd: number, data: Uint8Array): void {
    try {
      let written = 0;
      while (written < data.length) {
        const remaining = data.slice(written);
        const count = fs.writeSync(fd, remaining.buffer as ArrayBuffer, { length: remaining.length });
        if (count <= 0) { throw new Error('文件写入不完整'); }
        written += count;
      }
    } catch (error) {
      throw normalizeError(error);
    }
  }

  private readExact(fd: number, length: number, message: string): Uint8Array {
    try {
      const output = new Uint8Array(length);
      let completed = 0;
      while (completed < length) {
        const buffer = new ArrayBuffer(length - completed);
        const count = fs.readSync(fd, buffer, { length: length - completed });
        if (count <= 0) { throw new Error(message); }
        output.set(new Uint8Array(buffer, 0, count), completed);
        completed += count;
      }
      return output;
    } catch (error) {
      throw normalizeError(error);
    }
  }

  private isZeroBytes(data: Uint8Array): boolean {
    for (let index = 0; index < data.length; index += 1) {
      if (data[index] !== 0) { return false; }
    }
    return true;
  }

  private describeInspectionFailure(stage: string, detail: string): string {
    const safeDetail = detail.trim().slice(0, 180);
    if (stage === '解密与完整性认证') {
      if (safeDetail.indexOf('不是掌心密匣') >= 0 || safeDetail.indexOf('版本') >= 0 ||
        safeDetail.indexOf('参数') >= 0 || safeDetail.indexOf('标签缺失') >= 0 ||
        safeDetail.indexOf('文件头') >= 0 || safeDetail.indexOf('不完整') >= 0) {
        return `备份文件头校验失败：${safeDetail}`;
      }
      return `备份解密认证失败：密码不正确，或备份密文已被修改。底层错误：${safeDetail}`;
    }
    if (stage === '读取选中的备份文件') {
      return `无法读取选中的备份文件：${safeDetail}`;
    }
    if (stage === '读取压缩包信息' || stage === '解压备份内容') {
      return `备份已成功解密，但${stage}失败：${safeDetail}`;
    }
    return `${stage}失败：${safeDetail}`;
  }

  private removeDirectory(path: string): void {
    try {
      const names = fs.listFileSync(path);
      names.forEach((name: string): void => {
        const child = `${path}/${name}`;
        try {
          if (fs.statSync(child).isDirectory()) { this.removeDirectory(child); }
          else { fs.unlinkSync(child); }
        } catch (error) {
          logRecoverableError(`could not remove temporary backup entry ${child}`, error);
        }
      });
      fs.rmdirSync(path);
    } catch (error) {
      logRecoverableError(`could not remove temporary backup directory ${path}`, error);
    }
  }

  private hex(data: Uint8Array): string {
    let output = '';
    for (let index = 0; index < data.length; index += 1) {
      output += data[index].toString(16).padStart(2, '0');
    }
    return output;
  }

  private backupFileName(): string {
    const now = new Date();
    const two = (value: number): string => value.toString().padStart(2, '0');
    return `PalmVault-${now.getFullYear()}${two(now.getMonth() + 1)}${two(now.getDate())}-` +
      `${two(now.getHours())}${two(now.getMinutes())}.palmvault`;
  }

  private progress(callback: ((progress: BackupProgress) => void) | undefined,
    phase: string, completed: number, total: number): void {
    if (callback) { callback({ phase: phase, completed: completed, total: Math.max(total, 1) }); }
  }

  private isCancelled(error: Object): boolean {
    const message = normalizeError(error).message.toLowerCase();
    return message.indexOf('cancel') >= 0 || message.indexOf('取消') >= 0;
  }
}
