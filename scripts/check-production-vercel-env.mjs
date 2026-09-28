import { readFileSync } from 'node:fs';

const PRODUCTION_ID = 'prj_ZW7nVAOcYPjttZtES2iHoeA8iOTo';
const PRODUCTION_REF = 'yasrmxwjojepessivhmc';

export function parseVercelEnv(envText) {
  const env = new Map();
  for (const line of envText.split(/\r?\n/)) {
    const match = line.match(/^([A-Z][A-Z0-9_]*)=(.*)$/);
    if (!match) continue;
    let value = match[2];
    if (value.startsWith('"')) {
      try { value = JSON.parse(value); } catch { throw new Error(`Invalid env encoding for ${match[1]}`); }
    }
    env.set(match[1], value);
  }
  return env;
}

export function validateProductionVercelConfig(project, envText, expectedOrgId) {
  if (project?.projectId !== PRODUCTION_ID || !expectedOrgId || project.orgId !== expectedOrgId) {
    throw new Error('Linked Vercel project identity mismatch');
  }
  const env = parseVercelEnv(envText);
  const actualUrl = env.get('NEXT_PUBLIC_SUPABASE_URL');
  if (actualUrl !== `https://${PRODUCTION_REF}.supabase.co`) {
    throw new Error('Vercel production Supabase URL mismatch');
  }
  if (env.get('SITE_URL') !== 'https://foglalas.a-hely.com') {
    throw new Error('Vercel production site URL mismatch');
  }
  if (!env.get('NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY') || !env.get('SUPABASE_SERVICE_ROLE_KEY')) {
    throw new Error('Required Supabase production keys missing');
  }
  return true;
}

if (process.argv[1]?.endsWith('/check-production-vercel-env.mjs')) {
  validateProductionVercelConfig(
    JSON.parse(readFileSync('.vercel/project.json', 'utf8')),
    readFileSync('.vercel/.env.production.local', 'utf8'),
    process.env.VERCEL_ORG_ID,
  );
  console.log('Vercel production project, Supabase URL, site URL and key presence verified.');
}
