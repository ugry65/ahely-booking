#!/usr/bin/env bash
set -Eeuo pipefail

umask 077

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_env() {
  local name="$1"
  if [ -z "${!name:-}" ]; then
    echo "Missing required environment variable: $name" >&2
    exit 1
  fi
}

for command_name in supabase psql age rclone sha256sum tar jq date python3; do
  require_command "$command_name"
done

require_env PRODUCTION_DB_URL
require_env PRODUCTION_DRILL_AGE_RECIPIENT
require_env BACKUP_GDRIVE_REMOTE
require_env BACKUP_B2_REMOTE

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
"$script_dir/lib/validate-production-db-url.sh" "$PRODUCTION_DB_URL"

work_dir="$(mktemp -d)"
cleanup() { rm -rf "$work_dir"; }
trap cleanup EXIT

# Supabase CLI selects its pg_dump image from config.toml, not from the remote
# server. The repo's local development baseline is PostgreSQL 15, while the
# approved production project is PostgreSQL 17. Keep that difference isolated to
# this temporary backup workspace and fail closed if production changes version.
server_version_num="$(psql "$PRODUCTION_DB_URL" -X -A -t -v ON_ERROR_STOP=1 -c 'show server_version_num')"
server_major="$((server_version_num / 10000))"
if [ "$server_major" -ne 17 ]; then
  echo "Unexpected production PostgreSQL major version: $server_major (expected 17)" >&2
  exit 1
fi

dump_project_dir="$work_dir/dump-project"
mkdir -p "$dump_project_dir/supabase"
cp -a "$script_dir/../supabase/." "$dump_project_dir/supabase/"
sed -i -E 's/^major_version = [0-9]+$/major_version = 17/' "$dump_project_dir/supabase/config.toml"
if ! grep -qx 'major_version = 17' "$dump_project_dir/supabase/config.toml"; then
  echo "Could not prepare the PostgreSQL 17 production dump client" >&2
  exit 1
fi

payload_dir="$work_dir/payload"
mkdir -p "$payload_dir"

utc_timestamp="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
file_timestamp="$(date -u +'%Y%m%dT%H%M%SZ')"
budapest_timestamp="$(TZ=Europe/Budapest date +'%Y-%m-%dT%H:%M:%S%z')"
git_sha="${GITHUB_SHA:-unknown}"
git_short="${git_sha:0:12}"
artifact_base="ahely-booking-production-drill_${file_timestamp}_${git_short}"
plain_bundle="$work_dir/${artifact_base}.tar.gz"
encrypted_bundle="$work_dir/${artifact_base}.tar.gz.age"
encrypted_checksum="$work_dir/${artifact_base}.tar.gz.age.sha256"

printf 'Creating PRODUCTION DRILL logical backup at %s (%s)\n' "$utc_timestamp" "$budapest_timestamp"

supabase --workdir "$dump_project_dir" db dump --db-url "$PRODUCTION_DB_URL" -f "$payload_dir/roles.sql" --role-only
supabase --workdir "$dump_project_dir" db dump --db-url "$PRODUCTION_DB_URL" -f "$payload_dir/schema.sql"
supabase --workdir "$dump_project_dir" db dump --db-url "$PRODUCTION_DB_URL" -f "$payload_dir/data.sql" --use-copy --data-only -x "storage.buckets_vectors" -x "storage.vector_indexes"
supabase --workdir "$dump_project_dir" db dump --db-url "$PRODUCTION_DB_URL" -f "$payload_dir/migration-schema.sql" --schema supabase_migrations
supabase --workdir "$dump_project_dir" db dump --db-url "$PRODUCTION_DB_URL" -f "$payload_dir/migration-history.sql" --use-copy --data-only --schema supabase_migrations

for backup_file in roles.sql schema.sql data.sql migration-schema.sql migration-history.sql; do
  if [ ! -s "$payload_dir/$backup_file" ]; then
    echo "Backup component is empty: $backup_file" >&2
    exit 1
  fi
done

psql "$PRODUCTION_DB_URL" -X -A -t -v ON_ERROR_STOP=1 -c "select json_build_object(
  'auth_users', (select count(*) from auth.users),
  'profiles', (select count(*) from public.profiles),
  'rooms', (select count(*) from public.rooms),
  'user_room_permissions', (select count(*) from public.user_room_permissions),
  'access_groups', (select count(*) from public.access_groups),
  'access_group_members', (select count(*) from public.access_group_members),
  'access_group_rooms', (select count(*) from public.access_group_rooms),
  'booking_series', (select count(*) from public.booking_series),
  'booking_series_occurrences', (select count(*) from public.booking_series_occurrences),
  'bookings_total', (select count(*) from public.bookings),
  'bookings_active', (select count(*) from public.bookings where status = 'active'),
  'bookings_cancelled', (select count(*) from public.bookings where status = 'cancelled'),
  'booking_cancellations', (select count(*) from public.booking_cancellations),
  'audit_logs', (select count(*) from public.audit_logs),
  'monthly_settlements', (select count(*) from public.monthly_settlements),
  'settlement_revisions', (select count(*) from public.settlement_revisions),
  'settlement_booking_lines', (select count(*) from public.settlement_booking_lines),
  'migration_history_rows', (select count(*) from supabase_migrations.schema_migrations),
  'migration_sample_auth_users', (select count(*) from auth.users where lower(email) = 'pappdalma17@gmail.com'),
  'migration_sample_profiles', (select count(*) from public.profiles where lower(email) = 'pappdalma17@gmail.com'),
  'migration_sample_bookings', (select count(*) from public.bookings b join public.profiles p on p.id = b.user_id where lower(p.email) = 'pappdalma17@gmail.com'),
  'migration_sample_direct_permissions', (select count(*) from public.user_room_permissions urp join public.profiles p on p.id = urp.user_id where lower(p.email) = 'pappdalma17@gmail.com'),
  'migration_sample_access_groups', (select count(*) from public.access_group_members agm join public.profiles p on p.id = agm.user_id where lower(p.email) = 'pappdalma17@gmail.com')
)" > "$payload_dir/control-counts.json"

jq -e 'type == "object"' "$payload_dir/control-counts.json" >/dev/null

(
  cd "$payload_dir"
  sha256sum roles.sql schema.sql data.sql migration-schema.sql migration-history.sql control-counts.json > DATA_SHA256SUMS
)

jq -n \
  --arg backupVersion "2" \
  --arg environment "production-drill" \
  --arg utcTimestamp "$utc_timestamp" \
  --arg budapestTimestamp "$budapest_timestamp" \
  --arg gitSha "$git_sha" \
  --slurpfile controlCounts "$payload_dir/control-counts.json" \
  '{backupVersion:$backupVersion, environment:$environment, utcTimestamp:$utcTimestamp, budapestTimestamp:$budapestTimestamp, gitSha:$gitSha, controlCounts:$controlCounts[0]}' \
  > "$payload_dir/manifest.json"

(
  cd "$payload_dir"
  sha256sum roles.sql schema.sql data.sql migration-schema.sql migration-history.sql control-counts.json manifest.json > SHA256SUMS
)

tar -czf "$plain_bundle" -C "$payload_dir" .
age \
  --recipient "$PRODUCTION_DRILL_AGE_RECIPIENT" \
  --output "$encrypted_bundle" \
  "$plain_bundle"

if [ ! -s "$encrypted_bundle" ]; then
  echo "Encrypted production drill artifact is empty" >&2
  exit 1
fi

artifact_sha="$(sha256sum "$encrypted_bundle" | awk '{print $1}')"
printf '%s  %s\n' "$artifact_sha" "$(basename "$encrypted_bundle")" > "$encrypted_checksum"

upload_and_verify() {
  local remote_root="$1"
  local remote_base="${remote_root%/}/production-drill"
  local remote_artifact="${remote_base}/$(basename "$encrypted_bundle")"
  local remote_checksum="${remote_base}/$(basename "$encrypted_checksum")"

  rclone copyto "$encrypted_bundle" "$remote_artifact" --no-traverse
  rclone copyto "$encrypted_checksum" "$remote_checksum" --no-traverse

  local remote_sha
  remote_sha="$(rclone cat "$remote_artifact" | sha256sum | awk '{print $1}')"
  if [ "$remote_sha" != "$artifact_sha" ]; then
    echo "Remote artifact checksum mismatch" >&2
    exit 1
  fi

  if [ "$(rclone cat "$remote_checksum")" != "$(cat "$encrypted_checksum")" ]; then
    echo "Remote checksum sidecar mismatch" >&2
    exit 1
  fi
}

upload_and_verify "$BACKUP_GDRIVE_REMOTE"
upload_and_verify "$BACKUP_B2_REMOTE"

printf 'PRODUCTION DRILL backup verified on both targets: %s\n' "$(basename "$encrypted_bundle")"
printf 'CONTROL_COUNTS=%s\n' "$(cat "$payload_dir/control-counts.json")"
