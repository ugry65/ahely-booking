#!/usr/bin/env bash
set -euo pipefail

if ! command -v psql >/dev/null 2>&1; then
  echo "Hiba: a psql kliens nincs telepítve." >&2
  exit 127
fi

readonly database_url="${AHELY_TEST_DB_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
readonly admin_a="00000000-0000-0000-0000-000000000191"
readonly admin_b="00000000-0000-0000-0000-000000000192"
readonly deactivate_key="29000000-0000-0000-0000-000000000191"
readonly downgrade_key="29000000-0000-0000-0000-000000000192"

test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

psql "$database_url" -X -v ON_ERROR_STOP=1 <<SQL
insert into auth.users (id, email, raw_user_meta_data) values
  ('$admin_a', 'admin-race-a@example.invalid', '{"first_name":"Race","last_name":"AdminA"}'),
  ('$admin_b', 'admin-race-b@example.invalid', '{"first_name":"Race","last_name":"AdminB"}');
update public.profiles set role='admin', is_active=true where id in ('$admin_a', '$admin_b');
update public.profiles set role='user' where id not in ('$admin_a', '$admin_b') and role='admin';
SQL

run_deactivate_b() {
  psql "$database_url" -X -v ON_ERROR_STOP=1 >"$test_dir/deactivate.log" 2>&1 <<SQL
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '$admin_a', true);
select public.admin_update_profile(
  '$admin_b',
  'Race', 'AdminB', null, 'private', null, null, null, null, null, null,
  false,
  '$deactivate_key'
);
select pg_sleep(2);
commit;
SQL
}

run_downgrade_a() {
  psql "$database_url" -X -v ON_ERROR_STOP=1 >"$test_dir/downgrade.log" 2>&1 <<SQL
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '$admin_b', true);
select public.admin_set_profile_role('$admin_a', 'user', '$downgrade_key');
commit;
SQL
}

set +e
run_deactivate_b &
first_pid=$!
sleep 0.25
run_downgrade_a &
second_pid=$!
wait "$first_pid"
first_status=$?
wait "$second_pid"
second_status=$?
set -e

if [[ "$first_status" -ne 0 ]]; then
  echo "Hiba: az első admin-deaktiválásnak sikeresnek kell lennie." >&2
  sed -n '1,160p' "$test_dir/deactivate.log" >&2
  exit 1
fi

if [[ "$second_status" -eq 0 ]]; then
  echo "Hiba: a konkurens lefokozás nem hagyhat 0 aktív admint." >&2
  sed -n '1,160p' "$test_dir/downgrade.log" >&2
  exit 1
fi

if ! grep -q "Az utolsó aktív adminisztrátor nem fokozható le" "$test_dir/downgrade.log"; then
  echo "Hiba: a második művelet nem a várt utolsó-admin védelemmel bukott el." >&2
  sed -n '1,160p' "$test_dir/downgrade.log" >&2
  exit 1
fi

read -r active_admins admin_a_role admin_b_active <<<"$(
  psql "$database_url" -X -AtF' ' -v ON_ERROR_STOP=1 -c "
    select
      (select count(*) from public.profiles where role='admin' and is_active),
      (select role::text from public.profiles where id='$admin_a'),
      (select is_active::text from public.profiles where id='$admin_b');
  "
)"

if [[ "$active_admins $admin_a_role $admin_b_active" != "1 admin false" ]]; then
  echo "Hiba: a végállapotban pontosan egy aktív adminnak kell maradnia." >&2
  echo "active_admins=$active_admins admin_a_role=$admin_a_role admin_b_active=$admin_b_active" >&2
  exit 1
fi

echo "Utolsó-admin konkurenciateszt sikeres: a keresztfunkciós race után pontosan egy aktív admin maradt."
