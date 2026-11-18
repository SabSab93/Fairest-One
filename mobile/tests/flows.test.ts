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
const client = { id: 'one', email: 'a@example.fr', card_uid: uid, created_at: '2026-11-04', photo_count: 1, messages: [], photos: [{ id: 'photo', created_at: '2026-11-04', url: 'https://example.test/essayage.jpg' }] };
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
  assert.deepEqual((await flow.read('recovery')).client?.photos, client.photos);
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
  async send(c: Record<string, unknown>) {
    this.sent.push(c); this.onSend?.(c);
    if (c.type === 'card_result' && c.capture === false) {
      this.listener?.({ type: 'card_result_applied', token: String(c.token) });
    }
  }
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
    if (c.type === 'card_result' && c.recognized === true) ble.listener?.({ type: 'photo_captured', token, uid, proof });
    if (c.type === 'capture_saved') flow.stop();
  };
  flow = new MirrorFlow(mockApi(b => {
    if (b.action === 'begin_recognition') return { state: 'pending', token };
    if (b.action === 'scan') return { state: 'recognized' };
    if (b.action === 'capture_status') { saves++; if (saves === 1) throw new ApiError('timeout', 0); return { state: 'captured' }; }
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
test('la récupération HTTP transmet les vraies photos signées à la galerie', async () => {
  const api = new ApiClient(() => 'https://test.example/api/', async () => Response.json({
    state: 'recovered',
    client: { ...client, photos: [...client.photos, { ...client.photos[0], url: 'http://test.example/photo.jpg' }, null] },
  }));
  const result = await api.post({ action: 'scan', token, card_uid: uid, proof });
  assert.equal(result.state, 'recovered');
  assert.deepEqual(result.client?.photos, client.photos);
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

test('interruption en arrière-plan : raison conservée, aucune inscription envoyée', async () => {
  let calls = 0;
  const flow = new PhoneFlow(mockApi(() => { calls++; return { state: 'associated' }; }), {
    readUid: signal => wait(new Promise(() => {}), signal, 1000, 'timeout'),
  }, access());
  const reading = flow.read('registration', 'a@example.fr');
  flow.stop('Lecture interrompue : l’application est passée en arrière-plan.');
  await assert.rejects(reading, /arrière-plan/);
  assert.equal(calls, 0);
  assert.equal(flow.getSnapshot().message, 'Lecture interrompue : l’application est passée en arrière-plan.');
  assert.equal(flow.getSnapshot().busy, false);
});

test('arrêt explicite : le message reste Lecture annulée', async () => {
  const flow = new PhoneFlow(mockApi(() => ({ state: 'associated' })), {
    readUid: signal => wait(new Promise(() => {}), signal, 1000, 'timeout'),
  }, access());
  const reading = flow.read('registration', 'a@example.fr');
  flow.stop();
  await assert.rejects(reading, /Lecture annulée/);
});

test('iOS miroir : inscription signée avec e-mail, sans commande de capture', async () => {
  const ble = new Ble(), calls: Record<string, unknown>[] = [];
  ble.onSend = command => { if (command.type === 'scan') ble.listener?.({ type: 'card_scanned', token, uid, proof }); };
  const flow = new MirrorFlow(mockApi(body => {
    calls.push(body);
    return body.action === 'begin_registration' ? { state: 'pending', token } : { state: 'associated' };
  }), ble);
  assert.equal((await flow.read('registration', ' A@EXAMPLE.FR ')).uid, uid);
  assert.equal(calls[0].email, 'a@example.fr');
  assert.deepEqual(calls[1], { action: 'scan', token, card_uid: uid, proof });
  assert(ble.sent.some(c => c.type === 'card_result' && c.recognized === true && c.capture === false));
  assert(!ble.sent.some(c => c.capture === true)); assert(ble.disconnected);
});

test('iOS miroir : récupération signée et affichage des messages existants', async () => {
  const ble = new Ble();
  ble.onSend = command => { if (command.type === 'scan') ble.listener?.({ type: 'card_scanned', token, uid, proof }); };
  const flow = new MirrorFlow(mockApi(b => b.action === 'begin_recovery' ? { state: 'pending', token } : { state: 'recovered', client }), ble);
  assert.deepEqual((await flow.read('recovery')).client?.photos, client.photos);
  assert(!ble.sent.some(c => c.capture === true)); assert(ble.disconnected);
});

test('iOS miroir : preuve absente ou événement d’un autre défi refusé avant envoi de l’UID', async () => {
  for (const wrongToken of [false, true]) {
    const ble = new Ble(), calls: Record<string, unknown>[] = [];
    ble.onSend = c => { if (c.type === 'scan') ble.listener?.({ type: 'card_scanned', token: wrongToken ? 'd'.repeat(64) : token, uid }); };
    const flow = new MirrorFlow(mockApi(body => { calls.push(body); return { state: 'pending', token }; }), ble, 10);
    await assert.rejects(flow.read('registration', 'a@example.fr'), wrongToken ? /ne répond pas/ : /non signée/);
    assert(!calls.some(c => c.action === 'scan')); assert(!ble.sent.some(c => c.recognized === true));
  }
});

test('iOS miroir : erreur backend, aucune confirmation positive et déconnexion', async () => {
  const ble = new Ble();
  ble.onSend = c => { if (c.type === 'scan') ble.listener?.({ type: 'card_scanned', token, uid, proof }); };
  const flow = new MirrorFlow(mockApi(b => {
    if (b.action === 'begin_registration') return { state: 'pending', token };
    if (b.action === 'cancel') return { state: 'cancelled' };
    throw new ApiError('Service indisponible', 503);
  }), ble);
  await assert.rejects(flow.read('registration', 'a@example.fr'), /indisponible/);
  assert(!ble.sent.some(c => c.recognized === true)); assert(ble.disconnected);
});

test('iOS miroir : récupération inconnue refusée sans capture', async () => {
  const ble = new Ble();
  ble.onSend = c => { if (c.type === 'scan') ble.listener?.({ type: 'card_scanned', token, uid, proof }); };
  const flow = new MirrorFlow(mockApi(b => b.action === 'begin_recovery' ? { state: 'pending', token } : { state: 'unknown' }), ble);
  await assert.rejects(flow.read('recovery'), /pas enregistrée/);
  assert(ble.sent.some(c => c.recognized === false && c.capture === false));
});

test('iOS miroir : une lecture exclut les autres lectures et les essayages simultanés', async () => {
  const ble = new Ble();
  const flow = new MirrorFlow(mockApi(() => ({ state: 'pending', token })), ble);
  const first = flow.read('registration', 'a@example.fr');
  await assert.rejects(flow.read('recovery'), /déjà/);
  await assert.rejects(flow.start(), /déjà/);
  flow.stop(); await assert.rejects(first, Cancelled); assert(ble.disconnected);
});

test('iOS miroir : perte de l’accusé BLE après association, succès backend conservé', async () => {
  const ble = new Ble();
  ble.send = async c => {
    ble.sent.push(c);
    if (c.type === 'scan') ble.listener?.({ type: 'card_scanned', token, uid, proof });
    if (c.type === 'card_result') throw new Error('Déconnexion');
  };
  const flow = new MirrorFlow(mockApi(b => b.action === 'begin_registration' ? { state: 'pending', token } : { state: 'associated' }), ble);
  assert.equal((await flow.read('registration', 'a@example.fr')).state, 'associated');
  assert.equal(flow.getSnapshot().stage, 'saved');
  assert(!ble.sent.some(c => c.capture === true));
});

test('iPhone : attendre les LED et bips du firmware avant de déconnecter', async () => {
  for (const registration of [true, false]) {
    const ble = new Ble();
    let commandReceived!: () => void;
    const ready = new Promise<void>(resolve => { commandReceived = resolve; });
    ble.send = async c => {
      ble.sent.push(c);
      if (c.type === 'scan') ble.listener?.({ type: 'card_scanned', token, uid, proof });
      if (c.type === 'card_result') commandReceived();
    };
    const flow = new MirrorFlow(mockApi(body => String(body.action).startsWith('begin_')
      ? { state: 'pending', token }
      : { state: registration ? 'associated' : 'unknown' }), ble);
    const pending = registration ? flow.read('registration', 'a@example.fr') : flow.tryOn();
    await ready;
    assert.equal(ble.disconnected, false);
    assert.equal(flow.getSnapshot().busy, true);
    ble.listener?.({ type: 'card_result_applied', token: 'd'.repeat(64) });
    assert.equal(ble.disconnected, false);
    ble.listener?.({ type: 'card_result_applied', token });
    await pending;
    assert(ble.disconnected);
  }
});

test('iPhone : un bouton déclenche un seul essayage et libère le lecteur', async () => {
  const ble = new Ble(), calls: Record<string, unknown>[] = [];
  ble.onSend = c => {
    if (c.type === 'scan') ble.listener?.({ type: 'card_scanned', token, uid, proof });
    if (c.type === 'card_result' && c.capture === true) ble.listener?.({ type: 'photo_captured', token, uid, proof });
  };
  const flow = new MirrorFlow(mockApi(body => {
    calls.push(body);
    if (body.action === 'begin_recognition') return { state: 'pending', token };
    return { state: body.action === 'scan' ? 'recognized' : 'captured' };
  }), ble);
  assert.equal((await flow.tryOn()).state, 'captured');
  assert.equal(calls.filter(c => c.action === 'begin_recognition').length, 1);
  assert.equal(calls.filter(c => c.action === 'capture_status').length, 1);
  assert.equal(flow.getSnapshot().busy, false);
  assert.equal(flow.getSnapshot().stage, 'saved');
  assert(ble.disconnected);
  await flow.tryOn();
  assert.equal(calls.filter(c => c.action === 'capture_status').length, 2);
});

test('iPhone : une carte inconnue termine l’essayage sans capture', async () => {
  const ble = new Ble(), calls: Record<string, unknown>[] = [];
  ble.onSend = c => { if (c.type === 'scan') ble.listener?.({ type: 'card_scanned', token, uid, proof }); };
  const flow = new MirrorFlow(mockApi(body => {
    calls.push(body);
    return body.action === 'begin_recognition' ? { state: 'pending', token } : { state: 'unknown' };
  }), ble);
  assert.equal((await flow.tryOn()).state, 'unknown');
  assert.equal(flow.getSnapshot().stage, 'error');
  assert(!calls.some(c => c.action === 'capture_status'));
  assert(!ble.sent.some(c => c.capture === true));
  assert(ble.disconnected);
});

test('iPhone : capture sauvegardée puis accusé BLE perdu, succès conservé sans annulation', async () => {
  // Both the guided iPhone flow and the existing continuous mode must stop
  // cleanly without creating another challenge after the connection is lost.
  for (const continuous of [false, true]) {
    const ble = new Ble(), calls: Record<string, unknown>[] = [];
    ble.send = async c => {
      ble.sent.push(c);
      if (c.type === 'scan') ble.listener?.({ type: 'card_scanned', token, uid, proof });
      if (c.type === 'card_result') ble.listener?.({ type: 'photo_captured', token, uid, proof });
      if (c.type === 'capture_saved') throw new Error('Déconnexion');
    };
    const flow = new MirrorFlow(mockApi(body => {
      calls.push(body);
      if (body.action === 'begin_recognition') return { state: 'pending', token };
      return { state: body.action === 'scan' ? 'recognized' : 'captured' };
    }), ble);
    if (continuous) await flow.start();
    else assert.equal((await flow.tryOn()).state, 'captured');
    assert.equal(flow.getSnapshot().stage, 'saved');
    assert.match(flow.getSnapshot().message, /enregistrée.*interrompue/);
    assert.equal(calls.filter(c => c.action === 'capture_status').length, 1);
    assert.equal(calls.filter(c => c.action === 'begin_recognition').length, 1);
    assert(!calls.some(c => c.action === 'cancel'));
    assert(!ble.sent.some(c => c.type === 'cancel'));
    assert(ble.disconnected);
  }
});

test('iPhone : annuler le compte à rebours interdit la sauvegarde et libère le lecteur', async () => {
  const ble = new Ble(), calls: Record<string, unknown>[] = [];
  let flow: MirrorFlow;
  ble.onSend = c => {
    if (c.type === 'scan') ble.listener?.({ type: 'card_scanned', token, uid, proof });
    if (c.type === 'card_result' && c.capture === true) flow.stop();
  };
  flow = new MirrorFlow(mockApi(body => {
    calls.push(body);
    if (body.action === 'begin_recognition') return { state: 'pending', token };
    return { state: body.action === 'scan' ? 'recognized' : 'cancelled' };
  }), ble);
  await assert.rejects(flow.tryOn(), Cancelled);
  assert(!calls.some(c => c.action === 'capture_status'));
  assert(ble.sent.some(c => c.type === 'cancel'));
  assert.equal(flow.getSnapshot().busy, false);
  assert(ble.disconnected);
});

test('iPhone : inscription, essayages successifs puis récupération utilisent la même carte', async () => {
  const ble = new Ble();
  let registered = false, purpose = '', captures = 0;
  ble.onSend = c => {
    if (c.type === 'scan') ble.listener?.({ type: 'card_scanned', token, uid, proof });
    if (c.type === 'card_result' && c.capture === true) ble.listener?.({ type: 'photo_captured', token, uid, proof });
  };
  const flow = new MirrorFlow(mockApi(body => {
    if (String(body.action).startsWith('begin_')) {
      purpose = String(body.action);
      if (purpose === 'begin_registration') assert.equal(body.email, 'a@example.fr');
      return { state: 'pending', token };
    }
    assert.equal(body.card_uid, uid);
    assert.equal(body.proof, proof);
    if (body.action === 'capture_status') { captures++; return { state: 'captured' }; }
    if (purpose === 'begin_registration') { registered = true; return { state: 'associated' }; }
    assert(registered);
    return purpose === 'begin_recovery'
      ? { state: 'recovered', client: { ...client, photo_count: captures, messages: Array.from({ length: captures }, (_, i) => `Photo simulée n°${i + 1}`) } }
      : { state: 'recognized' };
  }), ble);
  await flow.read('registration', ' A@EXAMPLE.FR ');
  assert.equal(captures, 0);
  for (let i = 0; i < 3; i++) await flow.tryOn();
  const recovered = await flow.read('recovery');
  assert.equal(recovered.client?.photo_count, 3);
  assert.equal(recovered.client?.messages.length, 3);
  assert.equal(captures, 3);
  assert.equal(ble.sent.filter(c => c.capture === true).length, 3);
  assert.equal(ble.sent.filter(c => c.capture === false).length, 2);
});
