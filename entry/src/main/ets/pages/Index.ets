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

const COLOR_BG: string = '#08110F';
const COLOR_SURFACE: string = '#0F1D19';
const COLOR_SURFACE_2: string = '#162823';
const COLOR_PRIMARY: string = '#67E8C5';
const COLOR_TEXT: string = '#EDF8F4';
const COLOR_MUTED: string = '#91A9A0';
const COLOR_BORDER: string = '#243A33';
const COLOR_DANGER: string = '#FF7B86';

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
  @State private selectedGroupId: number = -1;
  @State private showNewItem: boolean = false;
  @State private showNewGroup: boolean = false;
  @State private showTrash: boolean = false;
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
  @State private newNotes: string = '';
  @State private newAttachmentUri: string = '';
  @State private newGroupId: number = 0;
  @State private newGroupName: string = '';
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
      this.screen = 'vault';
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
      this.screen = 'vault';
    } catch (error) {
      this.errorMessage = this.describeError(error);
    } finally {
      this.busy = false;
    }
  }

  private async lockVault(): Promise<void> {
    this.showTrash = false;
    this.trashItems = [];
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
      this.showGestureSetup = false;
      this.firstGesture = [];
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
      this.screen = 'vault';
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
      this.screen = 'vault';
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
    this.items = await vaultRepository.listItems(this.searchText, this.selectedGroupId);
  }

  private async refreshTrash(): Promise<void> {
    this.trashItems = (await vaultRepository.listItems('', -1, true)).filter((item: VaultItem): boolean => item.deletedAt > 0);
  }

  private async trashAction(item: VaultItem, permanent: boolean): Promise<void> {
    try {
      if (permanent) {
        const choice = await promptAction.showDialog({ title: '永久删除此项目？', message: '删除后无法恢复。',
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
    this.selectedGroupId = -1;
    this.activeTab = 1;
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
      this.showNewItem = false;
      await this.reloadVault();
      promptAction.showToast({ message: '项目已保存' });
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
      this.selectedItem = undefined;
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
    this.selectedItem = undefined;
    await this.reloadVault();
    promptAction.showToast({ message: '项目已移入回收站' });
  }

  private async downloadAttachment(item: VaultItem): Promise<void> {
    let data = new Uint8Array(0);
    try {
      data = await vaultRepository.readAttachment(item.id);
      if (data.length === 0) { throw new Error('此项目没有可导出的附件'); }
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

  private countType(type: VaultItemType): number {
    let count: number = 0;
    this.allItems.forEach((item: VaultItem): void => {
      if (item.type === type) {
        count += 1;
      }
    });
    return count;
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
        TextInput({ placeholder: '搜索账号、笔记、图片文字…', text: this.searchText })
          .layoutWeight(1)
          .height(44)
          .fontSize(14)
          .fontColor(COLOR_TEXT)
          .placeholderColor('#607B72')
          .backgroundColor(Color.Transparent)
          .onChange((value: string): void => { this.applySearch(value); })
      }
      .height(48)
      .layoutWeight(1)
      .padding({ left: 12, right: 8 })
      .backgroundColor(COLOR_SURFACE)
      .borderRadius(15)
      .border({ width: 1, color: COLOR_BORDER })

      Button('⌁')
        .width(46)
        .height(46)
        .fontSize(20)
        .fontColor(COLOR_PRIMARY)
        .backgroundColor(COLOR_SURFACE)
        .borderRadius(14)
        .onClick((): void => { this.lockVault(); })
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 12, bottom: 10 })
    .backgroundColor(COLOR_BG)
  }

  @Builder
  private statCard(label: string, value: string, glyph: string, hint: string): void {
    Column({ space: 8 }) {
      Row() {
        Text(label).fontSize(13).fontColor(COLOR_MUTED)
        Blank()
        Text(glyph).fontSize(18).fontColor(COLOR_PRIMARY)
      }
      .width('100%')
      Text(value)
        .fontSize(26)
        .fontWeight(FontWeight.Bold)
        .fontColor(COLOR_TEXT)
        .width('100%')
      Text(hint)
        .fontSize(11)
        .fontColor('#6F8B81')
        .width('100%')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('48.5%')
    .height(118)
    .padding(15)
    .backgroundColor(COLOR_SURFACE)
    .borderRadius(18)
    .border({ width: 1, color: COLOR_BORDER })
    .margin({ bottom: 10 })
  }

  @Builder
  private itemRow(item: VaultItem): void {
    Row({ space: 13 }) {
      Stack() {
        Text(itemTypeGlyph(item.type))
          .fontSize(18)
          .fontColor(COLOR_PRIMARY)
      }
      .width(44)
      .height(44)
      .borderRadius(13)
      .backgroundColor('#1B332C')

      Column({ space: 4 }) {
        Text(item.title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(COLOR_TEXT)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(item.username.length > 0 ? item.username : (item.notes.length > 0 ? item.notes : itemTypeLabel(item.type)))
          .fontSize(12)
          .fontColor(COLOR_MUTED)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Text('›').fontSize(23).fontColor('#607B72')
    }
    .width('100%')
    .height(68)
    .padding({ left: 12, right: 12 })
    .backgroundColor(COLOR_SURFACE)
    .borderRadius(15)
    .onClick((): void => { this.openItem(item); })
  }

  @Builder
  private emptyState(title: string, description: string): void {
    Column({ space: 9 }) {
      Text('◇').fontSize(32).fontColor('#526E64')
      Text(title).fontSize(16).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT)
      Text(description).fontSize(13).fontColor(COLOR_MUTED).textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding({ top: 48, bottom: 48 })
  }

  @Builder
  private homeTab(): void {
    Scroll() {
      Column({ space: 24 }) {
        Row() {
          Column({ space: 5 }) {
            Text('欢迎回来')
              .fontSize(28)
              .fontWeight(FontWeight.Bold)
              .fontColor(COLOR_TEXT)
            Text('开发模式 · 数据明文保存在本机')
              .fontSize(13)
              .fontColor(COLOR_MUTED)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Button('+  新建项目')
            .height(42)
            .fontColor(COLOR_BG)
            .fontWeight(FontWeight.Bold)
            .backgroundColor(COLOR_PRIMARY)
            .borderRadius(13)
            .onClick((): void => { this.showNewItem = true; })
        }
        .width('100%')

        Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
          this.statCard('账号密码', `${this.loginCount}`, '⌘', '本机保存')
          this.statCard('私密笔记', `${this.noteCount}`, '✎', '支持全文搜索')
          this.statCard('照片与视频', `${this.mediaCount}`, '▧', '支持预览与导出')
          this.statCard('文件', `${this.fileCount}`, '▤', '支持任意文件')
        }
        .width('100%')

        Column({ space: 12 }) {
          Row() {
            Text('最近项目').fontSize(18).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT)
            Blank()
            Text('查看全部 →')
              .fontSize(13)
              .fontColor(COLOR_PRIMARY)
              .onClick((): void => { this.activeTab = 1; })
          }
          .width('100%')
          if (this.allItems.length === 0) {
            this.emptyState('保险库还是空的', '新建账号、笔记，或导入文件与媒体')
          } else {
            ForEach(this.allItems.slice(0, 4), (item: VaultItem): void => {
              this.itemRow(item)
            }, (item: VaultItem): string => `${item.id}-${item.updatedAt}`)
          }
        }
        .width('100%')
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 14, bottom: 105 })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private itemsTab(): void {
    Column({ space: 13 }) {
      Row() {
        Column({ space: 4 }) {
          Text('全部项目').fontSize(27).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT)
          Text(`${this.items.length} 个本地项目`).fontSize(13).fontColor(COLOR_MUTED)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Button('+')
          .width(42).height(42).fontSize(23).fontColor(COLOR_BG)
          .backgroundColor(COLOR_PRIMARY).borderRadius(13)
          .onClick((): void => { this.showNewItem = true; })
      }
      .width('100%')

      Scroll() {
        Row({ space: 8 }) {
          this.groupFilterChip(-1, '全部')
          ForEach(this.groups, (group: VaultGroup): void => {
            this.groupFilterChip(group.id, group.name)
          }, (group: VaultGroup): string => `${group.id}`)
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')

      List({ space: 8 }) {
        if (this.items.length === 0) {
          ListItem() { this.emptyState('没有找到项目', '更换分组或搜索关键词再试试') }
        } else {
          ForEach(this.items, (item: VaultItem): void => {
            ListItem() { this.itemRow(item) }
          }, (item: VaultItem): string => `${item.id}-${item.updatedAt}`)
        }
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 18, right: 18, top: 12, bottom: 92 })
  }

  @Builder
  private groupFilterChip(id: number, label: string): void {
    Text(label)
      .fontSize(13)
      .fontColor(this.selectedGroupId === id ? COLOR_BG : COLOR_MUTED)
      .padding({ left: 14, right: 14, top: 9, bottom: 9 })
      .backgroundColor(this.selectedGroupId === id ? COLOR_PRIMARY : COLOR_SURFACE)
      .borderRadius(18)
      .border({ width: 1, color: this.selectedGroupId === id ? COLOR_PRIMARY : COLOR_BORDER })
      .onClick((): void => {
        this.selectedGroupId = id;
        this.reloadVault();
      })
  }

  @Builder
  private groupsTab(): void {
    Column({ space: 16 }) {
      Row() {
        Column({ space: 4 }) {
          Text('我的分组').fontSize(27).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT)
          Text('按自己的习惯组织保险库').fontSize(13).fontColor(COLOR_MUTED)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Button('+')
          .width(42).height(42).fontSize(23).fontColor(COLOR_BG)
          .backgroundColor(COLOR_PRIMARY).borderRadius(13)
          .onClick((): void => { this.showNewGroup = true; })
      }
      .width('100%')

      List({ space: 10 }) {
        ForEach(this.groups, (group: VaultGroup): void => {
          ListItem() {
            Row({ space: 14 }) {
              Stack() { Text('◆').fontSize(17).fontColor(group.color) }
                .width(46).height(46).borderRadius(14).backgroundColor('#183029')
              Column({ space: 4 }) {
                Text(group.name).fontSize(16).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT)
                Text(`${this.countGroup(group.id)} 个项目`).fontSize(12).fontColor(COLOR_MUTED)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              Text('›').fontSize(23).fontColor('#607B72')
            }
            .width('100%')
            .padding(15)
            .backgroundColor(COLOR_SURFACE)
            .borderRadius(17)
            .border({ width: 1, color: COLOR_BORDER })
            .onClick((): void => {
              this.selectedGroupId = group.id;
              this.reloadVault();
              this.activeTab = 1;
            })
          }
        }, (group: VaultGroup): string => `${group.id}`)
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 18, right: 18, top: 12, bottom: 92 })
  }

  @Builder
  private settingsTab(): void {
    Scroll() {
      Column({ space: 16 }) {
        Column({ space: 4 }) {
          Text('设置').fontSize(27).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT).width('100%')
          Text('安全、隐私与本地数据').fontSize(13).fontColor(COLOR_MUTED).width('100%')
        }
        .alignItems(HorizontalAlign.Start)
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
        this.settingSection('安全与隐私', [
          '主密码保护｜PBKDF2 密钥派生',
          '禁止截屏｜敏感窗口已保护',
          '自动锁定｜后台超过 10 分钟'
        ])
        this.settingSection('本地数据', [
          '开发数据库｜明文存储',
          '文件与媒体｜写入本地数据库',
          '云端同步｜未启用'
        ])
        Button('立即锁定保险库')
          .width('100%').height(50).fontColor(COLOR_PRIMARY)
          .backgroundColor('#173128').borderRadius(14)
          .onClick((): void => { this.lockVault(); })
        Button('回收站')
          .width('100%').height(48).fontColor(COLOR_PRIMARY).backgroundColor(COLOR_SURFACE_2)
          .onClick(async (): Promise<void> => { await this.refreshTrash(); this.showTrash = true; })
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
  private settingSection(title: string, rows: string[]): void {
    Column() {
      Text(title)
        .fontSize(15).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT)
        .width('100%').padding(15)
      ForEach(rows, (row: string): void => {
        Row() {
          Text('✓').fontSize(14).fontColor(COLOR_PRIMARY).width(32)
          Column({ space: 3 }) {
            Text(row.split('｜')[0]).fontSize(14).fontColor(COLOR_TEXT)
            Text(row.split('｜')[1]).fontSize(12).fontColor(COLOR_MUTED)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 15, right: 15, top: 13, bottom: 13 })
        .border({ width: { top: 1 }, color: COLOR_BORDER })
      })
    }
    .width('100%')
    .backgroundColor(COLOR_SURFACE)
    .borderRadius(18)
    .border({ width: 1, color: COLOR_BORDER })
  }

  @Builder
  private bottomBar(): void {
    Row() {
      this.navItem(0, '⌂', '概览')
      this.navItem(1, '▦', '项目')
      this.navItem(2, '◇', '分组')
      this.navItem(3, '⚙', '设置')
    }
    .width('100%')
    .height(76)
    .padding({ bottom: 8 })
    .backgroundColor('#F208110F')
    .border({ width: { top: 1 }, color: COLOR_BORDER })
  }

  @Builder
  private navItem(index: number, glyph: string, label: string): void {
    Column({ space: 4 }) {
      Text(glyph).fontSize(19).fontColor(this.activeTab === index ? COLOR_PRIMARY : COLOR_MUTED)
      Text(label).fontSize(11).fontColor(this.activeTab === index ? COLOR_PRIMARY : COLOR_MUTED)
    }
    .layoutWeight(1)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .onClick((): void => { this.activeTab = index; })
  }

  @Builder
  private vaultScreen(): void {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        this.topBar()
        Stack() {
          if (this.activeTab === 0) {
            this.homeTab()
          } else if (this.activeTab === 1) {
            this.itemsTab()
          } else if (this.activeTab === 2) {
            this.groupsTab()
          } else {
            this.settingsTab()
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
      if (this.selectedItem) {
        this.detailOverlay(this.selectedItem as VaultItem)
      }
      if (this.showTrash) { this.trashOverlay() }
      if (this.showGestureSetup) { this.gestureSetupOverlay() }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private gestureSetupOverlay(): void {
    Column() {
      Blank().onClick((): void => { this.showGestureSetup = false; this.firstGesture = []; })
      Column({ space: 10 }) {
        this.modalHeader('设置手势登录', (): void => {
          this.showGestureSetup = false;
          this.firstGesture = [];
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
  private trashOverlay(): void {
    Column() {
      Blank()
      Column({ space: 14 }) {
        this.modalHeader('回收站', (): void => { this.showTrash = false; })
        List({ space: 12 }) {
          if (this.trashItems.length === 0) { ListItem() { this.emptyState('回收站为空', '删除的项目会保留在这里') } }
          ForEach(this.trashItems, (item: VaultItem): void => {
            ListItem() {
              Column({ space: 8 }) {
                Text(item.title).fontColor(COLOR_TEXT).width('100%')
                Row({ space: 10 }) {
                  Button('恢复').onClick((): void => { this.trashAction(item, false); })
                  Button('永久删除').fontColor(COLOR_DANGER).onClick((): void => { this.trashAction(item, true); })
                }
              }.padding(12).width('100%').backgroundColor(COLOR_SURFACE_2).borderRadius(12)
            }
          }, (item: VaultItem): string => item.id)
        }.layoutWeight(1).width('100%')
      }.padding(20).height('80%').width('100%').backgroundColor(COLOR_SURFACE).borderRadius(24)
    }.width('100%').height('100%').backgroundColor('#99000000')
  }

  @Builder
  private modalHeader(title: string, closeAction: () => void): void {
    Row() {
      Text(title).fontSize(19).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT)
      Blank()
      Button('×')
        .width(36).height(36).fontSize(20).fontColor(COLOR_MUTED)
        .backgroundColor(COLOR_SURFACE_2).borderRadius(10)
        .onClick(closeAction)
    }
    .width('100%')
  }

  @Builder
  private typeChip(type: VaultItemType): void {
    Text(`${itemTypeGlyph(type)}  ${itemTypeLabel(type)}`)
      .fontSize(12)
      .fontColor(this.newType === type ? COLOR_BG : COLOR_MUTED)
      .padding({ left: 12, right: 12, top: 9, bottom: 9 })
      .backgroundColor(this.newType === type ? COLOR_PRIMARY : COLOR_SURFACE_2)
      .borderRadius(17)
      .margin({ right: 8, bottom: 8 })
      .onClick((): void => { this.newType = type; })
  }

  @Builder
  private newItemOverlay(): void {
    Column() {
      Blank().onClick((): void => { this.showNewItem = false; })
      Scroll() {
        Column({ space: 14 }) {
          this.modalHeader('新建项目', (): void => { this.showNewItem = false; })
          Flex({ wrap: FlexWrap.Wrap }) {
            this.typeChip(VaultItemType.Login)
            this.typeChip(VaultItemType.Note)
            this.typeChip(VaultItemType.Image)
            this.typeChip(VaultItemType.Video)
            this.typeChip(VaultItemType.File)
            this.typeChip(VaultItemType.Identity)
          }
          .width('100%')
          TextInput({ placeholder: '项目名称', text: this.newTitle })
            .fontColor(COLOR_TEXT).placeholderColor('#607B72').backgroundColor(COLOR_SURFACE_2)
            .height(48).borderRadius(12)
            .onChange((value: string): void => { this.newTitle = value; })
          if (this.newType === VaultItemType.Login) {
            TextInput({ placeholder: '账号或邮箱', text: this.newUsername })
              .fontColor(COLOR_TEXT).placeholderColor('#607B72').backgroundColor(COLOR_SURFACE_2)
              .height(48).borderRadius(12)
              .onChange((value: string): void => { this.newUsername = value; })
            TextInput({ placeholder: '密码', text: this.newPassword })
              .type(InputType.Password).fontColor(COLOR_TEXT).placeholderColor('#607B72')
              .backgroundColor(COLOR_SURFACE_2).height(48).borderRadius(12)
              .onChange((value: string): void => { this.newPassword = value; })
          }
          if (this.newType === VaultItemType.Image || this.newType === VaultItemType.Video) {
            Button(this.newAttachmentUri.length > 0 ? '✓ 已选择本机媒体' : '从系统相册选择')
              .width('100%').height(48).fontColor(COLOR_PRIMARY)
              .backgroundColor('#173128').borderRadius(12)
              .onClick((): void => { this.chooseMedia(); })
            Button('从文件选择')
              .width('100%').height(44).fontColor(COLOR_PRIMARY).backgroundColor(COLOR_SURFACE_2)
              .onClick((): void => { this.chooseMedia(true); })
          } else if (this.newType === VaultItemType.File) {
            Button(this.newAttachmentUri.length > 0 ? '✓ 已选择文件' : '选择要保存的文件')
              .width('100%').height(48).fontColor(COLOR_PRIMARY)
              .backgroundColor('#173128').borderRadius(12)
              .onClick((): void => { this.chooseMedia(true); })
          }
          TextArea({ placeholder: '私密内容或备注', text: this.newNotes })
            .fontColor(COLOR_TEXT).placeholderColor('#607B72').backgroundColor(COLOR_SURFACE_2)
            .height(92).borderRadius(12)
            .onChange((value: string): void => { this.newNotes = value; })
          Text('保存到分组').fontSize(12).fontColor(COLOR_MUTED).width('100%')
          Scroll() {
            Row({ space: 8 }) {
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
          Button('保存')
            .width('100%').height(50).fontWeight(FontWeight.Bold).fontColor(COLOR_BG)
            .backgroundColor(COLOR_PRIMARY).borderRadius(13)
            .onClick((): void => { this.createItem(); })
        }
        .width('100%')
        .padding(20)
      }
      .width('100%')
      .height('78%')
      .backgroundColor(COLOR_SURFACE)
      .borderRadius({ topLeft: 24, topRight: 24 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#99000000')
  }

  @Builder
  private newGroupOverlay(): void {
    Column() {
      Blank().onClick((): void => { this.showNewGroup = false; })
      Column({ space: 16 }) {
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
      .padding(20)
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
      Blank().onClick((): void => { this.selectedItem = undefined; })
      Scroll() {
        Column({ space: 14 }) {
          this.modalHeader('项目详情', (): void => { this.selectedItem = undefined; })
          Row({ space: 12 }) {
            Stack() { Text(itemTypeGlyph(item.type)).fontSize(22).fontColor(COLOR_PRIMARY) }
              .width(54).height(54).borderRadius(16).backgroundColor('#1B332C')
            Column({ space: 4 }) {
              Text(itemTypeLabel(item.type)).fontSize(13).fontColor(COLOR_PRIMARY)
              Text('敏感页面 · 已禁止截屏').fontSize(11).fontColor(COLOR_MUTED)
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
                .onClick((): void => { this.revealPassword = !this.revealPassword; })
            }
            .width('100%')
          }
          TextArea({ placeholder: '私密内容或备注', text: this.detailNotes })
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
