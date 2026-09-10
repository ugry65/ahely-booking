#!/usr/bin/env bash
set -Eeuo pipefail

umask 077

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

require_env() {
  local name="$1"
  [ -n "${!name:-}" ] || {
    echo "Missing required environment variable: $name" >&2
    exit 1
  }
}

for command_name in supabase psql age rclone sha256sum tar jq docker cmp; do
  require_command "$command_name"
done

require_env PRODUCTION_DRILL_ARTIFACT
require_env PRODUCTION_DRILL_AGE_IDENTITY
require_env BACKUP_GDRIVE_REMOTE
require_env BACKUP_B2_REMOTE

if [[ "$PRODUCTION_DRILL_ARTIFACT" =~ / ]] ||
  [[ ! "$PRODUCTION_DRILL_ARTIFACT" =~ ^ahely-booking-production-drill_[0-9]{8}T[0-9]{6}Z_[0-9a-f]{12}\.tar\.gz\.age$ ]]; then
  echo "Invalid production drill artifact name" >&2
  exit 1
fi

work_dir="$(mktemp -d)"
restore_project="$work_dir/restore-project"
restore_stack_started=0

cleanup() {
  if [ "$restore_stack_started" -eq 1 ] && [ -d "$restore_project" ]; then
    (cd "$restore_project" && supabase stop --no-backup >/dev/null 2>&1) || true
  fi
  rm -rf "$work_dir"
}
trap cleanup EXIT

gdrive_dir="$work_dir/gdrive"
b2_dir="$work_dir/b2"
bundle_dir="$work_dir/bundle"
mkdir -p "$gdrive_dir" "$b2_dir" "$bundle_dir"

download_and_verify() {
  local remote_root="$1"
  local target_dir="$2"
  local remote_base="${remote_root%/}/production-drill"
  local artifact_path="$target_dir/$PRODUCTION_DRILL_ARTIFACT"
  local sidecar_path="$artifact_path.sha256"

  rclone copyto "$remote_base/$PRODUCTION_DRILL_ARTIFACT" "$artifact_path" --no-traverse
  rclone copyto "$remote_base/$PRODUCTION_DRILL_ARTIFACT.sha256" "$sidecar_path" --no-traverse
  (
    cd "$target_dir"
    sha256sum --check "$(basename "$sidecar_path")"
  )
}

download_and_verify "$BACKUP_GDRIVE_REMOTE" "$gdrive_dir"
download_and_verify "$BACKUP_B2_REMOTE" "$b2_dir"

cmp "$gdrive_dir/$PRODUCTION_DRILL_ARTIFACT" "$b2_dir/$PRODUCTION_DRILL_ARTIFACT"
cmp "$gdrive_dir/$PRODUCTION_DRILL_ARTIFACT.sha256" "$b2_dir/$PRODUCTION_DRILL_ARTIFACT.sha256"

identity_file="$work_dir/production-drill-age-identity.txt"
printf '%s\n' "$PRODUCTION_DRILL_AGE_IDENTITY" > "$identity_file"
plain_bundle="$work_dir/restore.tar.gz"
age --decrypt \
  --identity "$identity_file" \
  --output "$plain_bundle" \
  "$gdrive_dir/$PRODUCTION_DRILL_ARTIFACT"

tar -xzf "$plain_bundle" -C "$bundle_dir"
(
  cd "$bundle_dir"
  sha256sum --check SHA256SUMS
)

expected_counts="$(jq -cS . "$bundle_dir/control-counts.json")"
jq -e '
  .migration_sample_auth_users == 0 and
  .migration_sample_profiles == 0 and
  .migration_sample_bookings == 0 and
  .migration_sample_direct_permissions == 0 and
  .migration_sample_access_groups == 0
' "$bundle_dir/control-counts.json" >/dev/null || {
  echo "Selected artifact is not a Papp Dalma pre-migration restore point" >&2
  exit 1
}

mkdir -p "$restore_project"
(
  cd "$restore_project"
  supabase init
  sed -i -E 's/^major_version = [0-9]+$/major_version = 17/' supabase/config.toml
  grep -qx 'major_version = 17' supabase/config.toml
  supabase db start
)
restore_stack_started=1

restore_project_id="$(sed -n 's/^project_id = "\([^"]*\)"/\1/p' "$restore_project/supabase/config.toml" | head -n 1)"
[ -n "$restore_project_id" ] || {
  echo "Could not determine isolated restore project id" >&2
  exit 1
}
restore_db_container="$(docker ps \
  --filter "label=com.supabase.cli.project=$restore_project_id" \
  --filter 'name=supabase_db_' \
  --format '{{.Names}}' | head -n 1)"
[ -n "$restore_db_container" ] || {
  echo "Could not find isolated restore database container" >&2
  exit 1
}

restore_sql="$work_dir/full-restore.sql"
{
  cat "$bundle_dir/roles.sql"
  printf '\n'
  cat "$bundle_dir/schema.sql"
  printf '\nSET session_replication_role = replica;\n'
  cat "$bundle_dir/data.sql"
  printf '\nDROP SCHEMA IF EXISTS supabase_migrations CASCADE;\n'
  cat "$bundle_dir/migration-schema.sql"
  printf '\n'
  cat "$bundle_dir/migration-history.sql"
  printf '\nSET session_replication_role = origin;\n'
} > "$restore_sql"

docker exec -i "$restore_db_container" \
  psql -U supabase_admin -d postgres -X --single-transaction -v ON_ERROR_STOP=1 \
  < "$restore_sql"

restore_db_url="postgresql://postgres:postgres@127.0.0.1:54322/postgres"
actual_counts="$(psql "$restore_db_url" -X -A -t -v ON_ERROR_STOP=1 -c "select json_build_object(
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
)")"
actual_counts="$(printf '%s\n' "$actual_counts" | jq -cS .)"

if [ "$actual_counts" != "$expected_counts" ]; then
  echo "Isolated restore control counts differ from the backup manifest" >&2
  echo "expected=$expected_counts" >&2
  echo "actual=$actual_counts" >&2
  exit 1
fi

psql "$restore_db_url" -X -v ON_ERROR_STOP=1 <<'SQL'
do $$
declare
  orphan_count bigint;
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename in ('profiles', 'bookings')
  ) then
    raise exception 'Restored RLS policies are missing';
  end if;
  if not exists (
    select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'bookings' and c.relrowsecurity
  ) then
    raise exception 'RLS is not enabled on restored bookings';
  end if;
  if not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.bookings'::regclass
      and tgname = 'bookings_validate_time_rules' and not tgisinternal
  ) then
    raise exception 'Booking validation trigger is missing';
  end if;
  select count(*) into orphan_count
  from public.bookings b
  left join public.profiles p on p.id = b.user_id
  left join public.rooms r on r.id = b.room_id
  where p.id is null or r.id is null;
  if orphan_count <> 0 then
    raise exception 'Orphan restored booking rows: %', orphan_count;
  end if;
  select count(*) into orphan_count
  from public.audit_logs a
  left join public.profiles p on p.id = a.actor_user_id
  where a.actor_user_id is not null and p.id is null;
  if orphan_count <> 0 then
    raise exception 'Orphan restored audit rows: %', orphan_count;
  end if;
end
$$;
SQL

(
  cd "$restore_project"
  supabase db lint --level warning
)

printf 'PRODUCTION DRILL isolated restore PASS: %s\n' "$PRODUCTION_DRILL_ARTIFACT"
printf 'RESTORE_COUNTS=%s\n' "$actual_counts"
