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
  assert.equal((await handler.fetch(request(signed('scan',{action:'capture'})))).status,401);
  assert.equal((await handler.fetch(request(signed('capture')))).status,200);
  assert.equal(calls,2);
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
