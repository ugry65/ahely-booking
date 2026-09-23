#!/usr/bin/env bash
set -euo pipefail

if ! command -v psql >/dev/null 2>&1; then
  echo "Hiba: a psql kliens nincs telepítve." >&2
  exit 127
fi

readonly database_url="${AHELY_TEST_DB_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
readonly admin_id="00000000-0000-0000-0000-000000000196"
readonly user_id="00000000-0000-0000-0000-000000000197"
readonly first_key="42000000-0000-0000-0000-000000000196"
readonly second_key="42000000-0000-0000-0000-000000000197"

test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

psql "$database_url" -X -v ON_ERROR_STOP=1 <<SQL
insert into auth.users(id,email,raw_user_meta_data) values
 ('$admin_id','pricing-race-admin@example.invalid','{"first_name":"Pricing","last_name":"RaceAdmin"}'),
 ('$user_id','pricing-race-user@example.invalid','{"first_name":"Pricing","last_name":"RaceUser"}');
update public.profiles set role='admin', is_active=true where id='$admin_id';
SQL

valid_from="$(psql "$database_url" -X -Atqc "select (timezone('Europe/Budapest',now())::date+1)::text")"

run_first() {
  psql "$database_url" -X -v ON_ERROR_STOP=1 >"$test_dir/first.log" 2>&1 <<SQL
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','$admin_id',true);
select public.admin_set_user_hourly_rate('$user_id',3100,'$valid_from','Első konkurens díj','$first_key');
select pg_sleep(2);
commit;
SQL
}

run_second() {
  psql "$database_url" -X -v ON_ERROR_STOP=1 >"$test_dir/second.log" 2>&1 <<SQL
begin;
set local role authenticated;
set local lock_timeout='500ms';
select set_config('request.jwt.claim.sub','$admin_id',true);
select public.admin_set_user_hourly_rate('$user_id',3200,'$valid_from','Második konkurens díj','$second_key');
commit;
SQL
}

set +e
run_first &
first_pid=$!
sleep 0.25
run_second &
second_pid=$!
wait "$first_pid"
first_status=$?
wait "$second_pid"
second_status=$?
set -e

if [[ "$first_status" -ne 0 ]]; then
  echo "Hiba: az első pricing tranzakciónak sikeresnek kell lennie." >&2
  sed -n '1,160p' "$test_dir/first.log" >&2
  exit 1
fi

if [[ "$second_status" -eq 0 ]]; then
  echo "Hiba: a második pricing tranzakció nem futhat át az első zárolása mellett." >&2
  sed -n '1,160p' "$test_dir/second.log" >&2
  exit 1
fi

if ! grep -Eqi "lock timeout|canceling statement due to lock timeout" "$test_dir/second.log"; then
  echo "Hiba: a második kérés nem a várt zárolási timeouttal állt meg." >&2
  sed -n '1,160p' "$test_dir/second.log" >&2
  exit 1
fi

read -r override_count rate audit_first audit_second <<<"$(
  psql "$database_url" -X -AtF' ' -v ON_ERROR_STOP=1 -c "
    select
      (select count(*) from public.user_price_overrides where user_id='$user_id' and valid_from='$valid_from'),
      (select hourly_rate_huf from public.user_price_overrides where user_id='$user_id' and valid_from='$valid_from'),
      (select count(*) from public.audit_logs where correlation_id='$first_key'),
      (select count(*) from public.audit_logs where correlation_id='$second_key');
  "
)"

if [[ "$override_count $rate $audit_first $audit_second" != "1 3100 1 0" ]]; then
  echo "Hiba: a pricing race után inkonzisztens állapot vagy részleges audit maradt." >&2
  echo "override_count=$override_count rate=$rate audit_first=$audit_first audit_second=$audit_second" >&2
  exit 1
fi

echo "Pricing konkurenciateszt sikeres: az advisory lock sorosít, a blokkolt tranzakció nem hagy részleges adatot vagy auditot."
