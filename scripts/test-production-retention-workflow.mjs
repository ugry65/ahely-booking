import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const workflow = readFileSync(".github/workflows/production-backup-retention.yml", "utf8");

assert.match(workflow, /cron: "0 2 \* \* \*"/);
assert.match(workflow, /timezone: "Europe\/Budapest"/);
assert.match(workflow, /group: production-backup-storage-maintenance/);
assert.match(workflow, /vars\.RETENTION_AUTOMATION_ENABLED == 'true'/);
assert.match(workflow, /vars\.RETENTION_POLICY_VERSION == '2026-09-26-v2'/);
assert.match(workflow, /environment: production/);
assert.match(workflow, /BACKUP_B2_DAILY_ACCOUNT_ID/);
assert.match(workflow, /BACKUP_B2_DAILY_APPLICATION_KEY/);
assert.doesNotMatch(workflow, /BACKUP_B2_ACCOUNT_ID|BACKUP_B2_APPLICATION_KEY/);
assert.match(workflow, /inputs\.mode == 'apply'/);
assert.match(workflow, /CONFIRMATION.*RETENTION/s);
assert.match(workflow, /python3 \.\/scripts\/retention-production\.py --apply/);
assert.match(workflow, /python3 \.\/scripts\/retention-production\.py\n/);
assert.doesNotMatch(workflow, /^\s{2}(push|pull_request):/m);

console.log("Production retention workflow gates passed");
