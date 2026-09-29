import { BackupStatusRecord } from '../models/VaultBackupModels';

const DAY_MS: number = 24 * 60 * 60 * 1000;

export function backupReminderDue(intervalDays: number, itemCount: number,
  status: BackupStatusRecord | undefined, dataRevision: number, now: number): boolean {
  if ((intervalDays !== 7 && intervalDays !== 30) || itemCount <= 0) { return false; }
  if (!status) { return true; }
  return dataRevision !== status.dataRevision && now - status.createdAt >= intervalDays * DAY_MS;
}

export function localBackupReminderDay(now: number): string {
  const date = new Date(now);
  const two = (value: number): string => value.toString().padStart(2, '0');
  return `${date.getFullYear()}-${two(date.getMonth() + 1)}-${two(date.getDate())}`;
}

export function shouldPresentBackupReminder(due: boolean, lastShownDay: string, now: number): boolean {
  return due && lastShownDay !== localBackupReminderDay(now);
}
