import type { Api, ClientRecord, FlowResult } from './types';
import { cancellation, checkActive } from './async';

export class ApiError extends Error {
  constructor(message: string, public readonly status: number) { super(message); this.name = 'ApiError'; }
}
export function apiBase(value: string | undefined): string {
  if (!value) throw new ApiError('Le service de cette version de test n’est pas encore configuré.', 0);
  let url: URL;
  try { url = new URL(value); } catch { throw new ApiError('Adresse du service invalide.', 0); }
  if (url.protocol !== 'https:' || url.username || url.password || url.search || url.hash || !url.pathname.endsWith('/api/')) {
    throw new ApiError('Le service doit utiliser une adresse HTTPS terminée par /api/.', 0);
  }
  return url.toString();
}
export function clientRecord(value: unknown): ClientRecord {
  if (!value || typeof value !== 'object') throw new ApiError('Réponse client invalide.', 502);
  const row = value as Record<string, unknown>;
  if (typeof row.id !== 'string' || typeof row.email !== 'string' || typeof row.created_at !== 'string') {
    throw new ApiError('Réponse client incomplète.', 502);
  }
  return { id: row.id, email: row.email, created_at: row.created_at,
    card_uid: typeof row.card_uid === 'string' ? row.card_uid : null,
    photo_count: typeof row.photo_count === 'number' ? row.photo_count : 0,
    messages: Array.isArray(row.messages) ? row.messages.filter((v): v is string => typeof v === 'string') : [],
  };
}
export class ApiClient implements Api {
  constructor(private readonly base: () => string | undefined, private readonly fetcher: typeof fetch = fetch, private readonly timeout = 10000) {}
  private async request(method: 'GET' | 'POST', body?: Record<string, unknown>, signal?: AbortSignal, password?: string): Promise<unknown> {
    const endpoint = new URL('clients', apiBase(this.base())).toString();
    if (signal) checkActive(signal);
    const controller = new AbortController();
    let timedOut = false;
    const abort = () => controller.abort();
    signal?.addEventListener('abort', abort, { once: true });
    const timer = setTimeout(() => { timedOut = true; controller.abort(); }, this.timeout);
    try {
      const response = await this.fetcher(endpoint, { method, signal: controller.signal,
        headers: { 'Content-Type': 'application/json', ...(password ? { 'X-Admin-Password': password } : {}) },
        ...(body ? { body: JSON.stringify(body) } : {}),
      });
      let data: unknown;
      try { data = await response.json(); } catch { throw new ApiError('Le service a renvoyé une réponse illisible.', 502); }
      if (!response.ok) {
        const message = data && typeof data === 'object' && 'error' in data && typeof data.error === 'string'
          ? data.error : 'Impossible de joindre le service.';
        throw new ApiError(message, response.status);
      }
      return data;
    } catch (error) {
      if (signal?.aborted) throw cancellation(signal);
      if (timedOut) throw new ApiError('Délai dépassé. Vérifiez Internet puis relancez la lecture.', 0);
      if (error instanceof ApiError) throw error;
      throw new ApiError('Connexion au service impossible. Vérifiez Internet puis réessayez.', 0);
    } finally {
      clearTimeout(timer);
      signal?.removeEventListener('abort', abort);
    }
  }
  async post(body: Record<string, unknown>, signal?: AbortSignal): Promise<FlowResult> {
    const data = await this.request('POST', body, signal);
    if (!data || typeof data !== 'object' || !('state' in data) || typeof data.state !== 'string') {
      throw new ApiError('Réponse du service NFC invalide.', 502);
    }
    const result = data as FlowResult;
    return result.client ? { ...result, client: clientRecord(result.client) } : result;
  }
  async clients(password: string, signal?: AbortSignal): Promise<ClientRecord[]> {
    const rows = await this.request('GET', undefined, signal, password);
    if (!Array.isArray(rows)) throw new ApiError('Liste des clients invalide.', 502);
    return rows.map(clientRecord);
  }
}
