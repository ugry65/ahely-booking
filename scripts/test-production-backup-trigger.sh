#!/usr/bin/env bash
set -Eeuo pipefail

guard="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/validate-production-backup-trigger.sh"
bash "$guard" workflow_dispatch main PRODUCTION-BACKUP

for args in   "workflow_dispatch staging PRODUCTION-BACKUP"   "workflow_dispatch main WRONG"   "push main PRODUCTION-BACKUP"; do
  if bash "$guard" $args >/dev/null 2>&1; then
    echo "Expected production backup trigger validation failure: $args" >&2
    exit 1
  fi
done
echo "Production backup trigger guard tests passed"
