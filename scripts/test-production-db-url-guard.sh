#!/usr/bin/env bash
set -Eeuo pipefail

guard="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/validate-production-db-url.sh"

expect_fail() {
  if bash "$guard" "$1" >/dev/null 2>&1; then
    echo "Expected production DB URL validation to fail" >&2
    exit 1
  fi
}

bash "$guard" 'postgresql://postgres:secret@db.yasrmxwjojepessivhmc.supabase.co:5432/postgres'
bash "$guard" 'postgres://postgres.yasrmxwjojepessivhmc:secret@aws-0-eu-west-2.pooler.supabase.com:5432/postgres'
expect_fail ''
expect_fail 'https://db.yasrmxwjojepessivhmc.supabase.co/postgres'
expect_fail 'postgresql://postgres:secret@db.fvwapntzhavhgazeflri.supabase.co:5432/postgres'
expect_fail 'postgresql://postgres.fvwapntzhavhgazeflri:secret@aws-0-eu-west-2.pooler.supabase.com:5432/postgres'
expect_fail 'postgresql://postgres.yasrmxwjojepessivhmc:secret@untrusted.example.com:5432/postgres'
echo "Production DB URL guard tests passed"
