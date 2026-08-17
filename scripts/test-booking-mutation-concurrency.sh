#!/usr/bin/env bash
set -euo pipefail

if ! command -v psql >/dev/null 2>&1; then
  echo "Hiba: a psql kliens nincs telepítve." >&2
  exit 127
fi

readonly database_url="${AHELY_TEST_DB_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
readonly actor_id="00000000-0000-0000-0000-000000000071"
readonly cancel_booking_id="20000000-0000-0000-0000-000000000071"
readonly update_booking_id="20000000-0000-0000-0000-000000000072"
readonly cross_first_booking_id="20000000-0000-0000-0000-000000000073"
readonly cross_second_booking_id="20000000-0000-0000-0000-000000000074"
readonly cancel_key="21000000-0000-0000-0000-000000000071"
readonly update_first_key="21000000-0000-0000-0000-000000000072"
readonly update_second_key="21000000-0000-0000-0000-000000000073"
readonly cross_first_key="21000000-0000-0000-0000-000000000074"
readonly cross_second_key="21000000-0000-0000-0000-000000000075"

test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

psql "$database_url" -X -v ON_ERROR_STOP=1 <<SQL
insert into auth.users (id, email, raw_user_meta_data) values (
  '$actor_id',
  'booking-mutation-concurrency@example.invalid',
  '{"first_name":"Mutation","last_name":"Concurrency"}'
);
insert into public.user_room_permissions (user_id, room_id, can_book) values
  ('$actor_id', '11000000-0000-0000-0000-000000000006', true),
  ('$actor_id', '11000000-0000-0000-0000-000000000007', true);

insert into public.bookings (
  id, room_id, user_id, created_by, start_at, end_at, idempotency_key
) values
  (
    '$cancel_booking_id', '11000000-0000-0000-0000-000000000006',
    '$actor_id', '$actor_id',
    ((((clock_timestamp() at time zone 'Europe/Budapest')::date + 7) + time '09:00') at time zone 'Europe/Budapest'),
    ((((clock_timestamp() at time zone 'Europe/Budapest')::date + 7) + time '10:00') at time zone 'Europe/Budapest'),
    '22000000-0000-0000-0000-000000000071'
  ),
  (
    '$update_booking_id', '11000000-0000-0000-0000-000000000007',
    '$actor_id', '$actor_id',
    ((((clock_timestamp() at time zone 'Europe/Budapest')::date + 7) + time '11:00') at time zone 'Europe/Budapest'),
    ((((clock_timestamp() at time zone 'Europe/Budapest')::date + 7) + time '12:00') at time zone 'Europe/Budapest'),
    '22000000-0000-0000-0000-000000000072'
  ),
  (
    '$cross_first_booking_id', '11000000-0000-0000-0000-000000000006',
    '$actor_id', '$actor_id',
    ((((clock_timestamp() at time zone 'Europe/Budapest')::date + 7) + time '17:00') at time zone 'Europe/Budapest'),
    ((((clock_timestamp() at time zone 'Europe/Budapest')::date + 7) + time '18:00') at time zone 'Europe/Budapest'),
    '22000000-0000-0000-0000-000000000073'
  ),
  (
    '$cross_second_booking_id', '11000000-0000-0000-0000-000000000007',
    '$actor_id', '$actor_id',
    ((((clock_timestamp() at time zone 'Europe/Budapest')::date + 7) + time '19:00') at time zone 'Europe/Budapest'),
    ((((clock_timestamp() at time zone 'Europe/Budapest')::date + 7) + time '20:00') at time zone 'Europe/Budapest'),
    '22000000-0000-0000-0000-000000000074'
  );
SQL

run_cancel() {
  local output_file="$1"
  psql "$database_url" -X -v ON_ERROR_STOP=1 >"$output_file" 2>&1 <<SQL
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '$actor_id', true);
select public.cancel_booking('$cancel_booking_id', 'Konkurens lemondás', '$cancel_key');
select pg_sleep(2);
commit;
SQL
}

set +e
run_cancel "$test_dir/cancel-first.log" &
first_pid=$!
run_cancel "$test_dir/cancel-second.log" &
second_pid=$!
wait "$first_pid"
first_status=$?
wait "$second_pid"
second_status=$?
set -e

if [[ "$first_status" -ne 0 || "$second_status" -ne 0 ]]; then
  echo "Hiba: mindkét azonos kulcsú párhuzamos lemondásnak sikeresnek kell lennie." >&2
  sed -n '1,120p' "$test_dir/cancel-first.log" >&2
  sed -n '1,120p' "$test_dir/cancel-second.log" >&2
  exit 1
fi

read -r cancellation_count audit_count outbox_count ledger_count <<<"$(
  psql "$database_url" -X -AtF' ' -v ON_ERROR_STOP=1 -c "
    select
      (select count(*) from public.booking_cancellations where booking_id = '$cancel_booking_id'),
      (select count(*) from public.audit_logs where entity_id = '$cancel_booking_id' and action = 'booking.cancelled'),
      (select count(*) from public.outbox_events where aggregate_id = '$cancel_booking_id' and event_type = 'booking.cancelled'),
      (select count(*) from public.booking_operation_requests where actor_user_id = '$actor_id' and idempotency_key = '$cancel_key');
  "
)"

if [[ "$cancellation_count $audit_count $outbox_count $ledger_count" != "1 1 1 1" ]]; then
  echo "Hiba: az idempotens lemondási race duplikált vagy részleges eredményt adott." >&2
  exit 1
fi

expected_updated_at="$(psql "$database_url" -X -Atqc "select updated_at::text from public.bookings where id = '$update_booking_id'")"
first_start="$(psql "$database_url" -X -Atqc "select ((((clock_timestamp() at time zone 'Europe/Budapest')::date + 7) + time '13:00') at time zone 'Europe/Budapest')::text")"
first_end="$(psql "$database_url" -X -Atqc "select ((((clock_timestamp() at time zone 'Europe/Budapest')::date + 7) + time '14:00') at time zone 'Europe/Budapest')::text")"
second_start="$(psql "$database_url" -X -Atqc "select ((((clock_timestamp() at time zone 'Europe/Budapest')::date + 7) + time '15:00') at time zone 'Europe/Budapest')::text")"
second_end="$(psql "$database_url" -X -Atqc "select ((((clock_timestamp() at time zone 'Europe/Budapest')::date + 7) + time '16:00') at time zone 'Europe/Budapest')::text")"

run_update() {
  local idempotency_key="$1"
  local requested_start="$2"
  local requested_end="$3"
  local output_file="$4"

  psql "$database_url" -X -v ON_ERROR_STOP=1 >"$output_file" 2>&1 <<SQL
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '$actor_id', true);
select public.update_booking(
  '$update_booking_id', '$expected_updated_at'::timestamptz,
  '11000000-0000-0000-0000-000000000007',
  '$requested_start'::timestamptz, '$requested_end'::timestamptz,
  'individual', 'Konkurens módosítás', '$idempotency_key'
);
select pg_sleep(2);
commit;
SQL
}

set +e
run_update "$update_first_key" "$first_start" "$first_end" "$test_dir/update-first.log" &
first_pid=$!
run_update "$update_second_key" "$second_start" "$second_end" "$test_dir/update-second.log" &
second_pid=$!
wait "$first_pid"
first_status=$?
wait "$second_pid"
second_status=$?
set -e

success_count=0
[[ "$first_status" -eq 0 ]] && success_count=$((success_count + 1))
[[ "$second_status" -eq 0 ]] && success_count=$((success_count + 1))

if [[ "$success_count" -ne 1 ]]; then
  echo "Hiba: két azonos verzióból induló párhuzamos módosításból pontosan egynek kell sikerülnie." >&2
  sed -n '1,120p' "$test_dir/update-first.log" >&2
  sed -n '1,120p' "$test_dir/update-second.log" >&2
  exit 1
fi

if [[ "$first_status" -ne 0 ]]; then
  stale_log="$test_dir/update-first.log"
else
  stale_log="$test_dir/update-second.log"
fi

if ! grep -Fq "A foglalás időközben módosult." "$stale_log"; then
  echo "Hiba: a vesztes módosítás nem a várt optimista zárolási hibát adta." >&2
  sed -n '1,120p' "$stale_log" >&2
  exit 1
fi

read -r audit_count outbox_count ledger_count <<<"$(
  psql "$database_url" -X -AtF' ' -v ON_ERROR_STOP=1 -c "
    select
      (select count(*) from public.audit_logs where entity_id = '$update_booking_id' and action = 'booking.updated'),
      (select count(*) from public.outbox_events where aggregate_id = '$update_booking_id' and event_type = 'booking.updated'),
      (select count(*) from public.booking_operation_requests where booking_id = '$update_booking_id' and operation = 'update');
  "
)"

if [[ "$audit_count $outbox_count $ledger_count" != "1 1 1" ]]; then
  echo "Hiba: a párhuzamos módosítás részleges vagy duplikált mellékhatást adott." >&2
  exit 1
fi

cross_first_updated_at="$(psql "$database_url" -X -Atqc "select updated_at::text from public.bookings where id = '$cross_first_booking_id'")"
cross_second_updated_at="$(psql "$database_url" -X -Atqc "select updated_at::text from public.bookings where id = '$cross_second_booking_id'")"
cross_first_start="$(psql "$database_url" -X -Atqc "select start_at::text from public.bookings where id = '$cross_first_booking_id'")"
cross_first_end="$(psql "$database_url" -X -Atqc "select end_at::text from public.bookings where id = '$cross_first_booking_id'")"
cross_second_start="$(psql "$database_url" -X -Atqc "select start_at::text from public.bookings where id = '$cross_second_booking_id'")"
cross_second_end="$(psql "$database_url" -X -Atqc "select end_at::text from public.bookings where id = '$cross_second_booking_id'")"

run_cross_update() {
  local booking_id="$1"
  local expected_updated_at="$2"
  local target_room_id="$3"
  local requested_start="$4"
  local requested_end="$5"
  local idempotency_key="$6"
  local output_file="$7"

  psql "$database_url" -X -v ON_ERROR_STOP=1 >"$output_file" 2>&1 <<SQL
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '$actor_id', true);
select public.update_booking(
  '$booking_id', '$expected_updated_at'::timestamptz,
  '$target_room_id',
  '$requested_start'::timestamptz,
  '$requested_end'::timestamptz,
  'individual', 'Kereszt-helyiséges módosítás', '$idempotency_key'
);
select pg_sleep(2);
commit;
SQL
}

set +e
run_cross_update \
  "$cross_first_booking_id" "$cross_first_updated_at" \
  "11000000-0000-0000-0000-000000000007" \
  "$cross_first_start" "$cross_first_end" "$cross_first_key" \
  "$test_dir/cross-first.log" &
first_pid=$!
run_cross_update \
  "$cross_second_booking_id" "$cross_second_updated_at" \
  "11000000-0000-0000-0000-000000000006" \
  "$cross_second_start" "$cross_second_end" "$cross_second_key" \
  "$test_dir/cross-second.log" &
second_pid=$!
wait "$first_pid"
first_status=$?
wait "$second_pid"
second_status=$?
set -e

if [[ "$first_status" -ne 0 || "$second_status" -ne 0 ]]; then
  echo "Hiba: a kereszt-helyiséges módosításoknak deadlock nélkül sikerülniük kell." >&2
  sed -n '1,120p' "$test_dir/cross-first.log" >&2
  sed -n '1,120p' "$test_dir/cross-second.log" >&2
  exit 1
fi

read -r swapped_count audit_count outbox_count ledger_count <<<"$(
  psql "$database_url" -X -AtF' ' -v ON_ERROR_STOP=1 -c "
    select
      (select count(*) from public.bookings
       where (id = '$cross_first_booking_id' and room_id = '11000000-0000-0000-0000-000000000007')
          or (id = '$cross_second_booking_id' and room_id = '11000000-0000-0000-0000-000000000006')),
      (select count(*) from public.audit_logs
       where entity_id in ('$cross_first_booking_id', '$cross_second_booking_id')
         and action = 'booking.updated'),
      (select count(*) from public.outbox_events
       where aggregate_id in ('$cross_first_booking_id', '$cross_second_booking_id')
         and event_type = 'booking.updated'),
      (select count(*) from public.booking_operation_requests
       where booking_id in ('$cross_first_booking_id', '$cross_second_booking_id')
         and operation = 'update');
  "
)"

if [[ "$swapped_count $audit_count $outbox_count $ledger_count" != "2 2 2 2" ]]; then
  echo "Hiba: a kereszt-helyiséges módosítás részleges vagy duplikált eredményt adott." >&2
  exit 1
fi

echo "Műveleti konkurenciateszt sikeres: lemondás, optimista módosítás és kereszt-helyiséges lock-sorrend helyes."
