#!/usr/bin/env bash
set -euo pipefail
readonly database_url="${AHELY_TEST_DB_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
case "$database_url" in postgresql://*@127.0.0.1:*/*|postgresql://*@localhost:*/*|postgres://*@127.0.0.1:*/*|postgres://*@localhost:*/*) ;; *) echo 'Isolated localhost database required.' >&2; exit 1;; esac
readonly admin_id='00000000-0000-0000-0000-000000000511'
readonly user_id='00000000-0000-0000-0000-000000000512'
readonly root_id='41000000-0000-0000-0000-000000000511'
readonly child_id='01000000-0000-0000-0000-000000000511'
readonly second_id='41000000-0000-0000-0000-000000000512'
readonly third_id='41000000-0000-0000-0000-000000000513'
readonly series_id='61000000-0000-0000-0000-000000000511'
readonly room_id='11000000-0000-0000-0000-000000000009'
test_dir="$(mktemp -d)"
pids=()
cleanup() {
  local result=$?
  if ((result!=0)); then for log in "$test_dir"/*.log; do [[ -f "$log" ]] && { printf 'Session: %s\n' "${log##*/}" >&2; cat "$log" >&2; }; done; fi
  for pid in "${pids[@]}"; do kill "$pid" 2>/dev/null || true; done
  rm -rf "$test_dir"
}
trap cleanup EXIT
month="$(psql "$database_url" -XAt -v ON_ERROR_STOP=1 -c "select (date_trunc('month',timezone('Europe/Budapest',now()))-interval '9 months')::date")"
series_day="$(psql "$database_url" -XAt -v ON_ERROR_STOP=1 -c "select timezone('Europe/Budapest',now())::date+2")"
psql "$database_url" -X -v ON_ERROR_STOP=1 <<SQL >/dev/null
insert into auth.users(id,email,raw_user_meta_data) values
('$admin_id','parts-race-admin@example.invalid','{"first_name":"Parts","last_name":"RaceAdmin"}'),
('$user_id','parts-race-user@example.invalid','{"first_name":"Parts","last_name":"RaceUser"}');
update public.profiles set role='admin',is_active=true where id='$admin_id';
insert into public.booking_series(id,owner_user_id,created_by,frequency,starts_on,occurrence_count,conflict_policy,room_id,local_start_time,duration_minutes,idempotency_key,request_payload)
values('$series_id','$user_id','$admin_id','weekly','$series_day',2,'abort_all','$room_id','08:00',60,gen_random_uuid(),'{}');
insert into public.bookings(id,room_id,user_id,created_by,series_id,start_at,end_at,use_type,status,idempotency_key)
values('$root_id','$room_id','$user_id','$admin_id','$series_id',timezone('Europe/Budapest','$series_day'::date+time '08:00'),timezone('Europe/Budapest','$series_day'::date+time '09:00'),'individual','active',gen_random_uuid());
insert into public.bookings(id,room_id,user_id,created_by,series_id,root_booking_id,start_at,end_at,use_type,status,idempotency_key)
values('$child_id','$room_id','$user_id','$admin_id','$series_id','$root_id',timezone('Europe/Budapest','$series_day'::date+time '10:00'),timezone('Europe/Budapest','$series_day'::date+time '15:00'),'individual','active',gen_random_uuid());
insert into public.bookings(id,room_id,user_id,created_by,start_at,end_at,use_type,status,idempotency_key)
values('$second_id','$room_id','$user_id','$admin_id',timezone('Europe/Budapest','$month'::date+16+time '08:00'),timezone('Europe/Budapest','$month'::date+16+time '15:00'),'individual','active',gen_random_uuid()),
('$third_id','$room_id','$user_id','$admin_id',timezone('Europe/Budapest','$month'::date+17+time '08:00'),timezone('Europe/Budapest','$month'::date+17+time '15:00'),'individual','active',gen_random_uuid());
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
parts_sql() {
  local booking="$1" day="$2" start="$3" finish="$4" key="$5" version base="${6:-$month}"
  version="$(psql "$database_url" -XAt -v ON_ERROR_STOP=1 -c "select updated_at from public.bookings where id='$booking'")"
  printf "select public.cancel_booking_parts('%s','%s',jsonb_build_array(jsonb_build_object('start',timezone('Europe/Budapest','%s'::date+%s+time '%s:00'),'end',timezone('Europe/Budapest','%s'::date+%s+time '%s:00'))),'Race fixture','%s');" "$booking" "$version" "$base" "$day" "$start" "$base" "$day" "$finish" "$key"
}
# Actual chronological series cancellation holds root FOR UPDATE; child UUID
# sorts before root. Partial operation must fail BEFORE its selected-child FK.
start_holder parts-series-holder "reset role;select 1 from public.bookings where id='$root_id' for update;set local role authenticated;select * from public.cancel_booking_scope('$root_id','series',null,gen_random_uuid());select pg_advisory_xact_lock(hashtextextended('parts-series-fixture',0));"
start_waiter parts-child-waiter "$(parts_sql "$child_id" 0 12 13 '51000000-0000-0000-0000-000000000511' "$series_day")" commit
if wait "$waiter_pid"; then echo 'Busy fragment unexpectedly changed.' >&2; exit 1; fi
grep -q 'P0001: A foglalás másik műveletben módosul' "$test_dir/parts-child-waiter.log"
printf 'release\n' > "$test_dir/parts-series-holder.release"
wait "$holder_pid"
[[ "$(psql "$database_url" -XAt -v ON_ERROR_STOP=1 -c "select count(*) from public.booking_partial_cancellations where booking_id='$child_id'")" == 0 ]]
# Simultaneous identical request must return one result, not make more pieces.
same_request="$(parts_sql "$second_id" 16 10 12 '51000000-0000-0000-0000-000000000512')"
start_holder parts-first-holder "$same_request"
start_waiter parts-retry-waiter "$same_request" commit
wait_for_state parts-first-holder parts-retry-waiter
printf 'release\n' > "$test_dir/parts-first-holder.release"
wait "$holder_pid"; wait "$waiter_pid"
[[ "$(psql "$database_url" -XAt -v ON_ERROR_STOP=1 -c "select count(*) from public.booking_partial_cancellations where booking_id='$second_id'")" == 1 ]]
[[ "$(psql "$database_url" -XAt -v ON_ERROR_STOP=1 -c "select count(*) from public.bookings where status='active' and (id='$second_id' or root_booking_id='$second_id')")" == 2 ]]
# Payment holds group serialization before split, preserving receipt exactly.
start_holder parts-payment-holder "select public.admin_record_booking_payment('$second_id',100,current_date,'cash','cash_register',null,'51000000-0000-0000-0000-000000000513');"
start_waiter parts-payment-split-waiter "$(parts_sql "$second_id" 16 09 10 '51000000-0000-0000-0000-000000000514')" commit
wait_for_state parts-payment-holder parts-payment-split-waiter
printf 'release\n' > "$test_dir/parts-payment-holder.release"
wait "$holder_pid"; wait "$waiter_pid"
[[ "$(psql "$database_url" -XAt -v ON_ERROR_STOP=1 -c "select sum(amount_huf) from public.payments where booking_id='$second_id'")" == 100 ]]
# Split wins first: close sees only five retained hours in its snapshot.
start_holder parts-before-close-holder "$(parts_sql "$third_id" 17 10 12 '51000000-0000-0000-0000-000000000515')"
start_waiter parts-close-waiter "select * from public.admin_close_monthly_settlement_period('$month');reset role;select sum(sl.duration_minutes) from public.settlement_booking_lines sl join public.monthly_settlements ms on ms.closed_revision_id=sl.settlement_revision_id join public.bookings b on b.id=sl.booking_id where coalesce(b.root_booking_id,b.id)='$third_id';" rollback
wait_for_state parts-before-close-holder parts-close-waiter
printf 'release\n' > "$test_dir/parts-before-close-holder.release"
wait "$holder_pid"; wait "$waiter_pid"
grep -qx '300' "$test_dir/parts-close-waiter.log"
# Close wins first: NO KEY UPDATE is compatible with snapshot FK KEY SHARE;
# wait at the period lock, then reject based on committed closure.
start_holder parts-close-holder "select * from public.admin_close_monthly_settlement_period('$month');"
start_waiter parts-after-close-waiter "$(parts_sql "$third_id" 17 09 10 '51000000-0000-0000-0000-000000000516')" commit
wait_for_state parts-close-holder parts-after-close-waiter
printf 'release\n' > "$test_dir/parts-close-holder.release"
wait "$holder_pid"
if wait "$waiter_pid"; then echo 'Partial cancellation crossed closed month.' >&2; exit 1; fi
grep -q '42501: Lezárt hónap' "$test_dir/parts-after-close-waiter.log"
pids=()
echo 'Partial booking concurrency PASS: series contention, identical requests, payment and both month-close orders.'
