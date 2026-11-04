export class Cancelled extends Error {
  constructor() { super('Lecture annulée.'); this.name = 'Cancelled'; }
}
export function checkActive(signal: AbortSignal) {
  if (signal.aborted) throw new Cancelled();
}
export function wait<T>(task: Promise<T>, signal: AbortSignal, ms: number, message: string): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    let timer: ReturnType<typeof setTimeout>;
    const abort = () => finish(() => reject(new Cancelled()));
    const finish = (callback: () => void) => {
      clearTimeout(timer);
      signal.removeEventListener('abort', abort);
      callback();
    };
    timer = setTimeout(() => finish(() => reject(new Error(message))), ms);
    signal.addEventListener('abort', abort, { once: true });
    task.then(value => finish(() => resolve(value)), error => finish(() => reject(error)));
    if (signal.aborted) abort();
  });
}
export function delay(ms: number, signal: AbortSignal): Promise<void> {
  return new Promise((resolve, reject) => {
    const abort = () => { clearTimeout(timer); reject(new Cancelled()); };
    const timer = setTimeout(() => { signal.removeEventListener('abort', abort); resolve(); }, ms);
    signal.addEventListener('abort', abort, { once: true });
    if (signal.aborted) abort();
  });
}
export function normalizeUid(value: unknown): string {
  if (typeof value !== 'string') throw new Error('Identifiant de carte absent.');
  const uid = value.trim().replace(/[:\s-]/g, '').toUpperCase();
  if (!/^(?:[0-9A-F]{8}|[0-9A-F]{14}|[0-9A-F]{20})$/.test(uid)) {
    throw new Error('Cette carte ne fournit pas un identifiant compatible avec le miroir.');
  }
  return uid;
}
export function errorMessage(error: unknown) {
  return error instanceof Error ? error.message : 'Lecture interrompue. Vérifiez Bluetooth et Internet puis réessayez.';
}
