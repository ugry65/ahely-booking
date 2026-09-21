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
./scripts/test-booking-concurrency.sh
./scripts/test-booking-mutation-concurrency.sh
bash ./scripts/test-room-access-concurrency.sh
bash ./scripts/test-recurring-booking-concurrency.sh
bash ./scripts/test-booking-email-outbox-concurrency.sh
supabase db lint --level warning
