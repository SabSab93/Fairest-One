import {timingSafeEqual} from 'node:crypto';
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

export default {
  async fetch(request) {
    if (request.method === 'OPTIONS') {
      return new Response(null, {status: 204});
    }

    let supabase;
    try {
      supabase = getSupabaseAdmin();
    } catch (error) {
      console.error(error.message);
      return json({error: 'Configuration serveur incomplète.'}, 503);
    }

    if (request.method === 'POST') {
      return createClientRecord(request, supabase);
    }

    if (request.method === 'GET') {
      const cardUid = new URL(request.url).searchParams.get('card_uid');
      return cardUid
        ? findClientByCard(cardUid, supabase)
        : listClients(request, supabase);
    }

    return json({error: 'Méthode non autorisée.'}, 405);
  },
};
