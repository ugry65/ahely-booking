#!/usr/bin/env bash
set -Eeuo pipefail

guard="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/validate-production-backup-trigger.sh"
fixture="$(mktemp)"
trap 'rm -f "$fixture"' EXIT
printf 'PRODUCTION-BACKUP\nissue=124\n' > "$fixture"

bash "$guard" workflow_dispatch main PRODUCTION-BACKUP "$fixture"
bash "$guard" push main "" "$fixture"

for args in   "workflow_dispatch staging PRODUCTION-BACKUP $fixture"   "workflow_dispatch main WRONG $fixture"   "push staging '' $fixture"   "pull_request main PRODUCTION-BACKUP $fixture"; do
  if bash "$guard" $args >/dev/null 2>&1; then
    echo "Expected production backup trigger validation failure: $args" >&2
    exit 1
  fi
done
printf 'WRONG\n' > "$fixture"
if bash "$guard" push main "" "$fixture" >/dev/null 2>&1; then
  echo "Expected invalid production backup marker to fail" >&2
  exit 1
fi
echo "Production backup trigger guard tests passed"
