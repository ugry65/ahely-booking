export const EXPECTED_STAGING_URL = 'https://fvwapntzhavhgazeflri.supabase.co';

export function assertStagingUrl(url) {
  const normalized = url.replace(/\/$/, '');
  if (normalized !== EXPECTED_STAGING_URL) {
    throw new Error(`Fail-closed: kizárólag a staging projekt engedélyezett (${EXPECTED_STAGING_URL}).`);
  }
  return normalized;
}

export function budapestDatePlusDays(days, now = new Date()) {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Europe/Budapest',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(now);
  const get = (type) => Number(parts.find((part) => part.type === type)?.value);
  const date = new Date(Date.UTC(get('year'), get('month') - 1, get('day') + days));
  return date.toISOString().slice(0, 10);
}
