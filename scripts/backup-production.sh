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
require_env BACKUP_AGE_RECIPIENT
require_env BACKUP_GDRIVE_REMOTE
require_env BACKUP_B2_REMOTE

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
bash "$script_dir/lib/validate-production-db-url.sh" "$PRODUCTION_DB_URL"

work_dir="$(mktemp -d)"
cleanup() { rm -rf "$work_dir"; }
trap cleanup EXIT

# Supabase CLI chooses its pg_dump image from config.toml. Keep the production
# PostgreSQL 17 client override isolated from the repository's PostgreSQL 15
# development baseline, and stop if production changes major version.
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
artifact_base="ahely-booking-production_${file_timestamp}_${git_short}"
plain_bundle="$work_dir/${artifact_base}.tar.gz"
encrypted_bundle="$work_dir/${artifact_base}.tar.gz.age"
encrypted_checksum="$work_dir/${artifact_base}.tar.gz.age.sha256"

printf 'Creating production logical backup at %s (%s)\n' "$utc_timestamp" "$budapest_timestamp"

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
  'migration_history_rows', (select count(*) from supabase_migrations.schema_migrations)
)" > "$payload_dir/control-counts.json"

if ! jq -e 'type == "object"' "$payload_dir/control-counts.json" >/dev/null; then
  echo "Critical source control counts are not valid JSON" >&2
  exit 1
fi

(
  cd "$payload_dir"
  sha256sum roles.sql schema.sql data.sql migration-schema.sql migration-history.sql control-counts.json > DATA_SHA256SUMS
)

roles_sha="$(sha256sum "$payload_dir/roles.sql" | awk '{print $1}')"
schema_sha="$(sha256sum "$payload_dir/schema.sql" | awk '{print $1}')"
data_sha="$(sha256sum "$payload_dir/data.sql" | awk '{print $1}')"
migration_schema_sha="$(sha256sum "$payload_dir/migration-schema.sql" | awk '{print $1}')"
migration_history_sha="$(sha256sum "$payload_dir/migration-history.sql" | awk '{print $1}')"
control_counts_sha="$(sha256sum "$payload_dir/control-counts.json" | awk '{print $1}')"
supabase_version="$(supabase --version | head -n 1)"

jq -n \
  --arg backupVersion "2" \
  --arg environment "production" \
  --arg utcTimestamp "$utc_timestamp" \
  --arg budapestTimestamp "$budapest_timestamp" \
  --arg gitSha "$git_sha" \
  --arg supabaseVersion "$supabase_version" \
  --arg rolesSha256 "$roles_sha" \
  --arg schemaSha256 "$schema_sha" \
  --arg dataSha256 "$data_sha" \
  --arg migrationSchemaSha256 "$migration_schema_sha" \
  --arg migrationHistorySha256 "$migration_history_sha" \
  --arg controlCountsSha256 "$control_counts_sha" \
  --slurpfile controlCounts "$payload_dir/control-counts.json" \
  '{
    backupVersion: $backupVersion,
    environment: $environment,
    utcTimestamp: $utcTimestamp,
    budapestTimestamp: $budapestTimestamp,
    gitSha: $gitSha,
    supabaseCliVersion: $supabaseVersion,
    controlCounts: $controlCounts[0],
    files: {
      "roles.sql": {sha256: $rolesSha256},
      "schema.sql": {sha256: $schemaSha256},
      "data.sql": {sha256: $dataSha256},
      "migration-schema.sql": {sha256: $migrationSchemaSha256},
      "migration-history.sql": {sha256: $migrationHistorySha256},
      "control-counts.json": {sha256: $controlCountsSha256}
    }
  }' > "$payload_dir/manifest.json"

(
  cd "$payload_dir"
  sha256sum roles.sql schema.sql data.sql migration-schema.sql migration-history.sql control-counts.json manifest.json > SHA256SUMS
)

tar -czf "$plain_bundle" -C "$payload_dir" .
age --recipient "$BACKUP_AGE_RECIPIENT" --output "$encrypted_bundle" "$plain_bundle"

if [ ! -s "$encrypted_bundle" ]; then
  echo "Encrypted backup artifact is empty" >&2
  exit 1
fi

artifact_sha="$(sha256sum "$encrypted_bundle" | awk '{print $1}')"
printf '%s  %s\n' "$artifact_sha" "$(basename "$encrypted_bundle")" > "$encrypted_checksum"

upload_and_verify() {
  local remote_base="$1"
  local remote_artifact="${remote_base%/}/$(basename "$encrypted_bundle")"
  local remote_checksum="${remote_base%/}/$(basename "$encrypted_checksum")"

  printf 'Uploading encrypted artifact to configured remote...\n'
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

printf 'Backup artifact verified on both independent targets: %s\n' "$(basename "$encrypted_bundle")"
