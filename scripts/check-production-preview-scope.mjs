import { readFileSync } from 'node:fs';
import { parseVercelEnv } from './check-production-vercel-env.mjs';

const PRODUCTION_REF = 'yasrmxwjojepessivhmc';
const SENSITIVE_KEYS = ['SUPABASE_SERVICE_ROLE_KEY', 'NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY', 'CRON_SECRET', 'SMTP_PASS'];

export function validatePreviewScope(productionText, previewText) {
  const production = parseVercelEnv(productionText);
  const preview = parseVercelEnv(previewText);
  if (!production.get('SUPABASE_SERVICE_ROLE_KEY')) {
    throw new Error('Missing production service-role key for scope comparison');
  }
  for (const key of SENSITIVE_KEYS) {
    if (production.get(key) && preview.get(key) === production.get(key)) {
      throw new Error(`Refusing release: production ${key} is available in Preview`);
    }
  }
  for (const key of ['NEXT_PUBLIC_SUPABASE_URL', 'SUPABASE_URL']) {
    if (preview.get(key) === `https://${PRODUCTION_REF}.supabase.co`) {
      throw new Error(`Refusing release: production Supabase URL is available in Preview as ${key}`);
    }
  }
  if (preview.get('SITE_URL') === 'https://foglalas.a-hely.com') {
    throw new Error('Refusing release: production site URL is available in Preview');
  }
  return true;
}

if (process.argv[1]?.endsWith('/check-production-preview-scope.mjs')) {
  validatePreviewScope(
    readFileSync('.vercel/.env.production.local', 'utf8'),
    readFileSync('.vercel/.env.preview.local', 'utf8'),
  );
  console.log('Preview scope comparison passed without printing secret values.');
}
