import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Buffer } from 'buffer';
import { PhoneFlow } from '../src/core/phone';
import { MirrorFlow } from '../src/core/mirror';
import { ApiClient, ApiError, apiBase } from '../src/core/api';
import { BleFrames, commandFrames } from '../src/core/ble-protocol';
import { Cancelled, normalizeUid, wait } from '../src/core/async';
import type { AccessStore, Api, BleEvent, FlowResult, MirrorTransport } from '../src/core/types';
const token = 'a'.repeat(64), proof = 'b'.repeat(64), uid = '04DE3A36D62A81';
const client = { id: 'one', email: 'a@example.fr', card_uid: uid, created_at: '2026-11-04', photo_count: 1, messages: ['Capture simulée'] };
function access(initial: string | null = null): AccessStore {
  let value = initial;
  return { read: async () => value, save: async next => { value = next; }, generate: async () => 'c'.repeat(64) };
}
function mockApi(handle: (body: Record<string, unknown>) => FlowResult | Promise<FlowResult>): Api {
  return { post: async body => handle(body), clients: async () => [] };
}
test('inscription : UID normalisé et accès conservé avant association', async () => {
  const store = access(), calls: Record<string, unknown>[] = [];
  const api = mockApi(async body => {
    assert.equal(await store.read(), body.mobile_token);
    calls.push(body);
    return body.action === 'begin_phone_registration' ? { state: 'pending', token } : { state: 'associated' };
  });
  const flow = new PhoneFlow(api, { readUid: async () => '04:de:3a:36:d6:2a:81' }, store);
  assert.equal((await flow.read('registration', ' A@EXAMPLE.FR ')).uid, uid);
  assert.equal(calls[0].email, 'a@example.fr'); assert.equal(calls[1].card_uid, uid);
  assert.equal(flow.getSnapshot().stage, 'saved');
});
test('récupération avec le même accès : messages de la session', async () => {
  const flow = new PhoneFlow(mockApi(body => body.action === 'begin_phone_recovery' ? { state: 'pending', token } : { state: 'recovered', client }), { readUid: async () => uid }, access(token));
  assert.deepEqual((await flow.read('recovery')).client?.messages, ['Capture simulée']);
});
test('un autre téléphone sans accès ne récupère rien et ne contacte pas le backend', async () => {
  let calls = 0;
  const flow = new PhoneFlow(mockApi(() => { calls++; return { state: 'recovered', client }; }), { readUid: async () => uid }, access());
  await assert.rejects(flow.read('recovery'), /téléphone/); assert.equal(calls, 0);
});
test('erreur de sauvegarde sécurisée : aucune inscription envoyée', async () => {
  let calls = 0;
  const store = access(); store.save = async () => { throw new Error('Stockage inaccessible'); };
  const flow = new PhoneFlow(mockApi(() => { calls++; return { state: 'associated' }; }), { readUid: async () => uid }, store);
  await assert.rejects(flow.read('registration', 'a@example.fr')); assert.equal(calls, 0);
});
test('carte déjà affectée : erreur lisible et pas de succès', async () => {
  const flow = new PhoneFlow(mockApi(b => b.action === 'begin_phone_registration' ? { state: 'pending', token } : { state: 'failed', code: 'card_already_assigned' }), { readUid: async () => uid }, access());
  await assert.rejects(flow.read('registration', 'a@example.fr'), /déjà associée/);
  assert.equal(flow.getSnapshot().stage, 'error');
});
test('annulation de lecture et refus des lectures simultanées', async () => {
  let calls = 0;
  const flow = new PhoneFlow(mockApi(() => { calls++; return { state: 'pending', token }; }), { readUid: s => wait(new Promise(() => {}), s, 1000, 'timeout') }, access());
  const pending = flow.read('registration', 'a@example.fr');
  await assert.rejects(flow.read('registration', 'a@example.fr'), /déjà/);
  flow.stop(); await assert.rejects(pending, Cancelled); assert.equal(calls, 0);
});
test('trames BLE fragmentées et UTF-8 reconstituées, événements non corrélés ignorés', () => {
  const frames = new BleFrames();
  const input = { type: 'error', token, code: 'échec' };
  const chunks = commandFrames(input);
  assert(chunks.every(c => Buffer.from(c, 'base64').length <= 20));
  assert.deepEqual(chunks.flatMap(c => frames.add(c)), [input]);
  assert.deepEqual(frames.add(Buffer.from('{"type":"card_scanned","uid":"12345678"}\n').toString('base64')), []);
});
class Ble implements MirrorTransport {
  listener?: (event: BleEvent | Error) => void;
  sent: Record<string, unknown>[] = [];
  disconnected = false;
  onSend?: (c: Record<string, unknown>) => void;
  async connect() {}
  async send(c: Record<string, unknown>) { this.sent.push(c); this.onSend?.(c); }
  subscribe(l: (event: BleEvent | Error) => void) { this.listener = l; return () => { this.listener = undefined; }; }
  async disconnect() { this.disconnected = true; }
}
test('capture : refus si backend indisponible, jamais de commande positive', async () => {
  const ble = new Ble(); ble.onSend = c => { if (c.type === 'scan') ble.listener?.({ type: 'card_scanned', token, uid, proof }); };
  const flow = new MirrorFlow(mockApi(b => { if (b.action === 'begin_recognition') return { state: 'pending', token }; if (b.action === 'cancel') return { state: 'cancelled' }; throw new ApiError('Indisponible', 503); }), ble);
  await assert.rejects(flow.start());
  assert(!ble.sent.some(c => c.recognized === true)); assert(ble.disconnected);
});
test('capture signée autorisée, enregistrée puis accusée, répétition réseau idempotente', async () => {
  const ble = new Ble(); let saves = 0; let flow: MirrorFlow;
  ble.onSend = c => {
    if (c.type === 'scan') ble.listener?.({ type: 'card_scanned', token, uid, proof });
    if (c.type === 'card_result' && c.recognized === true) ble.listener?.({ type: 'capture_simulated', token, uid, proof });
    if (c.type === 'capture_saved') flow.stop();
  };
  flow = new MirrorFlow(mockApi(b => {
    if (b.action === 'begin_recognition') return { state: 'pending', token };
    if (b.action === 'scan') return { state: 'recognized' };
    if (b.action === 'capture') { saves++; if (saves === 1) throw new ApiError('timeout', 0); return { state: 'captured' }; }
    return { state: 'cancelled' };
  }), ble);
  await assert.rejects(flow.start(), Cancelled);
  assert.equal(saves, 2); assert.equal(ble.sent.filter(c => c.type === 'capture_saved').length, 1); assert(ble.disconnected);
});
test('carte inconnue : commande rouge sans capture', async () => {
  const ble = new Ble(); let flow: MirrorFlow;
  ble.onSend = c => { if (c.type === 'scan') ble.listener?.({ type: 'card_scanned', token, uid, proof }); if (c.type === 'card_result') flow.stop(); };
  flow = new MirrorFlow(mockApi(b => b.action === 'begin_recognition' ? { state: 'pending', token } : { state: 'unknown' }), ble);
  await assert.rejects(flow.start(), Cancelled);
  assert(ble.sent.some(c => c.recognized === false && c.capture === false));
  assert(!ble.sent.some(c => c.type === 'capture_saved'));
});
test('déconnexion ou absence de réponse : abandon sans capture', async () => {
  for (const disconnected of [true, false]) {
    const ble = new Ble(); ble.onSend = c => { if (c.type === 'scan' && disconnected) ble.listener?.(new Error('Déconnecté')); };
    const flow = new MirrorFlow(mockApi(() => ({ state: 'pending', token })), ble, 10);
    await assert.rejects(flow.start(), disconnected ? /Déconnecté/ : /ne répond pas/);
    assert(!ble.sent.some(c => c.recognized === true)); assert(ble.disconnected);
  }
});
test('transport HTTP : pas de clé admin sur les opérations personnelles', async () => {
  let headers: HeadersInit | undefined;
  const fetcher: typeof fetch = async (_url, init) => { headers = init?.headers; return new Response(JSON.stringify({ state: 'pending', token }), { status: 200 }); };
  const api = new ApiClient(() => 'https://test.example/api/', fetcher);
  await api.post({ action: 'begin_phone_recovery', mobile_token: token });
  assert.equal(new Headers(headers).get('X-Admin-Password'), null);
  assert.throws(() => apiBase('http://test.example/api/'));
  assert.throws(() => normalizeUid('undefined'));
  assert.equal(normalizeUid('00-01-02-03'), '00010203');
});
test('réponse backend incorrecte et refus backend sont des erreurs', async () => {
  const bad = new ApiClient(() => 'https://test.example/api/', async () => new Response('{}'));
  await assert.rejects(bad.post({}), /invalide/);
  const denied = new ApiClient(() => 'https://test.example/api/', async () => new Response('{"error":"Accès refusé"}', { status: 403 }));
  await assert.rejects(denied.post({}), /Accès refusé/);
});
