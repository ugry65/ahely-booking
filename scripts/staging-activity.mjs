import { pathToFileURL } from 'node:url';

export const STAGING_HEALTH_URL = 'https://ahely-booking-staging-web.vercel.app/api/health';

// No caller-controlled DB/HTTP target and no credentials. Never follow redirects.
export async function probeStaging(fetcher = fetch, timeoutMs = 25000) {
  try {
    const response = await fetcher(STAGING_HEALTH_URL, {
      method: 'GET', redirect: 'error', cache: 'no-store',
      headers: { 'Cache-Control': 'no-cache' },
      signal: AbortSignal.timeout(timeoutMs),
    });
    if (response.status !== 200 || !response.headers.get('content-type')?.includes('application/json') ||
        !response.headers.get('cache-control')?.includes('no-store')) return false;
    const body = await response.json();
    return body.ok === true && body.database === 'ok' &&
      Number.isFinite(body.responseTimeMs) && body.responseTimeMs >= 0;
  } catch {
    return false; // Never print response bodies, URLs from errors, or internal details.
  }
}

export async function notifyHeartbeat(url, success, fetcher = fetch) {
  if (!/^https:\/\/hc-ping\.com\/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(url ?? '')) {
    throw new Error('Missing or invalid staging heartbeat configuration.');
  }
  try {
    const response = await fetcher(`${url}${success ? '' : '/fail'}`, {
      method: 'GET', redirect: 'error', signal: AbortSignal.timeout(10000),
    });
    if (!response.ok) throw new Error();
  } catch {
    throw new Error('Staging heartbeat delivery failed.');
  }
}

export async function runActivity({ heartbeatUrl, fetcher = fetch, log = console.log }) {
  const ok = await probeStaging(fetcher);
  log(ok ? 'Staging database activity probe passed.' : 'Staging database activity probe failed.');
  try {
    await notifyHeartbeat(heartbeatUrl, ok, fetcher);
  } catch (error) {
    log(error.message);
    return 1;
  }
  return ok ? 0 : 1;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  process.exitCode = await runActivity({ heartbeatUrl: process.env.STAGING_ACTIVITY_HEARTBEAT_URL });
}
