-- TEST DATABASE ONLY, after schema + BLE migration + phone migration.
\set ON_ERROR_STOP on
begin;
create function pg_temp.check_phone(ok boolean, label text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'FAIL: %',label; end if; end $$;
do $$
declare
  r jsonb;
  access_a text := repeat('a',64);
  access_b text := repeat('b',64);
  capture_hash text;
  i integer;
begin
  r := phone_nfc_operation('begin_registration','phone-register',access_a,'native-test@example.test');
  perform pg_temp.check_phone(r->>'state'='pending','phone challenge');
  r := phone_nfc_operation('scan','phone-register',access_b,'','04A1B2C3D4E5F6');
  perform pg_temp.check_phone((r->>'status')::int=403,'challenge bound to personal credential');
  r := phone_nfc_operation('scan','phone-register',access_a,'','04A1B2C3D4E5F6');
  perform pg_temp.check_phone(r->>'state'='associated','native registration');
  perform pg_temp.check_phone(exists(select 1 from clients where email='native-test@example.test'
    and card_uid='04A1B2C3D4E5F6' and mobile_access_hash=access_a),'owner hash persisted');
  r := phone_nfc_operation('scan','phone-register',access_a,'','04A1B2C3D4E5F6');
  perform pg_temp.check_phone(r->>'state'='associated','lost registration acknowledgement retried');
  perform pg_temp.check_phone((select count(*) from sessions s join clients c on c.id=s.client_id
    where c.card_uid='04A1B2C3D4E5F6')=1,'no duplicate session');
  -- The unchanged mirror recognition/capture flow sees the native registration.
  for i in 1..3 loop
    capture_hash := 'native-capture-'||i;
    perform nfc_operation('begin_recognition','test-c6',capture_hash);
    r := nfc_operation('scan','test-c6',capture_hash,'','04A1B2C3D4E5F6');
    perform pg_temp.check_phone(r->>'state'='recognized','mirror recognizes phone-enrolled card');
    perform nfc_operation('capture','test-c6',capture_hash,'','04A1B2C3D4E5F6');
  end loop;
  perform phone_nfc_operation('begin_recovery','wrong-owner',access_b);
  r := phone_nfc_operation('scan','wrong-owner',access_b,'','04A1B2C3D4E5F6');
  perform pg_temp.check_phone((r->>'status')::int=403 and not (r ? 'client'),'known UID cannot disclose photos to another phone');
  perform phone_nfc_operation('begin_recovery','phone-recover',access_a);
  r := phone_nfc_operation('scan','phone-recover',access_a,'','04A1B2C3D4E5F6');
  perform pg_temp.check_phone(r->>'state'='recovered' and jsonb_array_length(r->'client'->'messages')=3,'native recovery returns three messages');
  perform pg_temp.check_phone(not ((r->'client') ? 'mobile_access_hash'),'personal hash never returned');
  r := phone_nfc_operation('scan','phone-recover',access_a,'','04A1B2C3D4E5F6');
  perform pg_temp.check_phone((r->>'status')::int=410,'recovery is one use');
  perform phone_nfc_operation('begin_registration','hijack',access_b,'different@example.test');
  r := phone_nfc_operation('scan','hijack',access_b,'','04A1B2C3D4E5F6');
  perform pg_temp.check_phone(r->>'code'='card_already_assigned','cannot overwrite owner');
  perform pg_temp.check_phone((select mobile_access_hash from clients where card_uid='04A1B2C3D4E5F6')=access_a,'owner unchanged');
  perform phone_nfc_operation('begin_recovery','expired-phone',access_a);
  update nfc_requests set expires_at=now()-interval '1 second' where token_hash='expired-phone';
  r := phone_nfc_operation('scan','expired-phone',access_a,'','04A1B2C3D4E5F6');
  perform pg_temp.check_phone((r->>'status')::int=410,'phone challenge expires');
  perform phone_nfc_operation('begin_recovery','cancel-phone',access_a);
  perform phone_nfc_operation('cancel','cancel-phone',access_a);
  r := phone_nfc_operation('scan','cancel-phone',access_a,'','04A1B2C3D4E5F6');
  perform pg_temp.check_phone((r->>'status')::int=410,'phone cancellation');
  r := phone_nfc_operation('capture','phone-register',access_a,'','04A1B2C3D4E5F6');
  perform pg_temp.check_phone((r->>'status')::int=400,'phone actions cannot authorize mirror capture');
  perform pg_temp.check_phone(not has_function_privilege('anon','phone_nfc_operation(text,text,text,text,text)','execute'),'no anonymous RPC bypass');
end $$;
rollback;
\echo 'Native phone database scenarios passed (fixtures rolled back).'
