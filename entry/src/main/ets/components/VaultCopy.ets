export const ACTION_ADD: string = '添加';
export const ACTION_CANCEL: string = '取消';
export const ACTION_CLOSE: string = '关闭';
export const ACTION_DELETE: string = '删除';
export const ACTION_DOWNLOAD: string = '下载';
export const ACTION_ENABLE: string = '启用';
export const ACTION_MANAGE: string = '管理';
export const ACTION_PREVIEW: string = '预览';
export const ACTION_SAVE: string = '保存';
export const ACTION_SELECT: string = '选择';

export const LABEL_CONTENT: string = '内容';
export const LABEL_NAME: string = '名称';
export const LABEL_NOTES: string = '备注';
export const LABEL_READ_ONLY: string = '只读';

export const TITLE_ITEM_DETAILS: string = '资料详情';
export const TITLE_MEDIA: string = '媒体';
export const TITLE_FILES: string = '文件';

export function selectionAction(selectionMode: boolean): string {
  return selectionMode ? ACTION_CANCEL : ACTION_SELECT;
}

export function managementAction(managing: boolean): string {
  return managing ? ACTION_CANCEL : ACTION_MANAGE;
}
