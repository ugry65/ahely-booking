#!/usr/bin/env bash
set -euo pipefail

node <<'NODE'
const fs = require("fs");
const config = JSON.parse(fs.readFileSync("vercel.json", "utf8"));
const crons = Array.isArray(config.crons) ? config.crons : [];

if (crons.some((cron) => cron.path === "/api/internal/booking-email-worker")) {
  throw new Error("booking-email-worker must not be scheduled by Vercel Cron while booking e-mail notifications are disabled");
}

const expected = [
  "15 0 * * *",
  "15 6 * * *",
  "15 12 * * *",
  "15 18 * * *",
];
const health = crons
  .filter((cron) => cron.path === "/api/internal/production-health")
  .map((cron) => cron.schedule)
  .sort();
const wanted = [...expected].sort();

if (JSON.stringify(health) !== JSON.stringify(wanted)) {
  throw new Error(`production-health cron schedule changed unexpectedly: ${JSON.stringify(health)}`);
}

console.log("Vercel cron policy OK: booking e-mail worker unscheduled; production health schedule preserved.");
NODE
