import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { validatePreviewScope } from './check-production-preview-scope.mjs';

const production = 'SUPABASE_SERVICE_ROLE_KEY="prod-key"\nCRON_SECRET="prod-cron"\nSMTP_PASS="prod-smtp"\n';
const preview = 'SUPABASE_SERVICE_ROLE_KEY="staging-key"\nCRON_SECRET="staging-cron"\nSMTP_PASS="staging-smtp"\nNEXT_PUBLIC_SUPABASE_URL="https://fvwapntzhavhgazeflri.supabase.co"\n';

test('Preview cannot use production credentials or Supabase project', () => {
  assert.equal(validatePreviewScope(production, preview), true);
  for (const [key, stagingValue, productionValue] of [
    ['SUPABASE_SERVICE_ROLE_KEY', 'staging-key', 'prod-key'],
    ['CRON_SECRET', 'staging-cron', 'prod-cron'],
    ['SMTP_PASS', 'staging-smtp', 'prod-smtp'],
  ]) {
    assert.throws(() => validatePreviewScope(production, preview.replace(`${key}="${stagingValue}"`, `${key}="${productionValue}"`)), /available in Preview/);
  }
  assert.throws(() => validatePreviewScope(production, preview.replace('fvwapntzhavhgazeflri', 'yasrmxwjojepessivhmc')), /production Supabase URL/);
  assert.throws(() => validatePreviewScope('CRON_SECRET="prod-cron"\n', preview), /Missing production service-role/);
});
