#!/usr/bin/env bash
set -Eeuo pipefail

validator="./scripts/lib/validate-production-backup-schedule-trigger.sh"

test "$(bash "$validator" workflow_dispatch main BACKUP '')" = "manual"
test "$(bash "$validator" schedule main '' '0 8 * * *')" = "08"
test "$(bash "$validator" schedule main '' '0 12 * * *')" = "12"
test "$(bash "$validator" schedule main '' '0 16 * * *')" = "16"
test "$(bash "$validator" schedule main '' '0 20 * * *')" = "20"

if bash "$validator" workflow_dispatch main WRONG '' >/dev/null 2>&1; then
  echo "Invalid manual confirmation unexpectedly passed" >&2
  exit 1
fi
if bash "$validator" schedule staging '' '0 8 * * *' >/dev/null 2>&1; then
  echo "Non-main scheduled backup unexpectedly passed" >&2
  exit 1
fi
if bash "$validator" schedule main '' '0 9 * * *' >/dev/null 2>&1; then
  echo "Unknown schedule unexpectedly passed" >&2
  exit 1
fi
if bash "$validator" pull_request main '' '' >/dev/null 2>&1; then
  echo "Pull request event unexpectedly passed" >&2
  exit 1
fi

echo "Production backup schedule trigger tests passed"
