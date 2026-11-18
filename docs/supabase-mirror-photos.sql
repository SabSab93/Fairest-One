-- Apply after supabase-nfc.sql. Keep historical rows and store new photos privately.
begin;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('mirror-photos', 'mirror-photos', false, 524288, array['image/jpeg'])
on conflict (id) do update set
  public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

alter table public.photos add column if not exists capture_request_id uuid;
create unique index if not exists photos_capture_request_idx on public.photos(capture_request_id);

create or replace function public.mirror_photo_capture(
  p_device text, p_hash text, p_uid text, p_storage_path text default ''
) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  r public.nfc_requests%rowtype;
  existing_path text;
begin
  select * into r from public.nfc_requests
    where device_id = p_device and token_hash = p_hash for update;
  if not found then
    return jsonb_build_object('error','Demande expirée. Relancez la lecture.','status',410);
  end if;
  if r.session_id is null or r.kind <> 'recognition' or r.card_uid is distinct from p_uid
      or r.state not in ('ready','consumed') then
    return jsonb_build_object('error','Capture non autorisée.','status',409);
  end if;
  if r.state = 'consumed' then
    select storage_path into existing_path from public.photos where capture_request_id = r.id;
    if existing_path is null or (p_storage_path <> '' and existing_path <> p_storage_path) then
      return jsonb_build_object('error','Cette demande a déjà été utilisée.','status',409);
    end if;
    return jsonb_build_object('state','captured','storage_path',existing_path);
  end if;
  if r.expires_at <= now() then
    return jsonb_build_object('error','Demande expirée. Relancez la lecture.','status',410);
  end if;
  if p_storage_path = '' then return jsonb_build_object('state','ready'); end if;

  if p_storage_path is null or p_storage_path !~ ('^captures/' || p_hash || '/[0-9a-f]{64}[.]jpg$')
      or not exists (select 1 from storage.objects where bucket_id = 'mirror-photos' and name = p_storage_path) then
    return jsonb_build_object('error','Fichier photo indisponible.','status',409);
  end if;
  insert into public.photos(session_id,storage_path,capture_request_id,created_at)
    values (r.session_id,p_storage_path,r.id,clock_timestamp());
  update public.nfc_requests set state = 'consumed' where id = r.id;
  return jsonb_build_object('state','captured','storage_path',p_storage_path);
end;
$$;

revoke all on function public.mirror_photo_capture(text,text,text,text) from public, anon, authenticated;
grant execute on function public.mirror_photo_capture(text,text,text,text) to service_role;
commit;
