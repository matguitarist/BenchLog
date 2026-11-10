import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { after, before, test } from 'node:test';
import { createServer } from '../src/server.js';
import { Store } from '../src/store.js';

let server, base, dir;
const token = 'test-token';
const auth = { Authorization: `Bearer ${token}` };

before(async () => {
  dir = mkdtempSync(path.join(tmpdir(), 'benchlog-server-'));
  server = createServer({ store: new Store(':memory:'), token, filesDir: path.join(dir, 'files') });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  base = `http://127.0.0.1:${server.address().port}`;
});
after(() => { server.close(); rmSync(dir, { recursive: true, force: true }); });

const post = (route, body, headers = auth) =>
  fetch(base + route, { method: 'POST', headers: { ...headers, 'Content-Type': 'application/json' }, body: JSON.stringify(body) });

test('health needs no token; everything else does', async () => {
  assert.equal((await fetch(`${base}/v1/health`)).status, 200);
  assert.equal((await fetch(`${base}/v1/library`)).status, 401);
  assert.equal((await fetch(`${base}/v1/library`, { headers: { Authorization: 'Bearer wrong' } })).status, 401);
  assert.equal((await fetch(`${base}/v1/library`, { headers: auth })).status, 200);
});

test('push then pull round-trips rows', async () => {
  const pushed = await (await post('/v1/push', { rows: [{ table: 'repair', id: 'r1', updatedAt: '2026-11-09 12:00:00.000', data: { ticketNumber: 1 } }] })).json();
  assert.equal(pushed.applied, 1);
  const pulled = await (await fetch(`${base}/v1/pull?after=0`, { headers: auth })).json();
  assert.equal(pulled.rows.at(-1).data.ticketNumber, 1);
  assert.equal((await post('/v1/push', { rows: 'nope' })).status, 400);
});

test('numbers are handed out over HTTP', async () => {
  await post('/v1/numbers/invoice/start', { atLeast: 12 });
  assert.deepEqual(await (await post('/v1/numbers/invoice', {})).json(), { first: 12, count: 1 });
  assert.equal((await post('/v1/numbers/invoice', { count: 3 })).status, 400);
});

test('files are stored by id and checked by SHA-256', async () => {
  const bytes = Buffer.from('photo bytes');
  const sha = createHash('sha256').update(bytes).digest('hex');
  const bad = await fetch(`${base}/v1/files/f1`, { method: 'PUT', headers: { ...auth, 'X-Sha256': '0'.repeat(64) }, body: bytes });
  assert.equal(bad.status, 422);
  assert.equal((await fetch(`${base}/v1/files/f1`, { method: 'HEAD', headers: auth })).status, 404);
  const put = await fetch(`${base}/v1/files/f1`, { method: 'PUT', headers: { ...auth, 'X-Sha256': sha }, body: bytes });
  assert.equal(put.status, 200);
  const got = await fetch(`${base}/v1/files/f1`, { headers: auth });
  assert.equal(got.headers.get('x-sha256'), sha);
  assert.equal(Buffer.from(await got.arrayBuffer()).toString(), 'photo bytes');
  assert.equal((await fetch(`${base}/v1/files/..%2Fetc`, { headers: auth })).status, 400);
  const escape = await fetch(`${base}/v1/files/..`, { method: 'PUT', headers: { ...auth, 'X-Sha256': sha }, body: bytes });
  assert.notEqual(escape.status, 200);
});
