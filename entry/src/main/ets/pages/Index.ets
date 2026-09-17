import promptAction from '@ohos.promptAction';
import { BusinessError } from '@ohos.base';
import { GestureGrid } from '../components/GestureGrid';
import { VaultMedia } from '../components/VaultMedia';
import { AbilityContextHolder } from '../services/AbilityContextHolder';
import { QuickUnlockStatus, VaultSecurityService } from '../services/VaultSecurityService';
import { mediaPickerService } from '../services/MediaPickerService';
import { vaultRepository } from '../services/VaultRepository';
import {
  itemTypeGlyph,
  itemTypeLabel,
  VaultGroup,
  VaultItem,
  VaultItemInput,
  VaultItemType
} from '../models/VaultModels';

const COLOR_BG: string = '#F5F6FA';
const COLOR_SURFACE: string = '#FFFFFF';
const COLOR_SURFACE_2: string = '#F0F2F6';
const COLOR_PRIMARY: string = '#24B88A';
const COLOR_TEXT: string = '#172033';
const COLOR_MUTED: string = '#7D8696';
const COLOR_BORDER: string = '#E6E9EF';
const COLOR_DANGER: string = '#E75561';

@Entry
@Component
struct Index {
  @StorageLink('vaultLockedByLifecycle') @Watch('handleLifecycleLock')
  private lifecycleLocked: boolean = false;
  @State private screen: string = 'loading';
  @State private activeTab: number = 0;
  @State private masterPassword: string = '';
  @State private confirmPassword: string = '';
  @State private busy: boolean = false;
  @State private errorMessage: string = '';
  @State private groups: VaultGroup[] = [];
  @State private items: VaultItem[] = [];
  @State private allItems: VaultItem[] = [];
  @State private loginCount: number = 0;
  @State private noteCount: number = 0;
  @State private mediaCount: number = 0;
  @State private fileCount: number = 0;
  @State private searchText: string = '';
  @State private searchActive: boolean = false;
  @State private showNewItem: boolean = false;
  @State private showNewGroup: boolean = false;
  @State private expandedGroupId: number = -1;
  @State private selectedCategoryType: VaultItemType = VaultItemType.Login;
  @State private showCategoryItems: boolean = false;
  @State private showGestureSetup: boolean = false;
  @State private gestureSetupStep: number = 1;
  @State private gestureSetupHint: string = '绘制新手势';
  @State private gestureEnabled: boolean = false;
  @State private fingerprintEnabled: boolean = false;
  @State private fingerprintAvailable: boolean = false;
  @State private unlockMode: string = 'password';
  @State private gestureFailures: number = 0;
  @State private gestureCooldownUntil: number = 0;
  @State private trashItems: VaultItem[] = [];
  @State private selectedItem?: VaultItem = undefined;
  @State private revealPassword: boolean = false;
  @State private newType: VaultItemType = VaultItemType.Login;
  @State private newTitle: string = '';
  @State private newUsername: string = '';
  @State private newPassword: string = '';
  @State private revealNewPassword: boolean = false;
  @State private newNotes: string = '';
  @State private newAttachmentUri: string = '';
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
  @State private detailNotes: string = '';
  private pendingAttachment: Uint8Array = new Uint8Array(0);
  private sessionKey: Uint8Array = new Uint8Array(0);
  private firstGesture: number[] = [];

  aboutToAppear(): void {
    this.initialize();
  }

  private async initialize(): Promise<void> {
    try {
      const security = new VaultSecurityService(AbilityContextHolder.getContext());
      const initialized = await security.isInitialized();
      if (initialized) {
        await this.refreshQuickUnlockStatus();
        this.unlockMode = this.preferredUnlockMode();
      }
      this.screen = initialized ? 'locked' : 'setup';
      if (initialized && this.unlockMode === 'fingerprint') {
        this.unlockWithFingerprint();
      }
    } catch (error) {
      this.errorMessage = this.describeError(error);
      this.screen = 'setup';
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
    this.errorMessage = '';
    if (this.masterPassword.length < 8) {
      this.errorMessage = '主密码至少需要 8 个字符';
      return;
    }
    if (this.masterPassword !== this.confirmPassword) {
      this.errorMessage = '两次输入的密码不一致';
      return;
    }
    this.busy = true;
    try {
      const security = new VaultSecurityService(AbilityContextHolder.getContext());
      const key = await security.createMasterPassword(this.masterPassword);
      await this.openWithKey(key);
      this.masterPassword = '';
      this.confirmPassword = '';
      await this.reloadVault();
      this.showVaultScreen();
    } catch (error) {
      this.errorMessage = this.describeError(error);
    } finally {
      this.busy = false;
    }
  }

  private async unlockVault(): Promise<void> {
    this.errorMessage = '';
    if (this.masterPassword.length === 0) {
      this.errorMessage = '请输入主密码';
      return;
    }
    this.busy = true;
    try {
      const security = new VaultSecurityService(AbilityContextHolder.getContext());
      const key = await security.unlock(this.masterPassword);
      if (!key) {
        this.errorMessage = '主密码不正确';
        return;
      }
      await this.openWithKey(key);
      this.masterPassword = '';
      await this.reloadVault();
      this.showVaultScreen();
    } catch (error) {
      this.errorMessage = this.describeError(error);
    } finally {
      this.busy = false;
    }
  }

  private async lockVault(): Promise<void> {
    AbilityContextHolder.setPrivacyMode(true);
    this.trashItems = [];
    this.activeTab = 0;
    this.searchText = '';
    this.searchActive = false;
    this.expandedGroupId = -1;
    this.showCategoryItems = false;
    this.masterPassword = '';
    this.confirmPassword = '';
    this.detailPassword = '';
    this.detailUsername = '';
    this.detailNotes = '';
    this.detailTitle = '';
    this.resetNewItem();
    this.selectedItem = undefined;
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
    this.groups = [];
    this.sessionKey.fill(0);
    this.sessionKey = new Uint8Array(0);
    await vaultRepository.close();
    await this.refreshQuickUnlockStatus();
    this.unlockMode = this.preferredUnlockMode();
    this.screen = 'locked';
    if (this.unlockMode === 'fingerprint') {
      this.unlockWithFingerprint();
    }
  }

  private async openWithKey(key: Uint8Array): Promise<void> {
    this.sessionKey.fill(0);
    this.sessionKey = key.slice();
    try {
      await vaultRepository.open(AbilityContextHolder.getContext(), key);
    } catch (error) {
      this.sessionKey.fill(0);
      this.sessionKey = new Uint8Array(0);
      throw new Error(this.describeError(error));
    }
  }

  private showVaultScreen(): void {
    this.screen = 'vault';
    AbilityContextHolder.setPrivacyMode(false);
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

  private openNewItem(type: VaultItemType = VaultItemType.Login, groupId: number = 0): void {
    this.newType = type;
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

  private selectNewItemType(type: VaultItemType): void {
    try {
      this.getUIContext().getFocusController().requestFocus(this.newItemTitleInputId());
    } catch (error) {
      // The title input may still be mounting during the first interaction.
    }
    this.newType = type;
    if (type !== VaultItemType.Login && this.revealNewPassword) {
      this.revealNewPassword = false;
      AbilityContextHolder.setPrivacyMode(false);
    }
    this.requestNewItemTitleFocus(120);
  }

  private toggleNewPasswordVisibility(): void {
    this.revealNewPassword = !this.revealNewPassword;
    AbilityContextHolder.setPrivacyMode(this.revealNewPassword);
  }

  private closeSelectedItem(): void {
    this.selectedItem = undefined;
    this.detailPassword = '';
    this.revealPassword = false;
    AbilityContextHolder.setPrivacyMode(false);
  }

  private toggleDetailPasswordVisibility(): void {
    this.revealPassword = !this.revealPassword;
    AbilityContextHolder.setPrivacyMode(this.revealPassword);
  }

  private closeGestureSetup(): void {
    this.showGestureSetup = false;
    this.firstGesture = [];
    AbilityContextHolder.setPrivacyMode(false);
  }

  private async refreshQuickUnlockStatus(): Promise<void> {
    const security = new VaultSecurityService(AbilityContextHolder.getContext());
    const status: QuickUnlockStatus = await security.getQuickUnlockStatus();
    this.gestureEnabled = status.gestureEnabled;
    this.fingerprintEnabled = status.fingerprintEnabled;
    this.fingerprintAvailable = status.fingerprintAvailable;
  }

  private preferredUnlockMode(): string {
    if (this.fingerprintEnabled) {
      return 'fingerprint';
    }
    return this.gestureEnabled ? 'gesture' : 'password';
  }

  private selectUnlockMode(mode: string): void {
    if (this.busy || this.unlockMode === mode) {
      return;
    }
    this.errorMessage = '';
    this.unlockMode = mode;
    if (mode === 'fingerprint') {
      this.unlockWithFingerprint();
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
    AbilityContextHolder.setPrivacyMode(true);
  }

  private async handleGestureSetup(pattern: number[]): Promise<void> {
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
      const security = new VaultSecurityService(AbilityContextHolder.getContext());
      await security.enableGesture(pattern, this.sessionKey);
      await this.refreshQuickUnlockStatus();
      this.closeGestureSetup();
      promptAction.showToast({ message: '手势登录已启用' });
    } catch (error) {
      this.gestureSetupHint = this.describeError(error);
    }
  }

  private async unlockWithGesture(pattern: number[]): Promise<void> {
    if (Date.now() < this.gestureCooldownUntil) {
      this.errorMessage = '尝试次数过多，请稍后使用主密码';
      return;
    }
    this.busy = true;
    this.errorMessage = '';
    try {
      const security = new VaultSecurityService(AbilityContextHolder.getContext());
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
      await this.reloadVault();
      this.showVaultScreen();
    } catch (error) {
      this.errorMessage = this.describeError(error);
    } finally {
      this.busy = false;
    }
  }

  private async unlockWithFingerprint(): Promise<void> {
    this.busy = true;
    this.errorMessage = '';
    try {
      const security = new VaultSecurityService(AbilityContextHolder.getContext());
      const key = await security.unlockWithFingerprint();
      await this.openWithKey(key);
      await this.reloadVault();
      this.showVaultScreen();
    } catch (error) {
      this.errorMessage = this.describeError(error);
    } finally {
      this.busy = false;
    }
  }

  private async toggleFingerprint(): Promise<void> {
    try {
      const security = new VaultSecurityService(AbilityContextHolder.getContext());
      if (this.fingerprintEnabled) {
        await security.disableFingerprint();
        promptAction.showToast({ message: '指纹登录已关闭' });
      } else {
        await security.enableFingerprint(this.sessionKey);
        promptAction.showToast({ message: '指纹登录已启用' });
      }
      await this.refreshQuickUnlockStatus();
    } catch (error) {
      promptAction.showToast({ message: this.describeError(error) });
    }
  }

  private async disableGesture(): Promise<void> {
    const security = new VaultSecurityService(AbilityContextHolder.getContext());
    await security.disableGesture();
    await this.refreshQuickUnlockStatus();
    promptAction.showToast({ message: '手势登录已关闭' });
  }

  private async reloadVault(): Promise<void> {
    this.groups = await vaultRepository.listGroups();
    this.allItems = await vaultRepository.listItems();
    this.loginCount = this.allItems.filter((item: VaultItem): boolean => item.type === VaultItemType.Login).length;
    this.noteCount = this.allItems.filter((item: VaultItem): boolean => item.type === VaultItemType.Note).length;
    this.mediaCount = this.allItems.filter((item: VaultItem): boolean => item.type === VaultItemType.Image || item.type === VaultItemType.Video).length;
    this.fileCount = this.allItems.filter((item: VaultItem): boolean => item.type === VaultItemType.File).length;
    if (this.groups.length > 0 && this.newGroupId === 0) {
      this.newGroupId = this.groups[0].id;
    }
    this.items = await vaultRepository.listItems(this.searchText, -1);
  }

  private async refreshTrash(): Promise<void> {
    this.trashItems = (await vaultRepository.listItems('', -1, true)).filter((item: VaultItem): boolean => item.deletedAt > 0);
  }

  private async trashAction(item: VaultItem, permanent: boolean): Promise<void> {
    try {
      if (permanent) {
        const choice = await promptAction.showDialog({ title: '永久删除此资料？', message: '删除后无法恢复。',
          buttons: [{ text: '取消', color: COLOR_MUTED }, { text: '永久删除', color: COLOR_DANGER }] });
        if (choice.index !== 1) { return; }
        await vaultRepository.permanentlyDelete(item.id);
      } else { await vaultRepository.restoreFromTrash(item.id); }
      await this.refreshTrash();
      await this.reloadVault();
    } catch (error) { promptAction.showToast({ message: this.describeError(error) }); }
  }

  private async applySearch(text: string): Promise<void> {
    this.searchText = text;
    this.activeTab = 0;
    this.items = await vaultRepository.listItems(text, -1);
  }

  private async createGroup(): Promise<void> {
    try {
      await vaultRepository.createGroup(this.newGroupName, COLOR_PRIMARY);
      this.newGroupName = '';
      this.showNewGroup = false;
      await this.reloadVault();
      promptAction.showToast({ message: '分组已创建' });
    } catch (error) {
      promptAction.showToast({ message: this.describeError(error) });
    }
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
    const name = this.groupRenameName.trim();
    if (name.length === 0) {
      promptAction.showToast({ message: '分组名称不能为空' });
      return;
    }
    try {
      await vaultRepository.updateGroup(group.id, name, group.color);
      this.closeRenameGroup();
      await this.reloadVault();
      promptAction.showToast({ message: '分组名称已修改' });
    } catch (error) {
      promptAction.showToast({ message: this.describeError(error) });
    }
  }

  private async requestDeleteGroup(group: VaultGroup): Promise<void> {
    try {
      const groupItems = await vaultRepository.listItems('', group.id, true);
      if (groupItems.length > 0) {
        this.groupPendingDelete = group;
        this.groupPendingDeleteCount = groupItems.length;
        this.groupDeleteConfirmName = '';
        return;
      }
      const choice = await promptAction.showDialog({
        title: `删除“${group.name}”？`,
        message: '这是一个空分组，删除后无法恢复。',
        buttons: [{ text: '取消', color: COLOR_MUTED }, { text: '删除', color: COLOR_DANGER }]
      });
      if (choice.index === 1) {
        await this.deleteGroup(group);
      }
    } catch (error) {
      promptAction.showToast({ message: this.describeError(error) });
    }
  }

  private async confirmDeleteGroup(group: VaultGroup): Promise<void> {
    if (this.groupDeleteConfirmName.trim() !== group.name) {
      promptAction.showToast({ message: '输入的分组名称不一致' });
      return;
    }
    await this.deleteGroup(group);
  }

  private async deleteGroup(group: VaultGroup): Promise<void> {
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
      await this.reloadVault();
      promptAction.showToast({ message: hadItems ? '分组已删除，原有资料已移至未分组' : '分组已删除' });
    } catch (error) {
      promptAction.showToast({ message: this.describeError(error) });
    }
  }

  private async chooseMedia(fromFile: boolean = false): Promise<void> {
    try {
      const media = fromFile || this.newType === VaultItemType.File ?
        await mediaPickerService.pickFile(this.newType) : await mediaPickerService.pickOne(this.newType);
      if (!media) {
        return;
      }
      if (this.screen !== 'vault') { media.data.fill(0); return; }
      this.newAttachmentUri = media.uri;
      this.pendingAttachment = media.data;
      this.newType = media.type;
      if (this.newTitle.length === 0) {
        this.newTitle = media.name;
      }
    } catch (error) {
      promptAction.showToast({ message: this.describeError(error) });
    }
  }

  private async createItem(): Promise<void> {
    try {
      const input: VaultItemInput = {
        type: this.newType,
        groupId: this.newGroupId,
        title: this.newTitle,
        username: this.newUsername,
        password: this.newPassword,
        notes: this.newNotes,
        attachmentUri: this.newAttachmentUri,
        attachmentData: this.pendingAttachment
      };
      await vaultRepository.createItem(input);
      this.resetNewItem();
      this.closeNewItem();
      await this.reloadVault();
      promptAction.showToast({ message: '资料已保存' });
    } catch (error) {
      promptAction.showToast({ message: this.describeError(error) });
    }
  }

  private openItem(item: VaultItem): void {
    this.selectedItem = item;
    this.detailTitle = item.title;
    this.detailUsername = item.username;
    this.detailPassword = item.password;
    this.detailNotes = item.notes;
    this.revealPassword = false;
    AbilityContextHolder.setPrivacyMode(item.type !== VaultItemType.Login);
  }

  private async saveSelectedItem(): Promise<void> {
    const item = this.selectedItem;
    if (!item) {
      return;
    }
    const updated: VaultItem = {
      id: item.id,
      type: item.type,
      groupId: item.groupId,
      title: this.detailTitle,
      username: this.detailUsername,
      password: this.detailPassword,
      notes: this.detailNotes,
      attachmentUri: item.attachmentUri,
      ocrText: item.ocrText,
      createdAt: item.createdAt,
      updatedAt: Date.now(),
      deletedAt: item.deletedAt
    };
    try {
      await vaultRepository.updateItem(updated);
      this.closeSelectedItem();
      await this.reloadVault();
      promptAction.showToast({ message: '修改已保存，旧版本已归档' });
    } catch (error) {
      promptAction.showToast({ message: this.describeError(error) });
    }
  }

  private async trashSelectedItem(): Promise<void> {
    const item = this.selectedItem;
    if (!item) {
      return;
    }
    await vaultRepository.moveToTrash(item.id);
    this.closeSelectedItem();
    await this.reloadVault();
    promptAction.showToast({ message: '资料已移入回收站' });
  }

  private async downloadAttachment(item: VaultItem): Promise<void> {
    let data = new Uint8Array(0);
    try {
      data = await vaultRepository.readAttachment(item.id);
      if (data.length === 0) { throw new Error('此资料没有可导出的附件'); }
      const fileName = mediaPickerService.downloadName(item.title, item.attachmentUri, item.type);
      const saved = await mediaPickerService.saveCopy(data, fileName);
      if (saved) { promptAction.showToast({ message: '已导出解密副本' }); }
    } catch (error) {
      promptAction.showToast({ message: this.describeError(error) });
    } finally {
      data.fill(0);
    }
  }

  private resetNewItem(): void {
    this.newType = VaultItemType.Login;
    this.newTitle = '';
    this.newUsername = '';
    this.newPassword = '';
    this.revealNewPassword = false;
    this.newNotes = '';
    this.newAttachmentUri = '';
    this.pendingAttachment.fill(0);
    this.pendingAttachment = new Uint8Array(0);
  }

  private describeError(error: Object): string {
    if (error instanceof Error) {
      return error.message;
    }
    const businessError = error as BusinessError;
    if (businessError.message) {
      return businessError.code ? `${businessError.message}（${businessError.code}）` : businessError.message;
    }
    return `${error}`;
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

  private countType(type: VaultItemType): number {
    return this.allItems.filter((item: VaultItem): boolean => item.type === type).length;
  }

  private itemsInGroup(groupId: number): VaultItem[] {
    return this.allItems.filter((item: VaultItem): boolean => item.groupId === groupId);
  }

  private itemsInGroupByType(groupId: number, type: VaultItemType): VaultItem[] {
    return this.allItems.filter((item: VaultItem): boolean => item.groupId === groupId && item.type === type);
  }

  private countGroupByType(groupId: number, type: VaultItemType): number {
    return this.itemsInGroupByType(groupId, type).length;
  }

  private typeColor(type: VaultItemType): string {
    switch (type) {
      case VaultItemType.Login:
        return '#24B88A';
      case VaultItemType.Note:
        return '#E6A627';
      case VaultItemType.Image:
        return '#5078E8';
      case VaultItemType.Video:
        return '#8B62D9';
      case VaultItemType.File:
        return '#E3655B';
      default:
        return '#5794C8';
    }
  }

  private typeBackground(type: VaultItemType): string {
    switch (type) {
      case VaultItemType.Login:
        return '#E6F7F1';
      case VaultItemType.Note:
        return '#FFF5DC';
      case VaultItemType.Image:
        return '#EAF0FF';
      case VaultItemType.Video:
        return '#F2EBFF';
      case VaultItemType.File:
        return '#FDECEA';
      default:
        return '#EAF4FB';
    }
  }

  @Builder
  private brandMark(size: number = 54): void {
    Stack() {
      Text('◆')
        .fontSize(size * 0.36)
        .fontColor(COLOR_BG)
    }
    .width(size)
    .height(size)
    .borderRadius(size * 0.3)
    .backgroundColor(COLOR_PRIMARY)
  }

  @Builder
  private loadingScreen(): void {
    Column({ space: 18 }) {
      this.brandMark(66)
      Text('正在开启掌心密匣')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(COLOR_TEXT)
      LoadingProgress()
        .width(30)
        .height(30)
        .color(COLOR_PRIMARY)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(COLOR_BG)
  }

  @Builder
  private setupScreen(): void {
    Scroll() {
      Column({ space: 22 }) {
        Row() {
          this.brandMark(58)
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)

        Column({ space: 7 }) {
          Text('创建你的本地保险库')
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLOR_TEXT)
          Text('主密码不会离开这台设备，也无法由我们找回。')
            .fontSize(14)
            .fontColor(COLOR_MUTED)
            .textAlign(TextAlign.Center)
        }

        Column({ space: 14 }) {
          TextInput({ placeholder: '至少 8 个字符', text: this.masterPassword })
            .type(InputType.Password)
            .height(52)
            .fontColor(COLOR_TEXT)
            .placeholderColor('#607B72')
            .backgroundColor(COLOR_SURFACE_2)
            .borderRadius(14)
            .onChange((value: string): void => { this.masterPassword = value; })
          TextInput({ placeholder: '再次输入主密码', text: this.confirmPassword })
            .type(InputType.Password)
            .height(52)
            .fontColor(COLOR_TEXT)
            .placeholderColor('#607B72')
            .backgroundColor(COLOR_SURFACE_2)
            .borderRadius(14)
            .onChange((value: string): void => { this.confirmPassword = value; })
          if (this.errorMessage.length > 0) {
            Text(this.errorMessage)
              .fontSize(13)
              .fontColor(COLOR_DANGER)
              .width('100%')
          }
          Button(this.busy ? '正在创建…' : '创建本地保险库')
            .width('100%')
            .height(52)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLOR_BG)
            .backgroundColor(COLOR_PRIMARY)
            .borderRadius(14)
            .enabled(!this.busy)
            .onClick((): void => { this.createVault(); })
        }
        .padding(20)
        .width('100%')
        .backgroundColor(COLOR_SURFACE)
        .borderRadius(22)
        .border({ width: 1, color: COLOR_BORDER })

        Row({ space: 9 }) {
          Text('✓').fontColor(COLOR_PRIMARY)
          Text('登录验证 · 明文本机存储（开发模式）')
            .fontSize(12)
            .fontColor(COLOR_MUTED)
        }
      }
      .width('100%')
      .padding({ left: 24, right: 24, top: 70, bottom: 40 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(COLOR_BG)
  }

  @Builder
  private unlockModeButton(mode: string, label: string): void {
    Button(label)
      .layoutWeight(1)
      .height(40)
      .fontSize(13)
      .fontWeight(this.unlockMode === mode ? FontWeight.Bold : FontWeight.Regular)
      .fontColor(this.unlockMode === mode ? COLOR_BG : COLOR_MUTED)
      .backgroundColor(this.unlockMode === mode ? COLOR_PRIMARY : Color.Transparent)
      .borderRadius(12)
      .enabled(!this.busy)
      .onClick((): void => { this.selectUnlockMode(mode); })
  }

  @Builder
  private lockedScreen(): void {
    Scroll() {
      Column({ space: 18 }) {
        this.brandMark(66)
        Column({ space: 7 }) {
          Text('掌心密匣已锁定')
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLOR_TEXT)
          Text(this.unlockMode === 'gesture' ? '绘制手势解锁本地保险库' :
            (this.unlockMode === 'fingerprint' ? '使用指纹验证身份' : '输入主密码解锁本地保险库'))
            .fontSize(14)
            .fontColor(COLOR_MUTED)
        }
        Column({ space: 12 }) {
          Row({ space: 4 }) {
            if (this.fingerprintEnabled) {
              this.unlockModeButton('fingerprint', '指纹')
            }
            this.unlockModeButton('password', '密码')
            if (this.gestureEnabled) {
              this.unlockModeButton('gesture', '手势')
            }
          }
          .width('100%')
          .padding(4)
          .backgroundColor(COLOR_SURFACE_2)
          .borderRadius(14)

          if (this.unlockMode === 'gesture' && this.gestureEnabled) {
            GestureGrid({
              hint: this.busy ? '正在验证…' : '从任意点开始滑动',
              disabled: this.busy,
              onComplete: (pattern: number[]): void => { this.unlockWithGesture(pattern); }
            })
          } else if (this.unlockMode === 'fingerprint' && this.fingerprintEnabled) {
            Column({ space: 14 }) {
              Text('◎')
                .fontSize(58)
                .fontColor(COLOR_PRIMARY)
              Text(this.busy ? '正在验证指纹…' : '触碰指纹传感器完成验证')
                .fontSize(14)
                .fontColor(COLOR_MUTED)
              Button(this.busy ? '正在验证…' : '验证指纹')
                .width('100%')
                .height(52)
                .fontWeight(FontWeight.Bold)
                .fontColor(COLOR_BG)
                .backgroundColor(COLOR_PRIMARY)
                .borderRadius(14)
                .enabled(!this.busy)
                .onClick((): void => { this.unlockWithFingerprint(); })
            }
            .width('100%')
            .padding({ top: 18, bottom: 8 })
          } else {
            TextInput({ placeholder: '主密码', text: this.masterPassword })
              .type(InputType.Password)
              .height(52)
              .fontColor(COLOR_TEXT)
              .placeholderColor('#607B72')
              .backgroundColor(COLOR_SURFACE_2)
              .borderRadius(14)
              .onChange((value: string): void => { this.masterPassword = value; })
              .onSubmit((): void => { this.unlockVault(); })
            Button(this.busy ? '正在验证…' : '使用主密码解锁')
              .width('100%')
              .height(52)
              .fontWeight(FontWeight.Bold)
              .fontColor(COLOR_BG)
              .backgroundColor(COLOR_PRIMARY)
              .borderRadius(14)
              .enabled(!this.busy)
              .onClick((): void => { this.unlockVault(); })
          }
        if (this.errorMessage.length > 0) {
          Text(this.errorMessage)
            .fontSize(13)
            .fontColor(COLOR_DANGER)
            .width('100%')
        }
        }
        .width('100%')
        .padding(16)
      }
      .width('100%')
      .padding({ left: 24, right: 24, top: 48, bottom: 36 })
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(COLOR_BG)
  }

  @Builder
  private topBar(): void {
    Row({ space: 12 }) {
      Row({ space: 10 }) {
        Text('⌕').fontSize(21).fontColor(COLOR_MUTED)
        if (this.searchActive) {
          TextInput({ placeholder: '搜索账号、笔记、图片文字…', text: this.searchText })
            .id('homeSearchInput')
            .layoutWeight(1)
            .height(40)
            .defaultFocus(true)
            .fontSize(14)
            .fontColor(COLOR_TEXT)
            .placeholderColor('#9AA2B1')
            .backgroundColor(Color.Transparent)
            .onChange((value: string): void => { this.applySearch(value); })
        } else {
          Text(this.searchText.length > 0 ? this.searchText : '搜索账号、笔记、图片文字…')
            .layoutWeight(1)
            .fontSize(14)
            .fontColor(this.searchText.length > 0 ? COLOR_TEXT : '#9AA2B1')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .height(44)
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
  private itemRow(item: VaultItem): void {
    Row({ space: 8 }) {
      Column({ space: 0 }) {
        Text(item.title)
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
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Text('›').fontSize(20).fontColor('#B2B8C2')
    }
    .width('100%')
    .height(42)
    .padding({ left: 12, right: 10 })
    .backgroundColor(COLOR_SURFACE)
    .borderRadius(15)
    .onClick((): void => { this.openItem(item); })
  }

  @Builder
  private emptyState(title: string, description: string): void {
    Column({ space: 9 }) {
      Text('◇').fontSize(32).fontColor('#A7AFBC')
      Text(title).fontSize(16).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT)
      Text(description).fontSize(13).fontColor(COLOR_MUTED).textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding({ top: 48, bottom: 48 })
  }

  @Builder
  private homeTab(): void {
    Scroll() {
      Column({ space: 12 }) {
        Column({ space: 10 }) {
          Row() {
            Column({ space: 5 }) {
              Text('安全存储')
                .fontSize(22).fontWeight(FontWeight.Bold).fontColor('#F4CA62')
              Text('所有资料只会存储在本地')
                .fontSize(13).fontColor('#AAB5C8')
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Column({ space: 2 }) {
              Text(`${this.allItems.length}`)
                .fontSize(28).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
              Text('条资料').fontSize(11).fontColor('#AAB5C8')
            }
          }
          .width('100%')
          Row({ space: 6 }) {
            this.summaryPill('账号', this.loginCount)
            this.summaryPill('笔记', this.noteCount)
            this.summaryPill('媒体', this.mediaCount)
            this.summaryPill('文件', this.fileCount)
          }
          .width('100%')
        }
        .width('100%')
        .padding({ left: 15, right: 15, top: 13, bottom: 13 })
        .backgroundColor('#17243A')
        .borderRadius(18)

        Row() {
          Column({ space: 3 }) {
            Text(this.searchText.length > 0 ? '搜索结果' : '我的分组')
              .fontSize(20).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT)
            if (this.searchText.length > 0) {
              Text(`找到 ${this.items.length} 条资料`)
                .fontSize(12).fontColor(COLOR_MUTED)
            }
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          if (this.searchText.length === 0) {
            Button('+ 新建分组')
              .height(38).fontSize(13).fontColor(COLOR_PRIMARY)
              .backgroundColor('#E5F6F0').borderRadius(12)
              .onClick((): void => { this.showNewGroup = true; })
          }
        }
        .width('100%')

        if (this.searchText.length > 0) {
          Column({ space: 7 }) {
            if (this.items.length === 0) {
              this.emptyState('没有找到资料', '换个关键词搜索标题、内容或图片文字')
            } else {
              ForEach(this.items, (item: VaultItem): void => {
                this.itemRow(item)
              }, (item: VaultItem): string => `${item.id}-${item.updatedAt}`)
            }
          }
          .width('100%')
        } else if (this.groups.length === 0 && this.countGroup(0) === 0) {
          this.emptyState('还没有分组', '创建分组后，即可分类保存各种资料')
        } else {
          Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
            ForEach(this.groups, (group: VaultGroup, index: number): void => {
              this.groupSection(group,
                this.countGroup(0) === 0 && this.groups.length % 2 === 1 && index === this.groups.length - 1)
            }, (group: VaultGroup): string => `${group.id}`)
            if (this.countGroup(0) > 0) {
              this.ungroupedSection((this.groups.length + 1) % 2 === 1)
            }
          }
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
  private summaryPill(label: string, count: number): void {
    Text(`${label} ${count}`)
      .fontSize(11).fontColor('#CFD6E2')
      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
      .backgroundColor('#28364D')
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
    .backgroundColor('#F5FBF9')
    .border({ width: { top: 1 }, color: COLOR_BORDER })
    .onClick((): void => {
      this.expandedGroupId = this.expandedGroupId === groupId ? -1 : groupId;
    })
  }

  @Builder
  private groupSection(group: VaultGroup, fullWidth: boolean): void {
    Column() {
      Row({ space: 8 }) {
        Row({ space: 5 }) {
          Column({ space: 2 }) {
            Text(group.name)
              .fontSize(15).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
            Text(`${this.countGroup(group.id)} 条资料`).fontSize(11).fontColor(COLOR_MUTED)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .layoutWeight(1)
        .onClick((): void => {
          if (this.countGroup(group.id) > 3) {
            this.expandedGroupId = this.expandedGroupId === group.id ? -1 : group.id;
          }
        })
        Stack() {
          Text('+').fontSize(22).fontColor(COLOR_PRIMARY)
        }
          .width(34).height(34).borderRadius(11).backgroundColor('#E8F7F2')
          .onClick((): void => {
            this.openNewItem(VaultItemType.Login, group.id);
          })
      }
      .width('100%')
      .padding({ left: 12, right: 10, top: 8, bottom: 7 })
      if (this.countGroup(group.id) === 0) {
        Text('暂无资料，点击添加')
          .fontSize(11).fontColor(COLOR_MUTED).maxLines(1)
          .width('100%').padding({ left: 12, right: 12, top: 10, bottom: 12 })
          .border({ width: { top: 1 }, color: COLOR_BORDER })
      } else {
        Column({ space: 0 }) {
          ForEach(this.expandedGroupId === group.id ? this.itemsInGroup(group.id) :
            this.itemsInGroup(group.id).slice(0, 3), (item: VaultItem): void => {
            this.itemRow(item)
          }, (item: VaultItem): string => `${item.id}-${item.updatedAt}`)
        }
        .width('100%')
        .padding({ left: 3, right: 3, bottom: 3 })
        .border({ width: { top: 1 }, color: COLOR_BORDER })
        if (this.countGroup(group.id) > 3) {
          this.moreItemsRow(group.id, this.countGroup(group.id))
        }
      }
    }
    .width(fullWidth ? '100%' : '48.5%')
    .margin({ bottom: 12 })
    .backgroundColor(COLOR_SURFACE)
    .borderRadius(18)
    .border({ width: 1, color: COLOR_BORDER })
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
        if (this.countGroup(0) > 3) {
          this.expandedGroupId = this.expandedGroupId === 0 ? -1 : 0;
        }
      })
      Column({ space: 0 }) {
        ForEach(this.expandedGroupId === 0 ? this.itemsInGroup(0) : this.itemsInGroup(0).slice(0, 3),
          (item: VaultItem): void => {
          this.itemRow(item)
        }, (item: VaultItem): string => `${item.id}-${item.updatedAt}`)
      }
      .width('100%').padding({ left: 3, right: 3, bottom: 3 })
      .border({ width: { top: 1 }, color: COLOR_BORDER })
      if (this.countGroup(0) > 3) {
        this.moreItemsRow(0, this.countGroup(0))
      }
    }
    .width(fullWidth ? '100%' : '48.5%')
    .margin({ bottom: 12 }).backgroundColor(COLOR_SURFACE).borderRadius(18)
    .border({ width: 1, color: COLOR_BORDER })
  }

  @Builder
  private categoryCard(type: VaultItemType, description: string): void {
    Column({ space: 8 }) {
      Row() {
        Stack() {
          Text(itemTypeGlyph(type)).fontSize(22).fontColor(this.typeColor(type))
        }
        .width(40).height(40).borderRadius(13).backgroundColor(this.typeBackground(type))
        Blank()
        Text(`${this.countType(type)}`).fontSize(18).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT)
      }
      .width('100%')
      Column({ space: 4 }) {
        Text(itemTypeLabel(type)).fontSize(16).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT)
        Text(description).fontSize(11).fontColor(COLOR_MUTED).maxLines(1)
      }
      .width('100%').alignItems(HorizontalAlign.Start)
    }
    .width('48.5%')
    .padding(12)
    .margin({ bottom: 6 })
    .backgroundColor(COLOR_SURFACE)
    .borderRadius(18)
    .border({ width: 1, color: COLOR_BORDER })
    .onClick((): void => {
      this.selectedCategoryType = type;
      this.showCategoryItems = true;
    })
  }

  @Builder
  private categoryGroupSection(group: VaultGroup, type: VaultItemType): void {
    Column() {
      Row() {
        Text(group.name).fontSize(15).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT)
        Blank()
        Text(`${this.countGroupByType(group.id, type)} 条`).fontSize(11).fontColor(COLOR_MUTED)
      }
      .width('100%').padding({ left: 12, right: 12, top: 9, bottom: 8 })
      Column({ space: 0 }) {
        ForEach(this.itemsInGroupByType(group.id, type), (item: VaultItem): void => {
          this.itemRow(item)
        }, (item: VaultItem): string => `${item.id}-${item.updatedAt}`)
      }
      .width('100%').padding({ left: 3, right: 3, bottom: 3 })
      .border({ width: { top: 1 }, color: COLOR_BORDER })
    }
    .width('100%').backgroundColor(COLOR_SURFACE).borderRadius(18)
    .border({ width: 1, color: COLOR_BORDER })
  }

  @Builder
  private categoryTab(): void {
    Scroll() {
      Column({ space: 12 }) {
        if (this.showCategoryItems) {
          Row({ space: 10 }) {
            Button('‹')
              .width(40).height(40).fontSize(26).fontColor(COLOR_TEXT)
              .backgroundColor(COLOR_SURFACE).borderRadius(12)
              .onClick((): void => { this.showCategoryItems = false; })
            Column({ space: 3 }) {
              Text(itemTypeLabel(this.selectedCategoryType))
                .fontSize(26).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT)
              Text(`共 ${this.countType(this.selectedCategoryType)} 条资料`)
                .fontSize(12).fontColor(COLOR_MUTED)
            }
            .alignItems(HorizontalAlign.Start).layoutWeight(1)
          }
          .width('100%')
          if (this.countType(this.selectedCategoryType) === 0) {
            this.emptyState(`还没有${itemTypeLabel(this.selectedCategoryType)}`, '点击底部加号添加第一条资料')
          } else {
            ForEach(this.groups, (group: VaultGroup): void => {
              if (this.countGroupByType(group.id, this.selectedCategoryType) > 0) {
                this.categoryGroupSection(group, this.selectedCategoryType)
              }
            }, (group: VaultGroup): string => `${group.id}`)
            if (this.countGroupByType(0, this.selectedCategoryType) > 0) {
              Column() {
                Row() {
                  Text('未分组').fontSize(15).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT)
                  Blank()
                  Text(`${this.countGroupByType(0, this.selectedCategoryType)} 条`)
                    .fontSize(11).fontColor(COLOR_MUTED)
                }.width('100%').padding({ left: 12, right: 12, top: 9, bottom: 8 })
                Column({ space: 0 }) {
                  ForEach(this.itemsInGroupByType(0, this.selectedCategoryType), (item: VaultItem): void => {
                    this.itemRow(item)
                  }, (item: VaultItem): string => `${item.id}-${item.updatedAt}`)
                }.width('100%').padding({ left: 3, right: 3, bottom: 3 })
                  .border({ width: { top: 1 }, color: COLOR_BORDER })
              }.width('100%').backgroundColor(COLOR_SURFACE).borderRadius(18)
                .border({ width: 1, color: COLOR_BORDER })
            }
          }
        } else {
          Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
            this.categoryCard(VaultItemType.Login, '网站账号与密码')
            this.categoryCard(VaultItemType.Note, '文字与私密记录')
            this.categoryCard(VaultItemType.Image, '本地保存的图片')
            this.categoryCard(VaultItemType.Video, '可直接播放的视频')
            this.categoryCard(VaultItemType.File, '文档与任意文件')
          }
          .width('100%')
        }
      }
      .width('100%').padding({ left: 18, right: 18, top: 12, bottom: 92 })
    }
    .width('100%').height('100%')
  }

  @Builder
  private trashTab(): void {
    Column({ space: 16 }) {
      List({ space: 10 }) {
        if (this.trashItems.length === 0) {
          ListItem() { this.emptyState('回收站为空', '删除的资料会保留在这里') }
        } else {
          ForEach(this.trashItems, (item: VaultItem): void => {
            ListItem() {
              Column({ space: 10 }) {
                Row({ space: 12 }) {
                  Stack() { Text(itemTypeGlyph(item.type)).fontSize(18).fontColor(this.typeColor(item.type)) }
                    .width(42).height(42).borderRadius(13).backgroundColor(this.typeBackground(item.type))
                  Column({ space: 3 }) {
                    Text(item.title).fontSize(15).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT)
                    Text(itemTypeLabel(item.type)).fontSize(11).fontColor(COLOR_MUTED)
                  }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                }.width('100%')
                Row({ space: 10 }) {
                  Button('恢复')
                    .layoutWeight(1).height(38).fontColor(COLOR_PRIMARY).backgroundColor('#E7F7F2')
                    .onClick((): void => { this.trashAction(item, false); })
                  Button('永久删除')
                    .layoutWeight(1).height(38).fontColor(COLOR_DANGER).backgroundColor('#FDEDEF')
                    .onClick((): void => { this.trashAction(item, true); })
                }.width('100%')
              }.width('100%').padding(14).backgroundColor(COLOR_SURFACE).borderRadius(17)
                .border({ width: 1, color: COLOR_BORDER })
            }
          }, (item: VaultItem): string => item.id)
        }
      }
      .layoutWeight(1).width('100%').scrollBar(BarState.Off)
    }
    .width('100%').height('100%')
    .padding({ left: 18, right: 18, top: 12, bottom: 92 })
  }

  @Builder
  private groupManagerTab(): void {
    Column({ space: 16 }) {
      Row({ space: 10 }) {
        Button('‹')
          .width(40).height(40).fontSize(26).fontColor(COLOR_TEXT)
          .backgroundColor(COLOR_SURFACE).borderRadius(12)
          .onClick((): void => { this.showGroupManager = false; })
        Column({ space: 3 }) {
          Text('分组管理').fontSize(25).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT)
          Text('删除分组不会删除其中的资料').fontSize(12).fontColor(COLOR_MUTED)
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      }.width('100%')
      List({ space: 10 }) {
        ForEach(this.groups, (group: VaultGroup): void => {
          ListItem() {
            Row({ space: 12 }) {
              Stack() { Text('◆').fontSize(14).fontColor(group.color) }
                .width(44).height(44).borderRadius(14).backgroundColor(COLOR_SURFACE_2)
              Column({ space: 3 }) {
                Text(group.name).fontSize(15).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT)
                Text(`${this.countGroup(group.id)} 条资料`).fontSize(11).fontColor(COLOR_MUTED)
              }.alignItems(HorizontalAlign.Start).layoutWeight(1)
              Row({ space: 6 }) {
                Button('修改')
                  .height(36).fontSize(11).fontColor(COLOR_PRIMARY)
                  .backgroundColor(COLOR_SURFACE_2).borderRadius(10)
                  .onClick((): void => { this.requestRenameGroup(group); })
                Button('删除')
                  .height(36).fontSize(11).fontColor(COLOR_DANGER)
                  .backgroundColor('#FDEDEF').borderRadius(10)
                  .onClick((): void => { this.requestDeleteGroup(group); })
              }
            }
            .width('100%').padding(14).backgroundColor(COLOR_SURFACE).borderRadius(17)
            .border({ width: 1, color: COLOR_BORDER })
          }
        }, (group: VaultGroup): string => `${group.id}`)
      }
      .layoutWeight(1).width('100%').scrollBar(BarState.Off)
    }
    .width('100%').height('100%')
    .padding({ left: 18, right: 18, top: 20, bottom: 92 })
  }

  @Builder
  private settingsTab(): void {
    Scroll() {
      Column({ space: 16 }) {
        Column() {
          Text('快捷登录')
            .fontSize(15).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT)
            .width('100%').padding(15)
          Row({ space: 12 }) {
            Stack() { Text('◎').fontSize(22).fontColor(COLOR_PRIMARY) }
              .width(44).height(44).borderRadius(14).backgroundColor('#183029')
            Column({ space: 3 }) {
              Text('指纹登录').fontSize(14).fontColor(COLOR_TEXT)
              Text(this.fingerprintEnabled ? '已启用 · 由系统指纹验证' :
                (this.fingerprintAvailable ? '未启用' : '设备未录入或不支持'))
                .fontSize(12).fontColor(COLOR_MUTED)
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            Button(this.fingerprintEnabled ? '关闭' : '启用')
              .height(38).fontColor(this.fingerprintEnabled ? COLOR_DANGER : COLOR_PRIMARY)
              .backgroundColor(COLOR_SURFACE_2)
              .enabled(this.fingerprintEnabled || this.fingerprintAvailable)
              .onClick((): void => { this.toggleFingerprint(); })
          }
          .width('100%').padding(15).border({ width: { top: 1 }, color: COLOR_BORDER })
          Row({ space: 12 }) {
            Stack() { Text('⌁').fontSize(22).fontColor(COLOR_PRIMARY) }
              .width(44).height(44).borderRadius(14).backgroundColor('#183029')
            Column({ space: 3 }) {
              Text('手势登录').fontSize(14).fontColor(COLOR_TEXT)
              Text(this.gestureEnabled ? '已启用 · 九宫格快捷解锁' : '未启用 · 至少连接 4 个点')
                .fontSize(12).fontColor(COLOR_MUTED)
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            Button(this.gestureEnabled ? '关闭' : '设置')
              .height(38).fontColor(this.gestureEnabled ? COLOR_DANGER : COLOR_PRIMARY)
              .backgroundColor(COLOR_SURFACE_2)
              .onClick((): void => {
                if (this.gestureEnabled) { this.disableGesture(); } else { this.beginGestureSetup(); }
              })
          }
          .width('100%').padding(15).border({ width: { top: 1 }, color: COLOR_BORDER })
        }
        .width('100%').backgroundColor(COLOR_SURFACE).borderRadius(18)
        .border({ width: 1, color: COLOR_BORDER })
        Row({ space: 12 }) {
          Stack() { Text('◆').fontSize(15).fontColor(COLOR_PRIMARY) }
            .width(42).height(42).borderRadius(13).backgroundColor('#E7F7F2')
          Column({ space: 3 }) {
            Text('分组管理').fontSize(15).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT)
            Text('查看和删除自定义分组').fontSize(11).fontColor(COLOR_MUTED)
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          Text('›').fontSize(22).fontColor('#B2B8C2')
        }
        .width('100%').padding(14).backgroundColor(COLOR_SURFACE).borderRadius(17)
        .border({ width: 1, color: COLOR_BORDER })
        .onClick((): void => { this.showGroupManager = true; })
        Button('立即锁定保险库')
          .width('100%').height(50).fontColor(COLOR_PRIMARY)
          .backgroundColor('#173128').borderRadius(14)
          .onClick((): void => { this.lockVault(); })
        Text('掌心密匣 PalmVault · 阶段 1')
          .fontSize(12).fontColor('#607B72').width('100%').textAlign(TextAlign.Center)
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 12, bottom: 105 })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private bottomBar(): void {
    Row() {
      this.navItem(0, $r('app.media.nav_home'), '首页')
      this.navItem(1, $r('app.media.nav_category'), '分类')
      this.newItemNav()
      this.navItem(2, $r('app.media.nav_trash'), '回收站')
      this.navItem(3, $r('app.media.nav_settings'), '设置')
    }
    .width('100%')
    .height(76)
    .padding({ top: 6, bottom: 2 })
    .backgroundColor('#FAFFFFFF')
    .border({ width: { top: 1 }, color: COLOR_BORDER })
  }

  @Builder
  private navItem(index: number, icon: Resource, label: string): void {
    Column({ space: 5 }) {
      Image(icon)
        .width(24).height(24)
        .fillColor(this.activeTab === index ? COLOR_PRIMARY : COLOR_MUTED)
      Text(label)
        .width('100%').height(18).lineHeight(18)
        .fontSize(11).textAlign(TextAlign.Center)
        .fontColor(this.activeTab === index ? COLOR_PRIMARY : COLOR_MUTED)
    }
    .layoutWeight(1)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ top: 6, bottom: 4 })
    .onClick((): void => {
      this.activeTab = index;
      if (index === 1) {
        this.showCategoryItems = false;
      }
      if (index === 2) {
        this.refreshTrash();
      }
      if (index === 3) {
        this.showGroupManager = false;
      }
    })
  }

  @Builder
  private newItemNav(): void {
    Column() {
      Stack() {
        Text('+').fontSize(28).fontWeight(FontWeight.Medium).fontColor('#FFFFFF')
      }
      .width(48).height(48).borderRadius(16).backgroundColor(COLOR_PRIMARY)
    }
    .layoutWeight(1).height('100%').justifyContent(FlexAlign.Center)
    .translate({ y: -4 })
    .onClick((): void => { this.openNewItem(); })
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
      if (this.selectedItem) {
        this.detailOverlay(this.selectedItem as VaultItem)
      }
      if (this.showGestureSetup) { this.gestureSetupOverlay() }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private gestureSetupOverlay(): void {
    Column() {
      Blank().onClick((): void => { this.closeGestureSetup(); })
      Column({ space: 10 }) {
        this.modalHeader('设置手势登录', (): void => {
          this.closeGestureSetup();
        })
        Text(this.gestureSetupStep === 1 ? '第一步，共两步' : '第二步，共两步')
          .fontSize(12).fontColor(COLOR_PRIMARY).width('100%')
        GestureGrid({
          hint: this.gestureSetupHint,
          onComplete: (pattern: number[]): void => { this.handleGestureSetup(pattern); }
        })
        Text('手势只用于快捷登录，主密码仍可随时解锁。')
          .fontSize(12).fontColor(COLOR_MUTED).textAlign(TextAlign.Center).width('100%')
      }
      .padding(20).width('100%').backgroundColor(COLOR_SURFACE)
      .borderRadius({ topLeft: 24, topRight: 24 })
    }
    .width('100%').height('100%').backgroundColor('#99000000')
  }

  @Builder
  private modalHeader(title: string, closeAction: () => void): void {
    Row() {
      Text(title).fontSize(19).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT)
      Blank()
      Stack() {
        Text('×')
          .fontSize(22)
          .lineHeight(24)
          .fontColor(COLOR_MUTED)
      }
        .width(38).height(38)
        .backgroundColor(COLOR_SURFACE_2).borderRadius(11)
        .onClick(closeAction)
    }
    .width('100%')
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
      .onClick((): void => { this.selectNewItemType(type); })
  }

  @Builder
  private screenshotProtectionHint(): void {
    Row({ space: 5 }) {
      Text('✓').fontSize(11).fontWeight(FontWeight.Bold).fontColor(COLOR_PRIMARY)
      Text('已禁止截屏').fontSize(11).fontColor(COLOR_PRIMARY)
    }
    .padding({ left: 10, right: 10, top: 6, bottom: 6 })
    .backgroundColor('#173128')
    .borderRadius(12)
    .alignSelf(ItemAlign.Start)
  }

  @Builder
  private newItemOverlay(): void {
    Column() {
      Blank().onClick((): void => { this.closeNewItem(); })
      Scroll() {
        Column({ space: 10 }) {
          this.modalHeader('新建资料', (): void => { this.closeNewItem(); })
          Text('保存到分组').fontSize(12).fontColor(COLOR_MUTED).width('100%')
          Scroll() {
            Row({ space: 6 }) {
              ForEach(this.groups, (group: VaultGroup): void => {
                Text(group.name)
                  .fontSize(12)
                  .fontColor(this.newGroupId === group.id ? COLOR_BG : COLOR_MUTED)
                  .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                  .backgroundColor(this.newGroupId === group.id ? COLOR_PRIMARY : COLOR_SURFACE_2)
                  .borderRadius(16)
                  .onClick((): void => { this.newGroupId = group.id; })
              }, (group: VaultGroup): string => `${group.id}`)
            }
          }
          .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')
          Row({ space: 4 }) {
            this.typeChip(VaultItemType.Login)
            this.typeChip(VaultItemType.Note)
            this.typeChip(VaultItemType.Image)
            this.typeChip(VaultItemType.Video)
            this.typeChip(VaultItemType.File)
          }
          .width('100%')
          TextInput({ placeholder: '资料名称', text: this.newTitle })
            .id(this.newItemTitleInputId())
            .defaultFocus(true)
            .onAppear((): void => { this.requestNewItemTitleFocus(60); })
            .fontColor(COLOR_TEXT).placeholderColor('#607B72').backgroundColor(COLOR_SURFACE_2)
            .height(48).borderRadius(12)
            .onChange((value: string): void => { this.newTitle = value; })
          if (this.newType === VaultItemType.Login) {
            TextInput({ placeholder: '账号', text: this.newUsername })
              .fontColor(COLOR_TEXT).placeholderColor('#607B72').backgroundColor(COLOR_SURFACE_2)
              .height(48).borderRadius(12)
              .onChange((value: string): void => { this.newUsername = value; })
            Row({ space: 8 }) {
              TextInput({ placeholder: '密码', text: this.newPassword })
                .type(this.revealNewPassword ? InputType.Normal : InputType.Password)
                .layoutWeight(1).fontColor(COLOR_TEXT).placeholderColor('#607B72')
                .backgroundColor(COLOR_SURFACE_2).height(48).borderRadius(12)
                .onChange((value: string): void => { this.newPassword = value; })
              Button(this.revealNewPassword ? '隐藏' : '显示')
                .height(48).fontColor(COLOR_PRIMARY).backgroundColor('#173128').borderRadius(12)
                .onClick((): void => { this.toggleNewPasswordVisibility(); })
            }
            .width('100%')
            if (this.revealNewPassword) {
              this.screenshotProtectionHint()
            }
          }
          if (this.newType === VaultItemType.Image || this.newType === VaultItemType.Video) {
            Button(this.newAttachmentUri.length > 0 ? '✓ 已选择本机媒体' : '从系统相册选择')
              .width('100%').height(48).fontColor(COLOR_PRIMARY)
              .backgroundColor('#173128').borderRadius(12)
              .onClick((): void => { this.chooseMedia(); })
          } else if (this.newType === VaultItemType.File) {
            Button(this.newAttachmentUri.length > 0 ? '✓ 已选择文件' : '选择要保存的文件')
              .width('100%').height(48).fontColor(COLOR_PRIMARY)
              .backgroundColor('#173128').borderRadius(12)
              .onClick((): void => { this.chooseMedia(true); })
          }
          TextArea({ placeholder: '备注', text: this.newNotes })
            .fontColor(COLOR_TEXT).placeholderColor('#607B72').backgroundColor(COLOR_SURFACE_2)
            .height(92).borderRadius(12)
            .onChange((value: string): void => { this.newNotes = value; })
          Button('保存')
            .width('100%').height(50).fontWeight(FontWeight.Bold).fontColor(COLOR_BG)
            .backgroundColor(COLOR_PRIMARY).borderRadius(13)
            .onClick((): void => { this.createItem(); })
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 12, bottom: 16 })
      }
      .width('100%')
      .constraintSize({ minHeight: 420, maxHeight: '88%' })
      .backgroundColor(COLOR_SURFACE)
      .borderRadius({ topLeft: 24, topRight: 24 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#99000000')
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
          .fontColor(COLOR_TEXT).placeholderColor('#607B72').backgroundColor(COLOR_SURFACE_2)
          .height(50).borderRadius(12)
          .onChange((value: string): void => { this.groupRenameName = value; })
        Button('保存修改')
          .width('100%').height(50).fontWeight(FontWeight.Bold).fontColor(COLOR_BG)
          .backgroundColor(COLOR_PRIMARY).borderRadius(13)
          .onClick((): void => { this.renameGroup(group); })
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 12, bottom: 16 })
      .backgroundColor(COLOR_SURFACE)
      .borderRadius({ topLeft: 24, topRight: 24 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#99000000')
  }

  @Builder
  private deleteGroupOverlay(group: VaultGroup): void {
    Column() {
      Blank().onClick((): void => {
        this.groupPendingDelete = undefined;
        this.groupDeleteConfirmName = '';
      })
      Column({ space: 15 }) {
        this.modalHeader('删除非空分组', (): void => {
          this.groupPendingDelete = undefined;
          this.groupDeleteConfirmName = '';
        })
        Text(`“${group.name}”中有 ${this.groupPendingDeleteCount} 条资料。删除分组后，这些资料将移至“未分组”，资料本身不会被删除。`)
          .fontSize(13).fontColor(COLOR_MUTED).lineHeight(21).width('100%')
        Text(`请输入分组名称“${group.name}”以确认删除`)
          .fontSize(12).fontColor(COLOR_DANGER).width('100%')
        TextInput({ placeholder: group.name, text: this.groupDeleteConfirmName })
          .fontColor(COLOR_TEXT).placeholderColor('#A7AFBC').backgroundColor(COLOR_SURFACE_2)
          .height(50).borderRadius(12)
          .onChange((value: string): void => { this.groupDeleteConfirmName = value; })
        Button('删除分组')
          .width('100%').height(50).fontWeight(FontWeight.Bold)
          .fontColor(this.groupDeleteConfirmName.trim() === group.name ? '#FFFFFF' : COLOR_MUTED)
          .backgroundColor(this.groupDeleteConfirmName.trim() === group.name ? COLOR_DANGER : COLOR_SURFACE_2)
          .borderRadius(13)
          .enabled(this.groupDeleteConfirmName.trim() === group.name)
          .onClick((): void => { this.confirmDeleteGroup(group); })
      }
      .width('100%').padding(20).backgroundColor(COLOR_SURFACE)
      .borderRadius({ topLeft: 24, topRight: 24 })
    }
    .width('100%').height('100%').backgroundColor('#99000000')
  }

  @Builder
  private newGroupOverlay(): void {
    Column() {
      Blank().onClick((): void => { this.showNewGroup = false; })
      Column({ space: 10 }) {
        this.modalHeader('新建分组', (): void => { this.showNewGroup = false; })
        TextInput({ placeholder: '分组名称', text: this.newGroupName })
          .fontColor(COLOR_TEXT).placeholderColor('#607B72').backgroundColor(COLOR_SURFACE_2)
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
      .borderRadius({ topLeft: 24, topRight: 24 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#99000000')
  }

  @Builder
  private detailOverlay(item: VaultItem): void {
    Column() {
      Blank().onClick((): void => { this.closeSelectedItem(); })
      Scroll() {
        Column({ space: 14 }) {
          this.modalHeader('资料详情', (): void => { this.closeSelectedItem(); })
          Row({ space: 12 }) {
            Stack() { Text(itemTypeGlyph(item.type)).fontSize(22).fontColor(COLOR_PRIMARY) }
              .width(54).height(54).borderRadius(16).backgroundColor('#1B332C')
            Column() {
              Text(itemTypeLabel(item.type)).fontSize(13).fontColor(COLOR_PRIMARY)
            }
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          TextInput({ placeholder: '名称', text: this.detailTitle })
            .fontColor(COLOR_TEXT).backgroundColor(COLOR_SURFACE_2).height(48).borderRadius(12)
            .onChange((value: string): void => { this.detailTitle = value; })
          if (item.type === VaultItemType.Login) {
            TextInput({ placeholder: '账号', text: this.detailUsername })
              .fontColor(COLOR_TEXT).backgroundColor(COLOR_SURFACE_2).height(48).borderRadius(12)
              .onChange((value: string): void => { this.detailUsername = value; })
            Row({ space: 8 }) {
              TextInput({ placeholder: '密码', text: this.detailPassword })
                .type(this.revealPassword ? InputType.Normal : InputType.Password)
                .layoutWeight(1).fontColor(COLOR_TEXT).backgroundColor(COLOR_SURFACE_2)
                .height(48).borderRadius(12)
                .onChange((value: string): void => { this.detailPassword = value; })
              Button(this.revealPassword ? '隐藏' : '显示')
                .height(48).fontColor(COLOR_PRIMARY).backgroundColor('#173128').borderRadius(12)
                .onClick((): void => { this.toggleDetailPasswordVisibility(); })
            }
            .width('100%')
            if (this.revealPassword) {
              this.screenshotProtectionHint()
            }
          }
          TextArea({ placeholder: '备注', text: this.detailNotes })
            .fontColor(COLOR_TEXT).backgroundColor(COLOR_SURFACE_2).height(105).borderRadius(12)
            .onChange((value: string): void => { this.detailNotes = value; })
          if (item.type === VaultItemType.Image || item.type === VaultItemType.Video) {
            VaultMedia({ itemId: item.id, mediaType: item.type })
          }
          if (item.type === VaultItemType.File) {
            Row({ space: 12 }) {
              Text('▤').fontSize(28).fontColor(COLOR_PRIMARY)
              Column({ space: 3 }) {
                Text(item.title).fontSize(14).fontColor(COLOR_TEXT).maxLines(1)
                Text('文件保存在应用本地数据库中').fontSize(11).fontColor(COLOR_MUTED)
              }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            }.width('100%').padding(14).backgroundColor(COLOR_SURFACE_2).borderRadius(12)
          }
          if (item.type === VaultItemType.Image || item.type === VaultItemType.Video || item.type === VaultItemType.File) {
            Button('下载到本地')
              .width('100%').height(48).fontColor(COLOR_PRIMARY)
              .backgroundColor('#173128').borderRadius(13)
              .onClick((): void => { this.downloadAttachment(item); })
          }
          Button('保存修改')
            .width('100%').height(50).fontWeight(FontWeight.Bold).fontColor(COLOR_BG)
            .backgroundColor(COLOR_PRIMARY).borderRadius(13)
            .onClick((): void => { this.saveSelectedItem(); })
          Button('移入回收站')
            .width('100%').height(48).fontColor(COLOR_DANGER)
            .backgroundColor('#2A1719').borderRadius(13)
            .onClick((): void => { this.trashSelectedItem(); })
        }
        .width('100%')
        .padding(20)
      }
      .width('100%')
      .height('82%')
      .backgroundColor(COLOR_SURFACE)
      .borderRadius({ topLeft: 24, topRight: 24 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#99000000')
  }

  build() {
    if (this.screen === 'loading') {
      this.loadingScreen()
    } else if (this.screen === 'setup') {
      this.setupScreen()
    } else if (this.screen === 'locked') {
      this.lockedScreen()
    } else {
      this.vaultScreen()
    }
  }
}
