-- Proposition à exécuter plus tard dans l'éditeur SQL Supabase.
-- La carte NFC ne contient qu'un UID opaque, jamais l'adresse email.

create table clients (
  id uuid primary key default gen_random_uuid(),
  email text not null unique,
  card_uid text not null unique,
  created_at timestamptz not null default now()
);

create table sessions (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references clients(id) on delete cascade,
  status text not null default 'active',
  started_at timestamptz not null default now(),
  ended_at timestamptz
);

create table photos (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references sessions(id) on delete cascade,
  storage_path text not null unique,
  selected boolean not null default false,
  created_at timestamptz not null default now()
);

create table device_logs (
  id bigint generated always as identity primary key,
  device_id text not null,
  level text not null default 'info',
  event text not null,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index sessions_client_id_idx on sessions(client_id);
create index photos_session_id_idx on photos(session_id);
create index device_logs_created_at_idx on device_logs(created_at desc);

alter table clients enable row level security;
alter table sessions enable row level security;
alter table photos enable row level security;
alter table device_logs enable row level security;

-- Aucune politique ouverte n'est créée volontairement : avec RLS activé, la clé
-- publishable ne peut pas encore lire ou modifier les emails. Ajouter ensuite
-- une authentification et des politiques limitées au rôle de la borne, ou faire
-- passer ces opérations par la Raspberry Pi. La clé service_role restera
-- uniquement sur la Raspberry Pi ou le backend, jamais dans Flutter.
