#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
local_db_url="${LOCAL_SUPABASE_DB_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
test_root="$(mktemp -d)"
cleanup() { rm -rf "$test_root"; }
trap cleanup EXIT

for command_name in supabase psql age age-keygen sha256sum tar jq; do
  command -v "$command_name" >/dev/null 2>&1 || { echo "Missing required command: $command_name" >&2; exit 1; }
done

printf '%s\n' 'Resetting local Supabase before nonzero fixture...'
supabase db reset

psql "$local_db_url" -X -v ON_ERROR_STOP=1 -f "$repo_root/scripts/fixtures/nonzero-restore-fixture.sql"

control_counts_sql="select json_build_object(
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
)"

source_counts="$(psql "$local_db_url" -X -A -t -v ON_ERROR_STOP=1 -c "$control_counts_sql")"
printf '%s\n' "$source_counts" | jq -e '
  .auth_users > 0 and
  .profiles > 0 and
  .user_room_permissions > 0 and
  .booking_series > 0 and
  .bookings_total > 0 and
  .bookings_cancelled > 0 and
  .booking_cancellations > 0 and
  .audit_logs > 0 and
  .monthly_settlements > 0 and
  .settlement_revisions > 0 and
  .settlement_booking_lines > 0
' >/dev/null || { echo "Fixture did not create all required nonzero control categories" >&2; exit 1; }

source_migration_rows="$(psql "$local_db_url" -X -A -t -v ON_ERROR_STOP=1 -c 'select count(*) from supabase_migrations.schema_migrations')"

fake_bin="$test_root/bin"
remote_root="$test_root/remotes"
mkdir -p "$fake_bin" "$remote_root"

cat > "$fake_bin/rclone" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
command_name="${1:-}"
shift || true
remote_path() {
  local remote="$1"
  local provider="${remote%%:*}"
  local path="${remote#*:}"
  printf '%s/%s/%s' "$FAKE_RCLONE_ROOT" "$provider" "$path"
}
case "$command_name" in
  copyto)
    source_file="$1"
    destination="$2"
    target="$(remote_path "$destination")"
    mkdir -p "$(dirname "$target")"
    cp "$source_file" "$target"
    ;;
  cat)
    cat "$(remote_path "$1")"
    ;;
  *)
    echo "Unexpected fake rclone command: $command_name" >&2
    exit 1
    ;;
esac
EOF
chmod +x "$fake_bin/rclone"

key_file="$test_root/age-key.txt"
age-keygen -o "$key_file" >/dev/null
recipient="$(age-keygen -y "$key_file")"

export PATH="$fake_bin:$PATH"
export FAKE_RCLONE_ROOT="$remote_root"
export PRODUCTION_DB_URL="$local_db_url"
export BACKUP_AGE_RECIPIENT="$recipient"
export BACKUP_GDRIVE_REMOTE="gdrive:nonzero-restore-test"
export BACKUP_B2_REMOTE="b2:nonzero-restore-test"
export BACKUP_HEARTBEAT_URL=""
export GITHUB_SHA="9300000000000000000000000000000000000000"

bash "$repo_root/scripts/backup-production.sh"

artifact="$(find "$remote_root/gdrive/nonzero-restore-test" -maxdepth 1 -type f -name '*.tar.gz.age' -print -quit)"
[ -n "$artifact" ] || { echo "Encrypted test artifact not found" >&2; exit 1; }
sidecar="$artifact.sha256"
[ -s "$sidecar" ] || { echo "Encrypted artifact checksum sidecar not found" >&2; exit 1; }

(
  cd "$(dirname "$artifact")"
  sha256sum -c "$(basename "$sidecar")"
)

plain_bundle="$test_root/restore.tar.gz"
age --decrypt -i "$key_file" -o "$plain_bundle" "$artifact"
restore_dir="$test_root/restore"
mkdir -p "$restore_dir"
tar -xzf "$plain_bundle" -C "$restore_dir"
(
  cd "$restore_dir"
  sha256sum -c SHA256SUMS
)

artifact_counts="$(jq -cS . "$restore_dir/control-counts.json")"
expected_counts="$(printf '%s\n' "$source_counts" | jq -cS .)"
[ "$artifact_counts" = "$expected_counts" ] || {
  echo "Artifact control counts differ from source counts" >&2
  echo "source=$expected_counts" >&2
  echo "artifact=$artifact_counts" >&2
  exit 1
}

printf '%s\n' 'Resetting local Supabase to clean restore target...'
supabase db reset

psql "$local_db_url" \
  -X \
  --single-transaction \
  -v ON_ERROR_STOP=1 \
  -f "$restore_dir/roles.sql" \
  -f "$restore_dir/schema.sql" \
  -c 'set session_replication_role = replica;' \
  -f "$restore_dir/data.sql" \
  -c 'drop schema if exists supabase_migrations cascade;' \
  -f "$restore_dir/migration-schema.sql" \
  -f "$restore_dir/migration-history.sql" \
  -c 'set session_replication_role = origin;'

restored_counts="$(psql "$local_db_url" -X -A -t -v ON_ERROR_STOP=1 -c "$control_counts_sql")"
actual_counts="$(printf '%s\n' "$restored_counts" | jq -cS .)"
[ "$actual_counts" = "$expected_counts" ] || {
  echo "Restored control counts differ from source counts" >&2
  echo "source=$expected_counts" >&2
  echo "restored=$actual_counts" >&2
  exit 1
}

restored_migration_rows="$(psql "$local_db_url" -X -A -t -v ON_ERROR_STOP=1 -c 'select count(*) from supabase_migrations.schema_migrations')"
[ "$restored_migration_rows" = "$source_migration_rows" ] || {
  echo "Migration history row count mismatch: source=$source_migration_rows restored=$restored_migration_rows" >&2
  exit 1
}

psql "$local_db_url" -X -v ON_ERROR_STOP=1 <<'SQL'
do $$
declare
  rls_ok boolean;
  policy_count integer;
  fk_ok boolean;
  trigger_ok boolean;
begin
  select bool_and(c.relrowsecurity)
    into rls_ok
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relname in ('profiles', 'bookings');
  if coalesce(rls_ok, false) is not true then
    raise exception 'RLS is not enabled on restored profiles/bookings tables';
  end if;

  select count(*) into policy_count
  from pg_policies
  where schemaname = 'public'
    and tablename in ('profiles', 'bookings');
  if policy_count = 0 then
    raise exception 'Expected restored RLS policies are missing';
  end if;

  select exists (
    select 1
    from pg_constraint
    where conrelid = 'public.bookings'::regclass
      and contype = 'f'
  ) into fk_ok;
  if not fk_ok then
    raise exception 'Expected booking foreign key constraints are missing';
  end if;

  select exists (
    select 1
    from pg_trigger
    where tgrelid = 'public.bookings'::regclass
      and tgname = 'bookings_validate_time_rules'
      and not tgisinternal
  ) into trigger_ok;
  if not trigger_ok then
    raise exception 'Expected booking validation trigger is missing';
  end if;
end
$$;
SQL

printf '%s\n' "Nonzero backup/restore sandbox drill passed: $actual_counts; migration_history_rows=$restored_migration_rows"
