import vaultCorePolicyTest from './VaultCorePolicy.test';
import vaultBackupValidationTest from './VaultBackupValidation.test';
import vaultBackupMergePolicyTest from './VaultBackupMergePolicy.test';
import vaultBackupReminderPolicyTest from './VaultBackupReminderPolicy.test';
import vaultSchemaDefinitionTest from './VaultSchemaDefinition.test';
import vaultModelsTest from './VaultModels.test';
import vaultByteUtilsTest from './VaultByteUtils.test';

export default function testsuite(): void {
  vaultCorePolicyTest();
  vaultBackupValidationTest();
  vaultBackupMergePolicyTest();
  vaultBackupReminderPolicyTest();
  vaultSchemaDefinitionTest();
  vaultModelsTest();
  vaultByteUtilsTest();
}
