import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { validatePreviewScope } from './check-production-preview-scope.mjs';

const production = 'SUPABASE_SERVICE_ROLE_KEY="prod-key"\nNEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY="prod-public"\nCRON_SECRET="prod-cron"\nSMTP_PASS="prod-smtp"\n';
const preview = 'SUPABASE_SERVICE_ROLE_KEY="staging-key"\nNEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY="staging-public"\nCRON_SECRET="staging-cron"\nSMTP_PASS="staging-smtp"\nNEXT_PUBLIC_SUPABASE_URL="https://fvwapntzhavhgazeflri.supabase.co"\nSITE_URL="https://ahely-booking-staging-web.vercel.app"\n';

test('Preview cannot use production credentials or Supabase project', () => {
  assert.equal(validatePreviewScope(production, preview), true);
  for (const [key, stagingValue, productionValue] of [
    ['SUPABASE_SERVICE_ROLE_KEY', 'staging-key', 'prod-key'],
    ['NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY', 'staging-public', 'prod-public'],
    ['CRON_SECRET', 'staging-cron', 'prod-cron'],
    ['SMTP_PASS', 'staging-smtp', 'prod-smtp'],
  ]) {
    assert.throws(() => validatePreviewScope(production, preview.replace(`${key}="${stagingValue}"`, `${key}="${productionValue}"`)), /available in Preview/);
  }
  assert.throws(() => validatePreviewScope(production, preview.replace('fvwapntzhavhgazeflri', 'yasrmxwjojepessivhmc')), /production Supabase URL/);
  assert.throws(() => validatePreviewScope(production, preview.replace('https://ahely-booking-staging-web.vercel.app', 'https://foglalas.a-hely.com')), /production site URL/);
  assert.throws(() => validatePreviewScope('CRON_SECRET="prod-cron"\n', preview), /Missing production service-role/);
});
