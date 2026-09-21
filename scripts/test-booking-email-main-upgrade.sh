#!/usr/bin/env bash
# Disposable local Supabase only: verify late application onto the main schema.
set -euo pipefail
cd "$(dirname "$0")/.."
readonly db_url='postgresql://postgres:postgres@127.0.0.1:54322/postgres'
readonly migrations=(
  202609030001_booking_email_outbox.sql
  202609030002_enqueue_booking_emails_from_audit.sql
  20260903185410_booking_email_delivery_monitor.sql
)
holding_dir="$(mktemp -d)"
restore_files() {
  for name in "${migrations[@]}"; do
    if [[ -f "$holding_dir/$name" ]]; then
      mv "$holding_dir/$name" "supabase/migrations/$name"
    fi
  done
  rmdir "$holding_dir"
}
trap restore_files EXIT
for name in "${migrations[@]}"; do
  mv "supabase/migrations/$name" "$holding_dir/$name"
done
# --local explicitly prevents any linked project database mutation.
supabase db reset --local
for name in "${migrations[@]}"; do
  mv "$holding_dir/$name" "supabase/migrations/$name"
  psql "$db_url" -X -v ON_ERROR_STOP=1 -f "supabase/migrations/$name"
done
supabase test db
echo 'Main schema -> booking email upgrade and regression suite passed.'
