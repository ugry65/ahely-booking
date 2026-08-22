#!/usr/bin/env bash
set -euo pipefail

if ! command -v psql >/dev/null 2>&1; then
  echo "Hiba: a psql kliens nincs telepítve." >&2
  exit 127
fi

readonly database_url="${AHELY_TEST_DB_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
readonly admin_id="00000000-0000-0000-0000-000000000221"
readonly user_id="00000000-0000-0000-0000-000000000222"
readonly room_id="11000000-0000-0000-0000-000000000002"
readonly off_key_1="22100000-0000-0000-0000-000000000001"
readonly grant_key_1="22100000-0000-0000-0000-000000000002"
readonly grant_key_2="22100000-0000-0000-0000-000000000003"
readonly off_key_2="22100000-0000-0000-0000-000000000004"

test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

psql "$database_url" -X -v ON_ERROR_STOP=1 <<SQL
insert into auth.users (id, email, raw_user_meta_data) values
  ('$admin_id', 'repeat-concurrency-admin@example.invalid', '{"first_name":"Repeat","last_name":"Admin"}'),
  ('$user_id', 'repeat-concurrency-user@example.invalid', '{"first_name":"Repeat","last_name":"User"}');
update public.profiles set role='admin' where id='$admin_id';
insert into public.user_room_permissions(user_id,room_id,can_book,can_repeat)
values ('$user_id','$room_id',true,true);
SQL

run_disable_holding_lock() {
  local correlation_id="$1"
  local output_file="$2"
  psql "$database_url" -X -v ON_ERROR_STOP=1 >"$output_file" 2>&1 <<SQL
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '$admin_id', true);
select pg_advisory_xact_lock(hashtextextended('profile_repeat_permission:$user_id', 0));
select public.admin_set_profile_repeat_permission('$user_id', false, '$correlation_id');
select pg_sleep(2);
commit;
SQL
}

run_legacy_grant() {
  local correlation_id="$1"
  local output_file="$2"
  psql "$database_url" -X -v ON_ERROR_STOP=1 >"$output_file" 2>&1 <<SQL
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '$admin_id', true);
select public.admin_set_user_room_permission('$user_id', '$room_id', true, true, '$correlation_id');
commit;
SQL
}

run_legacy_grant_holding_lock() {
  local correlation_id="$1"
  local output_file="$2"
  psql "$database_url" -X -v ON_ERROR_STOP=1 >"$output_file" 2>&1 <<SQL
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '$admin_id', true);
select pg_advisory_xact_lock(hashtextextended('profile_repeat_permission:$user_id', 0));
select public.admin_set_user_room_permission('$user_id', '$room_id', true, true, '$correlation_id');
select pg_sleep(2);
commit;
SQL
}

run_disable() {
  local correlation_id="$1"
  local output_file="$2"
  psql "$database_url" -X -v ON_ERROR_STOP=1 >"$output_file" 2>&1 <<SQL
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '$admin_id', true);
select public.admin_set_profile_repeat_permission('$user_id', false, '$correlation_id');
commit;
SQL
}

# Scenario 1: OFF commits first, then the queued legacy TRUE grant wins.
set +e
run_disable_holding_lock "$off_key_1" "$test_dir/off-first.log" &
off_pid=$!
sleep 0.25
run_legacy_grant "$grant_key_1" "$test_dir/grant-second.log" &
grant_pid=$!
wait "$off_pid"; off_status=$?
wait "$grant_pid"; grant_status=$?
set -e

if [[ "$off_status" -ne 0 || "$grant_status" -ne 0 ]]; then
  echo "Hiba: az OFF → legacy TRUE konkurens műveleteknek holtpont nélkül le kell futniuk." >&2
  sed -n '1,160p' "$test_dir/off-first.log" >&2
  sed -n '1,160p' "$test_dir/grant-second.log" >&2
  exit 1
fi

read -r profile_repeat legacy_repeat <<<"$(psql "$database_url" -X -AtF' ' -v ON_ERROR_STOP=1 -c "
  select can_repeat_bookings,
         (select can_repeat from public.user_room_permissions where user_id='$user_id' and room_id='$room_id')
  from public.profiles where id='$user_id';")"
if [[ "$profile_repeat $legacy_repeat" != "t t" ]]; then
  echo "Hiba: az OFF után sorban végrehajtott legacy TRUE grantnak vissza kell kapcsolnia a user-szintű repeat jogot." >&2
  echo "profile_repeat=$profile_repeat legacy_repeat=$legacy_repeat" >&2
  exit 1
fi

# Reset to OFF without stale legacy TRUE before the reverse ordering.
psql "$database_url" -X -v ON_ERROR_STOP=1 <<SQL
set role authenticated;
select set_config('request.jwt.claim.sub', '$admin_id', false);
select public.admin_set_profile_repeat_permission('$user_id', false, gen_random_uuid());
reset role;
SQL

# Scenario 2: legacy TRUE commits first, then the queued OFF wins and clears legacy flags.
set +e
run_legacy_grant_holding_lock "$grant_key_2" "$test_dir/grant-first.log" &
grant_pid=$!
sleep 0.25
run_disable "$off_key_2" "$test_dir/off-second.log" &
off_pid=$!
wait "$grant_pid"; grant_status=$?
wait "$off_pid"; off_status=$?
set -e

if [[ "$grant_status" -ne 0 || "$off_status" -ne 0 ]]; then
  echo "Hiba: a legacy TRUE → OFF konkurens műveleteknek holtpont nélkül le kell futniuk." >&2
  sed -n '1,160p' "$test_dir/grant-first.log" >&2
  sed -n '1,160p' "$test_dir/off-second.log" >&2
  exit 1
fi

read -r profile_repeat legacy_repeat_count <<<"$(psql "$database_url" -X -AtF' ' -v ON_ERROR_STOP=1 -c "
  select can_repeat_bookings,
         (select count(*) from public.user_room_permissions where user_id='$user_id' and can_repeat)
  from public.profiles where id='$user_id';")"
if [[ "$profile_repeat $legacy_repeat_count" != "f 0" ]]; then
  echo "Hiba: a később commitoló user-szintű OFF állapotnak kell érvényesülnie, legacy TRUE maradvány nélkül." >&2
  echo "profile_repeat=$profile_repeat legacy_repeat_count=$legacy_repeat_count" >&2
  exit 1
fi

echo "Repeat-jog konkurenciateszt sikeres: az új profiljog és a legacy grant közös zár alatt, holtpont nélkül sorosodik."
