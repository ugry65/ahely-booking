#!/usr/bin/env bash
set -euo pipefail

if ! command -v psql >/dev/null 2>&1; then
  echo "Hiba: a psql kliens nincs telepítve." >&2
  exit 127
fi

readonly database_url="${AHELY_TEST_DB_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
readonly admin_id="00000000-0000-0000-0000-000000000081"
readonly user_id="00000000-0000-0000-0000-000000000082"
readonly room_id="11000000-0000-0000-0000-000000000008"
readonly first_key="23000000-0000-0000-0000-000000000081"
readonly second_key="23000000-0000-0000-0000-000000000082"

test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

psql "$database_url" -X -v ON_ERROR_STOP=1 <<SQL
insert into auth.users (id, email, raw_user_meta_data) values
  ('$admin_id', 'room-access-admin-concurrency@example.invalid', '{"first_name":"Access","last_name":"Admin"}'),
  ('$user_id', 'room-access-user-concurrency@example.invalid', '{"first_name":"Access","last_name":"User"}');
update public.profiles set role = 'admin' where id = '$admin_id';
SQL

run_permission() {
  local correlation_id="$1"
  local output_file="$2"
  psql "$database_url" -X -v ON_ERROR_STOP=1 >"$output_file" 2>&1 <<SQL
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '$admin_id', true);
select public.admin_set_user_room_permission(
  '$user_id', '$room_id', true, true, '$correlation_id'
);
select pg_sleep(2);
commit;
SQL
}

set +e
run_permission "$first_key" "$test_dir/first.log" &
first_pid=$!
run_permission "$second_key" "$test_dir/second.log" &
second_pid=$!
wait "$first_pid"
first_status=$?
wait "$second_pid"
second_status=$?
set -e

if [[ "$first_status" -ne 0 || "$second_status" -ne 0 ]]; then
  echo "Hiba: mindkét konkurens jogosultságadásnak sikeresnek kell lennie." >&2
  sed -n '1,120p' "$test_dir/first.log" >&2
  sed -n '1,120p' "$test_dir/second.log" >&2
  exit 1
fi

read -r permission_count audit_count <<<"$(
  psql "$database_url" -X -AtF' ' -v ON_ERROR_STOP=1 -c "
    select
      (select count(*) from public.user_room_permissions
       where user_id = '$user_id' and room_id = '$room_id' and can_book and can_repeat),
      (select count(*) from public.audit_logs
       where entity_type = 'user_room_permission'
         and entity_id = '$user_id:$room_id'
         and correlation_id in ('$first_key', '$second_key'));
  "
)"

if [[ "$permission_count $audit_count" != "1 1" ]]; then
  echo "Hiba: a konkurens első jogosultságadás duplikált állapotot vagy auditot eredményezett." >&2
  echo "permissions=$permission_count audit_logs=$audit_count" >&2
  exit 1
fi

echo "Helyiségjog-konkurenciateszt sikeres: egy állapotváltozás és pontosan egy auditrekord keletkezett."
