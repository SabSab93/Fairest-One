import { cancellation, checkActive, delay } from '../core/async';
import type { BleEvent, MirrorTransport } from '../core/types';

export function mirrorAddress(value: string) {
  const address = value.trim();
  const parts = address.split('.');
  if (parts.length !== 4 || parts.some(part => !/^(0|[1-9]\d{0,2})$/.test(part) || Number(part) > 255)) {
    throw new Error('Saisissez l’adresse IPv4 affichée dans le moniteur Arduino.');
  }
  const [a, b] = parts.map(Number);
  if (a !== 10 && !(a === 172 && b >= 16 && b <= 31) && !(a === 192 && b === 168)) {
    throw new Error('Utilisez une adresse IP privée sur le réseau du miroir.');
  }
  return address;
}

export class WifiMirror implements MirrorTransport {
  private base?: string;
  private polling?: AbortController;
  private token?: string;
  private listeners = new Set<(event: BleEvent | Error) => void>();

  constructor(private readonly address: () => string | Promise<string>, private readonly fetcher: typeof fetch = fetch) {}

  subscribe(listener: (event: BleEvent | Error) => void) {
    this.listeners.add(listener);
    return () => { this.listeners.delete(listener); };
  }

  private async request(path: string, body?: Record<string, unknown>, signal?: AbortSignal) {
    if (!this.base) throw new Error('Le miroir est déconnecté.');
    if (signal) checkActive(signal);
    const controller = new AbortController();
    const abort = () => controller.abort();
    signal?.addEventListener('abort', abort, { once: true });
    const timeout = setTimeout(abort, 2500);
    try {
      const response = await this.fetcher(this.base + path, {
        signal: controller.signal,
        redirect: 'error',
        ...(body ? { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) } : {}),
      });
      if (!response.ok) throw new Error('Le miroir est occupé ou la lecture a expiré. Réessayez.');
      return response.status === 204 ? '' : await response.text();
    } catch (error) {
      if (signal?.aborted) throw cancellation(signal);
      if (error instanceof Error && error.message.startsWith('Le miroir est occupé')) throw error;
      throw new Error('Miroir Wi-Fi inaccessible. Vérifiez le partage de connexion et l’adresse du miroir.');
    } finally {
      clearTimeout(timeout);
      signal?.removeEventListener('abort', abort);
    }
  }

  async connect(signal: AbortSignal) {
    this.base = 'http://' + mirrorAddress(await this.address());
    if (await this.request('/mirror/status', undefined, signal) !== 'fairest-one-wifi-v1') {
      throw new Error('Le programme Wi-Fi de Fairest One est introuvable sur le miroir.');
    }
  }

  async send(command: Record<string, unknown>, signal?: AbortSignal) {
    if (command.type === 'scan' && typeof command.token === 'string') {
      // Keep the token even if the response is lost so disconnect can cancel it.
      this.token = command.token;
      await this.request('/mirror/command', command, signal);
      const controller = new AbortController();
      this.polling?.abort();
      this.polling = controller;
      void this.poll(command.token, controller.signal);
      return;
    }
    // disconnect owns Wi-Fi cancellation so it can stop polling first.
    if (command.type === 'cancel') return;
    await this.request('/mirror/command', command, signal);
    if (command.type === 'capture_saved') this.token = undefined;
  }

  private async poll(token: string, signal: AbortSignal) {
    let last = '';
    try {
      while (!signal.aborted) {
        const body = await this.request('/mirror/event', { token }, signal);
        if (body && body !== last && !signal.aborted) {
          last = body;
          const event = JSON.parse(body) as BleEvent;
          if (event.token === token && typeof event.type === 'string') {
            if (event.type === 'card_result_applied' || event.type === 'error') this.token = undefined;
            for (const listener of this.listeners) listener(event);
          }
        }
        await delay(250, signal);
      }
    } catch (error) {
      if (!signal.aborted) {
        for (const listener of this.listeners) listener(error instanceof Error ? error : new Error('Connexion au miroir interrompue.'));
      }
    }
  }

  async disconnect() {
    this.polling?.abort();
    this.polling = undefined;
    const token = this.token;
    this.token = undefined;
    if (token) await this.request('/mirror/command', { type: 'cancel', token }).catch(() => {});
    this.base = undefined;
  }
}
