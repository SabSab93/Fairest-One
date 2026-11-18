import { strict as assert } from 'node:assert';
import { test } from 'node:test';
import { WifiMirror, mirrorAddress } from '../src/adapters/wifi-mirror';

test('le transport Wi-Fi utilise une adresse locale et ne suit pas les redirections', async () => {
  for (const invalid of ['example.com', '8.8.8.8', '172.32.0.1', '192.168.0.256', 'http://172.20.10.4']) {
    assert.throws(() => mirrorAddress(invalid));
  }
  const mirror = new WifiMirror(() => '172.20.10.4', async (url, options) => {
    assert.equal(url, 'http://172.20.10.4/mirror/status');
    assert.equal(options?.redirect, 'error');
    return new Response('fairest-one-wifi-v1');
  });
  await mirror.connect(new AbortController().signal);
  await mirror.disconnect();
});

test('une lecture Wi-Fi reçoit les événements et annule la session quand elle est interrompue', async () => {
  const token = 'a'.repeat(64);
  const calls: Record<string, unknown>[] = [];
  const mirror = new WifiMirror(() => '172.20.10.4', async (url, options) => {
    if (String(url).endsWith('/status')) return new Response('fairest-one-wifi-v1');
    const body = JSON.parse(String(options?.body));
    assert.equal(body.token, token);
    if (String(url).endsWith('/event')) {
      return Response.json({ type: 'card_scanned', token, uid: '01234567' });
    }
    calls.push(body);
    return new Response(null, { status: 204 });
  });

  await mirror.connect(new AbortController().signal);
  const event = new Promise(resolve => mirror.subscribe(resolve));
  await mirror.send({ type: 'scan', token });
  assert.deepEqual(await event, { type: 'card_scanned', token, uid: '01234567' });
  await mirror.disconnect();
  assert.deepEqual(calls.map(call => call.type), ['scan', 'cancel']);
});
