#!/usr/bin/env bash
set -euo pipefail
readonly database_url="${AHELY_TEST_DB_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
case "$database_url" in
 postgresql://*@127.0.0.1:*/*|postgresql://*@localhost:*/*|postgres://*@127.0.0.1:*/*|postgres://*@localhost:*/*) ;;
 *) echo 'Only isolated local database allowed.' >&2; exit 1 ;;
esac
readonly admin_id="00000000-0000-0000-0000-000000000405"
readonly user_id="00000000-0000-0000-0000-000000000406"
readonly booking_id="41000000-0000-0000-0000-000000000405"
readonly room_id="11000000-0000-0000-0000-000000000009"
test_dir="$(mktemp -d)"
pids=()
cleanup() { for pid in "${pids[@]}"; do kill "$pid" 2>/dev/null || true; done; rm -rf "$test_dir"; }
trap cleanup EXIT
month="$(psql "$database_url" -XAt -v ON_ERROR_STOP=1 -c "select (date_trunc('month',timezone('Europe/Budapest',now()))-interval '7 months')::date")"
psql "$database_url" -X -v ON_ERROR_STOP=1 <<SQL >/dev/null
insert into auth.users(id,email,raw_user_meta_data) values
 ('$admin_id','historical-race-admin@example.invalid','{"first_name":"Historical","last_name":"RaceAdmin"}'),
 ('$user_id','historical-race-user@example.invalid','{"first_name":"Historical","last_name":"RaceUser"}');
update public.profiles set role='admin',is_active=true where id='$admin_id';
insert into public.bookings(id,room_id,user_id,created_by,start_at,end_at,use_type,status,idempotency_key)
values('$booking_id','$room_id','$user_id','$admin_id',timezone('Europe/Budapest','$month'::date+15+time '08:00'),timezone('Europe/Budapest','$month'::date+15+time '17:00'),'individual','active',gen_random_uuid());
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



correction_sql() {
 local hour="$1" reason="$2" version
 version="$(psql "$database_url" -XAt -v ON_ERROR_STOP=1 -c "select updated_at from public.bookings where id='$booking_id'")"
 printf "select public.admin_correct_open_month_booking('%s','%s','%s',timezone('Europe/Budapest','%s'::date+15+time '%s:00'),timezone('Europe/Budapest','%s'::date+15+time '17:00'),'individual',null,gen_random_uuid(),null,'%s');" "$booking_id" "$version" "$room_id" "$month" "$hour" "$month" "$reason"
}
# Normal create owns room -> period. Correction must wait for the same room.
start_holder historical-create-holder "select public.create_booking('$room_id','$user_id',timezone('Europe/Budapest','$month'::date+16+time '08:00'),timezone('Europe/Budapest','$month'::date+16+time '09:00'),'individual',null,'51000000-0000-0000-0000-000000000405');"
start_waiter historical-correct-waiter "$(correction_sql 09 'Create race')" commit
wait_for_state historical-create-holder historical-correct-waiter
printf 'release\n' > "$test_dir/historical-create-holder.release"
wait "$holder_pid"; wait "$waiter_pid"
read -r second_id second_version <<<"$(psql "$database_url" -XAtF' ' -v ON_ERROR_STOP=1 -c "select id,updated_at from public.bookings where idempotency_key='51000000-0000-0000-0000-000000000405'")"
# Correction owns room -> period. Normal update must wait for the same room.
start_holder historical-correct-holder "$(correction_sql 10 'Update race')"
start_waiter historical-update-waiter "select public.update_booking('$second_id','$second_version','$room_id',timezone('Europe/Budapest','$month'::date+16+time '09:00'),timezone('Europe/Budapest','$month'::date+16+time '10:00'),'individual',null,gen_random_uuid());" commit
wait_for_state historical-correct-holder historical-update-waiter
printf 'release\n' > "$test_dir/historical-correct-holder.release"
wait "$holder_pid"; wait "$waiter_pid"
# Correction first: closure sees corrected 6-hour booking, then rolls back.
start_holder historical-before-close-holder "$(correction_sql 11 'Close race')"
start_waiter historical-close-waiter "select * from public.admin_close_monthly_settlement_period('$month');select duration_minutes from public.settlement_booking_lines sl join public.monthly_settlements ms on ms.closed_revision_id=sl.settlement_revision_id where ms.user_id='$user_id' and ms.settlement_month='$month' and sl.booking_id='$booking_id';" rollback
wait_for_state historical-before-close-holder historical-close-waiter
printf 'release\n' > "$test_dir/historical-before-close-holder.release"
wait "$holder_pid"; wait "$waiter_pid"
grep -qx '360' "$test_dir/historical-close-waiter.log" || { cat "$test_dir/historical-close-waiter.log" >&2; exit 1; }
# Closure first: FK KEY SHARE must permit correction NO KEY UPDATE before wait.
start_holder historical-close-holder "select * from public.admin_close_monthly_settlement_period('$month');"
start_waiter historical-after-close-waiter "$(correction_sql 12 'Forbidden after close')" commit
wait_for_state historical-close-holder historical-after-close-waiter
printf 'release\n' > "$test_dir/historical-close-holder.release"
wait "$holder_pid"
if wait "$waiter_pid"; then echo 'Correction crossed closed month.' >&2; exit 1; fi
grep -q '42501: Lezárt hónap' "$test_dir/historical-after-close-waiter.log" || { cat "$test_dir/historical-after-close-waiter.log" >&2; exit 1; }
actual="$(psql "$database_url" -XAt -v ON_ERROR_STOP=1 -c "select extract(epoch from (end_at-start_at))::integer/60 from public.bookings where id='$booking_id'")"
[[ "$actual" == '360' ]] || { echo "Partial correction after close: $actual" >&2; exit 1; }
pids=()
echo 'Historical correction concurrency PASS: normal create/update and both closure orders.'
