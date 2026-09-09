#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
guard="$script_dir/lib/validate-staging-db-url.sh"

expect_pass() {
  "$guard" "$1"
}

expect_fail() {
  if "$guard" "$1" >/dev/null 2>&1; then
    echo "Expected staging DB URL validation to fail" >&2
    exit 1
  fi
}

expect_pass 'postgresql://postgres:secret@db.fvwapntzhavhgazeflri.supabase.co:5432/postgres'
expect_pass 'postgres://postgres.fvwapntzhavhgazeflri:secret@aws-0-eu-west-2.pooler.supabase.com:5432/postgres'

expect_fail ''
expect_fail 'https://db.fvwapntzhavhgazeflri.supabase.co/postgres'
expect_fail 'postgresql://postgres:fvwapntzhavhgazeflri@db.otherprojectref.supabase.co:5432/postgres'
expect_fail 'postgresql://postgres.otherprojectref:secret@aws-0-eu-west-2.pooler.supabase.com:5432/postgres'
expect_fail 'postgresql://postgres.fvwapntzhavhgazeflri:secret@untrusted.example.com:5432/postgres'

echo "Staging DB URL guard tests passed"
