import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';
import { createServer } from 'node:http';
import { once } from 'node:events';
import { probeStaging, notifyHeartbeat, runActivity, STAGING_HEALTH_URL } from './staging-activity.mjs';

const heartbeat = 'https://hc-ping.com/00000000-0000-0000-0000-000000000000';
const healthy = () => new Response(JSON.stringify({ ok: true, database: 'ok', responseTimeMs: 7 }), {
  headers: { 'content-type': 'application/json', 'cache-control': 'no-store, max-age=0' },
});

test('only the fixed staging GET target is contacted; redirects disabled and deadline set', async () => {
  assert.equal(await probeStaging(async (url, options) => {
    assert.equal(url, STAGING_HEALTH_URL);
    assert.equal(options.method, 'GET');
    assert.equal(options.redirect, 'error');
    assert.equal(options.cache, 'no-store');
    assert.ok(options.signal instanceof AbortSignal);
    assert.equal(options.headers.Authorization, undefined);
    return healthy();
  }), true);
});

for (const [name, response] of [
  ['503', () => new Response('private db error', { status: 503 })],
  ['redirect', () => new Response('', { status: 302 })],
  ['HTML login page', () => new Response('<html>login</html>')],
  ['cached success', () => new Response('{"ok":true,"database":"ok","responseTimeMs":0}', { headers: { 'content-type': 'application/json' } })],
  ['malformed JSON', () => new Response('{', { headers: { 'content-type': 'application/json', 'cache-control': 'no-store' } })],
  ['database error', () => new Response('{"ok":true,"database":"error","responseTimeMs":0}', { headers: { 'content-type': 'application/json', 'cache-control': 'no-store' } })],
  ['network failure', () => { throw new Error('secret detail'); }],
]) test(`fails closed: ${name}`, async () => assert.equal(await probeStaging(response), false));

test('real fetch aborts a hanging HTTP response without following redirects', async () => {
  let redirected = 0;
  const server = createServer((req, res) => {
    if (req.url === '/redirect') { res.writeHead(302, { Location: '/target' }); res.end(); }
    if (req.url === '/target') { redirected++; res.end(); }
  }).listen(0, '127.0.0.1');
  await once(server, 'listening');
  const local = `http://127.0.0.1:${server.address().port}`;
  try {
    assert.equal(await probeStaging((_url, options) => fetch(local, options), 30), false);
    assert.equal(await probeStaging((_url, options) => fetch(`${local}/redirect`, options)), false);
    assert.equal(redirected, 0);
  } finally { server.closeAllConnections(); server.close(); }
});

test('success heartbeat only follows verified DB success; failure sends /fail and nonzero exit', async () => {
  for (const ok of [true, false]) {
    const calls = [];
    const logs = [];
    const code = await runActivity({ heartbeatUrl: heartbeat, log: x => logs.push(x), fetcher: async (url) => {
      calls.push(url);
      return url === STAGING_HEALTH_URL ? (ok ? healthy() : new Response('secret', { status: 503 })) : new Response('OK');
    }});
    assert.equal(code, ok ? 0 : 1);
    assert.deepEqual(calls, [STAGING_HEALTH_URL, `${heartbeat}${ok ? '' : '/fail'}`]);
    assert.doesNotMatch(logs.join(' '), /secret|hc-ping/);
  }
});

test('invalid heartbeat cannot contact another service or production monitor path', async () => {
  for (const url of [undefined, 'http://hc-ping.com/x', 'https://evil.example/x', `${heartbeat}/start`, `${heartbeat}?token=x`]) {
    await assert.rejects(notifyHeartbeat(url, true, () => assert.fail('must not fetch')), /configuration/);
  }
});

test('heartbeat delivery error remains nonzero, sanitized, and cannot report success', async () => {
  const logs = [];
  assert.equal(await runActivity({ heartbeatUrl: heartbeat, log: x => logs.push(x), fetcher: async (url) => {
    if (url === STAGING_HEALTH_URL) return healthy();
    throw new Error(`secret ${heartbeat}`);
  }}), 1);
  assert.doesNotMatch(logs.join(' '), /secret|hc-ping/);
});

test('workflow scopes credentials to staging/manual-or-schedule/main and keeps PR tests offline', () => {
  const workflow = readFileSync('.github/workflows/staging-supabase-activity.yml', 'utf8');
  assert.match(workflow, /cron: "17 3,9,15,21 \* \* \*"\n\s+timezone: "Europe\/Budapest"/);
  assert.match(workflow, /github\.ref == 'refs\/heads\/main'/);
  assert.match(workflow, /github\.repository == 'ugry65\/ahely-booking'/);
  assert.match(workflow, /github\.event_name == 'schedule' \|\| github\.event_name == 'workflow_dispatch'/);
  assert.match(workflow, /environment: staging/);
  assert.match(workflow, /permissions:\n\s+contents: read/);
  assert.doesNotMatch(workflow, /environment: production|SUPABASE_.*(KEY|URL)|pull_request_target/);
  assert.doesNotMatch(workflow.split('  staging-activity:')[0], /secrets\./);
});

test('Budapest schedule has four unique slots on DST change days', () => {
  const formatter = new Intl.DateTimeFormat('en-GB', { timeZone: 'Europe/Budapest', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' });
  for (const date of ['2026-03-29', '2026-10-25']) {
    const found = [];
    for (let ms = Date.parse(`${date}T00:00:00Z`); ms < Date.parse(`${date}T23:00:00Z`); ms += 60000) {
      const time = formatter.format(new Date(ms));
      if (['03:17', '09:17', '15:17', '21:17'].includes(time)) found.push(time);
    }
    assert.deepEqual(found, ['03:17', '09:17', '15:17', '21:17']);
  }
});
