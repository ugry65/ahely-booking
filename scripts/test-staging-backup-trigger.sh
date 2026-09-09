#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
guard="$script_dir/lib/validate-staging-backup-trigger.sh"
fixture="$(mktemp)"
trap 'rm -f "$fixture"' EXIT

printf 'STAGING-BACKUP\nissue=124\n' > "$fixture"

"$guard" workflow_dispatch staging STAGING-BACKUP "$fixture"
"$guard" push staging "" "$fixture"

expect_fail() {
  if "$@" >/dev/null 2>&1; then
    echo "Expected staging backup trigger validation to fail" >&2
    exit 1
  fi
}

expect_fail "$guard" workflow_dispatch staging WRONG "$fixture"
expect_fail "$guard" workflow_dispatch main STAGING-BACKUP "$fixture"
expect_fail "$guard" push main "" "$fixture"
expect_fail "$guard" pull_request staging "" "$fixture"

printf 'WRONG\n' > "$fixture"
expect_fail "$guard" push staging "" "$fixture"
expect_fail "$guard" push staging "" "$fixture.missing"

echo "Staging backup trigger guard tests passed"
