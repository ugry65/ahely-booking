#!/usr/bin/env bash
set -Eeuo pipefail

guard="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/validate-production-restore-trigger.sh"
artifact='ahely-booking-production-drill_20260910T120000Z_123456789abc.tar.gz.age'

bash "$guard" workflow_dispatch main RESTORE-PRODUCTION "$artifact"

for args in   "workflow_dispatch staging RESTORE-PRODUCTION $artifact"   "workflow_dispatch main WRONG $artifact"   "push main RESTORE-PRODUCTION $artifact"   "workflow_dispatch main RESTORE-PRODUCTION ahely-booking-staging-drill_20260910T120000Z_123456789abc.tar.gz.age"   "workflow_dispatch main RESTORE-PRODUCTION ../$artifact"; do
  if bash "$guard" $args >/dev/null 2>&1; then
    echo "Expected production restore trigger validation failure: $args" >&2
    exit 1
  fi
done
echo "Production restore trigger guard tests passed"
