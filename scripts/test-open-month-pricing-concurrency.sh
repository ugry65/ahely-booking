#!/usr/bin/env bash
set -euo pipefail

readonly database_url="${AHELY_TEST_DB_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
case "$database_url" in
  postgresql://*@127.0.0.1:*/*|postgresql://*@localhost:*/*|postgres://*@127.0.0.1:*/*|postgres://*@localhost:*/*) ;;
  *) echo 'Hiba: kizárólag helyi, izolált adatbázis engedett.' >&2; exit 1 ;;
esac
readonly admin_id="00000000-0000-0000-0000-000000000325"
readonly user_id="00000000-0000-0000-0000-000000000326"
test_dir="$(mktemp -d)"
pids=()
cleanup() {
  for pid in "${pids[@]}"; do kill "$pid" 2>/dev/null || true; done
  rm -rf "$test_dir"
}
trap cleanup EXIT

month="$(psql "$database_url" -XAt -v ON_ERROR_STOP=1 -c "select date_trunc('month',timezone('Europe/Budapest',now()))::date")"
# Earlier CI races leave future current-month fixtures. Only inside each close
# transaction use a 31-day cutoff to make those isolated fixtures immutable,
# then restore the original setting before commit. No live DB can be targeted.
cutoff="$(psql "$database_url" -XAt -v ON_ERROR_STOP=1 -c "select (value #>> '{}')::integer from public.app_settings where key='cancellation_cutoff_hours'")"
[[ "$cutoff" =~ ^[0-9]+$ ]] || { echo 'Hiba: hibás cutoff fixture.' >&2; exit 1; }
close_sql="reset role; update public.app_settings set value='744'::jsonb where key='cancellation_cutoff_hours';
set local role authenticated;
select total_due_huf from public.admin_close_monthly_settlement_period('$month');
reset role; update public.app_settings set value='$cutoff'::jsonb where key='cancellation_cutoff_hours';
select r.calculated_due_huf from public.monthly_settlements s join public.settlement_revisions r on r.id=s.closed_revision_id
where s.user_id='$user_id' and s.settlement_month='$month';"
psql "$database_url" -X -v ON_ERROR_STOP=1 <<SQL >/dev/null
insert into auth.users(id,email,raw_user_meta_data) values
 ('$admin_id','open-month-race-admin@example.invalid','{"first_name":"Pricing","last_name":"RaceAdmin"}'),
 ('$user_id','open-month-race-user@example.invalid','{"first_name":"Pricing","last_name":"RaceUser"}');
update public.profiles set role='admin',is_active=true where id='$admin_id';
insert into public.bookings(room_id,user_id,created_by,start_at,end_at,use_type,status,idempotency_key)
values ('11000000-0000-0000-0000-000000000002','$user_id','$admin_id',
 ('$month'::date+time '07:00') at time zone 'Europe/Budapest',
 ('$month'::date+time '08:00') at time zone 'Europe/Budapest',
 'individual','active',gen_random_uuid());
SQL

wait_for_state() {
  local holder="$1" waiter="${2:-}" ready
  for ((attempt=0;attempt<100;attempt++)); do
    if [[ -z "$waiter" ]]; then
      ready="$(psql "$database_url" -XAt -v ON_ERROR_STOP=1 -c "select exists(
        select 1 from pg_stat_activity a join pg_locks l on l.pid=a.pid
        where a.application_name='$holder' and a.state='idle in transaction'
          and l.locktype='advisory' and l.granted)")"
    else
      ready="$(psql "$database_url" -XAt -v ON_ERROR_STOP=1 -c "select exists(
        select 1 from pg_stat_activity h cross join pg_stat_activity w
        where h.application_name='$holder' and w.application_name='$waiter'
          and w.wait_event='advisory' and h.pid=any(pg_blocking_pids(w.pid)))")"
    fi
    [[ "$ready" == t ]] && return 0
    sleep 0.1
  done
  echo "Hiba: nem igazolt a várt zárolási állapot: $holder / $waiter" >&2
  exit 1
}

start_holder() {
  local name="$1" sql="$2"
  mkfifo "$test_dir/$name.release"
  (
    {
      printf "begin; set local statement_timeout='20s'; set local role authenticated;\n"
      printf "select set_config('request.jwt.claim.sub','%s',true);\n" "$admin_id"
      printf '%s\n' "$sql"
      IFS= read -r _ < "$test_dir/$name.release"
      printf 'commit;\n'
    } | PGAPPNAME="$name" psql "$database_url" -X -v ON_ERROR_STOP=1
  ) >"$test_dir/$name.log" 2>&1 &
  holder_pid=$!; pids+=("$holder_pid")
  wait_for_state "$name"
}

start_waiter() {
  local name="$1" sql="$2" ending="$3"
  (
    PGAPPNAME="$name" psql "$database_url" -XAt -v ON_ERROR_STOP=1 -v VERBOSITY=verbose <<SQL
begin;
set local statement_timeout='20s';
set local lock_timeout='15s';
set local role authenticated;
select set_config('request.jwt.claim.sub','$admin_id',true);
$sql
$ending;
SQL
  ) >"$test_dir/$name.log" 2>&1 &
  waiter_pid=$!; pids+=("$waiter_pid")
}

# Setter first: close must wait and then calculate the committed new tariff.
start_holder ahely-open-price-holder "select public.admin_set_central_pricing('$month',3200,2200,1800,'Pricing race first',gen_random_uuid());"
start_waiter ahely-open-close-waiter "$close_sql" rollback
close_pid="$waiter_pid"
wait_for_state ahely-open-price-holder ahely-open-close-waiter
printf 'release\n' > "$test_dir/ahely-open-price-holder.release"
wait "$holder_pid"; wait "$close_pid"
if ! grep -qx '3200' "$test_dir/ahely-open-close-waiter.log"; then
  echo 'Hiba: a zárás nem a commitált új 3200 Ft-os díjjal számolt.' >&2
  cat "$test_dir/ahely-open-close-waiter.log" >&2
  exit 1
fi

# Close first: both real setters wait, then reject the committed publication.
start_holder ahely-open-close-holder "$close_sql"
start_waiter ahely-open-central-waiter "select public.admin_set_central_pricing('$month',9999,9999,9999,'Tiltott race','42000000-0000-0000-0000-000000000325');" commit
central_pid="$waiter_pid"
start_waiter ahely-open-training-waiter "select public.admin_set_training_room_rate(9999,'$month','Tiltott race','42000000-0000-0000-0000-000000000326');" commit
training_pid="$waiter_pid"
wait_for_state ahely-open-close-holder ahely-open-central-waiter
wait_for_state ahely-open-close-holder ahely-open-training-waiter
printf 'release\n' > "$test_dir/ahely-open-close-holder.release"
wait "$holder_pid"
for pid in "$central_pid" "$training_pid"; do
  if wait "$pid"; then echo 'Hiba: lezárás után átjutott egy tarifaírás.' >&2; exit 1; fi
done
for name in central training; do
  if ! grep -q '22023: Lezárt hónap' "$test_dir/ahely-open-$name-waiter.log"; then
    cat "$test_dir/ahely-open-$name-waiter.log" >&2; exit 1
  fi
done
actual="$(psql "$database_url" -XAtF' ' -v ON_ERROR_STOP=1 -c "select
 (select hourly_rate_huf from public.pricing_tiers where min_minutes=60 and valid_from='$month'),
 (select r.calculated_due_huf from public.monthly_settlements s join public.settlement_revisions r on r.id=s.closed_revision_id
  where s.user_id='$user_id' and s.settlement_month='$month'),
 (select count(*) from public.audit_logs where correlation_id in ('42000000-0000-0000-0000-000000000325','42000000-0000-0000-0000-000000000326'))")"
if [[ "$actual" != '3200 3200 0' ]]; then
  echo "Hiba: részleges tarifa/snapshot/audit állapot: $actual" >&2; exit 1
fi
restored="$(psql "$database_url" -XAt -v ON_ERROR_STOP=1 -c "select (value #>> '{}')::integer from public.app_settings where key='cancellation_cutoff_hours'")"
[[ "$restored" == "$cutoff" ]] || { echo 'Hiba: cutoff fixture nem állt vissza.' >&2; exit 1; }
pids=()
echo 'Nyitott havi pricing race PASS: külön kapcsolatok; pricing → close új díjjal, close → central/training tiltás; nincs részleges audit.'
