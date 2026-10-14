#!/usr/bin/env bash
set -euo pipefail
readonly database_url="${AHELY_TEST_DB_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
case "$database_url" in
  postgresql://*@127.0.0.1:*/*|postgresql://*@localhost:*/*|postgres://*@127.0.0.1:*/*|postgres://*@localhost:*/*) ;;
  *) echo 'Only isolated local database allowed.' >&2; exit 1 ;;
esac
readonly admin_id="00000000-0000-0000-0000-000000000395"
readonly user_id="00000000-0000-0000-0000-000000000396"
readonly booking_id="41000000-0000-0000-0000-000000000395"
test_dir="$(mktemp -d)"
pids=()
cleanup() {
  for pid in "${pids[@]}"; do kill "$pid" 2>/dev/null || true; done
  rm -rf "$test_dir"
}
trap cleanup EXIT
month="$(psql "$database_url" -XAt -v ON_ERROR_STOP=1 -c "select (date_trunc('month',timezone('Europe/Budapest',now()))-interval '8 months')::date")"
psql "$database_url" -X -v ON_ERROR_STOP=1 <<SQL >/dev/null
insert into auth.users(id,email,raw_user_meta_data) values
 ('$admin_id','payment-race-admin@example.invalid','{"first_name":"Payment","last_name":"RaceAdmin"}'),
 ('$user_id','payment-race-user@example.invalid','{"first_name":"Payment","last_name":"RaceUser"}');
update public.profiles set role='admin',is_active=true where id='$admin_id';
insert into public.bookings(id,room_id,user_id,created_by,start_at,end_at,use_type,status,idempotency_key)
values('$booking_id','11000000-0000-0000-0000-000000000009','$user_id','$admin_id',
 timezone('Europe/Budapest','$month'::date+14+time '20:00'),
 timezone('Europe/Budapest','$month'::date+14+time '21:00'),'individual','active',gen_random_uuid());
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


# Receipt first: snapshot FK checks must not deadlock the booking lock.
start_holder payment-receipt-holder "select public.admin_record_booking_payment('$booking_id',10,current_date,'cash','cash_register',null,'51000000-0000-0000-0000-000000000395');"
start_waiter payment-snapshot-waiter "select * from public.admin_create_monthly_settlement_revision('$user_id','$month','Payment race',gen_random_uuid());" commit
wait_for_state payment-receipt-holder payment-snapshot-waiter
printf 'release\n' > "$test_dir/payment-receipt-holder.release"
wait "$holder_pid"; wait "$waiter_pid"
# Snapshot first: receipt gets its booking lock despite snapshot FK KEY SHARE.
start_holder payment-snapshot-holder "select * from public.admin_create_monthly_settlement_revision('$user_id','$month','Reverse payment race',gen_random_uuid());"
start_waiter payment-receipt-waiter "select public.admin_record_booking_payment('$booking_id',1,current_date,'cash','cash_register',null,'51000000-0000-0000-0000-000000000396');" commit
wait_for_state payment-snapshot-holder payment-receipt-waiter
printf 'release\n' > "$test_dir/payment-snapshot-holder.release"
wait "$holder_pid"; wait "$waiter_pid"
payment_id="$(psql "$database_url" -XAt -v ON_ERROR_STOP=1 -c "select id from public.payments where idempotency_key='51000000-0000-0000-0000-000000000395'")"
# Void first: legacy monthly writer waits and sees the committed void.
start_holder payment-void-holder "select public.admin_void_booking_payment('$payment_id','Wrong entry race');"
start_waiter payment-monthly-waiter "select * from public.admin_record_payment('$user_id','$month',10,current_date,'cash','cash_register',null,'51000000-0000-0000-0000-000000000397');" commit
wait_for_state payment-void-holder payment-monthly-waiter
printf 'release\n' > "$test_dir/payment-void-holder.release"
wait "$holder_pid"; wait "$waiter_pid"
actual="$(psql "$database_url" -XAt -v ON_ERROR_STOP=1 -c "begin;set local role authenticated;select set_config('request.jwt.claim.sub','$admin_id',true);select paid_huf from public.admin_monthly_booking_payment_summary('$month') where user_id='$user_id';rollback;" | tail -2 | head -1)"
[[ "$actual" == '11' ]] || { echo "Wrong final balance: $actual" >&2; exit 1; }
pids=()
echo 'Booking payment concurrency PASS: both snapshot orders and serialized void/monthly receipt.'
