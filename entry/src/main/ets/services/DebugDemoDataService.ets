import fs from '@ohos.file.fs';
import common from '@ohos.app.ability.common';
import { DEBUG } from 'BuildProfile';
import { AbilityContextHolder } from './AbilityContextHolder';
import { logRecoverableError, normalizeError } from './ErrorUtils';
import { vaultRepository } from './VaultRepository';
import {
  VaultAttachmentInput,
  VaultGroup,
  VaultItem,
  VaultItemInput,
  VaultItemType
} from '../models/VaultModels';

const DEMO_RESOURCE_ROOT: string = 'palmkeep_demo/';

interface DemoGroupSpec {
  name: string;
  color: string;
}

interface DemoAttachmentSpec {
  resourceName: string;
  fileName: string;
  type: VaultItemType;
  ocrText: string;
}

interface DemoItemSpec {
  type: VaultItemType;
  groupName: string;
  title: string;
  username: string;
  password: string;
  website: string;
  notes: string;
  attachments: DemoAttachmentSpec[];
}

export interface DebugDemoDataResult {
  createdGroupCount: number;
  skippedGroupCount: number;
  createdItemCount: number;
  updatedItemCount: number;
  skippedItemCount: number;
}

const DEMO_GROUPS: DemoGroupSpec[] = [
  { name: '工作项目', color: '#75D7FF' },
  { name: '旅行收藏', color: '#67E8C5' },
  { name: '证件票据', color: '#F3C969' },
  { name: '家庭资料', color: '#F59E9E' }
];

const DEMO_ITEMS: DemoItemSpec[] = [
  {
    type: VaultItemType.Login,
    groupName: '工作项目',
    title: '设计协作平台',
    username: 'palmkeep.demo@example.com',
    password: 'Demo-2026-Safe',
    website: 'https://example.com/workspace',
    notes: '商店截图演示账号，不对应任何真实服务。',
    attachments: []
  },
  {
    type: VaultItemType.Note,
    groupName: '家庭资料',
    title: '新家装修计划',
    username: '',
    password: '',
    website: '',
    notes: '本周确认照明方案，下周复核收纳尺寸。\n客厅保持明亮，书房优先考虑安静和实用。',
    attachments: []
  },
  {
    type: VaultItemType.Image,
    groupName: '旅行收藏',
    title: '旅途与生活照片',
    username: '',
    password: '',
    website: '',
    notes: '适合放进年度相册的照片。',
    attachments: [
      { resourceName: 'home-office.png', fileName: '清晨书桌.png', type: VaultItemType.Image,
        ocrText: '清晨工作记录' },
      { resourceName: 'home-renovation.png', fileName: '装修选材.png', type: VaultItemType.Image,
        ocrText: '新家装修\n材料色卡\n尺寸测量' },
      { resourceName: 'mountain-trip.png', fileName: '湖畔日出.png', type: VaultItemType.Image,
        ocrText: '旅行计划\n湖畔日出\n雪山摄影' }
    ]
  },
  {
    type: VaultItemType.Video,
    groupName: '旅行收藏',
    title: '周末旅行视频',
    username: '',
    password: '',
    website: '',
    notes: '保存值得回看的旅途片段。',
    attachments: [
      { resourceName: 'trip-memory.mp4', fileName: '湖边散步.mp4', type: VaultItemType.Video, ocrText: '' },
      { resourceName: 'weekend-walk.mp4', fileName: '周末漫步.mp4', type: VaultItemType.Video, ocrText: '' }
    ]
  },
  {
    type: VaultItemType.Audio,
    groupName: '工作项目',
    title: '产品例会录音',
    username: '',
    password: '',
    website: '',
    notes: '三段录音分别对应开场、讨论和总结。',
    attachments: [
      { resourceName: 'meeting-opening.wav', fileName: '会议开场.wav', type: VaultItemType.Audio, ocrText: '' },
      { resourceName: 'meeting-notes.wav', fileName: '方案讨论.wav', type: VaultItemType.Audio, ocrText: '' },
      { resourceName: 'meeting-summary.wav', fileName: '会议总结.wav', type: VaultItemType.Audio, ocrText: '' }
    ]
  },
  {
    type: VaultItemType.File,
    groupName: '证件票据',
    title: '装修合同与预算',
    username: '',
    password: '',
    website: '',
    notes: '合同、预算与采购清单集中保存。',
    attachments: [
      { resourceName: 'renovation-contract.txt', fileName: '装修合同摘要.txt', type: VaultItemType.File, ocrText: '' },
      { resourceName: 'renovation-budget.csv', fileName: '装修预算.csv', type: VaultItemType.File, ocrText: '' },
      { resourceName: 'purchase-list.md', fileName: '材料采购清单.md', type: VaultItemType.File, ocrText: '' }
    ]
  }
];

class DebugDemoDataService {
  private temporarySequence: number = 0;

  async generate(): Promise<DebugDemoDataResult> {
    if (!DEBUG) { throw new Error('示例数据只能在 Debug 版本中生成'); }
    const groups = await vaultRepository.listGroups();
    const groupByName = new Map<string, VaultGroup>();
    groups.forEach((group: VaultGroup): void => { groupByName.set(group.name.trim(), group); });
    let createdGroupCount = 0;
    let skippedGroupCount = 0;
    for (let index = 0; index < DEMO_GROUPS.length; index += 1) {
      const spec = DEMO_GROUPS[index];
      if (groupByName.has(spec.name)) {
        skippedGroupCount += 1;
        continue;
      }
      const id = await vaultRepository.createGroup(spec.name, spec.color);
      groupByName.set(spec.name, { id: id, name: spec.name, color: spec.color, createdAt: Date.now() });
      createdGroupCount += 1;
    }

    const existingItems = await vaultRepository.listItems();
    const existingByKey = new Map<string, VaultItem>();
    existingItems.forEach((item: VaultItem): void => {
      existingByKey.set(this.itemKey(item.type, item.title), item);
    });
    let createdItemCount = 0;
    let updatedItemCount = 0;
    let skippedItemCount = 0;
    for (let index = 0; index < DEMO_ITEMS.length; index += 1) {
      const spec = DEMO_ITEMS[index];
      const key = this.itemKey(spec.type, spec.title);
      const existing = existingByKey.get(key);
      if (existing) {
        if (await this.refreshLegacyImageDemo(existing, spec)) {
          updatedItemCount += 1;
          continue;
        }
        skippedItemCount += 1;
        continue;
      }
      const group = groupByName.get(spec.groupName);
      if (!group) { throw new Error(`无法创建示例资料：缺少分组 ${spec.groupName}`); }
      await this.createItem(spec, group.id);
      createdItemCount += 1;
    }
    return {
      createdGroupCount: createdGroupCount,
      skippedGroupCount: skippedGroupCount,
      createdItemCount: createdItemCount,
      updatedItemCount: updatedItemCount,
      skippedItemCount: skippedItemCount
    };
  }

  private async refreshLegacyImageDemo(existing: VaultItem, spec: DemoItemSpec): Promise<boolean> {
    if (spec.type !== VaultItemType.Image || spec.title !== '旅途与生活照片' ||
      existing.notes !== spec.notes || spec.attachments.length === 0) {
      return false;
    }
    const current = await vaultRepository.listItemAttachments(existing.id);
    if (current.length !== spec.attachments.length) { return false; }
    let needsRefresh = false;
    for (let index = 0; index < spec.attachments.length; index += 1) {
      if (current[index].name !== spec.attachments[index].fileName) { return false; }
      if (current[index].ocrText !== spec.attachments[index].ocrText) { needsRefresh = true; }
    }
    if (!needsRefresh) { return false; }
    await this.replaceAttachments(existing.id, spec.attachments);
    return true;
  }

  private async replaceAttachments(itemId: string, specs: DemoAttachmentSpec[]): Promise<void> {
    const paths: string[] = [];
    const attachments: VaultAttachmentInput[] = [];
    try {
      for (let index = 0; index < specs.length; index += 1) {
        const spec = specs[index];
        const path = await this.copyRawFileToCache(spec.resourceName);
        paths.push(path);
        attachments.push({
          type: spec.type,
          uri: path,
          sourceUri: '',
          name: spec.fileName,
          ocrText: spec.ocrText
        });
      }
      await vaultRepository.replaceItemAttachments(itemId, attachments);
    } finally {
      paths.forEach((path: string): void => { this.removeTemporary(path); });
    }
  }

  private async createItem(spec: DemoItemSpec, groupId: number): Promise<void> {
    const input: VaultItemInput = {
      type: spec.type,
      groupId: groupId,
      title: spec.title,
      username: spec.username,
      password: spec.password,
      website: spec.website,
      notes: spec.notes
    };
    if (spec.attachments.length === 0) {
      await vaultRepository.createItem(input);
      return;
    }
    const paths: string[] = [];
    const attachments: VaultAttachmentInput[] = [];
    try {
      for (let index = 0; index < spec.attachments.length; index += 1) {
        const attachment = spec.attachments[index];
        const path = await this.copyRawFileToCache(attachment.resourceName);
        paths.push(path);
        attachments.push({
          type: attachment.type,
          uri: path,
          sourceUri: '',
          name: attachment.fileName,
          ocrText: attachment.ocrText
        });
      }
      await vaultRepository.createItemWithAttachments(input, attachments);
    } finally {
      paths.forEach((path: string): void => { this.removeTemporary(path); });
    }
  }

  private async copyRawFileToCache(resourceName: string): Promise<string> {
    const context: common.UIAbilityContext = AbilityContextHolder.getContext();
    let data: Uint8Array;
    try {
      data = await context.resourceManager.getRawFileContent(`${DEMO_RESOURCE_ROOT}${resourceName}`);
    } catch (error) {
      throw normalizeError(error);
    }
    const extensionIndex = resourceName.lastIndexOf('.');
    const extension = extensionIndex >= 0 ? resourceName.substring(extensionIndex) : '';
    const path = `${context.cacheDir}/pv-debug-demo-${Date.now()}-${this.temporarySequence++}${extension}`;
    let file: fs.File | undefined = undefined;
    try {
      file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      const written = fs.writeSync(file.fd, data.buffer as ArrayBuffer, { length: data.length });
      fs.fsyncSync(file.fd);
      if (written !== data.length) { throw new Error('示例附件写入不完整'); }
      return path;
    } catch (error) {
      this.removeTemporary(path);
      throw normalizeError(error);
    } finally {
      if (file) {
        try { fs.closeSync(file); }
        catch (error) { logRecoverableError('could not close debug demo attachment', error); }
      }
    }
  }

  private removeTemporary(path: string): void {
    try {
      if (fs.accessSync(path)) { fs.unlinkSync(path); }
    } catch (error) {
      logRecoverableError('could not remove debug demo attachment', error);
    }
  }

  private itemKey(type: VaultItemType, title: string): string {
    return `${type}|${title.trim()}`;
  }
}

export const debugDemoDataService = new DebugDemoDataService();
