import {randomBytes, createHash, createHmac, timingSafeEqual} from 'node:crypto';
import {createClient} from '@supabase/supabase-js';

const jsonHeaders = {
  'Content-Type': 'application/json; charset=utf-8',
  'Cache-Control': 'no-store',
};

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {status, headers: jsonHeaders});
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
    return total + (Array.isArray(session.photos) ? session.photos.length : 0);
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
    .select('id,email,card_uid,created_at,sessions(photos(id))')
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
    .select('id,email,card_uid,created_at,sessions(photos(id))')
    .eq('card_uid', cardUid.trim().toUpperCase())
    .maybeSingle();

  if (error) {
    console.error('Unable to find client:', error.code);
    return json({error: 'Impossible de rechercher cette carte.'}, 502);
  }
  if (!data) return json({error: 'Carte inconnue.'}, 404);
  return json(normalizeClient(data));
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

// Flutter relays BLE proofs; the dedicated mirror key never reaches the app.
export async function handleNfc(request, supabase, body) {
  const action = body?.action;
  const deviceId = process.env.MIRROR_DEVICE_ID;
  const key = process.env.MIRROR_SIGNING_KEY;
  if (!deviceId || !key || key.length < 32) return json({error: 'Configuration miroir incomplète.'}, 503);
  if (!['begin_registration','begin_recovery','begin_recognition','scan','capture','cancel'].includes(action)) {
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
  if (['scan','capture'].includes(action)) {
    if (!/^(?:[0-9A-F]{8}|[0-9A-F]{14}|[0-9A-F]{20})$/.test(uid) ||
        typeof body.proof !== 'string' || !/^[0-9a-f]{64}$/.test(body.proof)) {
      return json({error: 'Lecture signée invalide.'}, 400);
    }
    const expected = createHmac('sha256', key).update(`${token}|${uid}|${action}`).digest();
    if (!timingSafeEqual(expected, Buffer.from(body.proof, 'hex'))) return json({error: 'Preuve miroir invalide.'}, 401);
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
  return json({...data, ...(generated ? {token} : {})});
}

export function createHandler(supabaseFactory = getSupabaseAdmin) {
 return {
  async fetch(request) {
    if (request.method === 'OPTIONS') return new Response(null, {status: 204});
    if (!['GET', 'POST'].includes(request.method)) return json({error: 'Méthode non autorisée.'}, 405);
    let body;
    if (request.method === 'POST') {
      try { body = await request.clone().json(); }
      catch { return json({error: 'Corps JSON invalide.'}, 400); }
      if (!body || typeof body !== 'object' || Array.isArray(body)) return json({error: 'Corps JSON invalide.'}, 400);
    }
    // Legacy demo operations remain available to administrators only.
    if (!body?.action && !isAdminPasswordValid(request.headers.get('x-admin-password'))) {
      return json({error: 'Accès administrateur refusé.'}, 401);
    }
    let supabase;
    try { supabase = supabaseFactory(); }
    catch { return json({error: 'Configuration serveur incomplète.'}, 503); }
    try {
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
