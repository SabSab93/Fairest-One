-- Review on a TEST Supabase project first, after supabase-schema.sql.
-- This file is not applied automatically. Existing rows are preserved.
begin;
alter table public.photos add column if not exists message text;
create table if not exists public.nfc_requests (
  id uuid primary key default gen_random_uuid(),
  device_id text not null,
  token_hash text not null unique,
  kind text not null check (kind in ('registration','recovery','recognition')),
  state text not null default 'pending' check (state in ('pending','ready','consumed','cancelled')),
  email text,
  card_uid text,
  session_id uuid references public.sessions(id) on delete cascade,
  expires_at timestamptz not null default (now() + interval '90 seconds'),
  created_at timestamptz not null default now()
);
create index if not exists nfc_requests_device_idx on public.nfc_requests(device_id,created_at desc);
alter table public.nfc_requests enable row level security;
revoke all on public.nfc_requests from public, anon, authenticated;
grant all on public.nfc_requests to service_role;

-- API verifies a hardware HMAC before invoking scan/capture. Transactions and
-- row locks enforce single use even across concurrent Vercel instances.
create or replace function public.nfc_operation(
  p_action text, p_device text, p_hash text, p_email text default '', p_uid text default ''
) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  r public.nfc_requests%rowtype;
  c public.clients%rowtype;
  sid uuid;
  msgs jsonb;
  n integer;
begin
  if p_action in ('begin_registration','begin_recovery','begin_recognition') then
    -- Bound outstanding challenges for this single-mirror prototype.
    perform pg_advisory_xact_lock(hashtextextended(p_device,0));
    if (select count(*) from public.nfc_requests where device_id=p_device and expires_at>now()
        and state in ('pending','ready')) >= 20 then
      return jsonb_build_object('error','Trop de demandes. Réessayez dans 90 secondes.','status',429);
    end if;
    insert into public.nfc_requests(device_id,token_hash,kind,email)
      values(p_device,p_hash,substring(p_action from 7),nullif(p_email,''));
    return jsonb_build_object('state','pending','expires_in',90);
  end if;
  select * into r from public.nfc_requests where token_hash=p_hash and device_id=p_device for update;
  if not found or r.expires_at<=now() then
    return jsonb_build_object('error','Demande expirée. Relancez la lecture.','status',410);
  end if;
  if p_action='cancel' then
    update public.nfc_requests set state='cancelled' where id=r.id and state in ('pending','ready');
    return jsonb_build_object('state','cancelled');
  end if;
  if p_action='capture' then
    if r.session_id is null or r.kind<>'recognition' or r.card_uid is distinct from p_uid or r.state not in ('ready','consumed') then
      return jsonb_build_object('error','Capture non autorisée.','status',409);
    end if;
    if r.state='consumed' then return jsonb_build_object('state','captured'); end if;
    -- Serialize numbering across distinct requests for the same session.
    perform 1 from public.sessions where id=r.session_id for update;
    select count(*)+1 into n from public.photos where session_id=r.session_id;
    insert into public.photos(session_id,storage_path,message,created_at)
      values(r.session_id,'simulated/'||r.id::text,'Photo simulée n°'||n::text||' — Essayage effectué.',clock_timestamp());
    update public.nfc_requests set state='consumed' where id=r.id;
    return jsonb_build_object('state','captured');
  end if;
  if p_action<>'scan' or r.state<>'pending' then
    return jsonb_build_object('error','Demande déjà utilisée.','status',410);
  end if;
  update public.nfc_requests set state='consumed',card_uid=p_uid where id=r.id;
  if r.kind='registration' then
    begin
      insert into public.clients(email,card_uid) values(r.email,p_uid) returning * into c;
    exception when unique_violation then
      return jsonb_build_object('state','failed','code',
        case when exists(select 1 from public.clients where email=r.email)
          then 'email_already_exists' else 'card_already_assigned' end);
    end;
    insert into public.sessions(client_id) values(c.id) returning id into sid;
    update public.nfc_requests set session_id=sid where id=r.id;
    return jsonb_build_object('state','associated');
  end if;
  select * into c from public.clients where card_uid=p_uid;
  if not found then return jsonb_build_object('state','unknown'); end if;
  -- Client lock avoids creating concurrent active sessions for the same card.
  perform 1 from public.clients where id=c.id for update;
  select id into sid from public.sessions where client_id=c.id
    and (r.kind='recovery' or status='active') order by started_at desc,id desc limit 1;
  if r.kind='recognition' then
    if sid is null then insert into public.sessions(client_id) values(c.id) returning id into sid; end if;
    update public.nfc_requests set state='ready',session_id=sid where id=r.id;
    return jsonb_build_object('state','recognized');
  end if;
  select coalesce(jsonb_agg(message order by created_at,id) filter(where message is not null),'[]'::jsonb)
    into msgs from public.photos where session_id=sid;
  select count(*) into n from public.photos where session_id=sid;
  return jsonb_build_object('state','recovered','session_id',sid,
    'client',jsonb_build_object('id',c.id,'email',c.email,'card_uid',c.card_uid,
      'created_at',c.created_at,'photo_count',n,'messages',msgs));
end;
$$;
revoke all on function public.nfc_operation(text,text,text,text,text) from public, anon, authenticated;
grant execute on function public.nfc_operation(text,text,text,text,text) to service_role;
commit;
