#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
dump_script="$script_dir/lib/dump-staging-postgres17.sh"

bash -n "$dump_script"

grep -Fq 'postgres:17.6-bookworm' "$dump_script"
grep -Fq 'pg_dump (PostgreSQL) 17.6' "$dump_script"
grep -Fq 'server_major" != "17"' "$dump_script"
grep -Fq -- '--roles-only' "$dump_script"
grep -Fq -- '--schema-only' "$dump_script"
grep -Fq -- '--data-only' "$dump_script"
grep -Fq -- '--schema supabase_migrations' "$dump_script"
grep -Fq -- '--exclude-table "storage.buckets_vectors"' "$dump_script"
grep -Fq -- '--exclude-table "storage.vector_indexes"' "$dump_script"

if grep -Fq 'supabase db dump' "$dump_script"; then
  echo "PostgreSQL 15-backed Supabase CLI dump must not be used" >&2
  exit 1
fi

echo "Staging PostgreSQL 17 dump guard tests passed."
