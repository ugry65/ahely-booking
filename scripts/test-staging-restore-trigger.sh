#!/usr/bin/env bash
set -Eeuo pipefail

guard="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/validate-staging-restore-trigger.sh"
artifact='ahely-booking-staging-drill_20260909T180458Z_503bf621ef4a.tar.gz.age'

bash "$guard" push staging RESTORE-STAGING "$artifact"
bash "$guard" workflow_dispatch staging RESTORE-STAGING "$artifact"

for args in \
  "push main RESTORE-STAGING $artifact" \
  "push staging WRONG $artifact" \
  "schedule staging RESTORE-STAGING $artifact" \
  "push staging RESTORE-STAGING ahely-booking-production_20260909.tar.gz.age" \
  "push staging RESTORE-STAGING ../$artifact"; do
  if bash "$guard" $args >/dev/null 2>&1; then
    echo "Expected restore trigger validation failure: $args" >&2
    exit 1
  fi
done

echo "Staging restore trigger guard tests passed"
