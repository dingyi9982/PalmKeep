import promptAction from '@ohos.promptAction';
import pasteboard from '@ohos.pasteboard';
import { VERSION_CODE, VERSION_NAME } from 'BuildProfile';
import { VaultLoadingScreen, VaultLockedScreen, VaultSetupScreen } from '../components/VaultAuthScreens';
import { VaultSettingsPanel } from '../components/VaultSettingsPanel';
import { VaultBackupDialog } from '../components/VaultBackupDialog';
import { VaultBottomNavigation } from '../components/VaultBottomNavigation';
import { VaultGroupManager } from '../components/VaultGroupManager';
import { VaultCategoryPanel } from '../components/VaultCategoryPanel';
import { VaultItemDetailDialog } from '../components/VaultItemDetailDialog';
import { VaultTrashDetailDialog } from '../components/VaultTrashDetailDialog';
import { VaultLoginFieldsEditor } from '../components/VaultLoginFieldsEditor';
import {
  ChangePasswordDialog, GestureSetupDialog, RecoveryCenterDialog, ResetVaultDialog
} from '../components/VaultSecurityDialogs';
import {
  COLOR_BG, COLOR_BORDER, COLOR_CARD_HIGHLIGHT, COLOR_CHEVRON, COLOR_DANGER,
  COLOR_DANGER_TINT, COLOR_DANGER_WASH, COLOR_DANGER_WASH_STRONG, COLOR_DARK_ACTION,
  COLOR_DISABLED, COLOR_DIVIDER_SOFT, COLOR_GROUP_DRAG,
  COLOR_HERO_MUTED, COLOR_HERO_PILL, COLOR_HERO_SURFACE, COLOR_HERO_TEXT, COLOR_HERO_TITLE,
  COLOR_MUTED, COLOR_MUTED_LIGHT, COLOR_ON_DARK, COLOR_PLACEHOLDER, COLOR_PLACEHOLDER_LIGHT,
  COLOR_PRIMARY, COLOR_PRIMARY_ALT_TINT, COLOR_PRIMARY_TINT, COLOR_PRIMARY_WASH, COLOR_SCRIM,
  COLOR_SCRIM_STRONG, COLOR_SURFACE, COLOR_SURFACE_2, COLOR_TEXT, COLOR_TEXT_SECONDARY
} from '../components/VaultTheme';
import { VaultThumbnail } from '../components/VaultThumbnail';
import { VaultAttachmentPreview } from '../components/VaultAttachmentPreview';
import { VaultFileSummary } from '../components/VaultFileSummary';
import { VaultDialogHeader } from '../components/VaultCommonComponents';
import {
  ACTION_CANCEL, ACTION_DELETE, ACTION_MANAGE, ACTION_SAVE, LABEL_CONTENT, LABEL_NAME, LABEL_NOTES
} from '../components/VaultCopy';
import { AbilityContextHolder } from '../services/AbilityContextHolder';
import { logRecoverableError, normalizeError } from '../services/ErrorUtils';
import { QuickUnlockStatus, VaultSecurityService } from '../services/VaultSecurityService';
import { mediaPickerService, PickedMedia } from '../services/MediaPickerService';
import { mediaCompressionService } from '../services/MediaCompressionService';
import { mediaOcrService } from '../services/MediaOcrService';
import { vaultRepository } from '../services/VaultRepository';
import { PreparedVaultBackup, VaultBackupService } from '../services/VaultBackupService';
import { vaultUiPreferences } from '../services/VaultUiPreferences';
import { BUILD_GIT_LABEL } from '../generated/BuildMetadata';
import {
  itemDisplayTitle,
  itemTypeLabel,
  VaultAttachmentInput,
  VaultGroup,
  VaultItem,
  VaultItemInput,
  VaultSearchHit,
  VaultTrashEntry,
  VaultItemType
} from '../models/VaultModels';
import { BackupProgress, BackupRestoreResult } from '../models/VaultBackupModels';

@Entry
@Component
struct Index {
  @StorageLink('vaultLockedByLifecycle') @Watch('handleLifecycleLock')
  private lifecycleLocked: boolean = false;
  @StorageLink('vaultAutoLockMinutes')
  private autoLockMinutes: number = 10;
  @StorageLink('vaultLifecycleSuppressed')
  private lifecycleLockSuppressed: boolean = false;
  @State private screen: string = 'loading';
  @State private activeTab: number = 0;
  @State private masterPassword: string = '';
  @State private confirmPassword: string = '';
  @State private busy: boolean = false;
  @State private errorMessage: string = '';
  @State private groups: VaultGroup[] = [];
  @State private items: VaultItem[] = [];
  @State private allItems: VaultItem[] = [];
  @State private totalItemCount: number = 0;
  @State private loginCount: number = 0;
  @State private noteCount: number = 0;
  @State private mediaCount: number = 0;
  @State private fileCount: number = 0;
  @State private searchText: string = '';
  @State private searchHits: VaultSearchHit[] = [];
  @State private searchActive: boolean = false;
  @State private showNewItem: boolean = false;
  @State private showNewGroup: boolean = false;
  @State private expandedGroupId: number = -1;
  @State private draggingGroupId: number = -1;
  @State private draggingGroupName: string = '';
  @State private groupDropTargetId: number = -1;
  @State private groupDragCancelActive: boolean = false;
  @State private selectedCategoryType: VaultItemType = VaultItemType.Login;
  @State private categoryGroupId: number = -1;
  @State private categorySort: string = 'updated';
  @State private showGestureSetup: boolean = false;
  @State private gestureSetupStep: number = 1;
  @State private gestureSetupHint: string = '绘制新手势';
  @State private gestureEnabled: boolean = false;
  @State private fingerprintEnabled: boolean = false;
  @State private fingerprintAvailable: boolean = false;
  @State private faceEnabled: boolean = false;
  @State private faceAvailable: boolean = false;
  @State private preferredUnlock: string = 'password';
  @State private unlockMode: string = 'password';
  @State private gestureFailures: number = 0;
  @State private gestureCooldownUntil: number = 0;
  @State private trashEntries: VaultTrashEntry[] = [];
  @State private trashTypeFilter: string = 'all';
  @State private trashManaging: boolean = false;
  @State private trashSelectedIds: string[] = [];
  @State private showTrashMore: boolean = false;
  @State private trashBusy: boolean = false;
  @State private selectedTrashEntry?: VaultTrashEntry = undefined;
  @State private revealTrashPassword: boolean = false;
  @State private selectedItem?: VaultItem = undefined;
  @State private selectedAttachmentIndex: number = -1;
  @State private revealPassword: boolean = false;
  @State private showChangePassword: boolean = false;
  @State private currentPassword: string = '';
  @State private changedPassword: string = '';
  @State private changedPasswordConfirm: string = '';
  @State private passwordChangeBusy: boolean = false;
  @State private showResetVault: boolean = false;
  @State private resetVaultConfirmText: string = '';
  @State private resetVaultBusy: boolean = false;
  @State private showRecoveryCenter: boolean = false;
  @State private recoveryAuthenticated: boolean = false;
  @State private recoveryAuthLabel: string = '';
  @State private recoveryNewPassword: string = '';
  @State private recoveryPasswordConfirm: string = '';
  @State private recoveryBusy: boolean = false;
  @State private newType: VaultItemType = VaultItemType.Note;
  @State private newTitle: string = '';
  @State private newUsername: string = '';
  @State private newPassword: string = '';
  @State private newWebsite: string = '';
  @State private revealNewPassword: boolean = false;
  @State private newNotes: string = '';
  @State private selectedMediaCount: number = 0;
  @State private selectedMediaPreviewIndex: number = 0;
  @State private recognizingMedia: boolean = false;
  @State private recognitionProgressText: string = '';
  @State private selectedFileCount: number = 0;
  @State private savingNewItem: boolean = false;
  @State private saveProgress: number = 0;
  @State private saveProgressText: string = '';
  @State private newGroupId: number = 0;
  @State private newGroupName: string = '';
  @State private groupPendingRename?: VaultGroup = undefined;
  @State private groupRenameName: string = '';
  @State private groupPendingDelete?: VaultGroup = undefined;
  @State private showGroupManager: boolean = false;
  @State private groupDeleteConfirmName: string = '';
  @State private groupPendingDeleteCount: number = 0;
  @State private detailTitle: string = '';
  @State private detailUsername: string = '';
  @State private detailPassword: string = '';
  @State private detailWebsite: string = '';
  @State private detailNotes: string = '';
  @State private detailGroupId: number = 0;
  @State private showBackupDialog: boolean = false;
  @State private backupAction: string = 'create';
  @State private backupStage: string = 'password';
  @State private backupPassword: string = '';
  @State private backupBusy: boolean = false;
  @State private backupError: string = '';
  @State private backupProgressText: string = '';
  @State private backupProgressValue: number = 0;
  @State private backupDateText: string = '';
  @State private backupItemCount: number = 0;
  @State private backupAttachmentCount: number = 0;
  @State private backupAttachmentSizeText: string = '';
  @State private backupAddedCount: number = 0;
  @State private backupUpdatedCount: number = 0;
  @State private backupRetainedCount: number = 0;
  @State private backupNewerCount: number = 0;
  @State private backupConflictCount: number = 0;
  @State private backupUnchangedCount: number = 0;
  @State private backupDeletedCount: number = 0;
  @State private pendingMedia: PickedMedia[] = [];
  private pendingFiles: PickedMedia[] = [];
  private mediaRecognitionVersion: number = 0;
  private searchVersion: number = 0;
  private vaultRefreshVersion: number = 0;
  private trashRefreshVersion: number = 0;
  private trashLongPressTriggered: boolean = false;
  private groupDragClickSuppressed: boolean = false;
  private groupDragFinalizeScheduled: boolean = false;
  private groupDragAccepted: boolean = false;
  private groupDragCancelled: boolean = false;
  private groupsBeforeDrag: VaultGroup[] = [];
  private groupDragPositionLocked: boolean = false;
  private groupDragLastReorderX: number = 0;
  private groupDragLastReorderY: number = 0;
  private sessionKey: Uint8Array = new Uint8Array(0);
  private recoveryDatabaseKey: Uint8Array = new Uint8Array(0);
  private firstGesture: number[] = [];
  private selectedBackupUri: string = '';
  private preparedBackup?: PreparedVaultBackup = undefined;
  private restoringFreshInstall: boolean = false;
  private lastNewItemType: VaultItemType = VaultItemType.Note;
  private securityService?: VaultSecurityService = undefined;
  private backupService?: VaultBackupService = undefined;

  private getSecurityService(): VaultSecurityService {
    if (!this.securityService) {
      this.securityService = new VaultSecurityService(AbilityContextHolder.getContext());
    }
    return this.securityService;
  }

  private getBackupService(): VaultBackupService {
    if (!this.backupService) {
      this.backupService = new VaultBackupService(AbilityContextHolder.getContext());
    }
    return this.backupService;
  }

  aboutToAppear(): void {
    this.initialize();
  }

  onBackPress(): boolean {
    if (this.showBackupDialog && !this.backupBusy) {
      this.closeBackupDialog();
      return true;
    }
    if (this.showResetVault) {
      this.closeResetVault();
      return true;
    }
    if (this.showChangePassword) {
      this.closeChangePassword();
      return true;
    }
    if (this.showRecoveryCenter) {
      this.closeRecoveryCenter();
      return true;
    }
    if (this.showNewItem) {
      this.requestCloseNewItem();
      return true;
    }
    if (this.selectedTrashEntry) {
      this.closeTrashDetail();
      return true;
    }
    if (this.trashManaging) {
      this.closeTrashManagement();
      return true;
    }
    if (this.showTrashMore) {
      this.showTrashMore = false;
      return true;
    }
    return false;
  }

  private async initialize(): Promise<void> {
    try {
    try {
      this.lastNewItemType = await vaultUiPreferences.getLastNewItemType();
      this.newType = this.lastNewItemType;
      const security = this.getSecurityService();
      const initialized = await security.isInitialized();
      if (initialized) {
        await this.refreshQuickUnlockStatus();
        this.unlockMode = this.preferredUnlockMode();
      }
      this.screen = initialized ? 'locked' : 'setup';
      if (initialized && this.unlockMode === 'face') {
        this.unlockWithFace();
      } else if (initialized && this.unlockMode === 'fingerprint') {
        this.unlockWithFingerprint();
      }
    } catch (error) {
      this.errorMessage = this.describeError(error);
      this.screen = 'setup';
    }
      } catch (error) {
      throw normalizeError(error);
    }
  }

  private handleLifecycleLock(): void {
    if (!this.lifecycleLocked) {
      return;
    }
    this.lifecycleLocked = false;
    if (this.screen === 'vault') {
      this.lockVault();
    }
  }

  private async createVault(): Promise<void> {
    try {
    this.errorMessage = '';
    if (this.masterPassword.length === 0) {
      this.errorMessage = '密码不能为空';
      return;
    }
    if (this.masterPassword !== this.confirmPassword) {
      this.errorMessage = '两次输入的密码不一致';
      return;
    }
    this.busy = true;
    try {
      const security = this.getSecurityService();
      const key = await security.createMasterPassword(this.masterPassword);
      await this.openWithKey(key);
      this.masterPassword = '';
      this.confirmPassword = '';
      await this.refreshQuickUnlockStatus();
      await this.refreshData();
      await this.showVaultScreen();
    } catch (error) {
      this.errorMessage = this.describeError(error);
    } finally {
      this.busy = false;
    }
      } catch (error) {
      throw normalizeError(error);
    }
  }

  private openCreateBackup(): void {
    this.resetBackupDialog();
    this.backupAction = 'create';
    this.backupStage = 'password';
    this.showBackupDialog = true;
  }

  private async openRestoreBackup(freshInstall: boolean = false): Promise<void> {
    this.lifecycleLockSuppressed = true;
    try {
      const service = this.getBackupService();
      const uri = await service.chooseBackupFile();
      if (!uri) { return; }
      this.resetBackupDialog();
      this.selectedBackupUri = uri;
      this.restoringFreshInstall = freshInstall;
      this.backupAction = 'restore';
      this.backupStage = 'password';
      this.showBackupDialog = true;
    } catch (error) {
      try { this.getUIContext().getPromptAction().showToast({ message: this.describeError(error) }); }
      catch (toastError) { logRecoverableError('could not show backup file selection error', toastError); }
    } finally {
      this.lifecycleLockSuppressed = false;
    }
  }

  private resetBackupDialog(): void {
    if (this.preparedBackup) {
      this.getBackupService().disposePreparedBackup(this.preparedBackup);
    }
    this.preparedBackup = undefined;
    this.selectedBackupUri = '';
    this.restoringFreshInstall = false;
    this.backupPassword = '';
    this.backupBusy = false;
    this.backupError = '';
    this.backupProgressText = '';
    this.backupProgressValue = 0;
    this.backupDateText = '';
    this.backupItemCount = 0;
    this.backupAttachmentCount = 0;
    this.backupAttachmentSizeText = '';
    this.backupAddedCount = 0;
    this.backupUpdatedCount = 0;
    this.backupRetainedCount = 0;
    this.backupNewerCount = 0;
    this.backupConflictCount = 0;
    this.backupUnchangedCount = 0;
    this.backupDeletedCount = 0;
  }

  private closeBackupDialog(): void {
    if (this.backupBusy) { return; }
    if (this.preparedBackup) {
      this.getBackupService().disposePreparedBackup(this.preparedBackup);
    }
    this.preparedBackup = undefined;
    this.backupPassword = '';
    this.selectedBackupUri = '';
    this.showBackupDialog = false;
  }

  private async handleBackupPrimary(): Promise<void> {
    if (this.backupBusy) { return; }
    if (this.backupAction === 'create') {
      await this.createEncryptedBackup();
    } else if (this.backupStage === 'password') {
      await this.readSelectedBackup();
    } else if (this.backupStage === 'preview') {
      await this.restorePreparedBackup();
    }
  }

  private updateBackupProgress(progress: BackupProgress): void {
    this.backupProgressText = progress.phase;
    this.backupProgressValue = Math.max(0, Math.min(100,
      Math.round(progress.completed * 100 / Math.max(progress.total, 1))));
  }

  private async createEncryptedBackup(): Promise<void> {
    this.backupError = '';
    this.backupBusy = true;
    this.backupStage = 'running';
    this.lifecycleLockSuppressed = true;
    try {
      const security = this.getSecurityService();
      if (!await security.verifyPassword(this.backupPassword)) { throw new Error('密码不正确'); }
      const service = this.getBackupService();
      const saved = await service.createBackup(this.backupPassword, `${VERSION_NAME} (${VERSION_CODE})`,
        (progress: BackupProgress): void => { this.updateBackupProgress(progress); });
      this.backupBusy = false;
      if (!saved) {
        this.backupStage = 'password';
        return;
      }
      this.closeBackupDialog();
      this.getUIContext().getPromptAction().showToast({ message: '加密备份已保存' });
    } catch (error) {
      this.backupBusy = false;
      this.backupStage = 'password';
      this.backupError = this.describeError(error);
    } finally {
      this.lifecycleLockSuppressed = false;
    }
  }

  private async readSelectedBackup(): Promise<void> {
    this.backupError = '';
    this.backupBusy = true;
    this.backupStage = 'running';
    try {
      const service = this.getBackupService();
      const prepared = await service.inspectBackup(this.selectedBackupUri, this.backupPassword,
        (progress: BackupProgress): void => { this.updateBackupProgress(progress); }, this.restoringFreshInstall);
      this.preparedBackup = prepared;
      this.applyBackupPreview(prepared);
      this.backupStage = 'preview';
    } catch (error) {
      this.backupStage = 'password';
      this.backupError = this.describeError(error);
    } finally {
      this.backupBusy = false;
    }
  }

  private applyBackupPreview(prepared: PreparedVaultBackup): void {
    this.backupDateText = this.formatBackupDate(prepared.manifest.createdAt);
    this.backupItemCount = prepared.manifest.itemCount;
    this.backupAttachmentCount = prepared.manifest.attachmentCount;
    this.backupAttachmentSizeText = this.formatBackupSize(prepared.manifest.attachmentBytes);
    this.backupAddedCount = prepared.preview.addedCount;
    this.backupUpdatedCount = prepared.preview.updatedCount;
    this.backupRetainedCount = prepared.preview.retainedCount;
    this.backupNewerCount = prepared.preview.newerCount;
    this.backupConflictCount = prepared.preview.conflictCount;
    this.backupUnchangedCount = prepared.preview.unchangedCount;
    this.backupDeletedCount = prepared.preview.deletedCount;
  }

  private async restorePreparedBackup(): Promise<void> {
    if (!this.preparedBackup) { return; }
    const prepared = this.preparedBackup;
    this.backupBusy = true;
    this.backupStage = 'running';
    this.backupError = '';
    let securityCreated = false;
    try {
      if (this.restoringFreshInstall) {
        const security = this.getSecurityService();
        const key = await security.createMasterPassword(this.backupPassword);
        securityCreated = true;
        await this.openWithKey(key);
      }
      const service = this.getBackupService();
      const result = await service.applyPreparedBackup(prepared,
        (progress: BackupProgress): void => { this.updateBackupProgress(progress); });
      this.preparedBackup = undefined;
      await this.refreshData(true);
      if (this.restoringFreshInstall) {
        await this.refreshQuickUnlockStatus();
        await this.showVaultScreen();
      }
      this.backupBusy = false;
      this.closeBackupDialog();
      this.getUIContext().getPromptAction().showToast({
        message: this.restoreResultText(result)
      });
    } catch (error) {
      this.preparedBackup = undefined;
      if (securityCreated) {
        try {
          await vaultRepository.destroy(AbilityContextHolder.getContext());
          await this.getSecurityService().resetSecurity();
          this.sessionKey.fill(0);
          this.sessionKey = new Uint8Array(0);
        } catch (cleanupError) {
          logRecoverableError('could not roll back security created for failed first restore', cleanupError);
        }
      }
      this.backupBusy = false;
      this.backupStage = 'password';
      this.backupError = this.describeError(error);
    }
  }

  private formatBackupDate(timestamp: number): string {
    const date = new Date(timestamp);
    const two = (value: number): string => value.toString().padStart(2, '0');
    return `${date.getFullYear()}-${two(date.getMonth() + 1)}-${two(date.getDate())} ` +
      `${two(date.getHours())}:${two(date.getMinutes())}`;
  }

  private restoreResultText(result: BackupRestoreResult): string {
    const parts: string[] = [];
    if (result.addedCount > 0) { parts.push(`新增 ${result.addedCount} 项`); }
    if (result.updatedCount > 0) { parts.push(`恢复或更新 ${result.updatedCount} 项`); }
    if (result.retainedCount > 0) { parts.push(`保留当前新增 ${result.retainedCount} 项`); }
    if (result.conflictCount > 0) { parts.push(`创建冲突副本 ${result.conflictCount} 项`); }
    if (result.newerCount > 0) { parts.push(`保留本机较新版本 ${result.newerCount} 项`); }
    if (result.unchangedCount > 0) { parts.push(`无需变更 ${result.unchangedCount} 项`); }
    if (result.deletedCount > 0) { parts.push(`同步删除 ${result.deletedCount} 项`); }
    return parts.length > 0 ? `恢复完成：${parts.join('，')}` : '恢复完成，当前资料无需变更';
  }

  private formatBackupSize(bytes: number): string {
    if (bytes < 1024) { return `${bytes} B`; }
    if (bytes < 1024 * 1024) { return `${(bytes / 1024).toFixed(1)} KB`; }
    if (bytes < 1024 * 1024 * 1024) { return `${(bytes / 1024 / 1024).toFixed(1)} MB`; }
    return `${(bytes / 1024 / 1024 / 1024).toFixed(1)} GB`;
  }

  private async unlockVault(): Promise<void> {
    try {
    this.errorMessage = '';
    if (this.masterPassword.length === 0) {
      this.errorMessage = '请输入密码';
      return;
    }
    this.busy = true;
    try {
      const security = this.getSecurityService();
      const key = await security.unlock(this.masterPassword);
      if (!key) {
        this.errorMessage = '密码不正确';
        return;
      }
      await this.openWithKey(key);
      this.masterPassword = '';
      await this.refreshData();
      await this.showVaultScreen();
    } catch (error) {
      this.errorMessage = this.describeError(error);
    } finally {
      this.busy = false;
    }
      } catch (error) {
      throw normalizeError(error);
    }
  }

  private async lockVault(): Promise<void> {
    try {
    AbilityContextHolder.setPrivacyMode(false);
    this.trashEntries = [];
    this.trashRefreshVersion += 1;
    this.trashLongPressTriggered = false;
    this.trashTypeFilter = 'all';
    this.trashManaging = false;
    this.trashSelectedIds = [];
    this.showTrashMore = false;
    this.trashBusy = false;
    this.selectedTrashEntry = undefined;
    this.revealTrashPassword = false;
    this.activeTab = 0;
    this.searchText = '';
    this.searchHits = [];
    this.searchVersion += 1;
    this.searchActive = false;
    this.expandedGroupId = -1;
    this.draggingGroupId = -1;
    this.draggingGroupName = '';
    this.groupDropTargetId = -1;
    this.groupDragCancelActive = false;
    this.groupDragClickSuppressed = false;
    this.groupDragFinalizeScheduled = false;
    this.groupDragAccepted = false;
    this.groupDragCancelled = false;
    this.groupsBeforeDrag = [];
    this.groupDragPositionLocked = false;
    this.groupDragLastReorderX = 0;
    this.groupDragLastReorderY = 0;
    this.categoryGroupId = -1;
    this.categorySort = 'updated';
    this.masterPassword = '';
    this.confirmPassword = '';
    this.detailPassword = '';
    this.detailUsername = '';
    this.detailWebsite = '';
    this.detailNotes = '';
    this.detailTitle = '';
    this.detailGroupId = 0;
    this.resetNewItem();
    this.selectedItem = undefined;
    this.selectedAttachmentIndex = -1;
    this.showNewItem = false;
    this.showNewGroup = false;
    this.groupPendingRename = undefined;
    this.groupRenameName = '';
    this.groupPendingDelete = undefined;
    this.showGroupManager = false;
    this.groupDeleteConfirmName = '';
    this.groupPendingDeleteCount = 0;
    this.items = [];
    this.allItems = [];
    this.loginCount = 0;
    this.noteCount = 0;
    this.mediaCount = 0;
    this.fileCount = 0;
    this.totalItemCount = 0;
    this.groups = [];
    this.sessionKey.fill(0);
    this.sessionKey = new Uint8Array(0);
    await vaultRepository.close();
    await this.refreshQuickUnlockStatus();
    this.unlockMode = this.preferredUnlockMode();
    this.screen = 'locked';
      } catch (error) {
      throw normalizeError(error);
    }
  }

  private async openWithKey(key: Uint8Array): Promise<void> {
    try {
    this.sessionKey.fill(0);
    this.sessionKey = key.slice();
    try {
      await vaultRepository.open(AbilityContextHolder.getContext(), key);
    } catch (error) {
      this.sessionKey.fill(0);
      this.sessionKey = new Uint8Array(0);
      throw new Error(this.describeError(error));
    }
      } catch (error) {
      throw normalizeError(error);
    }
  }

  private async showVaultScreen(): Promise<void> {
    try {
    await AbilityContextHolder.setPrivacyMode(false);
    this.screen = 'vault';
      } catch (error) {
      throw normalizeError(error);
    }
  }

  private clearHomeFocus(): void {
    this.searchActive = false;
    setTimeout((): void => {
      this.getUIContext().getFocusController().clearFocus();
    }, 100);
  }

  private activateSearch(): void {
    if (this.searchActive) {
      return;
    }
    this.searchActive = true;
    setTimeout((): void => {
      try {
        this.getUIContext().getFocusController().requestFocus('homeSearchInput');
      } catch (error) {
        // The page may have changed before the delayed focus request runs.
      }
    }, 80);
  }

  private newItemTitleInputId(): string {
    return 'newItemTitleInput';
  }

  private requestNewItemTitleFocus(delay: number): void {
    setTimeout((): void => {
      if (!this.showNewItem) {
        return;
      }
      try {
        this.getUIContext().getFocusController().requestFocus(this.newItemTitleInputId());
      } catch (error) {
        // The overlay may be rebuilding or may already have been closed.
      }
    }, delay);
  }

  private openNewItem(type?: VaultItemType, groupId: number = 0): void {
    this.newType = type ?? this.lastNewItemType;
    this.revealNewPassword = false;
    if (groupId > 0) {
      this.newGroupId = groupId;
    }
    this.showNewItem = true;
    AbilityContextHolder.setPrivacyMode(false);
    this.requestNewItemTitleFocus(180);
    this.requestNewItemTitleFocus(360);
  }

  private closeNewItem(): void {
    this.showNewItem = false;
    this.revealNewPassword = false;
    AbilityContextHolder.setPrivacyMode(false);
  }

  private hasUnsavedNewItem(): boolean {
    return this.newTitle.length > 0 || this.newUsername.length > 0 || this.newPassword.length > 0 ||
      this.newWebsite.length > 0 ||
      this.newNotes.length > 0 || this.pendingMedia.length > 0 ||
      this.pendingFiles.length > 0;
  }

  private async requestCloseNewItem(): Promise<void> {
    try {
    if (this.savingNewItem) { return; }
    if (this.hasUnsavedNewItem()) {
      try {
        const choice = await this.getUIContext().getPromptAction().showDialog({
          title: '放弃未保存的资料？',
          message: '已填写的内容和已选择的素材将被清空。',
          buttons: [{ text: '继续编辑', color: COLOR_MUTED }, { text: '放弃', color: COLOR_DANGER }]
        });
        if (choice.index !== 1) { return; }
      } catch (error) {
        return;
      }
    }
    this.resetNewItem();
    this.closeNewItem();
      } catch (error) {
      throw normalizeError(error);
    }
  }

  private applyNewItemType(type: VaultItemType): void {
    try {
      this.getUIContext().getFocusController().requestFocus(this.newItemTitleInputId());
    } catch (error) {
      // The title input may still be mounting during the first interaction.
    }
    this.newType = type;
    if (type !== VaultItemType.Image && this.pendingMedia.length > 0) {
      this.clearPendingMedia();
    }
    if (type !== VaultItemType.File && this.pendingFiles.length > 0) {
      this.clearPendingFiles();
    }
    if (type !== VaultItemType.Login && this.revealNewPassword) {
      this.revealNewPassword = false;
      AbilityContextHolder.setPrivacyMode(false);
    }
    this.requestNewItemTitleFocus(120);
  }

  private async requestSelectNewItemType(type: VaultItemType): Promise<void> {
    try {
    if (type === this.newType || this.savingNewItem) { return; }
    if (this.hasUnsavedNewItem()) {
      try {
        const choice = await this.getUIContext().getPromptAction().showDialog({
          title: '切换资料类型？',
          message: '当前未保存的内容将被清空。',
          buttons: [{ text: '继续编辑', color: COLOR_MUTED }, { text: '切换', color: COLOR_DANGER }]
        });
        if (choice.index !== 1) { return; }
      } catch (error) {
        return;
      }
      this.resetNewItem();
    }
    this.applyNewItemType(type);
      } catch (error) {
      throw normalizeError(error);
    }
  }

  private async closeSelectedItem(refresh: boolean = true): Promise<void> {
    try {
    this.selectedItem = undefined;
    this.selectedAttachmentIndex = -1;
    this.detailGroupId = 0;
    this.detailPassword = '';
    this.revealPassword = false;
    try {
      await AbilityContextHolder.setPrivacyMode(false);
    } catch (error) {
      // 页面数据刷新不应被窗口隐私模式恢复失败阻断。
    }
    if (refresh) { await this.refreshData(); }
      } catch (error) {
      throw normalizeError(error);
    }
  }

  private closeGestureSetup(): void {
    this.showGestureSetup = false;
    this.firstGesture = [];
    AbilityContextHolder.setPrivacyMode(false);
  }

  private async refreshQuickUnlockStatus(): Promise<void> {
    try {
    const security = this.getSecurityService();
    const status: QuickUnlockStatus = await security.getQuickUnlockStatus();
    this.gestureEnabled = status.gestureEnabled;
    this.fingerprintEnabled = status.fingerprintEnabled;
    this.fingerprintAvailable = status.fingerprintAvailable;
    this.faceEnabled = status.faceEnabled;
    this.faceAvailable = status.faceAvailable;
    this.preferredUnlock = status.preferredUnlockMode;
    this.autoLockMinutes = status.autoLockMinutes;
      } catch (error) {
      throw normalizeError(error);
    }
  }

  private preferredUnlockMode(): string {
    if (this.preferredUnlock === 'fingerprint' && this.fingerprintEnabled && this.fingerprintAvailable) {
      return 'fingerprint';
    }
    if (this.preferredUnlock === 'face' && this.faceEnabled && this.faceAvailable) {
      return 'face';
    }
    if (this.preferredUnlock === 'gesture' && this.gestureEnabled) { return 'gesture'; }
    return 'password';
  }

  private selectUnlockMode(mode: string): void {
    if (this.busy || this.unlockMode === mode) {
      return;
    }
    this.errorMessage = '';
    this.unlockMode = mode;
    if (mode === 'fingerprint') {
      this.unlockWithFingerprint();
    } else if (mode === 'face') {
      this.unlockWithFace();
    }
  }

  private samePattern(left: number[], right: number[]): boolean {
    if (left.length !== right.length) { return false; }
    for (let index: number = 0; index < left.length; index += 1) {
      if (left[index] !== right[index]) { return false; }
    }
    return true;
  }

  private beginGestureSetup(): void {
    this.firstGesture = [];
    this.gestureSetupStep = 1;
    this.gestureSetupHint = '绘制新手势（至少 4 个点）';
    this.showGestureSetup = true;
    AbilityContextHolder.setPrivacyMode(false);
  }

  private async handleGestureSetup(pattern: number[]): Promise<void> {
    try {
    if (pattern.length < 4) {
      this.gestureSetupHint = '至少连接 4 个点，请重试';
      return;
    }
    if (this.gestureSetupStep === 1) {
      this.firstGesture = pattern.slice();
      this.gestureSetupStep = 2;
      this.gestureSetupHint = '再次绘制以确认';
      return;
    }
    if (!this.samePattern(this.firstGesture, pattern)) {
      this.firstGesture = [];
      this.gestureSetupStep = 1;
      this.gestureSetupHint = '两次手势不一致，请重新绘制';
      return;
    }
    try {
      const security = this.getSecurityService();
      const previousPreferred = this.preferredUnlock;
      await security.enableGesture(pattern, this.sessionKey);
      await this.refreshQuickUnlockStatus();
      this.closeGestureSetup();
      this.getUIContext().getPromptAction().showToast({
        message: previousPreferred === this.preferredUnlock ? '手势登录已启用' : '手势登录已启用，已设为首选'
      });
    } catch (error) {
      this.gestureSetupHint = this.describeError(error);
    }
      } catch (error) {
      throw normalizeError(error);
    }
  }

  private async unlockWithGesture(pattern: number[]): Promise<void> {
    try {
    if (Date.now() < this.gestureCooldownUntil) {
      this.errorMessage = '尝试次数过多，请稍后使用密码';
      return;
    }
    this.busy = true;
    this.errorMessage = '';
    try {
      const security = this.getSecurityService();
      const key = await security.unlockWithGesture(pattern);
      if (!key) {
        this.gestureFailures += 1;
        if (this.gestureFailures >= 5) {
          this.gestureCooldownUntil = Date.now() + 30000;
          this.gestureFailures = 0;
          this.unlockMode = 'password';
          this.errorMessage = '手势错误次数过多，已暂停 30 秒';
        } else {
          this.errorMessage = `手势不正确，还可尝试 ${5 - this.gestureFailures} 次`;
        }
        return;
      }
      await this.openWithKey(key);
      this.gestureFailures = 0;
      await this.refreshData();
      await this.showVaultScreen();
    } catch (error) {
      this.errorMessage = this.describeError(error);
    } finally {
      this.busy = false;
    }
      } catch (error) {
      throw normalizeError(error);
    }
  }

  private async unlockWithFingerprint(): Promise<void> {
    try {
    this.busy = true;
    this.errorMessage = '';
    try {
      const security = this.getSecurityService();
      const key = await security.unlockWithFingerprint();
      await this.openWithKey(key);
      await this.refreshData();
      await this.showVaultScreen();
    } catch (error) {
      this.errorMessage = this.describeError(error);
    } finally {
      this.busy = false;
    }
      } catch (error) {
      throw normalizeError(error);
    }
  }

  private async unlockWithFace(): Promise<void> {
    try {
      this.busy = true;
      this.errorMessage = '';
      try {
        const security = this.getSecurityService();
        const key = await security.unlockWithFace();
        await this.openWithKey(key);
        await this.refreshData();
        await this.showVaultScreen();
      } catch (error) {
        this.errorMessage = this.describeError(error);
      } finally {
        this.busy = false;
      }
    } catch (error) {
      throw normalizeError(error);
    }
  }

  private async toggleFingerprint(): Promise<void> {
    try {
    try {
      const security = this.getSecurityService();
      if (this.fingerprintEnabled) {
        const previousPreferred = this.preferredUnlock;
        await security.disableFingerprint();
        await this.refreshQuickUnlockStatus();
        this.getUIContext().getPromptAction().showToast({
          message: previousPreferred === this.preferredUnlock ? '指纹登录已关闭' :
            `指纹登录已关闭，已将${this.unlockModeLabel(this.preferredUnlock)}设为首选`
        });
      } else {
        const previousPreferred = this.preferredUnlock;
        await security.enableFingerprint(this.sessionKey);
        await this.refreshQuickUnlockStatus();
        this.getUIContext().getPromptAction().showToast({
          message: previousPreferred === this.preferredUnlock ? '指纹登录已启用' : '指纹登录已启用，已设为首选'
        });
      }
    } catch (error) {
      this.getUIContext().getPromptAction().showToast({ message: this.describeError(error) });
    }
      } catch (error) {
      throw normalizeError(error);
    }
  }

  private async toggleFace(): Promise<void> {
    try {
      try {
        const security = this.getSecurityService();
        if (this.faceEnabled) {
          const previousPreferred = this.preferredUnlock;
          await security.disableFace();
          await this.refreshQuickUnlockStatus();
          this.getUIContext().getPromptAction().showToast({
            message: previousPreferred === this.preferredUnlock ? '人脸登录已关闭' :
              `人脸登录已关闭，已将${this.unlockModeLabel(this.preferredUnlock)}设为首选`
          });
        } else {
          const previousPreferred = this.preferredUnlock;
          await security.enableFace(this.sessionKey);
          await this.refreshQuickUnlockStatus();
          this.getUIContext().getPromptAction().showToast({
            message: previousPreferred === this.preferredUnlock ? '人脸登录已启用' : '人脸登录已启用，已设为首选'
          });
        }
      } catch (error) {
        this.getUIContext().getPromptAction().showToast({ message: this.describeError(error) });
      }
    } catch (error) {
      throw normalizeError(error);
    }
  }

  private unlockModeLabel(mode: string): string {
    if (mode === 'fingerprint') { return '指纹'; }
    if (mode === 'face') { return '人脸'; }
    if (mode === 'gesture') { return '手势'; }
    return '密码';
  }

  private autoLockLabel(): string {
    if (this.autoLockMinutes < 0) { return '永不自动锁定'; }
    if (this.autoLockMinutes === 0) { return '切换到后台立即锁定'; }
    return `${this.autoLockMinutes} 分钟`;
  }

  private async choosePreferredUnlock(): Promise<void> {
    try {
      const values: string[] = ['face', 'fingerprint', 'gesture', 'password'];
      const buttons: [promptAction.Button, promptAction.Button, promptAction.Button, promptAction.Button] = [
        { text: `${this.preferredUnlock === 'face' ? '✓  ' : ''}人脸${this.faceEnabled ? '' : '（未启用）'}`,
          color: this.faceEnabled ? COLOR_TEXT : COLOR_MUTED },
        { text: `${this.preferredUnlock === 'fingerprint' ? '✓  ' : ''}指纹${this.fingerprintEnabled ? '' : '（未启用）'}`,
          color: this.fingerprintEnabled ? COLOR_TEXT : COLOR_MUTED },
        { text: `${this.preferredUnlock === 'gesture' ? '✓  ' : ''}手势${this.gestureEnabled ? '' : '（未启用）'}`,
          color: this.gestureEnabled ? COLOR_TEXT : COLOR_MUTED },
        { text: `${this.preferredUnlock === 'password' ? '✓  ' : ''}密码`, color: COLOR_TEXT }
      ];
      let selectedIndex = -1;
      try {
        const result = await this.getUIContext().getPromptAction().showActionMenu({
          title: '选择首选登录方式', buttons: buttons
        });
        selectedIndex = result.index;
      } catch (_) {
        return;
      }
      if (selectedIndex < 0 || selectedIndex >= values.length) { return; }
      try {
        const mode = values[selectedIndex];
        const security = this.getSecurityService();
        await security.setPreferredUnlockMode(mode);
        this.preferredUnlock = mode;
        this.getUIContext().getPromptAction().showToast({ message: `已将${this.unlockModeLabel(mode)}设为首选` });
      } catch (error) {
        this.getUIContext().getPromptAction().showToast({ message: this.describeError(error) });
      }
    } catch (error) {
      throw normalizeError(error);
    }
  }

  private async chooseAutoLockTime(): Promise<void> {
    try {
      const values: number[] = [0, 5, 10, 30, -1];
      const labels: string[] = ['立即锁定', '5 分钟', '10 分钟', '30 分钟', '永不自动锁定'];
      const buttons: [promptAction.Button, promptAction.Button, promptAction.Button,
        promptAction.Button, promptAction.Button] = [
        { text: `${this.autoLockMinutes === values[0] ? '✓  ' : ''}${labels[0]}`, color: COLOR_TEXT },
        { text: `${this.autoLockMinutes === values[1] ? '✓  ' : ''}${labels[1]}`, color: COLOR_TEXT },
        { text: `${this.autoLockMinutes === values[2] ? '✓  ' : ''}${labels[2]}`, color: COLOR_TEXT },
        { text: `${this.autoLockMinutes === values[3] ? '✓  ' : ''}${labels[3]}`, color: COLOR_TEXT },
        { text: `${this.autoLockMinutes === values[4] ? '✓  ' : ''}${labels[4]}`, color: COLOR_TEXT }
      ];
      let selectedIndex = -1;
      try {
        const result = await this.getUIContext().getPromptAction().showActionMenu({
          title: '自动锁定', buttons: buttons
        });
        selectedIndex = result.index;
      } catch (_) {
        return;
      }
      if (selectedIndex < 0 || selectedIndex >= values.length) { return; }
      try {
        const minutes = values[selectedIndex];
        const security = this.getSecurityService();
        await security.setAutoLockMinutes(minutes);
        this.autoLockMinutes = minutes;
        this.getUIContext().getPromptAction().showToast({ message: `自动锁定已设为${labels[selectedIndex]}` });
      } catch (error) {
        this.getUIContext().getPromptAction().showToast({ message: this.describeError(error) });
      }
    } catch (error) {
      throw normalizeError(error);
    }
  }

  private openChangePassword(): void {
    this.currentPassword = '';
    this.changedPassword = '';
    this.changedPasswordConfirm = '';
    this.showChangePassword = true;
  }

  private closeChangePassword(): void {
    if (this.passwordChangeBusy) { return; }
    this.currentPassword = '';
    this.changedPassword = '';
    this.changedPasswordConfirm = '';
    this.showChangePassword = false;
  }

  private async changePassword(): Promise<void> {
    try {
    if (this.currentPassword.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '请输入当前密码' });
      return;
    }
    if (this.changedPassword.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '新密码不能为空' });
      return;
    }
    if (this.changedPassword !== this.changedPasswordConfirm) {
      this.getUIContext().getPromptAction().showToast({ message: '两次输入的新密码不一致' });
      return;
    }
    this.passwordChangeBusy = true;
    try {
      const security = this.getSecurityService();
      const key = await security.changePassword(this.currentPassword, this.changedPassword);
      this.sessionKey.fill(0);
      this.sessionKey = key.slice();
      key.fill(0);
      await this.refreshQuickUnlockStatus();
      this.passwordChangeBusy = false;
      this.closeChangePassword();
      this.getUIContext().getPromptAction().showToast({ message: '密码已修改，请重新启用需要的快捷登录' });
    } catch (error) {
      this.passwordChangeBusy = false;
      this.getUIContext().getPromptAction().showToast({ message: this.describeError(error) });
    }
    } catch (error) {
      throw normalizeError(error);
    }
  }

  private openResetVault(): void {
    this.resetVaultConfirmText = '';
    this.showResetVault = true;
  }

  private openRecoveryCenter(): void {
    this.recoveryDatabaseKey.fill(0);
    this.recoveryDatabaseKey = new Uint8Array(0);
    this.recoveryAuthenticated = false;
    this.recoveryAuthLabel = '';
    this.recoveryNewPassword = '';
    this.recoveryPasswordConfirm = '';
    this.showRecoveryCenter = true;
  }

  private closeRecoveryCenter(): void {
    if (this.recoveryBusy) { return; }
    this.recoveryDatabaseKey.fill(0);
    this.recoveryDatabaseKey = new Uint8Array(0);
    this.recoveryAuthenticated = false;
    this.recoveryAuthLabel = '';
    this.recoveryNewPassword = '';
    this.recoveryPasswordConfirm = '';
    this.showRecoveryCenter = false;
  }

  private async authenticateRecovery(mode: string): Promise<void> {
    try {
      this.recoveryBusy = true;
      try {
        const security = this.getSecurityService();
        const key = mode === 'face' ? await security.unlockWithFace() : await security.unlockWithFingerprint();
        this.recoveryDatabaseKey.fill(0);
        this.recoveryDatabaseKey = key.slice();
        key.fill(0);
        this.recoveryAuthenticated = true;
        this.recoveryAuthLabel = this.unlockModeLabel(mode);
      } catch (error) {
        this.getUIContext().getPromptAction().showToast({ message: this.describeError(error) });
      } finally {
        this.recoveryBusy = false;
      }
    } catch (error) {
      throw normalizeError(error);
    }
  }

  private async resetRecoveredPassword(): Promise<void> {
    try {
      if (!this.recoveryAuthenticated || this.recoveryDatabaseKey.length !== 32) {
        this.getUIContext().getPromptAction().showToast({ message: '请先验证身份' });
        return;
      }
      if (this.recoveryNewPassword.length === 0) {
        this.getUIContext().getPromptAction().showToast({ message: '新密码不能为空' });
        return;
      }
      if (this.recoveryNewPassword !== this.recoveryPasswordConfirm) {
        this.getUIContext().getPromptAction().showToast({ message: '两次输入的新密码不一致' });
        return;
      }
      this.recoveryBusy = true;
      try {
        const security = this.getSecurityService();
        const key = await security.resetPasswordWithAuthenticatedKey(
          this.recoveryDatabaseKey, this.recoveryNewPassword);
        this.recoveryDatabaseKey = new Uint8Array(0);
        await this.openWithKey(key);
        await this.refreshQuickUnlockStatus();
        await this.refreshData();
        this.recoveryBusy = false;
        this.closeRecoveryCenter();
        await this.showVaultScreen();
        this.getUIContext().getPromptAction().showToast({ message: '密码已重设，快捷登录已关闭' });
      } catch (error) {
        this.recoveryDatabaseKey.fill(0);
        this.recoveryDatabaseKey = new Uint8Array(0);
        this.recoveryAuthenticated = false;
        this.recoveryBusy = false;
        this.getUIContext().getPromptAction().showToast({ message: this.describeError(error) });
      }
    } catch (error) {
      throw normalizeError(error);
    }
  }

  private closeResetVault(): void {
    if (this.resetVaultBusy) { return; }
    this.resetVaultConfirmText = '';
    this.showResetVault = false;
  }

  private async resetVault(): Promise<void> {
    try {
    if (this.resetVaultConfirmText !== '清除全部数据') { return; }
    this.resetVaultBusy = true;
    try {
      const context = AbilityContextHolder.getContext();
      await AbilityContextHolder.setPrivacyMode(false);
      await vaultRepository.destroy(context);
      const security = this.getSecurityService();
      await security.resetSecurity();
      this.lastNewItemType = VaultItemType.Note;
      this.newType = VaultItemType.Note;
      await vaultUiPreferences.setLastNewItemType(VaultItemType.Note);
      this.autoLockMinutes = 10;
      this.preferredUnlock = 'password';
      this.sessionKey.fill(0);
      this.sessionKey = new Uint8Array(0);
      this.masterPassword = '';
      this.confirmPassword = '';
      this.errorMessage = '';
      this.resetVaultBusy = false;
      this.closeResetVault();
      this.closeRecoveryCenter();
      this.screen = 'setup';
      this.getUIContext().getPromptAction().showToast({ message: '本地保险库已清除' });
    } catch (error) {
      this.resetVaultBusy = false;
      this.getUIContext().getPromptAction().showToast({ message: this.describeError(error) });
    }
    } catch (error) {
      throw normalizeError(error);
    }
  }

  private async disableGesture(): Promise<void> {
    try {
    const security = this.getSecurityService();
    const previousPreferred = this.preferredUnlock;
    await security.disableGesture();
    await this.refreshQuickUnlockStatus();
    this.getUIContext().getPromptAction().showToast({
      message: previousPreferred === this.preferredUnlock ? '手势登录已关闭' :
        `手势登录已关闭，已将${this.unlockModeLabel(this.preferredUnlock)}设为首选`
    });
      } catch (error) {
      throw normalizeError(error);
    }
  }

  private async reloadVault(): Promise<void> {
    try {
    const version = ++this.vaultRefreshVersion;
    const searchVersion = this.searchVersion;
    const searchText = this.searchText.trim();
    const groupsRequest: Promise<VaultGroup[]> = vaultRepository.listGroups();
    const itemsRequest: Promise<VaultItem[]> = vaultRepository.listItems();
    let searchHits: VaultSearchHit[] = [];
    let searchRequest: Promise<VaultSearchHit[]> | undefined = undefined;
    if (searchText.length > 0) {
      searchRequest = vaultRepository.searchItems(searchText);
    }
    const groups = await groupsRequest;
    const activeItems = await itemsRequest;
    if (searchRequest) { searchHits = await searchRequest; }
    if (version !== this.vaultRefreshVersion) { return; }
    this.groups = groups;
    this.applyActiveItems(activeItems);
    if (this.groups.length > 0 && this.newGroupId === 0) {
      this.newGroupId = this.groups[0].id;
    }
    if (searchVersion !== this.searchVersion || searchText !== this.searchText.trim()) { return; }
    if (searchText.length > 0) {
      this.searchHits = searchHits;
      this.items = [];
    } else {
      this.searchHits = [];
      this.items = activeItems.slice();
    }
      } catch (error) {
      throw normalizeError(error);
    }
  }

  private async refreshData(includeTrash: boolean = false): Promise<void> {
    if (includeTrash) {
      const vaultRequest: Promise<void> = this.reloadVault();
      const trashRequest: Promise<void> = this.refreshTrash();
      await vaultRequest;
      await trashRequest;
      return;
    }
    await this.reloadVault();
  }

  private applyActiveItems(items: VaultItem[]): void {
    this.allItems = items;
    this.totalItemCount = items.length;
    let loginCount = 0;
    let noteCount = 0;
    let mediaCount = 0;
    let fileCount = 0;
    items.forEach((item: VaultItem): void => {
      if (item.type === VaultItemType.Login) { loginCount += 1; }
      else if (item.type === VaultItemType.Note) { noteCount += 1; }
      else if (item.type === VaultItemType.Image || item.type === VaultItemType.Video) { mediaCount += 1; }
      else if (item.type === VaultItemType.File) { fileCount += 1; }
    });
    this.loginCount = loginCount;
    this.noteCount = noteCount;
    this.mediaCount = mediaCount;
    this.fileCount = fileCount;
  }

  private async refreshTrash(): Promise<void> {
    try {
    const version = ++this.trashRefreshVersion;
    let filter: VaultItemType | undefined = undefined;
    if (this.trashTypeFilter !== 'all') { filter = this.trashTypeFilter as VaultItemType; }
    const entries = await vaultRepository.listTrashEntries(filter);
    if (version !== this.trashRefreshVersion) { return; }
    this.trashEntries = entries;
    const visibleIds = new Set<string>(this.trashEntries.map((entry: VaultTrashEntry): string => entry.item.id));
    this.trashSelectedIds = this.trashSelectedIds.filter((id: string): boolean => visibleIds.has(id));
      } catch (error) {
      throw normalizeError(error);
    }
  }

  private async trashAction(item: VaultItem, permanent: boolean): Promise<void> {
    try {
    if (this.trashBusy) { return; }
    try {
      if (permanent) {
        const choice = await this.getUIContext().getPromptAction().showDialog({ title: '永久删除此资料？', message: '删除后无法恢复。',
          buttons: [{ text: ACTION_CANCEL, color: COLOR_MUTED }, { text: `永久${ACTION_DELETE}`, color: COLOR_DANGER }] });
        if (choice.index !== 1) { return; }
      }
      this.trashBusy = true;
      if (permanent) { await vaultRepository.permanentlyDelete(item.id); }
      else { await vaultRepository.restoreFromTrash(item.id); }
      if (this.selectedTrashEntry && this.selectedTrashEntry.item.id === item.id) {
        await this.closeTrashDetail();
      }
      await this.refreshData(true);
      this.getUIContext().getPromptAction().showToast({ message: permanent ? '资料已永久删除' : '资料已恢复' });
    } catch (error) { this.getUIContext().getPromptAction().showToast({ message: this.describeError(error) }); }
    finally { this.trashBusy = false; }
      } catch (error) {
      throw normalizeError(error);
    }
  }

  private setTrashTypeFilter(filter: string): void {
    this.trashTypeFilter = filter;
    this.trashSelectedIds = [];
    this.refreshTrash();
  }

  private openTrashManagement(selectedId: string = ''): void {
    this.trashManaging = true;
    this.showTrashMore = false;
    this.trashSelectedIds = selectedId.length > 0 ? [selectedId] : [];
    if (selectedId.length > 0) {
      this.trashLongPressTriggered = true;
      setTimeout((): void => { this.trashLongPressTriggered = false; }, 350);
    }
  }

  private closeTrashManagement(): void {
    this.trashManaging = false;
    this.trashSelectedIds = [];
  }

  private trashIsSelected(id: string): boolean {
    return this.trashSelectedIds.indexOf(id) >= 0;
  }

  private toggleTrashSelection(id: string): void {
    const selected = this.trashSelectedIds.slice();
    const position = selected.indexOf(id);
    if (position >= 0) { selected.splice(position, 1); } else { selected.push(id); }
    this.trashSelectedIds = selected;
  }

  private toggleSelectAllTrash(): void {
    this.trashSelectedIds = this.trashSelectedIds.length === this.trashEntries.length ? [] :
      this.trashEntries.map((entry: VaultTrashEntry): string => entry.item.id);
  }

  private async restoreSelectedTrash(): Promise<void> {
    try {
    if (this.trashBusy || this.trashSelectedIds.length === 0) { return; }
    const count = this.trashSelectedIds.length;
    this.trashBusy = true;
    try {
      await vaultRepository.restoreTrashItems(this.trashSelectedIds);
      this.closeTrashManagement();
      await this.refreshData(true);
      this.getUIContext().getPromptAction().showToast({ message: `已恢复 ${count} 条资料` });
    } catch (error) { this.getUIContext().getPromptAction().showToast({ message: this.describeError(error) }); }
    finally { this.trashBusy = false; }
      } catch (error) {
      throw normalizeError(error);
    }
  }

  private async permanentlyDeleteSelectedTrash(): Promise<void> {
    try {
    if (this.trashBusy || this.trashSelectedIds.length === 0) { return; }
    const count = this.trashSelectedIds.length;
    const choice = await this.getUIContext().getPromptAction().showDialog({
      title: `永久删除 ${count} 条资料？`,
      message: '资料和附件将被永久删除，且无法恢复。',
      buttons: [{ text: ACTION_CANCEL, color: COLOR_MUTED }, { text: `永久${ACTION_DELETE}`, color: COLOR_DANGER }]
    });
    if (choice.index !== 1) { return; }
    this.trashBusy = true;
    try {
      await vaultRepository.permanentlyDeleteItems(this.trashSelectedIds);
      this.closeTrashManagement();
      await this.refreshData(true);
      this.getUIContext().getPromptAction().showToast({ message: `已永久删除 ${count} 条资料` });
    } catch (error) { this.getUIContext().getPromptAction().showToast({ message: this.describeError(error) }); }
    finally { this.trashBusy = false; }
      } catch (error) {
      throw normalizeError(error);
    }
  }

  private async emptyTrash(): Promise<void> {
    try {
    if (this.trashBusy) { return; }
    this.showTrashMore = false;
    const allEntries = await vaultRepository.listTrashEntries();
    if (allEntries.length === 0) { return; }
    const choice = await this.getUIContext().getPromptAction().showDialog({
      title: `清空回收站中的 ${allEntries.length} 条资料？`,
      message: '所有资料和附件将被永久删除，且无法恢复。',
      buttons: [{ text: ACTION_CANCEL, color: COLOR_MUTED }, { text: '清空', color: COLOR_DANGER }]
    });
    if (choice.index !== 1) { return; }
    this.trashBusy = true;
    try {
      await vaultRepository.emptyTrash();
      this.closeTrashManagement();
      await this.refreshData(true);
      this.getUIContext().getPromptAction().showToast({ message: '回收站已清空' });
    } catch (error) { this.getUIContext().getPromptAction().showToast({ message: this.describeError(error) }); }
    finally { this.trashBusy = false; }
      } catch (error) {
      throw normalizeError(error);
    }
  }

  private trashSection(item: VaultItem): string {
    const now = new Date();
    const today = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
    if (item.deletedAt >= today) { return '今天'; }
    if (item.deletedAt >= today - 6 * 24 * 60 * 60 * 1000) { return '最近 7 天'; }
    return '更早';
  }

  private trashEntriesInSection(section: string): VaultTrashEntry[] {
    return this.trashEntries.filter((entry: VaultTrashEntry): boolean =>
      this.trashSection(entry.item) === section);
  }

  private formatTrashTime(value: number): string {
    const date = new Date(value);
    const now = new Date();
    const today = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
    const hour = `${date.getHours()}`.padStart(2, '0');
    const minute = `${date.getMinutes()}`.padStart(2, '0');
    if (value >= today) { return `今天 ${hour}:${minute}`; }
    return `${date.getMonth() + 1}月${date.getDate()}日 ${hour}:${minute}`;
  }

  private openTrashDetail(entry: VaultTrashEntry): void {
    if (this.trashLongPressTriggered) {
      this.trashLongPressTriggered = false;
      return;
    }
    if (this.trashManaging) {
      this.toggleTrashSelection(entry.item.id);
      return;
    }
    this.selectedTrashEntry = entry;
    this.revealTrashPassword = false;
    AbilityContextHolder.setPrivacyMode(false);
  }

  private openSearchResult(hit: VaultSearchHit): void {
    if (hit.item.deletedAt > 0) {
      this.openTrashDetail({ item: hit.item, originalGroupName: hit.originalGroupName });
      return;
    }
    this.openItem(hit.item, hit.attachmentIndex);
  }

  private async closeTrashDetail(): Promise<void> {
    try {
    this.selectedTrashEntry = undefined;
    this.revealTrashPassword = false;
    await AbilityContextHolder.setPrivacyMode(false);
      } catch (error) {
      throw normalizeError(error);
    }
  }

  private async copyTrashUsername(username: string): Promise<void> {
    await this.copyLoginValue(username, '账号');
  }

  private async copyLoginValue(value: string, label: string): Promise<void> {
    if (value.length === 0) { return; }
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, value);
      await pasteboard.getSystemPasteboard().setData(data);
      this.getUIContext().getPromptAction().showToast({ message: `${label}已复制` });
    } catch (error) {
      try { this.getUIContext().getPromptAction().showToast({ message: '复制失败' }); }
      catch (toastError) { logRecoverableError('could not show copy failure', toastError); }
    }
  }

  private async openLoginWebsite(website: string): Promise<void> {
    const trimmed = website.trim();
    if (trimmed.length === 0) { return; }
    const uri = trimmed.indexOf('://') >= 0 ? trimmed : `https://${trimmed}`;
    try {
      await AbilityContextHolder.getContext().startAbility({ action: 'ohos.want.action.viewData', uri: uri });
    } catch (error) {
      try { this.getUIContext().getPromptAction().showToast({ message: '无法打开该网站地址' }); }
      catch (toastError) { logRecoverableError('could not show website failure', toastError); }
    }
  }

  private async applySearch(text: string): Promise<void> {
    try {
    this.searchText = text;
    this.activeTab = 0;
    const version = ++this.searchVersion;
    if (text.trim().length === 0) {
      this.searchHits = [];
      if (version === this.searchVersion) { this.items = this.allItems.slice(); }
      return;
    }
    const hits = await vaultRepository.searchItems(text);
    if (version === this.searchVersion) {
      this.searchHits = hits;
      this.items = [];
    }
      } catch (error) {
      throw normalizeError(error);
    }
  }

  private async createGroup(): Promise<void> {
    try {
    try {
      await vaultRepository.createGroup(this.newGroupName, COLOR_PRIMARY);
      this.newGroupName = '';
      this.showNewGroup = false;
      await this.refreshData();
      this.getUIContext().getPromptAction().showToast({ message: '分组已创建' });
    } catch (error) {
      this.getUIContext().getPromptAction().showToast({ message: this.describeError(error) });
    }
      } catch (error) {
      throw normalizeError(error);
    }
  }

  private openNewGroup(): void {
    this.newGroupName = '';
    this.showNewGroup = true;
    setTimeout((): void => {
      try {
        this.getUIContext().getFocusController().requestFocus('newGroupInput');
      } catch (error) {
        // The overlay may have been closed before the input finishes mounting.
      }
    }, 80);
  }

  private closeNewGroup(): void {
    this.showNewGroup = false;
    this.newGroupName = '';
  }

  private requestRenameGroup(group: VaultGroup): void {
    this.groupPendingRename = group;
    this.groupRenameName = group.name;
    setTimeout((): void => {
      try {
        this.getUIContext().getFocusController().requestFocus('renameGroupInput');
      } catch (error) {
        // The rename overlay may have been closed before the delayed focus request runs.
      }
    }, 80);
  }

  private closeRenameGroup(): void {
    this.groupPendingRename = undefined;
    this.groupRenameName = '';
  }

  private async renameGroup(group: VaultGroup): Promise<void> {
    try {
    const name = this.groupRenameName.trim();
    if (name.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '分组名称不能为空' });
      return;
    }
    try {
      await vaultRepository.updateGroup(group.id, name, group.color);
      this.closeRenameGroup();
      await this.refreshData();
      this.getUIContext().getPromptAction().showToast({ message: '分组已重命名' });
    } catch (error) {
      this.getUIContext().getPromptAction().showToast({ message: this.describeError(error) });
    }
      } catch (error) {
      throw normalizeError(error);
    }
  }

  private async requestDeleteGroup(group: VaultGroup): Promise<void> {
    try {
    try {
      const itemCount = this.countGroup(group.id);
      if (itemCount > 0) {
        this.groupPendingDelete = group;
        this.groupPendingDeleteCount = itemCount;
        this.groupDeleteConfirmName = '';
        return;
      }
      const choice = await this.getUIContext().getPromptAction().showDialog({
        title: `删除“${group.name}”？`,
        message: '确定删除该分组吗？',
        buttons: [{ text: ACTION_CANCEL, color: COLOR_MUTED }, { text: ACTION_DELETE, color: COLOR_DANGER }]
      });
      if (choice.index === 1) {
        await this.deleteGroup(group);
      }
    } catch (error) {
      this.getUIContext().getPromptAction().showToast({ message: this.describeError(error) });
    }
      } catch (error) {
      throw normalizeError(error);
    }
  }

  private async confirmDeleteGroup(group: VaultGroup): Promise<void> {
    try {
    if (this.groupDeleteConfirmName.trim() !== group.name) {
      this.getUIContext().getPromptAction().showToast({ message: '输入的分组名称不一致' });
      return;
    }
    await this.deleteGroup(group);
      } catch (error) {
      throw normalizeError(error);
    }
  }

  private async deleteGroup(group: VaultGroup): Promise<void> {
    try {
    try {
      const hadItems = this.groupPendingDeleteCount > 0;
      await vaultRepository.deleteGroup(group.id);
      this.groupPendingDelete = undefined;
      this.groupDeleteConfirmName = '';
      this.groupPendingDeleteCount = 0;
      this.expandedGroupId = -1;
      if (this.newGroupId === group.id) {
        this.newGroupId = 0;
      }
      await this.refreshData();
      this.getUIContext().getPromptAction().showToast({ message: hadItems ? '分组及其当前资料已永久删除' : '分组已删除' });
    } catch (error) {
      this.getUIContext().getPromptAction().showToast({ message: this.describeError(error) });
    }
      } catch (error) {
      throw normalizeError(error);
    }
  }

  private async chooseMedia(fromFile: boolean = false): Promise<void> {
    try {
    try {
      if (!fromFile && this.newType === VaultItemType.Image) {
        const preselectedUris: string[] = [];
        this.pendingMedia.forEach((media: PickedMedia): void => { preselectedUris.push(media.uri); });
        const mediaItems = await mediaPickerService.pickMany(preselectedUris);
        if (mediaItems.length === 0) {
          return;
        }
        if (this.screen !== 'vault') {
          return;
        }
        this.clearPendingMedia();
        this.pendingMedia = mediaItems;
        this.selectedMediaCount = mediaItems.length;
        this.selectedMediaPreviewIndex = mediaItems.length - 1;
        await this.recognizePendingMedia();
        return;
      }
      const titleBeforeFilePicker = this.newTitle;
      const files = await mediaPickerService.pickFiles();
      this.newTitle = titleBeforeFilePicker;
      if (files.length === 0) {
        return;
      }
      if (this.screen !== 'vault') {
        return;
      }
      this.clearPendingFiles();
      this.pendingFiles = files;
      this.selectedFileCount = files.length;
    } catch (error) {
      this.getUIContext().getPromptAction().showToast({ message: this.describeError(error) });
    }
      } catch (error) {
      throw normalizeError(error);
    }
  }

  private async recognizePendingMedia(): Promise<void> {
    try {
    if (this.pendingMedia.length === 0) { return; }
    const imageCount = this.pendingMedia.filter((media: PickedMedia): boolean =>
      media.type === VaultItemType.Image).length;
    if (imageCount === 0) { return; }
    const recognitionVersion = ++this.mediaRecognitionVersion;
    this.recognizingMedia = true;
    this.recognitionProgressText = `正在识别图片文字 0/${imageCount}`;
    try {
      const results = await mediaOcrService.recognizeBatch(this.pendingMedia,
        (completed: number, total: number): void => {
          if (recognitionVersion === this.mediaRecognitionVersion) {
            this.recognitionProgressText = `正在识别图片文字 ${completed}/${total}`;
          }
        });
      if (recognitionVersion !== this.mediaRecognitionVersion) { return; }
      for (let index = 0; index < this.pendingMedia.length; index += 1) {
        this.pendingMedia[index].ocrText = results[index];
      }
      this.pendingMedia = this.pendingMedia.slice();
    } finally {
      if (recognitionVersion === this.mediaRecognitionVersion) {
        this.recognizingMedia = false;
        this.recognitionProgressText = '';
      }
    }
      } catch (error) {
      throw normalizeError(error);
    }
  }

  private removePendingMedia(index: number): void {
    if (this.recognizingMedia || this.savingNewItem || index < 0 || index >= this.pendingMedia.length) {
      return;
    }
    this.pendingMedia = this.pendingMedia.filter((media: PickedMedia, mediaIndex: number): boolean =>
      mediaIndex !== index);
    this.selectedMediaCount = this.pendingMedia.length;
    if (this.pendingMedia.length === 0) {
      this.selectedMediaPreviewIndex = 0;
    } else if (index < this.selectedMediaPreviewIndex) {
      this.selectedMediaPreviewIndex -= 1;
    } else if (this.selectedMediaPreviewIndex >= this.pendingMedia.length) {
      this.selectedMediaPreviewIndex = this.pendingMedia.length - 1;
    }
  }

  private selectPendingMedia(index: number): void {
    if (index < 0 || index >= this.pendingMedia.length) { return; }
    this.selectedMediaPreviewIndex = index;
  }

  private removePendingFile(index: number): void {
    if (this.savingNewItem || index < 0 || index >= this.pendingFiles.length) { return; }
    this.pendingFiles = this.pendingFiles.filter((file: PickedMedia, fileIndex: number): boolean =>
      fileIndex !== index);
    this.selectedFileCount = this.pendingFiles.length;
  }

  private async createItem(): Promise<void> {
    try {
    if (this.savingNewItem) { return; }
    this.savingNewItem = true;
    this.saveProgress = 0;
    try {
      if (this.newType === VaultItemType.Image) {
        if (this.pendingMedia.length === 0) {
          throw new Error('请先选择要导入的图片或视频');
        }
        const attachments: VaultAttachmentInput[] = [];
        const compressedPaths: string[] = [];
        try {
          for (let index = 0; index < this.pendingMedia.length; index += 1) {
            const picked = this.pendingMedia[index];
            this.saveProgressText = `正在压缩 ${index + 1}/${this.pendingMedia.length}`;
            const compressedPath = await mediaCompressionService.compress(picked.uri, picked.type,
              (progress: number): void => {
                this.saveProgress = Math.round(((index + progress / 100) / this.pendingMedia.length) * 70);
              });
            compressedPaths.push(compressedPath);
            attachments.push({
              type: picked.type,
              uri: compressedPath,
              sourceUri: picked.uri,
              name: picked.name,
              ocrText: picked.ocrText
            });
          }
          this.saveProgressText = '正在写入本地数据';
          const mediaInput: VaultItemInput = {
            type: VaultItemType.Image,
            groupId: this.newGroupId,
            title: this.newTitle,
            username: '',
            password: '',
            website: '',
            notes: this.newNotes
          };
          await vaultRepository.createItemWithAttachments(mediaInput, attachments,
            (completed: number, total: number): void => {
            this.saveProgress = 70 + Math.round(completed / total * 30);
          });
        } finally {
          compressedPaths.forEach((path: string): void => { mediaCompressionService.removeTemporary(path); });
        }
        const importedCount = this.pendingMedia.length;
        await this.rememberNewItemType(VaultItemType.Image);
        this.resetNewItem();
        this.closeNewItem();
        await this.refreshData();
        this.getUIContext().getPromptAction().showToast({ message: `已导入 ${importedCount} 项媒体` });
        return;
      }
      if (this.newType === VaultItemType.File) {
        if (this.pendingFiles.length === 0) {
          throw new Error('请先选择要导入的文件');
        }
        const attachments: VaultAttachmentInput[] = [];
        for (let index = 0; index < this.pendingFiles.length; index += 1) {
          const file = this.pendingFiles[index];
          attachments.push({
            type: VaultItemType.File,
            uri: file.uri,
            name: file.name,
            ocrText: ''
          });
        }
        this.saveProgressText = '正在写入本地数据';
        const fileInput: VaultItemInput = {
          type: VaultItemType.File,
          groupId: this.newGroupId,
          title: this.newTitle.trim(),
          username: '',
          password: '',
          website: '',
          notes: this.newNotes
        };
        await vaultRepository.createItemWithAttachments(fileInput, attachments,
          (completed: number, total: number): void => {
          this.saveProgress = Math.round(completed / total * 100);
        });
        const importedCount = this.pendingFiles.length;
        await this.rememberNewItemType(VaultItemType.File);
        this.resetNewItem();
        this.closeNewItem();
        await this.refreshData();
        this.getUIContext().getPromptAction().showToast({ message: `已导入 ${importedCount} 个文件` });
        return;
      }
      const input: VaultItemInput = {
        type: this.newType,
        groupId: this.newGroupId,
        title: this.newTitle,
        username: this.newUsername,
        password: this.newPassword,
        website: this.newWebsite,
        notes: this.newNotes
      };
      await vaultRepository.createItem(input);
      await this.rememberNewItemType(this.newType);
      this.resetNewItem();
      this.closeNewItem();
      await this.refreshData();
      this.getUIContext().getPromptAction().showToast({ message: '资料已保存' });
    } catch (error) {
      this.getUIContext().getPromptAction().showToast({ message: this.describeError(error) });
    } finally {
      this.savingNewItem = false;
      this.saveProgressText = '';
    }
      } catch (error) {
      throw normalizeError(error);
    }
  }

  private openItem(item: VaultItem, attachmentIndex: number = -1): void {
    this.selectedAttachmentIndex = attachmentIndex;
    this.selectedItem = item;
    this.detailGroupId = item.groupId;
    this.detailTitle = item.title;
    this.detailUsername = item.username;
    this.detailPassword = item.password;
    this.detailWebsite = item.website;
    this.detailNotes = item.notes;
    this.revealPassword = false;
    AbilityContextHolder.setPrivacyMode(false);
  }

  private async saveSelectedItem(): Promise<void> {
    try {
    const item = this.selectedItem;
    if (!item) {
      return;
    }
    const moved = item.groupId !== this.detailGroupId;
    const updated: VaultItem = {
      id: item.id,
      type: item.type,
      groupId: this.detailGroupId,
      title: this.detailTitle,
      username: this.detailUsername,
      password: this.detailPassword,
      website: this.detailWebsite,
      notes: this.detailNotes,
      ocrText: item.ocrText,
      createdAt: item.createdAt,
      updatedAt: Date.now(),
      deletedAt: item.deletedAt
    };
    try {
      await vaultRepository.updateItem(updated);
      await this.closeSelectedItem();
      this.getUIContext().getPromptAction().showToast({ message: moved ? '资料已移动并保存' : '修改已保存' });
    } catch (error) {
      this.getUIContext().getPromptAction().showToast({ message: this.describeError(error) });
    }
      } catch (error) {
      throw normalizeError(error);
    }
  }

  private async trashSelectedItem(): Promise<void> {
    try {
    const item = this.selectedItem;
    if (!item) {
      return;
    }
    try {
      await vaultRepository.moveToTrash(item.id);
      await this.closeSelectedItem(false);
      await this.refreshData(true);
      this.getUIContext().getPromptAction().showToast({ message: '资料已移入回收站' });
    } catch (error) {
      this.getUIContext().getPromptAction().showToast({ message: this.describeError(error) });
    }
      } catch (error) {
      throw normalizeError(error);
    }
  }

  private resetNewItem(): void {
    this.newType = this.lastNewItemType;
    this.newTitle = '';
    this.newUsername = '';
    this.newPassword = '';
    this.newWebsite = '';
    this.revealNewPassword = false;
    this.newNotes = '';
    this.clearPendingMedia();
    this.clearPendingFiles();
  }

  private async rememberNewItemType(type: VaultItemType): Promise<void> {
    this.lastNewItemType = type;
    await vaultUiPreferences.setLastNewItemType(type);
  }

  private clearPendingMedia(): void {
    this.mediaRecognitionVersion += 1;
    this.pendingMedia = [];
    this.selectedMediaCount = 0;
    this.selectedMediaPreviewIndex = 0;
    this.recognizingMedia = false;
    this.recognitionProgressText = '';
  }

  private clearPendingFiles(): void {
    this.pendingFiles = [];
    this.selectedFileCount = 0;
  }

  private describeError(error: Object): string {
    return normalizeError(error).message;
  }

  private countGroup(groupId: number): number {
    let count: number = 0;
    this.allItems.forEach((item: VaultItem): void => {
      if (item.groupId === groupId) {
        count += 1;
      }
    });
    return count;
  }

  private matchesCategory(item: VaultItem, type: VaultItemType): boolean {
    if (type === VaultItemType.Image) {
      return item.type === VaultItemType.Image || item.type === VaultItemType.Video;
    }
    return item.type === type;
  }

  private itemsInGroup(groupId: number): VaultItem[] {
    return this.allItems.filter((item: VaultItem): boolean => item.groupId === groupId);
  }

  private itemsInGroupByType(groupId: number, type: VaultItemType): VaultItem[] {
    return this.allItems.filter((item: VaultItem): boolean => item.groupId === groupId && this.matchesCategory(item, type));
  }

  private countGroupByType(groupId: number, type: VaultItemType): number {
    return this.itemsInGroupByType(groupId, type).length;
  }

  private selectCategoryType(type: VaultItemType): void {
    this.selectedCategoryType = type;
    if (this.categoryGroupId >= 0 && this.countGroupByType(this.categoryGroupId, type) === 0) {
      this.categoryGroupId = -1;
    }
  }

  private categoryItems(): VaultItem[] {
    const result = this.allItems.filter((item: VaultItem): boolean =>
      this.matchesCategory(item, this.selectedCategoryType) &&
      (this.categoryGroupId < 0 || item.groupId === this.categoryGroupId));
    result.sort((left: VaultItem, right: VaultItem): number => {
      if (this.categorySort === 'created') { return right.createdAt - left.createdAt; }
      if (this.categorySort === 'name') {
        const leftTitle = left.title.trim().toLowerCase();
        const rightTitle = right.title.trim().toLowerCase();
        if (leftTitle === rightTitle) { return right.updatedAt - left.updatedAt; }
        return leftTitle > rightTitle ? 1 : -1;
      }
      return right.updatedAt - left.updatedAt;
    });
    return result;
  }

  private categorySortLabel(): string {
    if (this.categorySort === 'created') { return '最近创建'; }
    if (this.categorySort === 'name') { return '名称'; }
    return '最近修改';
  }

  private async chooseCategorySort(): Promise<void> {
    try {
    const values: string[] = ['updated', 'created', 'name'];
    const buttons: [promptAction.Button, promptAction.Button, promptAction.Button] = [
      { text: `${this.categorySort === 'updated' ? '✓  ' : ''}最近修改`,
        color: this.categorySort === 'updated' ? COLOR_PRIMARY : COLOR_TEXT },
      { text: `${this.categorySort === 'created' ? '✓  ' : ''}最近创建`,
        color: this.categorySort === 'created' ? COLOR_PRIMARY : COLOR_TEXT },
      { text: `${this.categorySort === 'name' ? '✓  ' : ''}名称`,
        color: this.categorySort === 'name' ? COLOR_PRIMARY : COLOR_TEXT }
    ];
    try {
      const result: promptAction.ActionMenuSuccessResponse =
        await this.getUIContext().getPromptAction().showActionMenu({ title: '选择排序方式', buttons: buttons });
      if (result.index >= 0 && result.index < values.length) { this.categorySort = values[result.index]; }
    } catch (error) {
      // 用户关闭菜单时保持当前排序，不需要提示错误。
    }
      } catch (error) {
      throw normalizeError(error);
    }
  }

  @Builder
  private topBar(): void {
    Row({ space: 4 }) {
      Row({ space: 10 }) {
        Stack() {
          Circle({ width: 12, height: 12 })
            .fill(Color.Transparent).stroke(COLOR_MUTED).strokeWidth(2)
            .position({ left: 2, top: 2 })
          Divider()
            .width(7).strokeWidth(2).color(COLOR_MUTED).borderRadius(1)
            .rotate({ angle: 45 })
            .position({ left: 11, top: 14 })
        }
        .width(20).height(20)
        .alignSelf(ItemAlign.Center)
        if (this.searchActive) {
          TextInput({ placeholder: '搜索名称/内容/文件名/图片文字…', text: this.searchText })
            .id('homeSearchInput')
            .layoutWeight(1)
            .height(44)
            .defaultFocus(true)
            .fontSize(14)
            .fontWeight(FontWeight.Normal)
            .placeholderFont({ size: 14, weight: FontWeight.Normal })
            .padding(0)
            .fontColor(COLOR_TEXT)
            .placeholderColor(COLOR_MUTED_LIGHT)
            .backgroundColor(Color.Transparent)
            .onChange((value: string): void => { this.applySearch(value); })
        } else {
          Text(this.searchText.length > 0 ? this.searchText : '搜索名称/内容/文件名/图片文字…')
            .layoutWeight(1)
            .fontSize(14)
            .fontWeight(FontWeight.Normal)
            .fontColor(this.searchText.length > 0 ? COLOR_TEXT : COLOR_MUTED_LIGHT)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        if (this.searchText.length > 0) {
          Stack({ alignContent: Alignment.Center }) {
            Circle({ width: 22, height: 22 }).fill(COLOR_SURFACE_2)
            Divider().width(9).strokeWidth(1.6).color(COLOR_MUTED).borderRadius(1)
              .rotate({ angle: 45 })
            Divider().width(9).strokeWidth(1.6).color(COLOR_MUTED).borderRadius(1)
              .rotate({ angle: -45 })
          }
          .width(28).height(44)
          .alignSelf(ItemAlign.Center)
          .onClick((): void => { this.applySearch(''); })
        }
      }
      .height(44)
      .alignItems(VerticalAlign.Center)
      .layoutWeight(1)
      .padding({ left: 12, right: 8 })
      .backgroundColor(COLOR_SURFACE)
      .borderRadius(15)
      .border({ width: 1, color: COLOR_BORDER })
      .onClick((): void => { this.activateSearch(); })

      Button('锁定')
        .width(58)
        .height(42)
        .fontSize(12)
        .fontColor(COLOR_PRIMARY)
        .backgroundColor(COLOR_SURFACE)
        .borderRadius(14)
        .onClick((): void => { this.lockVault(); })
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 9, bottom: 0 })
    .backgroundColor(COLOR_BG)
  }

  @Builder
  private itemRow(item: VaultItem, showThumbnail: boolean = false, highlightedAttachmentIndex: number = -1,
    thumbnailCount: number = 3, originalGroupName: string = ''): void {
    Row({ space: 8 }) {
      if (showThumbnail && (item.type === VaultItemType.Image || item.type === VaultItemType.Video)) {
        VaultAttachmentPreview({
          itemId: item.id,
          fallbackType: item.type,
          highlightAttachmentIndex: highlightedAttachmentIndex,
          maxVisibleCount: thumbnailCount
        })
      }
      Column({ space: 1 }) {
        if (item.deletedAt > 0) {
          Row({ space: 5 }) {
            Text('回收站')
              .fontSize(10).fontWeight(FontWeight.Medium).fontColor(COLOR_DANGER)
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .backgroundColor(COLOR_DANGER_TINT).borderRadius(7)
            Text(originalGroupName.length > 0 ? `原分组 · ${originalGroupName}` : '已删除')
              .fontSize(10).fontColor(COLOR_MUTED).maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }.width('100%')
        }
        if (item.type === VaultItemType.File) {
          if (item.title.length > 0) {
            Text(item.title)
              .fontSize(13).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
          }
          VaultFileSummary({ itemId: item.id })
        } else if (item.type === VaultItemType.Image || item.type === VaultItemType.Video) {
          if (item.title.length > 0) {
            Text(item.title)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(COLOR_TEXT)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
        } else {
          Text(itemDisplayTitle(item))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(COLOR_TEXT)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          Text(item.username.length > 0 ? item.username : (item.notes.length > 0 ? item.notes : itemTypeLabel(item.type)))
            .fontSize(11)
            .fontColor(COLOR_MUTED)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Text('›').fontSize(20).fontColor(COLOR_CHEVRON)
    }
    .width('100%')
    .constraintSize({ minHeight: item.type === VaultItemType.File ? 48 + (item.deletedAt > 0 ? 20 : 0) :
      (showThumbnail && (item.type === VaultItemType.Image || item.type === VaultItemType.Video) ?
        (highlightedAttachmentIndex >= 0 ? 52 : 48) + (item.deletedAt > 0 ? 20 : 0) :
        42 + (item.deletedAt > 0 ? 20 : 0)) })
    .padding({ left: 8, right: 8, top: item.type === VaultItemType.File ? 5 : 0,
      bottom: item.type === VaultItemType.File ? 5 : 0 })
    .backgroundColor(COLOR_SURFACE)
    .borderRadius(15)
    .onClick((): void => {
      if (item.deletedAt > 0) {
        this.openTrashDetail({ item: item, originalGroupName: originalGroupName });
      } else {
        this.openItem(item, highlightedAttachmentIndex);
      }
    })
  }

  @Builder
  private homeMediaItemRow(item: VaultItem): void {
    Column({ space: 3 }) {
      if (item.title.length > 0) {
        Text(item.title)
          .fontSize(13).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      VaultAttachmentPreview({
        itemId: item.id,
        fallbackType: item.type,
        maxVisibleCount: 3
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 8, right: 8, top: 5, bottom: 5 })
    .backgroundColor(COLOR_SURFACE)
    .borderRadius(15)
    .onClick((): void => { this.openItem(item); })
  }

  @Builder
  private ocrSearchHitRow(hit: VaultSearchHit): void {
    Column({ space: 4 }) {
      if (hit.item.deletedAt > 0) {
        Row({ space: 5 }) {
          Text('回收站')
            .fontSize(10).fontWeight(FontWeight.Medium).fontColor(COLOR_DANGER)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .backgroundColor(COLOR_DANGER_TINT).borderRadius(7)
          Text(`原分组 · ${hit.originalGroupName}`)
            .fontSize(10).fontColor(COLOR_MUTED).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }.width('100%')
      }
      if (itemDisplayTitle(hit.item).length > 0) {
        Text(itemDisplayTitle(hit.item))
          .fontSize(14).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      if (hit.item.type === VaultItemType.File) {
        Row({ space: 6 }) {
          Text('文件')
            .fontSize(9).fontWeight(FontWeight.Medium).fontColor(COLOR_PRIMARY)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .backgroundColor(COLOR_PRIMARY_TINT).borderRadius(7)
          Text(hit.matchedTextLine)
            .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
        }
        .width('100%')
      } else {
        VaultAttachmentPreview({
          itemId: hit.item.id,
          fallbackType: hit.item.type,
          highlightAttachmentIndex: hit.attachmentIndex,
          maxVisibleCount: 6
        })
      }
      if (hit.item.type !== VaultItemType.File && hit.matchedTextLine.length > 0) {
        Text(hit.matchedTextLine)
          .fontSize(12).lineHeight(18).fontColor(COLOR_MUTED)
          .width('100%').textAlign(TextAlign.Start)
      }
    }
    .width('100%')
    .padding({ left: 12, right: 10, top: 6, bottom: 6 })
    .backgroundColor(COLOR_SURFACE)
    .borderRadius(15)
    .onClick((): void => { this.openSearchResult(hit); })
  }

  @Builder
  private emptyState(title: string, description: string): void {
    Column({ space: 6 }) {
      Text(title).fontSize(16).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT)
      Text(description).fontSize(13).fontColor(COLOR_MUTED).textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding({ top: 34, bottom: 34 })
  }

  private homeGroupCardHeight(groupId: number, showAll: boolean): number {
    const items = this.itemsInGroup(groupId);
    if (items.length === 0) {
      return 92;
    }
    const visibleItems = showAll ? items : items.slice(0, 3);
    let height = 58;
    for (let index = 0; index < visibleItems.length; index += 1) {
      const type = visibleItems[index].type;
      if (type === VaultItemType.Image || type === VaultItemType.Video) {
        height += visibleItems[index].title.length > 0 ? 62 : 48;
      } else if (type === VaultItemType.File) {
        height += 62;
      } else {
        height += 42;
      }
    }
    if (!showAll && items.length > 3) {
      height += 34;
    }
    return height + 3;
  }

  private canShowAllHomeItems(): boolean {
    let leftHeight = 0;
    let rightHeight = 0;
    for (let index = 0; index < this.groups.length; index += 1) {
      const height = this.homeGroupCardHeight(this.groups[index].id, true);
      if (leftHeight <= rightHeight) {
        leftHeight += height;
      } else {
        rightHeight += height;
      }
    }
    if (this.countGroup(0) > 0) {
      const height = this.homeGroupCardHeight(0, true);
      if (leftHeight <= rightHeight) {
        leftHeight += height;
      } else {
        rightHeight += height;
      }
    }
    // 首页上方还有搜索和安全存储区域，分组双列实际可见高度约为 420vp。
    // 使用可见区域而不是整屏高度判断，避免卡片已经超出首屏却仍被当成“可全部显示”。
    return Math.max(leftHeight, rightHeight) <= 420;
  }

  private homeItemsInGroup(groupId: number): VaultItem[] {
    const items = this.itemsInGroup(groupId);
    return this.canShowAllHomeItems() || this.expandedGroupId === groupId ? items : items.slice(0, 3);
  }

  private shouldShowHomeMoreRow(groupId: number): boolean {
    const total = this.countGroup(groupId);
    if (total <= 3) {
      return false;
    }
    return this.expandedGroupId === groupId || this.homeItemsInGroup(groupId).length < total;
  }

  private homeSectionColumn(sectionId: number): number {
    let leftHeight = 0;
    let rightHeight = 0;
    const showAll = this.canShowAllHomeItems();
    for (let index = 0; index < this.groups.length; index += 1) {
      const group = this.groups[index];
      const column = leftHeight <= rightHeight ? 0 : 1;
      if (group.id === sectionId) {
        return column;
      }
      if (column === 0) {
        leftHeight += this.homeGroupCardHeight(group.id, showAll);
      } else {
        rightHeight += this.homeGroupCardHeight(group.id, showAll);
      }
    }
    return leftHeight <= rightHeight ? 0 : 1;
  }

  @Builder
  private homeGroupColumn(column: number): void {
    Column() {
      ForEach(this.groups, (group: VaultGroup): void => {
        if (this.homeSectionColumn(group.id) === column) {
          this.groupSection(group, true)
        }
      }, (group: VaultGroup): string => `${group.id}-${group.name}`)
      if (this.countGroup(0) > 0 && this.homeSectionColumn(0) === column) {
        this.ungroupedSection(true)
      }
    }
    .width('48.5%')
  }

  private beginGroupDrag(group: VaultGroup, event: DragEvent): DragItemInfo {
    this.draggingGroupId = group.id;
    this.draggingGroupName = group.name;
    this.groupDropTargetId = group.id;
    this.groupDragAccepted = false;
    this.groupDragCancelled = false;
    this.groupDragCancelActive = false;
    this.groupsBeforeDrag = this.groups.slice();
    this.groupDragPositionLocked = false;
    this.groupDragLastReorderX = event.getWindowX();
    this.groupDragLastReorderY = event.getWindowY();
    this.groupDragClickSuppressed = true;
    return { extraInfo: `${group.id}` };
  }

  private previewGroupReorder(targetId: number, event: DragEvent): void {
    if (this.draggingGroupId < 0 || targetId < 0 || targetId === this.draggingGroupId ||
      targetId === this.groupDropTargetId) { return; }
    const pointerX = event.getWindowX();
    const pointerY = event.getWindowY();
    if (this.groupDragPositionLocked) {
      const deltaX = pointerX - this.groupDragLastReorderX;
      const deltaY = pointerY - this.groupDragLastReorderY;
      if (deltaX * deltaX + deltaY * deltaY < 2304) { return; }
      this.groupDragPositionLocked = false;
    }
    const sourceIndex = this.groups.findIndex((group: VaultGroup): boolean =>
      group.id === this.draggingGroupId);
    const targetIndex = this.groups.findIndex((group: VaultGroup): boolean => group.id === targetId);
    if (sourceIndex < 0 || targetIndex < 0 || sourceIndex === targetIndex) { return; }
    const reordered = this.groups.slice();
    const moved = reordered.splice(sourceIndex, 1)[0];
    reordered.splice(targetIndex, 0, moved);
    this.groupDropTargetId = targetId;
    this.groupDragLastReorderX = pointerX;
    this.groupDragLastReorderY = pointerY;
    this.groupDragPositionLocked = true;
    this.groups = reordered;
  }

  private scheduleFinishGroupDrag(): void {
    if (this.groupDragFinalizeScheduled) { return; }
    this.groupDragFinalizeScheduled = true;
    setTimeout((): void => {
      this.groupDragFinalizeScheduled = false;
      this.finishGroupDrag();
    }, 80);
  }

  private async finishGroupDrag(): Promise<void> {
    try {
    const sourceId = this.draggingGroupId;
    const accepted = this.groupDragAccepted && !this.groupDragCancelled;
    const originalGroups = this.groupsBeforeDrag.slice();
    const reordered = this.groups.slice();
    this.draggingGroupId = -1;
    this.draggingGroupName = '';
    this.groupDropTargetId = -1;
    this.groupDragCancelActive = false;
    this.groupDragAccepted = false;
    this.groupDragCancelled = false;
    this.groupsBeforeDrag = [];
    this.groupDragPositionLocked = false;
    setTimeout((): void => { this.groupDragClickSuppressed = false; }, 250);
    if (sourceId < 0) { return; }
    if (!accepted) {
      this.groups = originalGroups;
      return;
    }
    const originalIds = originalGroups.map((group: VaultGroup): number => group.id).join(',');
    const reorderedIds = reordered.map((group: VaultGroup): number => group.id).join(',');
    if (originalIds === reorderedIds) { return; }
    try {
      await vaultRepository.reorderGroups(reordered.map((group: VaultGroup): number => group.id));
    } catch (error) {
      this.groups = originalGroups;
      this.getUIContext().getPromptAction().showToast({ message: this.describeError(error) });
    }
      } catch (error) {
      throw normalizeError(error);
    }
  }

  @Builder
  private homeTab(): void {
    Scroll() {
      Column({ space: 12 }) {
        Column({ space: 10 }) {
          Row() {
            Column({ space: 5 }) {
              Text('安全存储')
                .fontSize(22).fontWeight(FontWeight.Bold).fontColor(COLOR_HERO_TITLE)
              Text('所有资料只会存储在本地')
                .fontSize(13).fontColor(COLOR_HERO_MUTED)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Column({ space: 2 }) {
              Text(`${this.totalItemCount}`)
                .fontSize(28).fontWeight(FontWeight.Bold).fontColor(COLOR_ON_DARK)
              Text('条资料').fontSize(11).fontColor(COLOR_HERO_MUTED)
            }
          }
          .width('100%')
          Row({ space: 5 }) {
            this.summaryPill(VaultItemType.Login)
            this.summaryPill(VaultItemType.Note)
            this.summaryPill(VaultItemType.Image)
            this.summaryPill(VaultItemType.File)
          }
          .width('100%')
        }
        .width('100%')
        .padding({ left: 15, right: 15, top: 13, bottom: 13 })
        .backgroundColor(COLOR_HERO_SURFACE)
        .borderRadius(18)

        Row() {
          Column({ space: 3 }) {
            Text(this.searchText.length > 0 ? '搜索结果' : '我的分组')
              .fontSize(20).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT)
            if (this.searchText.length > 0) {
              Text(`找到 ${this.searchHits.length} 项结果`)
                .fontSize(12).fontColor(COLOR_MUTED)
            }
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          if (this.searchText.length === 0) {
            if (this.draggingGroupId >= 0) {
              Button('拖到这里取消')
                .height(38).fontSize(12).fontColor(COLOR_DANGER)
                .backgroundColor(this.groupDragCancelActive ? COLOR_DANGER_WASH_STRONG : COLOR_DANGER_WASH)
                .border({ width: this.groupDragCancelActive ? 2 : 1, color: COLOR_DANGER })
                .borderRadius(12)
                .onDragEnter((): void => { this.groupDragCancelActive = true; })
                .onDragLeave((): void => { this.groupDragCancelActive = false; })
                .onDrop((): void => {
                  this.groupDragCancelled = true;
                  this.groupDragAccepted = true;
                  this.groupDragCancelActive = false;
                })
            } else {
              Button('+ 新建分组')
                .height(38).fontSize(13).fontColor(COLOR_PRIMARY)
                .backgroundColor(COLOR_PRIMARY_TINT).borderRadius(12)
                .onClick((): void => { this.openNewGroup(); })
            }
          }
        }
        .width('100%')

        if (this.searchText.length > 0) {
          Column({ space: 4 }) {
            if (this.searchHits.length === 0) {
              this.emptyState('没有找到资料', '换个关键词搜索标题、内容、附件文件名或图片文字')
            } else {
              ForEach(this.searchHits, (hit: VaultSearchHit): void => {
                if (hit.attachmentIndex >= 0) {
                  this.ocrSearchHitRow(hit)
                } else {
                  this.itemRow(hit.item, true, -1, 3, hit.originalGroupName)
                }
              }, (hit: VaultSearchHit): string =>
                `${hit.item.id}-${hit.attachmentIndex}-${hit.item.updatedAt}`)
            }
          }
          .width('100%')
        } else if (this.groups.length === 0 && this.countGroup(0) === 0) {
          this.emptyState('还没有分组', '创建分组后，即可分类保存各种资料')
        } else {
          Row({ space: 3 }) {
            this.homeGroupColumn(0)
            this.homeGroupColumn(1)
          }
          .alignItems(VerticalAlign.Top)
          .width('100%')
        }
      }
      .width('100%')
      .constraintSize({ minHeight: '100%' })
      .padding({ left: 18, right: 18, top: 12, bottom: 92 })
    }
    .width('100%')
    .height('100%')
    .onAppear((): void => { this.clearHomeFocus(); })
  }

  @Builder
  private summaryPill(type: VaultItemType): void {
    Text(`${itemTypeLabel(type)} ${type === VaultItemType.Login ? this.loginCount :
      (type === VaultItemType.Note ? this.noteCount :
        (type === VaultItemType.File ? this.fileCount : this.mediaCount))}`)
      .fontSize(11).fontColor(COLOR_HERO_TEXT)
      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
      .backgroundColor(COLOR_HERO_PILL)
      .borderRadius(10)
  }

  @Builder
  private moreItemsRow(groupId: number, total: number): void {
    Row() {
      Text(this.expandedGroupId === groupId ? `已显示全部 ${total} 条` : `另有 ${total - 3} 条资料`)
        .fontSize(11)
        .fontColor(COLOR_MUTED)
      Blank()
      Text(this.expandedGroupId === groupId ? '收起  ↑' : '展开全部  ↓')
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(COLOR_PRIMARY)
    }
    .width('100%')
    .height(34)
    .padding({ left: 12, right: 12 })
    .backgroundColor(COLOR_CARD_HIGHLIGHT)
    .border({ width: { top: 1 }, color: COLOR_BORDER })
    .opacity(this.draggingGroupId === groupId ? 0 : 1)
    .onClick((): void => {
      this.expandedGroupId = this.expandedGroupId === groupId ? -1 : groupId;
    })
  }

  @Builder
  private groupSection(group: VaultGroup, fullWidth: boolean): void {
    Column() {
      Row({ space: 8 }) {
        Row({ space: 5 }) {
          Stack({ alignContent: Alignment.Start }) {
            Column({ space: 2 }) {
              Text(group.name)
                .fontSize(15).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT)
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
              Text(`${this.countGroup(group.id)} 条资料`).fontSize(11).fontColor(COLOR_MUTED)
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
            .opacity(this.draggingGroupId === group.id ? 0 : 1)
            Text('松开以放置')
              .fontSize(13).fontWeight(FontWeight.Medium).fontColor(COLOR_PRIMARY)
              .opacity(this.draggingGroupId === group.id ? 1 : 0)
          }
          .layoutWeight(1)
        }
        .layoutWeight(1)
        .onClick((): void => {
          if (this.groupDragClickSuppressed) { return; }
          if (this.shouldShowHomeMoreRow(group.id)) {
            this.expandedGroupId = this.expandedGroupId === group.id ? -1 : group.id;
          }
        })
        .backgroundColor(this.groupDropTargetId === group.id && this.draggingGroupId !== group.id ?
          COLOR_PRIMARY_TINT : Color.Transparent)
        .borderRadius(11)
        Stack() {
          Text('+').fontSize(22).fontColor(COLOR_PRIMARY)
        }
          .width(34).height(34).borderRadius(11).backgroundColor(COLOR_PRIMARY_TINT)
          .opacity(this.draggingGroupId === group.id ? 0 : 1)
          .draggable(false)
          .onClick((): void => {
            this.openNewItem(undefined, group.id);
          })
      }
      .width('100%')
      .padding({ left: 12, right: 10, top: 8, bottom: 7 })
      if (this.countGroup(group.id) === 0) {
        Text('暂无资料，点击添加')
          .fontSize(11).fontColor(COLOR_MUTED).maxLines(1)
          .width('100%').padding({ left: 12, right: 12, top: 10, bottom: 12 })
          .border({ width: { top: 1 }, color: COLOR_BORDER })
          .opacity(this.draggingGroupId === group.id ? 0 : 1)
      } else {
        Column({ space: 0 }) {
          ForEach(this.homeItemsInGroup(group.id), (item: VaultItem, index: number): void => {
            if (index > 0) {
              Divider().strokeWidth(1).color(COLOR_BORDER).margin({ left: 8, right: 8 })
            }
            if (item.type === VaultItemType.Image || item.type === VaultItemType.Video) {
              this.homeMediaItemRow(item)
            } else {
              this.itemRow(item, true)
            }
          }, (item: VaultItem): string => `${item.id}-${item.updatedAt}`)
        }
        .width('100%')
        .padding({ left: 3, right: 3, bottom: 3 })
        .border({ width: { top: 1 }, color: COLOR_BORDER })
        .opacity(this.draggingGroupId === group.id ? 0 : 1)
        if (this.shouldShowHomeMoreRow(group.id)) {
          this.moreItemsRow(group.id, this.countGroup(group.id))
        }
      }
    }
    .width(fullWidth ? '100%' : '48.5%')
    .margin({ bottom: 3 })
    .backgroundColor(this.draggingGroupId === group.id ? COLOR_GROUP_DRAG : COLOR_SURFACE)
    .borderRadius(18)
    .border({ width: this.groupDropTargetId === group.id && this.draggingGroupId !== group.id ? 2 : 1,
      color: this.draggingGroupId === group.id ? COLOR_PRIMARY :
        (this.groupDropTargetId === group.id ? COLOR_PRIMARY : COLOR_BORDER),
      style: this.draggingGroupId === group.id ? BorderStyle.Dashed : BorderStyle.Solid })
    .onDragStart((event: DragEvent): DragItemInfo => this.beginGroupDrag(group, event))
    .onDragEnter((event: DragEvent): void => { this.previewGroupReorder(group.id, event); })
    .onDragMove((event: DragEvent): void => { this.previewGroupReorder(group.id, event); })
    .onDrop((): void => {
      this.groupDragAccepted = true;
      this.groupDragCancelled = false;
    })
    .onDragEnd((): void => { this.scheduleFinishGroupDrag(); })
  }

  @Builder
  private ungroupedSection(fullWidth: boolean): void {
    Column() {
      Row() {
        Text('未分组').fontSize(16).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT)
        Blank()
        Text(`${this.countGroup(0)} 条资料`).fontSize(11).fontColor(COLOR_MUTED)
      }
      .width('100%').padding({ left: 12, right: 12, top: 9, bottom: 8 })
      .onClick((): void => {
        if (this.shouldShowHomeMoreRow(0)) {
          this.expandedGroupId = this.expandedGroupId === 0 ? -1 : 0;
        }
      })
      Column({ space: 0 }) {
        ForEach(this.homeItemsInGroup(0), (item: VaultItem, index: number): void => {
          if (index > 0) {
            Divider().strokeWidth(1).color(COLOR_BORDER).margin({ left: 8, right: 8 })
          }
          if (item.type === VaultItemType.Image || item.type === VaultItemType.Video) {
            this.homeMediaItemRow(item)
          } else {
            this.itemRow(item, true)
          }
        }, (item: VaultItem): string => `${item.id}-${item.updatedAt}`)
      }
      .width('100%').padding({ left: 3, right: 3, bottom: 3 })
      .border({ width: { top: 1 }, color: COLOR_BORDER })
      if (this.shouldShowHomeMoreRow(0)) {
        this.moreItemsRow(0, this.countGroup(0))
      }
    }
    .width(fullWidth ? '100%' : '48.5%')
    .margin({ bottom: 3 }).backgroundColor(COLOR_SURFACE).borderRadius(18)
    .border({ width: 1, color: COLOR_BORDER })
  }

  @Builder
  private categoryTab(): void {
    VaultCategoryPanel({
      selectedType: this.selectedCategoryType,
      selectedGroupId: this.categoryGroupId,
      sortLabel: this.categorySortLabel(),
      groups: this.groups,
      items: this.categoryItems(),
      allItems: this.allItems,
      loginCount: this.loginCount,
      noteCount: this.noteCount,
      mediaCount: this.mediaCount,
      fileCount: this.fileCount,
      onSelectType: (type: VaultItemType): void => { this.selectCategoryType(type); },
      onSelectGroup: (groupId: number): void => { this.categoryGroupId = groupId; },
      onChooseSort: (): void => { this.chooseCategorySort(); },
      onOpenItem: (item: VaultItem): void => { this.openItem(item); }
    })
  }

  @Builder
  private trashFilterChip(value: string, label: string): void {
    Text(label)
      .fontSize(12).maxLines(1)
      .fontColor(this.trashTypeFilter === value ? COLOR_BG : COLOR_MUTED)
      .padding({ left: 12, right: 12, top: 7, bottom: 7 })
      .backgroundColor(this.trashTypeFilter === value ? COLOR_PRIMARY : COLOR_SURFACE_2)
      .borderRadius(14)
      .onClick((): void => { this.setTrashTypeFilter(value); })
  }

  @Builder
  private trashEntryCard(entry: VaultTrashEntry): void {
    Column({ space: 5 }) {
      Row({ space: 8 }) {
        if (this.trashManaging) {
          Stack({ alignContent: Alignment.Center }) {
            Circle({ width: 22, height: 22 })
              .fill(this.trashIsSelected(entry.item.id) ? COLOR_PRIMARY : Color.Transparent)
              .stroke(this.trashIsSelected(entry.item.id) ? COLOR_PRIMARY : COLOR_DISABLED).strokeWidth(1.5)
            if (this.trashIsSelected(entry.item.id)) {
              Text('✓').fontSize(13).fontWeight(FontWeight.Bold).fontColor(COLOR_ON_DARK)
            }
          }.width(26).height(32)
        }
        Column({ space: 3 }) {
          if (itemDisplayTitle(entry.item).length > 0) {
            Text(itemDisplayTitle(entry.item))
              .fontSize(14).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
          }
          Row({ space: 6 }) {
            Text(itemTypeLabel(entry.item.type)).fontSize(10).fontColor(COLOR_PRIMARY)
              .padding({ left: 7, right: 7, top: 2, bottom: 2 })
              .backgroundColor(COLOR_PRIMARY_TINT).borderRadius(8)
            Text(entry.originalGroupName).fontSize(11).fontColor(COLOR_MUTED)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          }.width('100%')
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Text(this.formatTrashTime(entry.item.deletedAt)).fontSize(10).fontColor(COLOR_MUTED_LIGHT)
      }.width('100%')
      if (entry.item.type === VaultItemType.Image || entry.item.type === VaultItemType.Video) {
        VaultAttachmentPreview({ itemId: entry.item.id, fallbackType: entry.item.type, maxVisibleCount: 5 })
      } else if (entry.item.type === VaultItemType.Login && entry.item.username.length > 0) {
        Text(entry.item.username).fontSize(11).fontColor(COLOR_MUTED).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
      } else if (entry.item.notes.length > 0) {
        Text(entry.item.notes).fontSize(11).fontColor(COLOR_MUTED).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
      }
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 8, bottom: 8 })
    .backgroundColor(COLOR_SURFACE).borderRadius(14)
    .border({ width: 1, color: this.trashIsSelected(entry.item.id) ? COLOR_PRIMARY : COLOR_BORDER })
    .onClick((): void => { this.openTrashDetail(entry); })
    .priorityGesture(LongPressGesture({ repeat: false, duration: 500 })
      .onAction((): void => { this.openTrashManagement(entry.item.id); }))
  }

  @Builder
  private trashSectionList(section: string): void {
    if (this.trashEntriesInSection(section).length > 0) {
      Column({ space: 4 }) {
        Text(section).fontSize(12).fontWeight(FontWeight.Medium).fontColor(COLOR_MUTED)
          .width('100%').padding({ left: 2, top: 3 })
        ForEach(this.trashEntriesInSection(section), (entry: VaultTrashEntry): void => {
          this.trashEntryCard(entry)
        }, (entry: VaultTrashEntry): string => `${entry.item.id}-${entry.item.deletedAt}`)
      }.width('100%')
    }
  }

  @Builder
  private trashTab(): void {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text(`${this.trashEntries.length} 条资料`).fontSize(11).fontColor(COLOR_MUTED)
        Blank()
        if (!this.trashManaging) {
          Button(ACTION_MANAGE).height(40).fontSize(12).fontColor(COLOR_PRIMARY)
            .backgroundColor(COLOR_SURFACE).borderRadius(12)
            .onClick((): void => { this.openTrashManagement(); })
          Row({ space: 3 }) {
            Circle({ width: 3, height: 3 }).fill(COLOR_MUTED)
            Circle({ width: 3, height: 3 }).fill(COLOR_MUTED)
            Circle({ width: 3, height: 3 }).fill(COLOR_MUTED)
          }
            .width(40).height(40).justifyContent(FlexAlign.Center)
            .backgroundColor(COLOR_SURFACE).borderRadius(12)
            .onClick((): void => { this.showTrashMore = !this.showTrashMore; })
        }
      }.width('100%')
      Scroll() {
        Row({ space: 6 }) {
          this.trashFilterChip('all', '全部')
          this.trashFilterChip(VaultItemType.Login, '账号')
          this.trashFilterChip(VaultItemType.Note, '笔记')
          this.trashFilterChip(VaultItemType.Image, '媒体')
          this.trashFilterChip(VaultItemType.File, '文件')
        }
      }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
      if (this.showTrashMore && !this.trashManaging) {
        Row() {
          Text('清空回收站').fontSize(12).fontColor(COLOR_DANGER)
          Blank()
          Text('永久删除全部资料').fontSize(10).fontColor(COLOR_MUTED)
        }
        .width('100%').height(38).padding({ left: 12, right: 12 })
        .backgroundColor(COLOR_DANGER_WASH).borderRadius(11)
        .onClick((): void => { this.emptyTrash(); })
      }
      if (this.trashManaging) {
        Row() {
          Text(`已选择 ${this.trashSelectedIds.length} 项`).fontSize(12).fontColor(COLOR_TEXT)
          Blank()
          Text(this.trashSelectedIds.length === this.trashEntries.length && this.trashEntries.length > 0 ? '取消全选' : '全选')
            .fontSize(12).fontColor(COLOR_PRIMARY).padding(6)
            .onClick((): void => { this.toggleSelectAllTrash(); })
          Text(ACTION_CANCEL).fontSize(12).fontColor(COLOR_MUTED).padding(6)
            .onClick((): void => { this.closeTrashManagement(); })
        }.width('100%').height(34)
      }
      Scroll() {
        Column({ space: 7 }) {
          if (this.trashEntries.length === 0) {
            this.emptyState(this.trashTypeFilter !== 'all' ? '没有此类型的资料' : '回收站为空',
              this.trashTypeFilter !== 'all' ? '选择其他类型查看' : '删除的资料会一直保留在这里')
          } else {
            this.trashSectionList('今天')
            this.trashSectionList('最近 7 天')
            this.trashSectionList('更早')
          }
        }.width('100%')
      }.layoutWeight(1).width('100%').scrollBar(BarState.Off)
      if (this.trashManaging) {
        Row({ space: 8 }) {
          Button('恢复')
            .layoutWeight(1).height(44).fontColor(COLOR_PRIMARY).backgroundColor(COLOR_PRIMARY_ALT_TINT).borderRadius(13)
            .enabled(this.trashSelectedIds.length > 0).opacity(this.trashSelectedIds.length > 0 ? 1 : 0.45)
            .onClick((): void => { this.restoreSelectedTrash(); })
          Button('永久删除')
            .layoutWeight(1).height(44).fontColor(COLOR_DANGER).backgroundColor(COLOR_DANGER_TINT).borderRadius(13)
            .enabled(this.trashSelectedIds.length > 0).opacity(this.trashSelectedIds.length > 0 ? 1 : 0.45)
            .onClick((): void => { this.permanentlyDeleteSelectedTrash(); })
        }.width('100%')
      }
    }
    .width('100%').height('100%')
    .padding({ left: 18, right: 18, top: 10, bottom: 92 })
  }

  @Builder
  private groupManagerTab(): void {
    VaultGroupManager({
      groups: this.groups,
      countGroup: (groupId: number): number => this.countGroup(groupId),
      onBack: (): void => { this.showGroupManager = false; },
      onRename: (group: VaultGroup): void => { this.requestRenameGroup(group); },
      onDelete: (group: VaultGroup): void => { this.requestDeleteGroup(group); }
    })
  }

  @Builder
  private settingsTab(): void {
    VaultSettingsPanel({
      faceEnabled: this.faceEnabled,
      faceAvailable: this.faceAvailable,
      fingerprintEnabled: this.fingerprintEnabled,
      fingerprintAvailable: this.fingerprintAvailable,
      gestureEnabled: this.gestureEnabled,
      preferredUnlockLabel: this.unlockModeLabel(this.preferredUnlock),
      autoLockLabel: this.autoLockLabel(),
      versionLabel: `${VERSION_NAME}（${VERSION_CODE}）`,
      buildLabel: BUILD_GIT_LABEL,
      onToggleFace: (): void => { this.toggleFace(); },
      onToggleFingerprint: (): void => { this.toggleFingerprint(); },
      onToggleGesture: (): void => {
        if (this.gestureEnabled) { this.disableGesture(); } else { this.beginGestureSetup(); }
      },
      onChoosePreferredUnlock: (): void => { this.choosePreferredUnlock(); },
      onChangePassword: (): void => { this.openChangePassword(); },
      onChooseAutoLock: (): void => { this.chooseAutoLockTime(); },
      onOpenGroupManager: (): void => { this.showGroupManager = true; },
      onCreateBackup: (): void => { this.openCreateBackup(); },
      onRestoreBackup: (): void => { this.openRestoreBackup(false); },
      onLockVault: (): void => { this.lockVault(); }
    })
  }

  @Builder
  private backupDialogOverlay(): void {
    VaultBackupDialog({
      password: $backupPassword,
      action: this.backupAction,
      stage: this.backupStage,
      busy: this.backupBusy,
      errorMessage: this.backupError,
      progressText: this.backupProgressText,
      progressValue: this.backupProgressValue,
      backupDateText: this.backupDateText,
      itemCount: this.backupItemCount,
      attachmentCount: this.backupAttachmentCount,
      attachmentSizeText: this.backupAttachmentSizeText,
      addedCount: this.backupAddedCount,
      updatedCount: this.backupUpdatedCount,
      retainedCount: this.backupRetainedCount,
      newerCount: this.backupNewerCount,
      conflictCount: this.backupConflictCount,
      unchangedCount: this.backupUnchangedCount,
      deletedCount: this.backupDeletedCount,
      onClose: (): void => { this.closeBackupDialog(); },
      onPrimary: (): void => { this.handleBackupPrimary(); }
    })
  }

  @Builder
  private bottomBar(): void {
    VaultBottomNavigation({
      activeTab: this.activeTab,
      onSelectTab: (index: number): void => {
        this.activeTab = index;
        if (index !== 2) {
          this.closeTrashManagement();
          this.showTrashMore = false;
        }
        if (index === 2) { this.refreshTrash(); }
        if (index === 3) { this.showGroupManager = false; }
      },
      onNewItem: (): void => { this.openNewItem(); }
    })
  }

  @Builder
  private vaultScreen(): void {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        if (this.activeTab === 0) {
          this.topBar()
        }
        Stack() {
          if (this.activeTab === 0) {
            this.homeTab()
          } else if (this.activeTab === 1) {
            this.categoryTab()
          } else if (this.activeTab === 2) {
            this.trashTab()
          } else {
            if (this.showGroupManager) {
              this.groupManagerTab()
            } else {
              this.settingsTab()
            }
          }
        }
        .layoutWeight(1)
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .backgroundColor(COLOR_BG)
      this.bottomBar()
      if (this.showNewItem) {
        this.newItemOverlay()
      }
      if (this.showNewGroup) {
        this.newGroupOverlay()
      }
      if (this.groupPendingRename) {
        this.renameGroupOverlay(this.groupPendingRename as VaultGroup)
      }
      if (this.groupPendingDelete) {
        this.deleteGroupOverlay(this.groupPendingDelete as VaultGroup)
      }
      if (this.selectedTrashEntry) {
        VaultTrashDetailDialog({
          entry: this.selectedTrashEntry as VaultTrashEntry,
          deletedTimeText: this.formatTrashTime((this.selectedTrashEntry as VaultTrashEntry).item.deletedAt),
          revealPassword: $revealTrashPassword,
          onClose: (): void => { this.closeTrashDetail(); },
          onRestore: (): void => { this.trashAction((this.selectedTrashEntry as VaultTrashEntry).item, false); },
          onPermanentlyDelete: (): void => {
            this.trashAction((this.selectedTrashEntry as VaultTrashEntry).item, true);
          },
          onCopyUsername: (username: string): void => { this.copyTrashUsername(username); },
          onPasswordVisibilityChange: (visible: boolean): void => {
            AbilityContextHolder.setPrivacyMode(visible);
          }
        })
      }
      if (this.selectedItem) {
        VaultItemDetailDialog({
          item: this.selectedItem as VaultItem,
          groups: this.groups,
          initialAttachmentIndex: this.selectedAttachmentIndex,
          title: $detailTitle,
          username: $detailUsername,
          password: $detailPassword,
          website: $detailWebsite,
          notes: $detailNotes,
          groupId: $detailGroupId,
          revealPassword: $revealPassword,
          onClose: (): void => { this.closeSelectedItem(); },
          onSave: (): void => { this.saveSelectedItem(); },
          onTrash: (): void => { this.trashSelectedItem(); },
          onPasswordVisibilityChange: (visible: boolean): void => {
            AbilityContextHolder.setPrivacyMode(visible);
          },
          onCopyLoginValue: (value: string, label: string): void => {
            this.copyLoginValue(value, label);
          },
          onOpenWebsite: (website: string): void => { this.openLoginWebsite(website); }
        })
      }
      if (this.showGestureSetup) {
        GestureSetupDialog({
          step: this.gestureSetupStep,
          hint: this.gestureSetupHint,
          onClose: (): void => { this.closeGestureSetup(); },
          onComplete: (pattern: number[]): void => { this.handleGestureSetup(pattern); }
        })
      }
      if (this.showChangePassword) {
        ChangePasswordDialog({
          currentPassword: $currentPassword,
          newPassword: $changedPassword,
          confirmPassword: $changedPasswordConfirm,
          busy: this.passwordChangeBusy,
          onClose: (): void => { this.closeChangePassword(); },
          onConfirm: (): void => { this.changePassword(); }
        })
      }
      if (this.showResetVault) {
        ResetVaultDialog({
          confirmation: $resetVaultConfirmText,
          busy: this.resetVaultBusy,
          onClose: (): void => { this.closeResetVault(); },
          onConfirm: (): void => { this.resetVault(); }
        })
      }
      if (this.showBackupDialog) {
        this.backupDialogOverlay()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private modalHeader(title: string, closeAction: () => void): void {
    VaultDialogHeader({ title: title, onClose: closeAction })
  }

  @Builder
  private typeChip(type: VaultItemType): void {
    Text(itemTypeLabel(type))
      .fontSize(12)
      .fontColor(this.newType === type ? COLOR_BG : COLOR_MUTED)
      .textAlign(TextAlign.Center)
      .maxLines(1)
      .padding({ top: 8, bottom: 8 })
      .backgroundColor(this.newType === type ? COLOR_PRIMARY : COLOR_SURFACE_2)
      .borderRadius(16)
      .layoutWeight(1)
      .focusable(false)
      .enabled(!this.savingNewItem)
      .onClick((): void => { this.requestSelectNewItemType(type); })
  }

  @Builder
  private selectedMediaPreview(): void {
    Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
      ForEach(this.pendingMedia, (media: PickedMedia, index: number): void => {
        Column({ space: 4 }) {
          Stack() {
            VaultThumbnail({
              itemId: '',
              mediaType: media.type,
              sourceUri: media.uri,
              thumbnailSize: 72
            })
            if (media.type === VaultItemType.Video) {
              Text('视频').fontSize(9).fontColor(COLOR_ON_DARK)
                .padding({ left: 5, right: 5, top: 2, bottom: 2 })
                .backgroundColor(COLOR_SCRIM).borderRadius(7)
                .position({ right: 5, bottom: 5 })
              }
            Text('×')
              .fontSize(17).fontWeight(FontWeight.Medium).fontColor(COLOR_ON_DARK)
              .textAlign(TextAlign.Center)
              .width(24).height(24).backgroundColor(COLOR_SCRIM_STRONG).borderRadius(12)
              .position({ right: 4, top: 4 }).zIndex(2)
              .hitTestBehavior(HitTestMode.Block)
              .enabled(!this.recognizingMedia && !this.savingNewItem)
              .opacity(this.recognizingMedia || this.savingNewItem ? 0.45 : 1)
              .onClick((): void => { this.removePendingMedia(index); })
          }
          .width(72).height(72)
          Text(`${index + 1}`)
            .fontSize(10).fontColor(COLOR_MUTED).textAlign(TextAlign.Center).width(72)
        }
        .margin({ right: 8, bottom: 8 })
        .padding(2)
        .borderRadius(13)
        .border({ width: index === this.selectedMediaPreviewIndex ? 2 : 0,
          color: index === this.selectedMediaPreviewIndex ? COLOR_PRIMARY : Color.Transparent })
        .onClick((): void => { this.selectPendingMedia(index); })
      }, (media: PickedMedia): string => media.uri)
    }
    .width('100%')
  }

  @Builder
  private pendingMediaOcrText(): void {
    if (this.selectedMediaPreviewIndex >= 0 && this.selectedMediaPreviewIndex < this.pendingMedia.length &&
      this.pendingMedia[this.selectedMediaPreviewIndex].type === VaultItemType.Image &&
      this.pendingMedia[this.selectedMediaPreviewIndex].ocrText.trim().length > 0) {
      Column({ space: 6 }) {
        Row({ space: 6 }) {
          Text('识别文字').fontSize(12).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT)
          Text('只读').fontSize(9).fontColor(COLOR_PRIMARY)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .backgroundColor(COLOR_PRIMARY_TINT).borderRadius(8)
        }.width('100%')
        Scroll() {
          Text(this.pendingMedia[this.selectedMediaPreviewIndex].ocrText)
            .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).lineHeight(19).width('100%')
            .textAlign(TextAlign.Start)
        }
        .width('100%')
        .constraintSize({ maxHeight: 108 })
        .scrollBar(BarState.Auto)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 11, right: 11, top: 9, bottom: 9 })
      .backgroundColor(COLOR_PRIMARY_WASH)
      .border({ width: { left: 3 }, color: COLOR_PRIMARY })
      .borderRadius(10)
    }
  }

  @Builder
  private selectedFilesPreview(): void {
    Column({ space: 0 }) {
      Row() {
        Text(`已选择 ${this.selectedFileCount} 个文件`)
          .fontSize(12).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT)
      }
      .width('100%')
      .height(34)
      .padding({ left: 11, right: 11 })
      Scroll() {
        Column({ space: 0 }) {
          ForEach(this.pendingFiles, (file: PickedMedia, index: number): void => {
            Row({ space: 9 }) {
              Stack({ alignContent: Alignment.Center }) {
                Text('▤').fontSize(17).fontColor(COLOR_PRIMARY)
              }
              .width(30).height(30).borderRadius(9).backgroundColor(COLOR_PRIMARY_TINT)
              Text(file.name)
                .fontSize(12).fontColor(COLOR_TEXT).maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
              Text('×')
                .fontSize(17).fontColor(COLOR_MUTED).textAlign(TextAlign.Center)
                .width(30).height(30).borderRadius(10).backgroundColor(COLOR_DIVIDER_SOFT)
                .enabled(!this.savingNewItem)
                .opacity(this.savingNewItem ? 0.45 : 1)
                .onClick((): void => { this.removePendingFile(index); })
            }
            .width('100%')
            .padding({ left: 9, right: 9, top: 7, bottom: 7 })
            if (index < this.pendingFiles.length - 1) {
              Divider().strokeWidth(1).color(COLOR_BORDER).margin({ left: 48 })
            }
          }, (file: PickedMedia, index: number): string => `${file.uri}-${index}`)
        }
        .width('100%')
      }
      .width('100%')
      .constraintSize({ maxHeight: 190 })
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .backgroundColor(COLOR_PRIMARY_WASH)
    .borderRadius(12)
  }

  @Builder
  private newItemOverlay(): void {
    Column() {
      Scroll() {
        Column({ space: 10 }) {
          this.modalHeader('新建资料', (): void => { this.requestCloseNewItem(); })
          Text('保存到分组').fontSize(12).fontColor(COLOR_MUTED).width('100%')
          Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
            ForEach(this.groups, (group: VaultGroup): void => {
              Text(group.name)
                .fontSize(12)
                .fontColor(this.newGroupId === group.id ? COLOR_BG : COLOR_MUTED)
                .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                .backgroundColor(this.newGroupId === group.id ? COLOR_PRIMARY : COLOR_SURFACE_2)
                .borderRadius(16)
                .margin({ right: 6, bottom: 6 })
                .onClick((): void => { this.newGroupId = group.id; })
            }, (group: VaultGroup): string => `${group.id}-${group.name}`)
          }
          .width('100%')
          Row({ space: 4 }) {
            this.typeChip(VaultItemType.Note)
            this.typeChip(VaultItemType.Login)
            this.typeChip(VaultItemType.Image)
            this.typeChip(VaultItemType.File)
          }
          .width('100%')
          TextInput({ placeholder: LABEL_NAME, text: this.newTitle })
            .id(this.newItemTitleInputId())
            .defaultFocus(true)
            .onAppear((): void => { this.requestNewItemTitleFocus(60); })
            .fontColor(COLOR_TEXT).placeholderColor(COLOR_PLACEHOLDER).backgroundColor(COLOR_SURFACE_2)
            .height(48).borderRadius(12)
            .onChange((value: string): void => { this.newTitle = value; })
          if (this.newType === VaultItemType.Login) {
            TextInput({ placeholder: '网站地址', text: this.newWebsite })
              .fontColor(COLOR_TEXT).placeholderColor(COLOR_PLACEHOLDER).backgroundColor(COLOR_SURFACE_2)
              .height(48).borderRadius(12)
              .onChange((value: string): void => { this.newWebsite = value; })
            VaultLoginFieldsEditor({
              username: $newUsername,
              password: $newPassword,
              revealPassword: $revealNewPassword,
              onPasswordVisibilityChange: (visible: boolean): void => {
                AbilityContextHolder.setPrivacyMode(visible);
              }
            })
          }
          if (this.newType === VaultItemType.Image) {
            Button('从系统相册添加')
              .width('100%').height(48).fontColor(COLOR_PRIMARY)
              .backgroundColor(COLOR_DARK_ACTION).borderRadius(12)
              .enabled(!this.recognizingMedia && !this.savingNewItem)
              .onClick((): void => { this.chooseMedia(); })
            if (this.selectedMediaCount > 0) {
              this.selectedMediaPreview()
              this.pendingMediaOcrText()
            }
            if (this.recognizingMedia) {
              Row({ space: 8 }) {
                LoadingProgress().width(18).height(18).color(COLOR_PRIMARY)
                Text(this.recognitionProgressText).fontSize(12).fontColor(COLOR_MUTED)
              }.width('100%')
            }
          } else if (this.newType === VaultItemType.File) {
            Button('从文件系统添加')
              .width('100%').height(48).fontColor(COLOR_PRIMARY)
              .backgroundColor(COLOR_DARK_ACTION).borderRadius(12)
              .enabled(!this.savingNewItem)
              .onClick((): void => { this.chooseMedia(true); })
            if (this.selectedFileCount > 0) {
              this.selectedFilesPreview()
            }
          }
          TextArea({ placeholder: this.newType === VaultItemType.Note ? LABEL_CONTENT : LABEL_NOTES, text: this.newNotes })
            .fontColor(COLOR_TEXT).placeholderColor(COLOR_PLACEHOLDER).backgroundColor(COLOR_SURFACE_2)
            .height(this.newType === VaultItemType.Login ? 46 : 92).borderRadius(12)
            .onChange((value: string): void => { this.newNotes = value; })
          if (this.savingNewItem) {
            Column({ space: 5 }) {
              Row() {
                Text(this.saveProgressText).fontSize(11).fontColor(COLOR_MUTED)
                Blank()
                Text(`${this.saveProgress}%`).fontSize(11).fontColor(COLOR_PRIMARY)
              }.width('100%')
              Progress({ value: this.saveProgress, total: 100, type: ProgressType.Linear })
                .width('100%').color(COLOR_PRIMARY).backgroundColor(COLOR_SURFACE_2)
            }.width('100%')
          }
          Button(this.savingNewItem ? '正在保存…' : (this.recognizingMedia ? '正在识别图片文字…' : ACTION_SAVE))
            .width('100%').height(50).fontWeight(FontWeight.Bold).fontColor(COLOR_BG)
            .backgroundColor(COLOR_PRIMARY).borderRadius(13)
            .enabled(!this.savingNewItem && !this.recognizingMedia)
            .onClick((): void => { this.createItem(); })
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 12, bottom: 16 })
      }
      .width('100%')
      .constraintSize({ minHeight: 420, maxHeight: '88%' })
      .backgroundColor(COLOR_SURFACE)
      .borderRadius({ bottomLeft: 24, bottomRight: 24 })
      Blank().onClick((): void => { this.requestCloseNewItem(); })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(COLOR_SCRIM)
  }

  @Builder
  private renameGroupOverlay(group: VaultGroup): void {
    Column() {
      Blank().onClick((): void => { this.closeRenameGroup(); })
      Column({ space: 10 }) {
        this.modalHeader('修改分组名称', (): void => { this.closeRenameGroup(); })
        TextInput({ placeholder: '分组名称', text: this.groupRenameName })
          .id('renameGroupInput')
          .defaultFocus(true)
          .fontColor(COLOR_TEXT).placeholderColor(COLOR_PLACEHOLDER).backgroundColor(COLOR_SURFACE_2)
          .height(50).borderRadius(12)
          .onChange((value: string): void => { this.groupRenameName = value; })
        Button('保存修改')
          .width('100%').height(50).fontWeight(FontWeight.Bold).fontColor(COLOR_BG)
          .backgroundColor(COLOR_PRIMARY).borderRadius(13)
          .onClick((): void => { this.renameGroup(group); })
      }
      .width('90%')
      .padding({ left: 20, right: 20, top: 12, bottom: 16 })
      .backgroundColor(COLOR_SURFACE)
      .borderRadius(24)
      Blank().onClick((): void => { this.closeRenameGroup(); })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(COLOR_SCRIM)
  }

  @Builder
  private deleteGroupOverlay(group: VaultGroup): void {
    Column() {
      Blank().onClick((): void => {
        this.groupPendingDelete = undefined;
        this.groupDeleteConfirmName = '';
      })
      Column({ space: 15 }) {
        this.modalHeader('⚠ 永久删除分组', (): void => {
          this.groupPendingDelete = undefined;
          this.groupDeleteConfirmName = '';
        })
        Column({ space: 6 }) {
          Text(`将删除“${group.name}”及其中 ${this.groupPendingDeleteCount} 条资料`)
            .fontSize(14).fontWeight(FontWeight.Bold).fontColor(COLOR_DANGER).width('100%')
          Text('分组中当前显示的资料和附件会永久删除。回收站资料会保留，恢复时将自动重建原分组。')
            .fontSize(13).fontColor(COLOR_DANGER).lineHeight(20).width('100%')
        }
        .width('100%').padding(12).backgroundColor(COLOR_DANGER_TINT).borderRadius(12)
        Text(`请输入分组名称“${group.name}”以确认删除`)
          .fontSize(12).fontColor(COLOR_DANGER).width('100%')
        TextInput({ placeholder: group.name, text: this.groupDeleteConfirmName })
          .fontColor(COLOR_TEXT).placeholderColor(COLOR_PLACEHOLDER_LIGHT).backgroundColor(COLOR_SURFACE_2)
          .height(50).borderRadius(12)
          .onChange((value: string): void => { this.groupDeleteConfirmName = value; })
        Button('永久删除分组及当前资料')
          .width('100%').height(50).fontWeight(FontWeight.Bold)
          .fontColor(this.groupDeleteConfirmName.trim() === group.name ? COLOR_ON_DARK : COLOR_MUTED)
          .backgroundColor(this.groupDeleteConfirmName.trim() === group.name ? COLOR_DANGER : COLOR_SURFACE_2)
          .borderRadius(13)
          .enabled(this.groupDeleteConfirmName.trim() === group.name)
          .onClick((): void => { this.confirmDeleteGroup(group); })
      }
      .width('100%').padding(20).backgroundColor(COLOR_SURFACE)
      .borderRadius({ topLeft: 24, topRight: 24 })
    }
    .width('100%').height('100%').backgroundColor(COLOR_SCRIM)
  }

  @Builder
  private newGroupOverlay(): void {
    Column() {
      Blank().onClick((): void => { this.closeNewGroup(); })
      Column({ space: 10 }) {
        this.modalHeader('新建分组', (): void => { this.closeNewGroup(); })
        TextInput({ placeholder: '分组名称', text: this.newGroupName })
          .id('newGroupInput')
          .defaultFocus(true)
          .fontColor(COLOR_TEXT).placeholderColor(COLOR_PLACEHOLDER).backgroundColor(COLOR_SURFACE_2)
          .height(50).borderRadius(12)
          .onChange((value: string): void => { this.newGroupName = value; })
        Button('创建分组')
          .width('100%').height(50).fontWeight(FontWeight.Bold).fontColor(COLOR_BG)
          .backgroundColor(COLOR_PRIMARY).borderRadius(13)
          .onClick((): void => { this.createGroup(); })
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 12, bottom: 16 })
      .backgroundColor(COLOR_SURFACE)
      .borderRadius(24)
      Blank().onClick((): void => { this.closeNewGroup(); })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(COLOR_SCRIM)
  }

  build() {
    if (this.screen === 'loading') {
      VaultLoadingScreen()
    } else if (this.screen === 'setup') {
      Stack() {
        VaultSetupScreen({
          masterPassword: $masterPassword,
          confirmPassword: $confirmPassword,
          busy: this.busy,
          errorMessage: this.errorMessage,
          onCreateVault: (): void => { this.createVault(); },
          onRestoreBackup: (): void => { this.openRestoreBackup(true); }
        })
        if (this.showBackupDialog) {
          this.backupDialogOverlay()
        }
      }.width('100%').height('100%')
    } else if (this.screen === 'locked') {
      Stack() {
        VaultLockedScreen({
          masterPassword: $masterPassword,
          unlockMode: this.unlockMode,
          busy: this.busy,
          errorMessage: this.errorMessage,
          faceEnabled: this.faceEnabled,
          fingerprintEnabled: this.fingerprintEnabled,
          gestureEnabled: this.gestureEnabled,
          onSelectMode: (mode: string): void => { this.selectUnlockMode(mode); },
          onUnlockPassword: (): void => { this.unlockVault(); },
          onUnlockFingerprint: (): void => { this.unlockWithFingerprint(); },
          onUnlockFace: (): void => { this.unlockWithFace(); },
          onUnlockGesture: (pattern: number[]): void => { this.unlockWithGesture(pattern); },
          onOpenRecovery: (): void => { this.openRecoveryCenter(); }
        })
        if (this.showRecoveryCenter) {
          RecoveryCenterDialog({
            newPassword: $recoveryNewPassword,
            confirmPassword: $recoveryPasswordConfirm,
            faceEnabled: this.faceEnabled,
            fingerprintEnabled: this.fingerprintEnabled,
            authenticated: this.recoveryAuthenticated,
            authLabel: this.recoveryAuthLabel,
            busy: this.recoveryBusy,
            onClose: (): void => { this.closeRecoveryCenter(); },
            onAuthenticateFace: (): void => { this.authenticateRecovery('face'); },
            onAuthenticateFingerprint: (): void => { this.authenticateRecovery('fingerprint'); },
            onResetPassword: (): void => { this.resetRecoveredPassword(); },
            onClearVault: (): void => { this.openResetVault(); }
          })
        }
        if (this.showResetVault) {
          ResetVaultDialog({
            confirmation: $resetVaultConfirmText,
            busy: this.resetVaultBusy,
            onClose: (): void => { this.closeResetVault(); },
            onConfirm: (): void => { this.resetVault(); }
          })
        }
      }.width('100%').height('100%')
    } else {
      this.vaultScreen()
    }
  }
}
