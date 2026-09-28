import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { validateProductionVercelConfig as check } from './check-production-vercel-env.mjs';

const project = { projectId: 'prj_ZW7nVAOcYPjttZtES2iHoeA8iOTo', orgId: 'team_test' };
const env = 'NEXT_PUBLIC_SUPABASE_URL="https://yasrmxwjojepessivhmc.supabase.co"\nSITE_URL="https://foglalas.a-hely.com"\nNEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY="key"\nSUPABASE_SERVICE_ROLE_KEY="secret"\n';
test('production identity requires actual linked project and pulled runtime values', () => {
  assert.equal(check(project, env, 'team_test'), true);
  assert.throws(() => check({ ...project, projectId: 'prj_LzVgZgZBCAj4zA64YoYED3XkLGKW' }, env, 'team_test'), /project identity/);
  assert.throws(() => check(project, env.replace('yasrmxwjojepessivhmc', 'fvwapntzhavhgazeflri'), 'team_test'), /Supabase URL/);
  assert.throws(() => check(project, env.replace('https://foglalas.a-hely.com', 'https://ahely-booking-staging-web.vercel.app'), 'team_test'), /site URL/);
  assert.throws(() => check(project, env.replace('SUPABASE_SERVICE_ROLE_KEY="secret"', ''), 'team_test'), /keys missing/);
});
