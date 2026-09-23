import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const read = (relativePath) => fs.readFileSync(path.join(root, relativePath), 'utf8');
const json = (relativePath) => JSON.parse(read(relativePath));
const assert = (condition, message) => {
  if (!condition) {
    console.error(`Release metadata regression failed: ${message}`);
    process.exit(1);
  }
};

const app = json('AppScope/app.json5').app;
const rootPackage = json('oh-package.json5');
const entryPackage = json('entry/oh-package.json5');
const strings = json('entry/src/main/resources/base/element/string.json').string;
const englishStrings = json('entry/src/main/resources/en_US/element/string.json').string;
const template = json('build-profile.example.json5');
const entryProfile = json('entry/build-profile.json5');
const hvigor = read('entry/hvigorfile.ts');
const limits = read('entry/src/main/ets/services/VaultLimits.ets');
const corePolicy = read('entry/src/main/ets/services/VaultCorePolicy.ets');
const picker = read('entry/src/main/ets/services/MediaPickerService.ets');
const sharedImport = read('entry/src/main/ets/services/ShareImportService.ets');
const repository = read('entry/src/main/ets/services/VaultRepository.ets');
const shareAbility = read('entry/src/main/ets/entryability/ShareReceiverAbility.ets');
const preflight = read('scripts/preflight.ps1');
const testRunner = read('scripts/test-core.ps1');
const preCommitHook = read('.githooks/pre-commit');
const hookInstaller = read('scripts/install-git-hooks.ps1');
const lockfile = json('oh-package-lock.json5');

assert(app.bundleName === 'com.palmkeep.app', 'bundleName must remain com.palmkeep.app');
assert(app.vendor === 'PalmKeep', 'vendor must remain PalmKeep');
assert(rootPackage.license === 'UNLICENSED' && entryPackage.license === 'UNLICENSED',
  'both packages must remain proprietary (UNLICENSED)');
assert(rootPackage.devDependencies?.['@ohos/hypium'] === '1.0.18',
  'the core-test framework version must remain pinned');
assert(lockfile.specifiers?.['@ohos/hypium@1.0.18'] === '@ohos/hypium@1.0.18',
  'the core-test framework must remain in the dependency lockfile');
assert(rootPackage.name === 'palmkeep' && rootPackage.author === 'PalmKeep' && entryPackage.author === 'PalmKeep',
  'package metadata must use the PalmKeep brand');
assert(englishStrings.some((item) => item.name === 'app_name' && item.value === 'PalmKeep'),
  'the English application name must remain PalmKeep');
assert(!rootPackage.description.includes('资料加密存储') && !rootPackage.description.includes('附件加密存储'),
  'package description must not claim additional at-rest encryption');
assert(strings.some((item) => item.name === 'module_desc' &&
  !item.value.includes('资料加密存储') && !item.value.includes('附件加密存储')),
  'module description must not claim additional at-rest encryption');

const products = new Map(template.app.products.map((product) => [product.name, product]));
for (const name of ['default', 'localRelease', 'debug']) {
  const product = products.get(name);
  assert(product, `build-profile template is missing ${name}`);
  assert(product.compatibleSdkVersion === '5.0.0(12)', `${name} must be compatible with API 12`);
  assert(product.targetSdkVersion === '6.0.1(21)', `${name} must target API 21`);
}
const releaseOptions = entryProfile.buildOptionSet.find((option) => option.name === 'release');
assert(releaseOptions?.arkOptions?.obfuscation?.ruleOptions?.enable === true,
  'Release obfuscation must remain enabled');
assert(hvigor.includes("gitOutput(repoRoot, ['rev-parse', 'HEAD'])") && hvigor.includes("${dirty ? '-dirty' : ''}"),
  'build metadata must identify the Git revision and dirty builds');
assert(limits.includes('MAX_IMPORTED_IMAGE_BYTES: number = 64 * 1024 * 1024'),
  'the 64 MB image import limit must remain explicit');
assert(limits.includes('MAX_IMPORTED_VIDEO_BYTES: number = 500 * 1024 * 1024'),
  'the 500 MB video import limit must remain explicit');
assert(limits.includes('MAX_SHARED_IMPORT_BYTES: number = 1024 * 1024 * 1024'),
  'the 1 GB shared-import aggregate limit must remain explicit');
assert(corePolicy.includes('size > MAX_IMPORTED_IMAGE_BYTES') &&
  corePolicy.includes('size > MAX_IMPORTED_VIDEO_BYTES'),
  'the shared core policy must enforce per-file media limits');
assert(picker.includes('validateImportedAttachmentSize(type, size, name)') &&
  picker.includes('checkedTotalBytes(totalBytes, size, MAX_MEDIA_IMPORT_BATCH_BYTES'),
  'the system media picker must enforce per-file and aggregate limits');
assert(sharedImport.includes('validateImportedAttachmentSize(type, size, name)') &&
  sharedImport.includes('checkedTotalBytes(totalBytes, size, MAX_SHARED_IMPORT_BYTES'),
  'shared media import must enforce per-file and aggregate limits');
assert(repository.includes('validateStoredAttachmentSize(attachment.type, size, attachment.name)'),
  'the repository must reject oversized media as a final safeguard');
assert(shareAbility.includes("import { BUNDLE_NAME } from 'BuildProfile'") &&
  shareAbility.includes('bundleName: BUNDLE_NAME'),
  'the share extension must launch the configured application bundle');
assert(hvigor.includes("postDependencies: ['assembleHap']") &&
  hvigor.includes("name: 'palmKeepCoreTest'") && testRunner.includes('test_result.txt'),
  'every HAP build must execute and verify core unit tests');
assert(preflight.includes('assembleHap') && preflight.includes('palmKeepCoreTest'),
  'release preflight must rely on the mandatory Hvigor core-test gate');
assert(preCommitHook.includes('scripts/test-core.ps1') &&
  preCommitHook.includes('commit aborted') && hookInstaller.includes('core.hooksPath .githooks'),
  'Git commits must be protected by the repository core-test hook');
for (const testFile of [
  'entry/src/test/VaultCorePolicy.test.ets',
  'entry/src/test/VaultBackupValidation.test.ets',
  'entry/src/test/VaultSchemaDefinition.test.ets',
  'entry/src/test/VaultModels.test.ets',
  'entry/src/test/VaultByteUtils.test.ets'
]) {
  assert(fs.existsSync(path.join(root, testFile)), `missing core test file: ${testFile}`);
}

console.log('Release metadata regression checks passed.');
