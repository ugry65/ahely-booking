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

for command_name in supabase psql age rclone sha256sum tar jq date curl; do
  require_command "$command_name"
done

require_env PRODUCTION_DB_URL
require_env BACKUP_AGE_RECIPIENT
require_env BACKUP_GDRIVE_REMOTE
require_env BACKUP_B2_REMOTE

work_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$work_dir"
}
trap cleanup EXIT

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

supabase db dump \
  --db-url "$PRODUCTION_DB_URL" \
  -f "$payload_dir/roles.sql" \
  --role-only

supabase db dump \
  --db-url "$PRODUCTION_DB_URL" \
  -f "$payload_dir/schema.sql"

supabase db dump \
  --db-url "$PRODUCTION_DB_URL" \
  -f "$payload_dir/data.sql" \
  --use-copy \
  --data-only \
  -x "storage.buckets_vectors" \
  -x "storage.vector_indexes"

# The migration history data is not self-describing. Preserve the exact
# production migration metadata schema separately so a restore is independent
# from whatever schema a future/local Supabase CLI version happens to create.
supabase db dump \
  --db-url "$PRODUCTION_DB_URL" \
  -f "$payload_dir/migration-schema.sql" \
  --schema supabase_migrations

supabase db dump \
  --db-url "$PRODUCTION_DB_URL" \
  -f "$payload_dir/migration-history.sql" \
  --use-copy \
  --data-only \
  --schema supabase_migrations

for backup_file in roles.sql schema.sql data.sql migration-schema.sql migration-history.sql; do
  if [ ! -s "$payload_dir/$backup_file" ]; then
    echo "Backup component is empty: $backup_file" >&2
    exit 1
  fi
done

psql \
  "$PRODUCTION_DB_URL" \
  -X \
  -A \
  -t \
  -v ON_ERROR_STOP=1 \
  -c "select json_build_object(
    'auth_users', (select count(*) from auth.users),
    'profiles', (select count(*) from public.profiles),
    'rooms', (select count(*) from public.rooms),
    'user_room_permissions', (select count(*) from public.user_room_permissions),
    'booking_series', (select count(*) from public.booking_series),
    'bookings_total', (select count(*) from public.bookings),
    'bookings_active', (select count(*) from public.bookings where status = 'active'),
    'bookings_cancelled', (select count(*) from public.bookings where status = 'cancelled'),
    'booking_cancellations', (select count(*) from public.booking_cancellations),
    'audit_logs', (select count(*) from public.audit_logs),
    'monthly_settlements', (select count(*) from public.monthly_settlements),
    'settlement_revisions', (select count(*) from public.settlement_revisions),
    'settlement_booking_lines', (select count(*) from public.settlement_booking_lines)
  )" \
  > "$payload_dir/control-counts.json"

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

age \
  --recipient "$BACKUP_AGE_RECIPIENT" \
  --output "$encrypted_bundle" \
  "$plain_bundle"

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

  local remote_checksum_content
  remote_checksum_content="$(rclone cat "$remote_checksum")"
  if [ "$remote_checksum_content" != "$(cat "$encrypted_checksum")" ]; then
    echo "Remote checksum sidecar mismatch" >&2
    exit 1
  fi
}

upload_and_verify "$BACKUP_GDRIVE_REMOTE"
upload_and_verify "$BACKUP_B2_REMOTE"

printf 'Backup artifact verified on both independent targets: %s\n' "$(basename "$encrypted_bundle")"

if [ -n "${BACKUP_HEARTBEAT_URL:-}" ]; then
  curl \
    --fail \
    --silent \
    --show-error \
    --retry 4 \
    --retry-all-errors \
    --max-time 20 \
    "$BACKUP_HEARTBEAT_URL" \
    >/dev/null
  printf 'Backup success heartbeat sent.\n'
fi
