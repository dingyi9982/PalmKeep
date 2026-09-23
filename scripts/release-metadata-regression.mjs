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
const template = json('build-profile.example.json5');
const entryProfile = json('entry/build-profile.json5');
const hvigor = read('entry/hvigorfile.ts');
const limits = read('entry/src/main/ets/services/VaultLimits.ets');
const picker = read('entry/src/main/ets/services/MediaPickerService.ets');
const sharedImport = read('entry/src/main/ets/services/ShareImportService.ets');
const repository = read('entry/src/main/ets/services/VaultRepository.ets');
const shareAbility = read('entry/src/main/ets/entryability/ShareReceiverAbility.ets');

assert(app.bundleName === 'com.palmvault.app', 'bundleName must remain com.palmvault.app');
assert(rootPackage.license === 'UNLICENSED' && entryPackage.license === 'UNLICENSED',
  'both packages must remain proprietary (UNLICENSED)');
assert(!rootPackage.description.includes('纯本地加密'), 'package description must not overstate attachment encryption');
assert(strings.some((item) => item.name === 'module_desc' && !item.value.includes('纯本地加密')),
  'module description must not overstate attachment encryption');

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
assert(picker.includes('size > MAX_IMPORTED_IMAGE_BYTES') &&
  picker.includes('size > MAX_IMPORTED_VIDEO_BYTES') &&
  picker.includes('totalBytes > MAX_MEDIA_IMPORT_BATCH_BYTES'),
  'the system media picker must enforce per-file and aggregate limits');
assert(sharedImport.includes('size > MAX_IMPORTED_IMAGE_BYTES') &&
  sharedImport.includes('size > MAX_IMPORTED_VIDEO_BYTES') &&
  sharedImport.includes('totalBytes > MAX_SHARED_IMPORT_BYTES'),
  'shared media import must enforce per-file and aggregate limits');
assert(repository.includes('size > MAX_IMPORTED_IMAGE_BYTES') &&
  repository.includes('size > MAX_IMPORTED_VIDEO_BYTES'),
  'the repository must reject oversized media as a final safeguard');
assert(shareAbility.includes("import { BUNDLE_NAME } from 'BuildProfile'") &&
  shareAbility.includes('bundleName: BUNDLE_NAME'),
  'the share extension must launch the configured application bundle');

console.log('Release metadata regression checks passed.');
