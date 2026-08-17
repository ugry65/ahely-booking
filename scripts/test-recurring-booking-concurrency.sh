#!/usr/bin/env bash
set -euo pipefail

if ! command -v psql >/dev/null 2>&1; then
  echo "Hiba: a psql kliens nincs telepítve." >&2
  exit 127
fi

readonly database_url="${AHELY_TEST_DB_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
readonly user_id="00000000-0000-0000-0000-000000000131"
readonly room_id="11000000-0000-0000-0000-000000000005"
readonly idempotency_key="29000000-0000-0000-0000-000000000131"

test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

psql "$database_url" -X -v ON_ERROR_STOP=1 <<SQL
insert into auth.users (id, email, raw_user_meta_data) values
  ('$user_id', 'recurring-concurrency@example.invalid',
   '{"first_name":"Konkurens","last_name":"Sorozat"}');
insert into public.user_room_permissions (user_id, room_id, can_book, can_repeat)
values ('$user_id', '$room_id', true, true);
SQL

run_series() {
  local output_file="$1"
  psql "$database_url" -X -v ON_ERROR_STOP=1 >"$output_file" 2>&1 <<SQL
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '$user_id', true);
select public.create_booking_series(
  '$room_id',
  '$user_id',
  ((((clock_timestamp() at time zone 'Europe/Budapest')::date + 30) + time '09:00')
    at time zone 'Europe/Budapest'),
  ((((clock_timestamp() at time zone 'Europe/Budapest')::date + 30) + time '10:00')
    at time zone 'Europe/Budapest'),
  'weekly', null, 2, '{}', 'abort_all', 'individual',
  'Konkurens idempotenciateszt', '$idempotency_key'
);
select pg_sleep(2);
commit;
SQL
}

set +e
run_series "$test_dir/first.log" &
first_pid=$!
run_series "$test_dir/second.log" &
second_pid=$!
wait "$first_pid"
first_status=$?
wait "$second_pid"
second_status=$?
set -e

if [[ "$first_status" -ne 0 || "$second_status" -ne 0 ]]; then
  echo "Hiba: mindkét konkurens, azonos kulcsú sorozatkérésnek sikeresnek kell lennie." >&2
  sed -n '1,160p' "$test_dir/first.log" >&2
  sed -n '1,160p' "$test_dir/second.log" >&2
  exit 1
fi

read -r series_count booking_count occurrence_count audit_count outbox_count <<<"$(
  psql "$database_url" -X -AtF' ' -v ON_ERROR_STOP=1 -c "
    select
      (select count(*) from public.booking_series
       where created_by = '$user_id' and idempotency_key = '$idempotency_key'),
      (select count(*) from public.bookings
       where series_id = (select id from public.booking_series
         where created_by = '$user_id' and idempotency_key = '$idempotency_key')),
      (select count(*) from public.booking_series_occurrences
       where series_id = (select id from public.booking_series
         where created_by = '$user_id' and idempotency_key = '$idempotency_key')),
      (select count(*) from public.audit_logs where correlation_id = '$idempotency_key'),
      (select count(*) from public.outbox_events
       where payload ->> 'series_id' = (select id::text from public.booking_series
         where created_by = '$user_id' and idempotency_key = '$idempotency_key'));
  "
)"

if [[ "$series_count $booking_count $occurrence_count $audit_count $outbox_count" != "1 2 2 3 2" ]]; then
  echo "Hiba: a konkurens retry duplikált vagy hiányos sorozatállapotot eredményezett." >&2
  echo "series=$series_count bookings=$booking_count occurrences=$occurrence_count audits=$audit_count outbox=$outbox_count" >&2
  exit 1
fi

echo "Ismétlődő foglalás konkurenciateszt sikeres: mindkét kliens azonos, egyszer létrehozott sorozatot kapott."
