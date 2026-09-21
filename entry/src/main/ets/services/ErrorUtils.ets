import { BusinessError } from '@ohos.base';

export function normalizeError(error: Object): Error {
  if (error instanceof Error) { return error; }
  const businessError = error as BusinessError;
  if (businessError.message && businessError.message.length > 0) {
    return new Error(businessError.code ? `${businessError.message}（${businessError.code}）` : businessError.message);
  }
  const text = `${error}`;
  return new Error(text.length > 0 && text !== '[object Object]' ? text : '操作失败');
}

export function logRecoverableError(operation: string, error: Object): void {
  console.warn(`PalmVault ${operation}: ${normalizeError(error).message}`);
}
