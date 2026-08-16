#!/usr/bin/env bash
set -euo pipefail

if ! command -v supabase >/dev/null 2>&1; then
  echo "Hiba: a Supabase CLI nincs telepítve." >&2
  echo "Telepítés: https://supabase.com/docs/guides/local-development/cli/getting-started" >&2
  exit 127
fi

supabase db start
supabase db reset
supabase test db
supabase db lint --level warning
