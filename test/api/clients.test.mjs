import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createHmac, createHash} from 'node:crypto';
import {createHandler} from '../../api/clients.mjs';
process.env.MIRROR_DEVICE_ID = 'test-c6';
process.env.MIRROR_SIGNING_KEY = 'test-only-key-0000000000000000000000000000';
process.env.ADMIN_PASSWORD = 'test-only-admin';
const token = 'a'.repeat(64);
const uid = 'A1B2C3D4';
function request(body, headers = {}) {
  return new Request('https://example.test/api/clients', {method:'POST', headers:{'Content-Type':'application/json', ...headers}, body:JSON.stringify(body)});
}
function signed(action, overrides={}) {
  return {action, token, card_uid:uid, proof:createHmac('sha256',process.env.MIRROR_SIGNING_KEY).update(`${token}|${uid}|${action}`).digest('hex'), ...overrides};
}
test('UID lookup and direct registration require admin access', async () => {
  const handler = createHandler(() => { throw Error('must not reach database'); });
  assert.equal((await handler.fetch(new Request('https://example.test/api/clients?card_uid=A1B2C3D4'))).status,401);
  assert.equal((await handler.fetch(request({email:'client@example.test',card_uid:uid}))).status,401);
});
test('card reset requires admin access and deletes only the confirmed association', async () => {
  const clientId = 'c552232b-cdfb-49fa-88c3-48c04a5b03b8';
  const reset = {action:'admin_reset_card', client_id:clientId, card_uid:uid};
  const admin = {'X-Admin-Password':process.env.ADMIN_PASSWORD};
  const filters = [];
  let matches = true;
  const query = {
    delete: () => query,
    eq: (key, value) => { filters.push([key, value]); return query; },
    select: (columns) => { assert.equal(columns, 'id'); return query; },
    maybeSingle: async () => ({data:matches ? {id:clientId} : null}),
  };
  let databaseCalls = 0;
  const handler = createHandler(() => {
    databaseCalls++;
    return {from: table => { assert.equal(table, 'clients'); return query; }};
  });

  assert.equal((await handler.fetch(request(reset))).status, 401);
  assert.equal((await handler.fetch(request(reset, {'X-Admin-Password':'incorrect'}))).status, 401);
  assert.equal(databaseCalls, 0);
  assert.equal((await handler.fetch(request({...reset, client_id:'invalid'}, admin))).status, 400);
  assert.deepEqual(filters, []);
  const response = await handler.fetch(request(reset, admin));
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), {reset:true});
  assert.deepEqual(filters, [['id', clientId], ['card_uid', uid]]);
  matches = false;
  assert.equal((await handler.fetch(request(reset, admin))).status, 404);
});
test('temporary registration challenge contains no server credentials', async () => {
  let args;
  const handler = createHandler(() => ({rpc:async (_, input) => {args=input;return {data:{state:'pending'},error:null};}}));
  const response = await handler.fetch(request({action:'begin_registration',email:'CLIENT@EXAMPLE.TEST'}));
  const body = await response.json();
  assert.equal(response.status,200);
  assert.match(body.token,/^[a-f0-9]{64}$/);
  assert.equal(args.p_email,'client@example.test');
  assert.equal(args.p_hash,createHash('sha256').update(body.token).digest('hex'));
  assert.ok(!JSON.stringify(body).includes(process.env.MIRROR_SIGNING_KEY));
});
test('scan and capture proofs have distinct domains and reject tampering', async () => {
  let calls = 0;
  const handler = createHandler(() => ({rpc:async () => { calls++;return {data:{state:'recognized'}}; }}));
  assert.equal((await handler.fetch(request(signed('scan')))).status,200);
  assert.equal((await handler.fetch(request(signed('scan',{card_uid:'01020304'})))).status,401);
  assert.equal((await handler.fetch(request(signed('scan',{action:'capture_status'})))).status,401);
  assert.equal((await handler.fetch(request(signed('capture')))).status,410);
  assert.equal(calls,1);
});

test('uploads only signed JPEG bytes and retries without creating a second photo', async () => {
  const photo = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0xff, 0xd9]);
  const digest = createHash('sha256').update(photo).digest('hex');
  const hash = createHash('sha256').update(token).digest('hex');
  const expectedPath = `captures/${hash}/${digest}.jpg`;
  const proof = createHmac('sha256', process.env.MIRROR_SIGNING_KEY)
    .update(`${token}|${uid}|capture_photo|${digest}`).digest('hex');
  const photoRequest = (bytes = photo) => new Request('https://example.test/api/clients', {
    method: 'POST',
    headers: {
      'Content-Type': 'image/jpeg',
      'X-Mirror-Token': token,
      'X-Mirror-Card': uid,
      'X-Mirror-Photo-Sha256': digest,
      'X-Mirror-Proof': proof,
    },
    body: bytes,
  });
  let path;
  let uploads = 0;
  const handler = createHandler(() => ({
    rpc: async (name, args) => {
      assert.equal(name, 'mirror_photo_capture');
      assert.equal(args.p_hash, hash);
      assert.equal(args.p_uid, uid);
      if (args.p_storage_path) {
        assert.equal(args.p_storage_path, expectedPath);
        path = args.p_storage_path;
      }
      return {data: path ? {state: 'captured', storage_path: path} : {state: 'ready'}};
    },
    storage: {from: bucket => {
      assert.equal(bucket, 'mirror-photos');
      return {upload: async (file, bytes, options) => {
        assert.equal(file, expectedPath);
        assert.deepEqual(bytes, photo);
        assert.equal(options.upsert, false);
        uploads++;
        return {};
      }};
    }},
  }));
  assert.equal((await handler.fetch(photoRequest(Buffer.from([0xff, 0xd8, 0xff, 0xd9])))).status, 400);
  const first = await handler.fetch(photoRequest());
  assert.deepEqual(await first.json(), {state: 'captured'});
  assert.equal((await handler.fetch(photoRequest())).status, 200);
  assert.deepEqual(await (await handler.fetch(request(signed('capture_status')))).json(), {state: 'captured'});
  assert.equal(uploads, 1);
});

test('recovery signs real photos for the recovered session and omits old placeholders', async () => {
  const storagePath = 'captures/opaque/image.jpg';
  const createdAt = '2026-11-18T12:00:00Z';
  const filters = [];
  const query = {
    select: () => query,
    eq: (column, value) => { filters.push([column, value]); return query; },
    like: (column, value) => { filters.push([column, value]); return query; },
    order: column => column === 'id' ? {data: [{id: 'photo', storage_path: storagePath, created_at: createdAt}]} : query,
  };
  const url = 'https://storage.example.test/signed-photo';
  const handler = createHandler(() => ({
    rpc: async () => ({data: {
      state: 'recovered', session_id: 'session', client: {email: 'client@example.test', photo_count: 2, messages: ['historical']},
    }}),
    from: table => { assert.equal(table, 'photos'); return query; },
    storage: {from: () => ({createSignedUrls: async paths => {
      assert.deepEqual(paths, [storagePath]);
      return {data: [{path: storagePath, signedUrl: url}]};
    }})},
  }));
  const response = await handler.fetch(request(signed('scan')));
  assert.equal(response.status, 200);
  assert.deepEqual((await response.json()).client, {
    email: 'client@example.test', photo_count: 1, messages: [], photos: [{id: 'photo', created_at: createdAt, url}],
  });
  assert.deepEqual(filters, [['session_id', 'session'], ['storage_path', 'captures/%']]);
});
test('bad input, invalid proof, expiration and backend failures stay explicit', async () => {
  const handler = createHandler(() => ({rpc:async () => ({data:{error:'expired',status:410}})}));
  for (const body of [null, [], {action:'scan',token}, {action:'scan',token:'x'}, {action:'begin_registration',email:'bad'}]) {
    assert.equal((await handler.fetch(request(body))).status,400);
  }
  assert.equal((await handler.fetch(request(signed('scan')))).status,410);
  const broken = createHandler(() => ({rpc:async () => ({error:{code:'test'}})}));
  assert.equal((await broken.fetch(request(signed('scan')))).status,502);
  const thrown = createHandler(() => ({rpc:async () => {throw Error('secret-details');}}));
  const response=await thrown.fetch(request(signed('scan')));
  assert.equal(response.status,502);
  assert.ok(!(await response.text()).includes('secret-details'));
});

test('native phone challenges require a personal credential and no mirror key', async () => {
  const oldKey = process.env.MIRROR_SIGNING_KEY;
  delete process.env.MIRROR_SIGNING_KEY;
  const access='b'.repeat(64);
  let called;
  const handler=createHandler(() => ({rpc:async (name,args) => {called={name,args};return {data:{state:'pending'}};}}));
  try {
    assert.equal((await handler.fetch(request({action:'begin_phone_registration',email:'client@example.test'}))).status,401);
    const response=await handler.fetch(request({action:'begin_phone_registration',email:'CLIENT@EXAMPLE.TEST',mobile_token:access}));
    const body=await response.json();
    assert.equal(response.status,200);
    assert.match(body.token,/^[0-9a-f]{64}$/);
    assert.equal(called.name,'phone_nfc_operation');
    assert.equal(called.args.p_action,'begin_registration');
    assert.equal(called.args.p_access_hash,createHash('sha256').update(access).digest('hex'));
    assert.equal(called.args.p_email,'client@example.test');
    assert.ok(!JSON.stringify(body).includes(access));
    assert.ok(!JSON.stringify(called.args).includes(access));
  } finally { process.env.MIRROR_SIGNING_KEY=oldKey; }
});

test('native scans validate inputs and keep authorization failures private', async () => {
  let calls=0;
  const handler=createHandler(() => ({rpc:async () => {calls++;return {data:{error:'Accès refusé.',status:403}};}}));
  const valid={action:'phone_scan',token,mobile_token:'b'.repeat(64),card_uid:'04A1B2C3D4E5F6'};
  assert.equal((await handler.fetch(request({...valid,mobile_token:undefined}))).status,401);
  assert.equal((await handler.fetch(request({...valid,card_uid:'DEMO-123'}))).status,400);
  assert.equal((await handler.fetch(request({...valid,token:'invalid'}))).status,400);
  assert.equal((await handler.fetch(request(valid))).status,403);
  assert.equal(calls,1);
  // An ordinary mirror scan still demands its signed hardware proof.
  assert.equal((await handler.fetch(request({...valid,action:'scan'}))).status,400);
});
