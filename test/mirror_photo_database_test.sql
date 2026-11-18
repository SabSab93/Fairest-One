-- Run after the schema, NFC, and mirror-photo migrations on a test database.
begin;
do $$
declare
  token_hash text := repeat('a',64);
  registration_hash text := repeat('b',64);
  asset_path text := 'captures/' || repeat('a',64) || '/' || repeat('c',64) || '.jpg';
  response jsonb;
  asset_session uuid;
begin
  perform public.nfc_operation('begin_registration','test-photo',registration_hash,'photo@example.test');
  response := public.nfc_operation('scan','test-photo',registration_hash,'','01234567');
  if response->>'state' <> 'associated' then raise exception 'Registration failed: %', response; end if;
  perform public.nfc_operation('begin_recognition','test-photo',token_hash);
  response := public.nfc_operation('scan','test-photo',token_hash,'','01234567');
  if response->>'state' <> 'recognized' then raise exception 'Recognition failed: %', response; end if;
  select session_id into asset_session from public.nfc_requests where nfc_requests.token_hash = repeat('a',64);
  response := public.mirror_photo_capture('test-photo',token_hash,'01234567',asset_path);
  if response->>'status' <> '409' then raise exception 'A missing image was accepted: %', response; end if;
  insert into storage.objects(bucket_id,name) values ('mirror-photos',asset_path);
  response := public.mirror_photo_capture('test-photo',token_hash,'89ABCDEF',asset_path);
  if response->>'status' <> '409' then raise exception 'A foreign card was accepted: %', response; end if;
  response := public.mirror_photo_capture('test-photo',token_hash,'01234567',asset_path);
  if response->>'state' <> 'captured' then raise exception 'JPEG registration failed: %', response; end if;
  response := public.mirror_photo_capture('test-photo',token_hash,'01234567',asset_path);
  if response->>'state' <> 'captured' then raise exception 'A retry failed: %', response; end if;
  if (select count(*) from public.photos where session_id = asset_session) <> 1 then
    raise exception 'Duplicate or misplaced photograph';
  end if;
  if (select public from storage.buckets where id = 'mirror-photos') is distinct from false then
    raise exception 'The photo bucket must remain private';
  end if;
end
$$;
rollback;
