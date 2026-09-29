#!/usr/bin/env bash
set -euo pipefail

if ! command -v psql >/dev/null 2>&1; then
  echo "Hiba: a psql kliens nincs telepítve." >&2
  exit 127
fi

readonly database_url="${AHELY_TEST_DB_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
case "$database_url" in
  postgresql://*@127.0.0.1:*/*|postgresql://*@localhost:*/*|postgres://*@127.0.0.1:*/*|postgres://*@localhost:*/*) ;;
  *) echo "Hiba: ez a teszt kizárólag helyi, izolált adatbázison futhat." >&2; exit 1 ;;
esac

readonly admin_a="00000000-0000-0000-0000-000000000280"
readonly admin_b="00000000-0000-0000-0000-000000000281"
readonly user_id="00000000-0000-0000-0000-000000000282"
readonly room_id="11000000-0000-0000-0000-000000000002"
readonly booking_a="41000000-0000-0000-0000-000000000280"
readonly booking_b="41000000-0000-0000-0000-000000000281"
readonly booking_c="41000000-0000-0000-0000-000000000282"

test_dir="$(mktemp -d)"
holder_pid=""
waiter_pid=""
cleanup() {
  if [[ -n "$waiter_pid" ]]; then kill "$waiter_pid" 2>/dev/null || true; fi
  if [[ -n "$holder_pid" ]]; then kill "$holder_pid" 2>/dev/null || true; fi
  rm -rf "$test_dir"
}
trap cleanup EXIT

psql "$database_url" -X -v ON_ERROR_STOP=1 <<SQL >/dev/null
insert into auth.users(id,email,raw_user_meta_data) values
 ('$admin_a','close-race-admin-a@example.invalid','{"first_name":"Close","last_name":"RaceAdminA"}'),
 ('$admin_b','close-race-admin-b@example.invalid','{"first_name":"Close","last_name":"RaceAdminB"}'),
 ('$user_id','close-race-user@example.invalid','{"first_name":"Close","last_name":"RaceUser"}');
update public.profiles set role='admin',is_active=true where id in ('$admin_a','$admin_b');
insert into public.user_room_permissions(user_id,room_id,can_book,can_repeat)
values ('$user_id','$room_id',true,true);
SQL

read -r month_a month_b month_c <<<"$(psql "$database_url" -X -AtF' ' -v ON_ERROR_STOP=1 -c \
  "select string_agg((date_trunc('month', timezone('Europe/Budapest',now())) - make_interval(months=>n))::date::text,' ' order by n)
   from generate_series(1,3) n")"

psql "$database_url" -X -v ON_ERROR_STOP=1 <<SQL >/dev/null
insert into public.bookings(id,room_id,user_id,created_by,start_at,end_at,use_type,status,idempotency_key)
select id::uuid,'$room_id','$user_id','$admin_a',
  (month_value::date + 4 + time '07:00') at time zone 'Europe/Budapest',
  (month_value::date + 4 + time '08:00') at time zone 'Europe/Budapest',
  'individual','active',gen_random_uuid()
from (values ('$booking_a','$month_a'),('$booking_b','$month_b'),('$booking_c','$month_c')) v(id,month_value);
SQL

wait_for_ready() {
  local scenario="$1" ready
  for ((attempt=0;attempt<100;attempt++)); do
    ready="$(psql "$database_url" -X -At -v ON_ERROR_STOP=1 -c "
      select exists (
        select 1 from pg_stat_activity holder join pg_locks held on held.pid=holder.pid
        where holder.application_name='ahely-close-$scenario-holder'
          and holder.state='idle in transaction'
          and held.locktype='advisory' and held.granted
      );")"
    if [[ "$ready" == "t" ]]; then return 0; fi
    if ! kill -0 "$holder_pid" 2>/dev/null; then break; fi
    sleep 0.1
  done
  echo "Hiba: $scenario: az első admin nem jutott el a zárás utáni, commit előtti állapotig." >&2
  cat "$test_dir/$scenario.holder.log" >&2
  exit 1
}

wait_for_blocked_connection() {
  local scenario="$1" blocking
  for ((attempt=0;attempt<100;attempt++)); do
    blocking="$(psql "$database_url" -X -At -v ON_ERROR_STOP=1 -c "
      select exists(
        select 1 from pg_stat_activity holder cross join pg_stat_activity waiter
        where holder.application_name='ahely-close-$scenario-holder'
          and waiter.application_name='ahely-close-$scenario-waiter'
          and waiter.wait_event_type='Lock'
          and (case when '$scenario'='c'
            then waiter.wait_event in ('tuple','transactionid')
            else waiter.wait_event='advisory' end)
          and holder.pid=any(pg_blocking_pids(waiter.pid))
      );")"
    if [[ "$blocking" == "t" ]]; then return 0; fi
    if ! kill -0 "$waiter_pid" 2>/dev/null; then break; fi
    sleep 0.1
  done
  echo "Hiba: $scenario: a második DB-kapcsolat bizonyíthatóan nem várt az első advisory lockjára." >&2
  cat "$test_dir/$scenario.waiter.log" >&2
  exit 1
}

start_holder() {
  local scenario="$1" month="$2"
  mkfifo "$test_dir/$scenario.release"
  (
    {
      printf "begin; set local statement_timeout='20s'; set local role authenticated;\n"
      printf "select set_config('request.jwt.claim.sub','%s',true);\n" "$admin_a"
      printf "select * from public.admin_close_monthly_settlement_period('%s'::date);\n" "$month"
      IFS= read -r _ < "$test_dir/$scenario.release"
      printf 'commit;\n'
    } | PGAPPNAME="ahely-close-$scenario-holder" psql "$database_url" -X -v ON_ERROR_STOP=1
  ) >"$test_dir/$scenario.holder.log" 2>&1 &
  holder_pid=$!
  wait_for_ready "$scenario"
}

assert_log_contains() {
  local scenario="$1" file="$2" pattern="$3"
  if ! grep -q "$pattern" "$test_dir/$file"; then
    echo "Hiba: $scenario: a várt hibaüzenet hiányzik: $pattern" >&2
    cat "$test_dir/$file" >&2
    exit 1
  fi
}

start_waiter() {
  local scenario="$1" actor="$2" sql="$3"
  (
    PGAPPNAME="ahely-close-$scenario-waiter" psql "$database_url" -X \
      -v ON_ERROR_STOP=1 -v VERBOSITY=verbose <<SQL
begin;
set local statement_timeout='20s';
set local lock_timeout='12s';
set local role authenticated;
select set_config('request.jwt.claim.sub','$actor',true);
$sql
commit;
SQL
  ) >"$test_dir/$scenario.waiter.log" 2>&1 &
  waiter_pid=$!
  wait_for_blocked_connection "$scenario"
}

finish_race() {
  local scenario="$1" expected_state="$2" holder_status waiter_status
  printf 'release\n' > "$test_dir/$scenario.release"
  set +e
  wait "$holder_pid"; holder_status=$?
  wait "$waiter_pid"; waiter_status=$?
  set -e
  holder_pid=""; waiter_pid=""
  if [[ "$holder_status" -ne 0 || "$waiter_status" -eq 0 ]] ||
     ! grep -q "$expected_state" "$test_dir/$scenario.waiter.log"; then
    echo "Hiba: $scenario: a szerializált végállapot vagy a várt SQLSTATE hibás." >&2
    cat "$test_dir/$scenario.holder.log" "$test_dir/$scenario.waiter.log" >&2
    exit 1
  fi
}

# A: one close commits, the second admin resumes after the lock and sees the
# committed period rather than creating another revision or a duplicate audit.
start_holder a "$month_a"
start_waiter a "$admin_b" "select * from public.admin_close_monthly_settlement_period('$month_a'::date);"
finish_race a P0001
assert_log_contains a a.waiter.log 'Ez a hónap már le van zárva'

# B: the public booking RPC reaches the bookings guard as the user and waits
# for the first admin's period lock. Its INSERT is then rejected after commit.
start_holder b "$month_b"
start_waiter b "$user_id" "select public.create_booking('$room_id','$user_id',
  ('$month_b'::date + 5 + time '09:00') at time zone 'Europe/Budapest',
  ('$month_b'::date + 5 + time '10:00') at time zone 'Europe/Budapest',
  'individual',null,'42000000-0000-0000-0000-000000000281');"
finish_race b 42501
assert_log_contains b b.waiter.log 'lezárt hónap foglalása'

# C: the public cancellation RPC first waits for the booking row held by the
# close's pricing snapshot. After commit it reads the current booking and is
# rejected at the established 24h cutoff; neither operation leaves a partial
# booking/revision. A separate direct write then verifies the guard itself.
start_holder c "$month_c"
start_waiter c "$user_id" "select public.cancel_booking('$booking_c',
  'Cutoff-teszt','42000000-0000-0000-0000-000000000282');"
finish_race c P0001
assert_log_contains c c.waiter.log 'órán belül már nem mondható le'
if psql "$database_url" -X -v ON_ERROR_STOP=1 -v VERBOSITY=verbose >"$test_dir/c.guard.log" 2>&1 <<SQL
begin;
set local statement_timeout='10s';
set local role service_role;
select set_config('request.jwt.claim.sub','$user_id',true);
update public.bookings set status='cancelled' where id='$booking_c';
commit;
SQL
then
  echo 'Hiba: a lezárt hónap user cancellation írása átjutott a DB guardon.' >&2
  exit 1
fi
assert_log_contains c c.guard.log 42501

for month in "$month_a" "$month_b" "$month_c"; do
  actual="$(psql "$database_url" -X -AtF' ' -v ON_ERROR_STOP=1 -c "
    select
      (select count(*) from public.monthly_settlement_periods where settlement_month='$month'),
      (select count(*) from public.monthly_settlements where settlement_month='$month'
        and is_closed and closed_revision_id is not null),
      (select count(*) from public.settlement_revisions r join public.monthly_settlements s
        on s.id=r.settlement_id where s.settlement_month='$month'),
      (select count(*) from public.audit_logs where action='monthly_settlement.period_closed'
        and entity_id='$month'),
      (select count(*) from public.audit_logs where action='monthly_settlement.revision_created'
        and after_data->>'settlement_month'='$month'),
      (select count(*) from public.bookings where user_id='$user_id' and status='active'
        and (start_at at time zone 'Europe/Budapest')::date >= '$month'::date
        and (start_at at time zone 'Europe/Budapest')::date < ('$month'::date+interval '1 month')::date),
      (select count(*) from public.monthly_settlements s join public.settlement_revisions r
        on r.id=s.closed_revision_id where s.settlement_month='$month'
        and r.normal_minutes+r.special_minutes=60 and r.calculated_due_huf=
          (select coalesce(sum(amount_huf),0) from public.settlement_booking_lines
           where settlement_revision_id=r.id)),
      (select count(*) from public.settlement_revisions r join public.monthly_settlements s
        on s.id=r.settlement_id where s.settlement_month='$month'
        and not exists (select 1 from public.settlement_booking_lines l
                        where l.settlement_revision_id=r.id));")"
  if [[ "$actual" != '1 1 1 1 1 1 1 0' ]]; then
    echo "Hiba: $month: részleges, többszörös vagy hibás pénzügyi/booking/audit állapot: $actual" >&2
    exit 1
  fi
done

remaining="$(psql "$database_url" -X -At -v ON_ERROR_STOP=1 -c "
  select (select count(*) from public.booking_cancellations where booking_id='$booking_c')
       + (select count(*) from public.audit_logs where action='booking.cancelled' and entity_id='$booking_c')
       + (select count(*) from public.booking_operation_requests where actor_user_id='$user_id'
          and idempotency_key in ('42000000-0000-0000-0000-000000000281',
                                  '42000000-0000-0000-0000-000000000282')); ")"
if [[ "$remaining" != '0' ]]; then
  echo "Hiba: sikertelen user művelet után részleges cancellation/operation/audit maradt: $remaining" >&2
  exit 1
fi

echo 'Havi zárás konkurenciateszt PASS: külön psql kapcsolatok; admin és booking advisory lock, publikus lemondás sorzár; atomikus snapshot és booking állapot.'
