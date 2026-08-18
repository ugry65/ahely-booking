import { createClient } from '@supabase/supabase-js';
import { assertStagingUrl } from './lib/staging-uat-bootstrap.mjs';
import { bootstrapUat, verifyUat } from './lib/staging-uat-operations.mjs';

function requiredEnv(name) {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`Hiányzó környezeti változó: ${name}`);
  return value;
}

const mode = process.argv[2] ?? 'verify';
if (!['bootstrap', 'verify'].includes(mode)) {
  throw new Error('Használat: node scripts/bootstrap-staging-uat.mjs [bootstrap|verify]');
}

const url = assertStagingUrl(requiredEnv('NEXT_PUBLIC_SUPABASE_URL'));
const serviceRoleKey = requiredEnv('SUPABASE_STAGING_SERVICE_ROLE_KEY');
const resetEmail = requiredEnv('UAT_RESET_EMAIL').toLowerCase();
const password = requiredEnv('UAT_SHARED_PASSWORD');
if (password.length < 12) throw new Error('Az UAT_SHARED_PASSWORD legalább 12 karakter legyen.');

const client = createClient(url, serviceRoleKey, {
  auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
});

if (mode === 'bootstrap') {
  const { exceptionDate } = await bootstrapUat(client, resetEmail, password);
  console.log(`UAT bootstrap kész. Kivételdátum: ${exceptionDate}.`);
}

await verifyUat(client, resetEmail);
console.log('UAT staging konfiguráció ellenőrzése sikeres.');
