import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";

const workflowPath = ".github/workflows/production-backup.yml";
const workflow = readFileSync(workflowPath, "utf8");
const expectedCrons = ["0 8 * * *", "0 12 * * *", "0 16 * * *", "0 20 * * *"];

const schedulePairs = [...workflow.matchAll(/- cron: "([^"]+)"\n\s+timezone: "([^"]+)"/g)]
  .map((match) => ({ cron: match[1], timezone: match[2] }));

assert.deepEqual(
  schedulePairs,
  expectedCrons.map((cron) => ({ cron, timezone: "Europe/Budapest" })),
  "The workflow must declare exactly the four approved Budapest-local schedules",
);
assert.match(workflow, /SCHEDULE_ENABLED: \$\{\{ vars\.PRODUCTION_BACKUP_SCHEDULE_ENABLED \}\}/);
assert.match(workflow, /if \[ "\$SCHEDULE_ENABLED" != "true" \]/);
assert.match(workflow, /environment: production/);
assert.match(workflow, /BACKUP_B2_DAILY_ACCOUNT_ID/);
assert.match(workflow, /BACKUP_B2_DAILY_APPLICATION_KEY/);
assert.doesNotMatch(workflow, /BACKUP_B2_RETENTION|B2_APPLICATION_KEY/);
assert.doesNotMatch(workflow, /^\s{2}(push|pull_request):/m);
assert.doesNotMatch(workflow, /production-backup:\n(?:.|\n)*?^    env:/m);
assert.match(workflow, /actions\/checkout@[0-9a-f]{40}/);
assert.match(workflow, /supabase\/setup-cli@[0-9a-f]{40}/);
for (const slot of ["08", "12", "16", "20"]) {
  assert.match(workflow, new RegExp(`BACKUP_HEARTBEAT_${slot}_URL`));
}
assert.match(workflow, /success\(\) && github\.event_name == 'schedule'/);
assert.match(workflow, /\(failure\(\) \|\| cancelled\(\)\).*steps\.heartbeat_start\.outcome == 'success'/);

for (const file of readdirSync(".github/workflows").filter((name) => name.endsWith(".yml"))) {
  const candidate = readFileSync(`.github/workflows/${file}`, "utf8");
  if (candidate.includes("environment: production")) {
    assert.doesNotMatch(candidate, /^\s{2}(push|pull_request):/m, `${file} must not expose production Environment to push/PR events`);
  }
}

const formatter = new Intl.DateTimeFormat("en-CA", {
  timeZone: "Europe/Budapest",
  year: "numeric",
  month: "2-digit",
  day: "2-digit",
  hour: "2-digit",
  minute: "2-digit",
  hourCycle: "h23",
});

function localTimestamp(date) {
  const parts = Object.fromEntries(
    formatter.formatToParts(date).filter((part) => part.type !== "literal").map((part) => [part.type, part.value]),
  );
  return `${parts.year}-${parts.month}-${parts.day} ${parts.hour}:${parts.minute}`;
}

function utcMatchesForLocalDay(localDate, localTimes) {
  const start = Date.parse(`${localDate}T00:00:00Z`) - 12 * 60 * 60 * 1000;
  const end = start + 48 * 60 * 60 * 1000;
  const counts = Object.fromEntries(localTimes.map((time) => [time, []]));
  for (let time = start; time < end; time += 60 * 1000) {
    const instant = new Date(time);
    const local = localTimestamp(instant);
    for (const localTime of localTimes) {
      if (local === `${localDate} ${localTime}`) counts[localTime].push(instant.toISOString());
    }
  }
  return counts;
}

const localTimes = ["08:00", "12:00", "16:00", "20:00"];
for (const transitionDay of ["2026-03-29", "2026-10-25"]) {
  const matches = utcMatchesForLocalDay(transitionDay, localTimes);
  for (const localTime of localTimes) {
    assert.equal(matches[localTime].length, 1, `${transitionDay} ${localTime} must occur exactly once`);
  }
}

const winter = utcMatchesForLocalDay("2026-01-15", localTimes);
const summer = utcMatchesForLocalDay("2026-07-15", localTimes);
assert.equal(winter["08:00"][0], "2026-01-15T07:00:00.000Z");
assert.equal(winter["20:00"][0], "2026-01-15T19:00:00.000Z");
assert.equal(summer["08:00"][0], "2026-07-15T06:00:00.000Z");
assert.equal(summer["20:00"][0], "2026-07-15T18:00:00.000Z");

console.log("Production backup schedule and DST tests passed");
