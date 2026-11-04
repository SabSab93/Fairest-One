-- Review and apply on TEST only, after supabase-schema.sql + supabase-nfc.sql.
-- No remote migration is run automatically. Existing clients/photos are kept.
begin;
alter table public.clients add column if not exists mobile_access_hash text;
alter table public.nfc_requests add column if not exists mobile_access_hash text;

-- Reuse the existing transaction logic for clients, sessions and photo recovery.
-- 'native-ios' is a reserved request namespace, prohibited as MIRROR_DEVICE_ID.
-- Only the API service role may invoke this wrapper. The native client never
-- receives a Supabase secret, mirror key, or anyone else's personal credential.
create or replace function public.phone_nfc_operation(
  p_action text, p_hash text, p_access_hash text, p_email text default '', p_uid text default ''
) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  r public.nfc_requests%rowtype;
  result jsonb;
begin
  if p_access_hash is null or p_access_hash !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('error','Accès personnel de cet iPhone requis.','status',401);
  end if;
  if p_action in ('begin_registration','begin_recovery') then
    result := public.nfc_operation(p_action,'native-ios',p_hash,p_email,p_uid);
    if result->>'state'='pending' then
      update public.nfc_requests set mobile_access_hash=p_access_hash
        where device_id='native-ios' and token_hash=p_hash;
    end if;
    return result;
  end if;
  if p_action not in ('scan','cancel') then
    return jsonb_build_object('error','Action non autorisée.','status',400);
  end if;
  select * into r from public.nfc_requests where device_id='native-ios' and token_hash=p_hash for update;
  if not found or r.expires_at<=now() then
    return jsonb_build_object('error','Demande expirée. Relancez la lecture.','status',410);
  end if;
  if r.mobile_access_hash is distinct from p_access_hash then
    return jsonb_build_object('error','Accès refusé. Utilisez l’iPhone de l’inscription.','status',403);
  end if;
  if p_action='cancel' then
    return public.nfc_operation('cancel','native-ios',p_hash);
  end if;
  -- Lost registration responses may be acknowledged again without creating rows
  -- or rotating ownership. Recovery remains strictly one-use.
  if r.kind='registration' and r.state='consumed' and r.session_id is not null and r.card_uid=p_uid
      and exists(select 1 from public.clients where card_uid=p_uid and mobile_access_hash=p_access_hash) then
    return jsonb_build_object('state','associated');
  end if;
  if r.state<>'pending' then
    return jsonb_build_object('error','Demande déjà utilisée. Relancez la lecture.','status',410);
  end if;
  if r.kind='recovery' and not exists(
    select 1 from public.clients where card_uid=p_uid and mobile_access_hash=p_access_hash
  ) then
    update public.nfc_requests set state='consumed',card_uid=p_uid where id=r.id;
    -- Same response for unknown UID, old BLE-only enrollment and another owner.
    return jsonb_build_object('error','Accès refusé. Utilisez l’iPhone ayant inscrit cette carte.','status',403);
  end if;
  result := public.nfc_operation('scan','native-ios',p_hash,'',p_uid);
  if r.kind='registration' and result->>'state'='associated' then
    update public.clients set mobile_access_hash=p_access_hash where card_uid=p_uid;
  end if;
  return result;
end;
$$;
revoke all on function public.phone_nfc_operation(text,text,text,text,text) from public, anon, authenticated;
grant execute on function public.phone_nfc_operation(text,text,text,text,text) to service_role;
commit;
