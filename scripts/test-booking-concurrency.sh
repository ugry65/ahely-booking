#!/usr/bin/env bash
set -euo pipefail

if ! command -v psql >/dev/null 2>&1; then
  echo "Hiba: a psql kliens nincs telepítve." >&2
  exit 127
fi

readonly database_url="${AHELY_TEST_DB_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
readonly actor_id="00000000-0000-0000-0000-000000000041"
readonly room_id="11000000-0000-0000-0000-000000000005"
readonly first_key="15000000-0000-0000-0000-000000000001"
readonly second_key="15000000-0000-0000-0000-000000000002"

test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

psql "$database_url" -X -v ON_ERROR_STOP=1 <<SQL
insert into auth.users (id, email, raw_user_meta_data) values (
  '$actor_id',
  'booking-concurrency@example.invalid',
  '{"first_name":"Konkurens","last_name":"Teszt"}'
);
insert into public.user_room_permissions (user_id, room_id, can_book) values (
  '$actor_id', '$room_id', true
);
SQL

start_at="$(psql "$database_url" -X -Atqc "select ((((clock_timestamp() at time zone 'Europe/Budapest')::date + 6) + time '16:00') at time zone 'Europe/Budapest')::text")"
end_at="$(psql "$database_url" -X -Atqc "select ((((clock_timestamp() at time zone 'Europe/Budapest')::date + 6) + time '17:00') at time zone 'Europe/Budapest')::text")"

run_booking() {
  local idempotency_key="$1"
  local output_file="$2"

  psql "$database_url" -X -v ON_ERROR_STOP=1 >"$output_file" 2>&1 <<SQL
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '$actor_id', true);
select public.create_booking(
  '$room_id',
  '$actor_id',
  '$start_at'::timestamptz,
  '$end_at'::timestamptz,
  'individual',
  'Konkurenciateszt',
  '$idempotency_key'
);
select pg_sleep(2);
commit;
SQL
}

set +e
run_booking "$first_key" "$test_dir/first.log" &
first_pid=$!
run_booking "$second_key" "$test_dir/second.log" &
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
  echo "Hiba: a két párhuzamos kérésből pontosan egynek kellett volna sikerülnie." >&2
  echo "Első kérés kilépési kódja: $first_status" >&2
  sed -n '1,120p' "$test_dir/first.log" >&2
  echo "Második kérés kilépési kódja: $second_status" >&2
  sed -n '1,120p' "$test_dir/second.log" >&2
  exit 1
fi

read -r booking_count audit_count outbox_count <<<"$(
  psql "$database_url" -X -AtF' ' -v ON_ERROR_STOP=1 -c "
    select
      count(distinct booking.id),
      count(distinct audit.id),
      count(distinct outbox.id)
    from public.bookings booking
    left join public.audit_logs audit
      on audit.entity_id = booking.id::text and audit.action = 'booking.created'
    left join public.outbox_events outbox
      on outbox.aggregate_id = booking.id::text and outbox.event_type = 'booking.created'
    where booking.created_by = '$actor_id'
      and booking.idempotency_key in ('$first_key', '$second_key');
  "
)"

if [[ "$booking_count $audit_count $outbox_count" != "1 1 1" ]]; then
  echo "Hiba: részleges vagy duplikált tranzakciós mellékhatás." >&2
  echo "bookings=$booking_count audit_logs=$audit_count outbox_events=$outbox_count" >&2
  exit 1
fi

echo "Konkurenciateszt sikeres: két átfedő párhuzamos kérésből pontosan egy commitált."
