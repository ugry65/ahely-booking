import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const workflow = readFileSync(".github/workflows/supabase-availability-healthcheck.yml", "utf8");

assert.match(workflow, /cron: "30 6 \* \* \*"/);
assert.match(workflow, /timezone: "Europe\/Budapest"/);
assert.match(workflow, /environment: production/);
assert.match(workflow, /SUPABASE_HEALTHCHECK_DB_URL/);
assert.match(workflow, /if \[ -z "\$\{SUPABASE_HEALTHCHECK_DB_URL:-\}" \]; then/);
assert.match(workflow, /postgres:\/\/\*\|postgresql:\/\/\*\)/);
assert.match(workflow, /-Atqc "select 1;"/);
assert.match(workflow, /PGCONNECT_TIMEOUT=15/);
assert.doesNotMatch(workflow, /SUPABASE_PRODUCTION_DB_URL|backup-production\.sh|INSERT|UPDATE|DELETE|CREATE|DROP|ALTER/);
assert.match(workflow, /permissions:\s*\n\s+contents: read/);

console.log("Supabase availability health-check workflow assertions passed.");
