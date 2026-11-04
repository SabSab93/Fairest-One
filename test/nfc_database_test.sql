-- Run only against the disposable/local TEST database after the schema + migration.
-- All fixtures roll back, including failed assertions (ON_ERROR_STOP).
\set ON_ERROR_STOP on
begin;
create function pg_temp.expect(ok boolean, label text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'FAIL: %',label; end if; end $$;
do $$
declare r jsonb; i integer; before_count integer;
begin
  select count(*) into before_count from public.photos;
  r := public.nfc_operation('begin_registration','test-c6','register','ble-integration@example.test');
  perform pg_temp.expect(r->>'state'='pending','challenge creation');
  r := public.nfc_operation('scan','test-c6','register','','A1B2C3D4');
  perform pg_temp.expect(r->>'state'='associated','registration');
  r := public.nfc_operation('scan','test-c6','register','','A1B2C3D4');
  perform pg_temp.expect((r->>'status')::int=410,'single-use registration');
  perform pg_temp.expect(exists(select 1 from clients where email='ble-integration@example.test' and card_uid='A1B2C3D4'),'email and uid persisted');
  perform public.nfc_operation('begin_registration','test-c6','duplicate','ble-integration@example.test');
  r := public.nfc_operation('scan','test-c6','duplicate','','01020304');
  perform pg_temp.expect(r->>'code'='email_already_exists','duplicate email');
  perform public.nfc_operation('begin_registration','test-c6','duplicate-card','different@example.test');
  r := public.nfc_operation('scan','test-c6','duplicate-card','','A1B2C3D4');
  perform pg_temp.expect(r->>'code'='card_already_assigned','duplicate card');
  perform public.nfc_operation('begin_recognition','test-c6','unknown');
  r := public.nfc_operation('scan','test-c6','unknown','','11223344');
  perform pg_temp.expect(r->>'state'='unknown','card B rejected');
  r := public.nfc_operation('capture','test-c6','unknown','','11223344');
  perform pg_temp.expect((r->>'status')::int=409,'unknown card cannot capture');
  for i in 1..3 loop
    perform public.nfc_operation('begin_recognition','test-c6','capture-'||i);
    r := public.nfc_operation('scan','test-c6','capture-'||i,'','A1B2C3D4');
    perform pg_temp.expect(r->>'state'='recognized','card A recognized');
    r := public.nfc_operation('capture','test-c6','capture-'||i,'','11223344');
    perform pg_temp.expect((r->>'status')::int=409,'capture bound to scanned card');
    r := public.nfc_operation('capture','test-c6','capture-'||i,'','A1B2C3D4');
    perform pg_temp.expect(r->>'state'='captured','capture saved');
    perform public.nfc_operation('capture','test-c6','capture-'||i,'','A1B2C3D4');
  end loop;
  perform pg_temp.expect((select count(*) from photos)=before_count+3,'three captures despite retries');
  perform public.nfc_operation('begin_recovery','test-c6','recover');
  r := public.nfc_operation('scan','test-c6','recover','','A1B2C3D4');
  perform pg_temp.expect(r->>'state'='recovered','recovery');
  perform pg_temp.expect(jsonb_array_length(r->'client'->'messages')=3,'three recovered messages');
  perform pg_temp.expect(r->'client'->'messages'->>2='Photo simulée n°3 — Essayage effectué.','message numbering');
  r := public.nfc_operation('scan','test-c6','recover','','A1B2C3D4');
  perform pg_temp.expect((r->>'status')::int=410,'recovery one-use');
  perform public.nfc_operation('begin_recovery','test-c6','expired');
  update nfc_requests set expires_at=now()-interval '1 second' where token_hash='expired';
  r := public.nfc_operation('scan','test-c6','expired','','A1B2C3D4');
  perform pg_temp.expect((r->>'status')::int=410,'expiration');
  perform public.nfc_operation('begin_recovery','test-c6','cancelled');
  perform public.nfc_operation('cancel','test-c6','cancelled');
  r := public.nfc_operation('scan','test-c6','cancelled','','A1B2C3D4');
  perform pg_temp.expect((r->>'status')::int=410,'cancellation');
  perform pg_temp.expect(not has_function_privilege('anon','public.nfc_operation(text,text,text,text,text)','execute'),'anon cannot bypass API proof verification');
  perform pg_temp.expect(not has_table_privilege('authenticated','public.nfc_requests','select'),'no direct access to capabilities');
end $$;
rollback;
\echo 'NFC database scenarios passed (fixtures rolled back).'
