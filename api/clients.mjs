import {randomBytes, createHash, createHmac, timingSafeEqual} from 'node:crypto';
import {createClient} from '@supabase/supabase-js';

const jsonHeaders = {
  'Content-Type': 'application/json; charset=utf-8',
  'Cache-Control': 'no-store',
};
const photoBucket = 'mirror-photos';
const maxPhotoBytes = 512 * 1024;
const tokenPattern = /^[0-9a-f]{64}$/;
const uidPattern = /^(?:[0-9A-F]{8}|[0-9A-F]{14}|[0-9A-F]{20})$/;
const sha256 = value => createHash('sha256').update(value).digest('hex');

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {status, headers: jsonHeaders});
}

function verifyMirrorProof(key, proof, message) {
  return typeof proof === 'string' && tokenPattern.test(proof) &&
    timingSafeEqual(createHmac('sha256', key).update(message).digest(), Buffer.from(proof, 'hex'));
}

async function recoverPhotos(supabase, result) {
  if (result.state !== 'recovered') return result;
  let photos = [];
  if (result.session_id) {
    const {data: rows, error} = await supabase.from('photos')
      .select('id,storage_path,created_at')
      .eq('session_id', result.session_id).like('storage_path', 'captures/%')
      .order('created_at', {ascending: false}).order('id');
    if (error) throw error;
    if (rows.length) {
      const {data: signed, error: signingError} = await supabase.storage.from(photoBucket)
        .createSignedUrls(rows.map(row => row.storage_path), 1800);
      if (signingError) throw signingError;
      const urls = new Map(signed.map(asset => [asset.path, asset.signedUrl]));
      photos = rows.map(row => {
        const url = urls.get(row.storage_path);
        if (!url) throw Error('Missing signed photo URL.');
        return {id: row.id, created_at: row.created_at, url};
      });
    }
  }
  return {...result, client: {...result.client, photos, photo_count: photos.length, messages: []}};
}

async function photoCapture(supabase, device, hash, uid, path = '') {
  const {data, error} = await supabase.rpc('mirror_photo_capture', {
    p_device: device, p_hash: hash, p_uid: uid, p_storage_path: path,
  });
  if (error) throw error;
  return data;
}

async function readJpeg(request) {
  if (!request.body || Number(request.headers.get('content-length')) > maxPhotoBytes) return null;
  const reader = request.body.getReader();
  const chunks = [];
  let size = 0;
  try {
    while (true) {
      const {done, value} = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > maxPhotoBytes) {
        await reader.cancel();
        return null;
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }
  const bytes = Buffer.concat(chunks, size);
  if (size < 4 || bytes.readUInt16BE(0) !== 0xffd8 || bytes.readUInt16BE(size - 2) !== 0xffd9) return null;
  return bytes;
}

async function uploadPhoto(request, supabase) {
  const device = process.env.MIRROR_DEVICE_ID;
  const key = process.env.MIRROR_SIGNING_KEY;
  if (!device || device === 'native-ios' || !key || key.length < 32) return json({error: 'Configuration miroir incomplète.'}, 503);
  const token = request.headers.get('x-mirror-token') ?? '';
  const uid = request.headers.get('x-mirror-card') ?? '';
  const signature = request.headers.get('x-mirror-proof') ?? '';
  const digest = request.headers.get('x-mirror-photo-sha256') ?? '';
  if (!tokenPattern.test(token) || !uidPattern.test(uid) || !tokenPattern.test(digest) ||
      !verifyMirrorProof(key, signature, `${token}|${uid}|capture_photo|${digest}`)) {
    return json({error: 'Preuve de capture invalide.'}, 401);
  }
  const bytes = await readJpeg(request);
  if (!bytes || sha256(bytes) !== digest) return json({error: 'JPEG invalide ou trop volumineux.'}, 400);
  const hash = sha256(token);
  const path = `captures/${hash}/${digest}.jpg`;
  const authorization = await photoCapture(supabase, device, hash, uid);
  if (authorization.error) return json(authorization, authorization.status ?? 409);
  if (authorization.state === 'captured') {
    return authorization.storage_path === path ? json({state: 'captured'}) :
      json({error: 'Cette demande a déjà enregistré une autre photo.'}, 409);
  }
  const bucket = supabase.storage.from(photoBucket);
  const {error: uploadError} = await bucket.upload(path, bytes, {contentType: 'image/jpeg', upsert: false});
  if (uploadError && !['409', 'Duplicate', 'ResourceAlreadyExists', 'KeyAlreadyExists'].includes(
    String(uploadError.statusCode ?? uploadError.code)
  )) throw uploadError;
  const result = await photoCapture(supabase, device, hash, uid, path);
  if (result.error) {
    // The database definitively rejected this object. Keep it on ambiguous
    // transport errors so that a retry can finish a potentially committed write.
    await bucket.remove([path]);
    return json(result, result.status ?? 409);
  }
  return json({state: result.state});
}

function getSupabaseAdmin() {
  const url = process.env.SUPABASE_URL;
  const secretKey = process.env.SUPABASE_SECRET_KEY;

  if (!url || !secretKey) {
    throw new Error('Supabase server environment is not configured.');
  }

  return createClient(url, secretKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });
}

function isAdminPasswordValid(password) {
  const expectedPassword = process.env.ADMIN_PASSWORD;
  if (!expectedPassword || typeof password !== 'string') return false;

  const expected = Buffer.from(expectedPassword, 'utf8');
  const received = Buffer.from(password, 'utf8');
  return expected.length === received.length && timingSafeEqual(expected, received);
}

function normalizeClient(row) {
  const sessions = Array.isArray(row.sessions) ? row.sessions : [];
  const photoCount = sessions.reduce((total, session) => {
    return total + (session.photos ?? []).filter(photo => photo.storage_path?.startsWith('captures/')).length;
  }, 0);

  return {
    id: row.id,
    email: row.email,
    card_uid: row.card_uid,
    created_at: row.created_at,
    photo_count: photoCount,
  };
}

async function listClients(request, supabase) {
  const password = request.headers.get('x-admin-password');
  if (!isAdminPasswordValid(password)) {
    return json({error: 'Accès administrateur refusé.'}, 401);
  }

  const {data, error} = await supabase
    .from('clients')
    .select('id,email,card_uid,created_at,sessions(photos(storage_path))')
    .order('email');

  if (error) {
    console.error('Unable to list clients:', error.code);
    return json({error: 'Impossible de charger les clients.'}, 502);
  }

  return json(data.map(normalizeClient));
}

async function findClientByCard(cardUid, supabase) {
  const {data, error} = await supabase
    .from('clients')
    .select('id,email,card_uid,created_at,sessions(photos(storage_path))')
    .eq('card_uid', cardUid.trim().toUpperCase())
    .maybeSingle();

  if (error) {
    console.error('Unable to find client:', error.code);
    return json({error: 'Impossible de rechercher cette carte.'}, 502);
  }
  if (!data) return json({error: 'Carte inconnue.'}, 404);
  return json(normalizeClient(data));
}

async function resetCard(body, supabase) {
  const {client_id: clientId, card_uid: cardUid} = body;
  if (typeof clientId !== 'string' || !/^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(clientId) ||
      typeof cardUid !== 'string' || !cardUid.trim() || cardUid.length > 128) {
    return json({error: 'Client ou carte invalide.'}, 400);
  }

  // The foreign keys delete the client's sessions and their captures atomically.
  const {data, error} = await supabase.from('clients').delete()
    .eq('id', clientId).eq('card_uid', cardUid).select('id').maybeSingle();
  if (error) {
    console.error('Unable to reset card:', error.code);
    return json({error: 'Impossible de réinitialiser cette carte.'}, 502);
  }
  if (!data) return json({error: 'Cette carte n’est plus associée à ce client.'}, 404);
  return json({reset: true});
}

async function createClientRecord(request, supabase) {
  let body;
  try {
    body = await request.json();
  } catch {
    return json({error: 'Corps JSON invalide.'}, 400);
  }

  const email = typeof body.email === 'string'
    ? body.email.trim().toLowerCase()
    : '';
  const cardUid = typeof body.card_uid === 'string'
    ? body.card_uid.trim().toUpperCase()
    : '';
  const validEmail = /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email);

  if (!validEmail || !cardUid || cardUid.length > 128) {
    return json({error: 'Adresse e-mail ou carte invalide.'}, 400);
  }

  const {error} = await supabase.from('clients').insert({
    email,
    card_uid: cardUid,
  });

  if (error?.code === '23505') {
    const isEmail = (error.message ?? '').includes('email');
    return json(
      {
        code: isEmail ? 'email_already_exists' : 'card_already_assigned',
      },
      409,
    );
  }
  if (error) {
    console.error('Unable to create client:', error.code);
    return json({error: 'Impossible de créer le client.'}, 502);
  }

  return json({created: true}, 201);
}

const phoneActions = new Map([
  ['begin_phone_registration', 'begin_registration'],
  ['begin_phone_recovery', 'begin_recovery'],
  ['phone_scan', 'scan'],
  ['phone_cancel', 'cancel'],
]);

// Native Android/iOS calls cannot carry a mirror proof. They use a personal,
// random device-local credential instead; knowledge of an NFC UID grants no reads.
export async function handlePhoneNfc(supabase, body) {
  const action = phoneActions.get(body.action);
  const access = body.mobile_token;
  if (typeof access !== 'string' || !/^[0-9a-f]{64}$/.test(access)) {
    return json({error: 'Accès personnel de ce téléphone requis.'}, 401);
  }
  const generated = action.startsWith('begin_');
  const token = generated ? randomBytes(32).toString('hex') : body.token;
  if (typeof token !== 'string' || !/^[0-9a-f]{64}$/.test(token)) return json({error: 'Demande invalide.'}, 400);
  const email = typeof body.email === 'string' ? body.email.trim().toLowerCase() : '';
  if (action === 'begin_registration' && (email.length > 254 || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email))) {
    return json({error: 'Adresse e-mail invalide.'}, 400);
  }
  const uid = typeof body.card_uid === 'string' ? body.card_uid.trim().toUpperCase() : '';
  if (action === 'scan' && !/^(?:[0-9A-F]{8}|[0-9A-F]{14}|[0-9A-F]{20})$/.test(uid)) {
    return json({error: 'Carte NFC invalide.'}, 400);
  }
  const hash = (value) => createHash('sha256').update(value).digest('hex');
  const {data, error} = await supabase.rpc('phone_nfc_operation', {
    p_action: action, p_hash: hash(token), p_access_hash: hash(access), p_email: email, p_uid: uid,
  });
  if (error) {
    console.error('Phone NFC operation failed:', error.code);
    return json({error: 'Service NFC indisponible. Vérifiez la configuration serveur.'}, 502);
  }
  if (data.error) return json(data, data.status ?? 409);
  return json({...await recoverPhotos(supabase, data), ...(generated ? {token} : {})});
}

// Flutter relays BLE proofs; the dedicated mirror key never reaches the app.
export async function handleNfc(request, supabase, body) {
  const action = body?.action;
  if (phoneActions.has(action)) return handlePhoneNfc(supabase, body);
  const deviceId = process.env.MIRROR_DEVICE_ID;
  const key = process.env.MIRROR_SIGNING_KEY;
  if (!deviceId || deviceId === 'native-ios' || !key || key.length < 32) return json({error: 'Configuration miroir incomplète.'}, 503);
  if (action === 'capture') return json({error: 'Le miroir doit transférer un JPEG réel.'}, 410);
  if (!['begin_registration','begin_recovery','begin_recognition','scan','capture_status','cancel'].includes(action)) {
    return json({error: 'Action inconnue.'}, 400);
  }
  const email = typeof body.email === 'string' ? body.email.trim().toLowerCase() : '';
  if (action === 'begin_registration' && (email.length > 254 || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email))) {
    return json({error: 'Adresse e-mail invalide.'}, 400);
  }
  const generated = action.startsWith('begin_');
  const token = generated ? randomBytes(32).toString('hex') : body.token;
  if (typeof token !== 'string' || !/^[0-9a-f]{64}$/.test(token)) return json({error: 'Jeton invalide.'}, 400);
  const uid = typeof body.card_uid === 'string' ? body.card_uid.toUpperCase() : '';
  if (['scan','capture_status'].includes(action)) {
    if (!uidPattern.test(uid) ||
        typeof body.proof !== 'string' || !/^[0-9a-f]{64}$/.test(body.proof)) {
      return json({error: 'Lecture signée invalide.'}, 400);
    }
    if (!verifyMirrorProof(key, body.proof, `${token}|${uid}|${action}`)) return json({error: 'Preuve miroir invalide.'}, 401);
  }
  if (action === 'capture_status') {
    const result = await photoCapture(supabase, deviceId, sha256(token), uid);
    if (result.error) return json(result, result.status ?? 409);
    return json({state: result.state});
  }
  const {data, error} = await supabase.rpc('nfc_operation', {
    p_action: action, p_device: deviceId,
    p_hash: createHash('sha256').update(token).digest('hex'), p_email: email, p_uid: uid,
  });
  if (error) {
    console.error('NFC operation failed:', error.code);
    return json({error: 'Service NFC indisponible.'}, 502);
  }
  if (data.error) return json(data, data.status ?? 409);
  return json({...await recoverPhotos(supabase, data), ...(generated ? {token} : {})});
}

export function createHandler(supabaseFactory = getSupabaseAdmin) {
 return {
  async fetch(request) {
    if (request.method === 'OPTIONS') return new Response(null, {status: 204});
    if (!['GET', 'POST'].includes(request.method)) return json({error: 'Méthode non autorisée.'}, 405);
    const isJpeg = request.method === 'POST' &&
      request.headers.get('content-type')?.split(';')[0].trim().toLowerCase() === 'image/jpeg';
    let body;
    if (request.method === 'POST' && !isJpeg) {
      try { body = await request.clone().json(); }
      catch { return json({error: 'Corps JSON invalide.'}, 400); }
      if (!body || typeof body !== 'object' || Array.isArray(body)) return json({error: 'Corps JSON invalide.'}, 400);
    }
    const isReset = body?.action === 'admin_reset_card';
    if (!isJpeg && (!body?.action || isReset) && !isAdminPasswordValid(request.headers.get('x-admin-password'))) {
      return json({error: 'Accès administrateur refusé.'}, 401);
    }
    let supabase;
    try { supabase = supabaseFactory(); }
    catch { return json({error: 'Configuration serveur incomplète.'}, 503); }
    try {
      if (isJpeg) return await uploadPhoto(request, supabase);
      if (isReset) return await resetCard(body, supabase);
      if (body?.action) return await handleNfc(request, supabase, body);
      if (request.method === 'POST') return await createClientRecord(request, supabase);
      const cardUid = new URL(request.url).searchParams.get('card_uid');
      return cardUid ? await findClientByCard(cardUid, supabase) : await listClients(request, supabase);
    } catch {
      return json({error: 'Service indisponible.'}, 502);
    }
  },
 };
}
export default createHandler();
