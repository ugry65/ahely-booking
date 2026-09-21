#!/usr/bin/env bash
set -euo pipefail

if ! command -v psql >/dev/null 2>&1; then
  echo "Hiba: a psql kliens nincs telepítve." >&2
  exit 127
fi

# This test writes a booking fixture. Never accept a caller-supplied target.
database_url="postgresql://postgres:postgres@127.0.0.1:54322/postgres"

test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

if ! psql "$database_url" -X -qAt -v ON_ERROR_STOP=1 >"$test_dir/stdout" 2>"$test_dir/stderr" <<'SQL'
begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('a5100000-0000-0000-0000-000000000001', 'warning-actor@example.invalid', '{"first_name":"Warning","last_name":"Actor"}'),
  ('a5100000-0000-0000-0000-000000000002', 'warning-owner@example.invalid', '{"first_name":"Warning","last_name":"Owner"}');

update public.profiles set role = 'admin'
where id = 'a5100000-0000-0000-0000-000000000001';

select set_config('request.jwt.claim.sub', 'a5100000-0000-0000-0000-000000000001', true) \gset

do $booking$
begin
  perform set_config('test.warning_booking_id', public.create_booking(
    '11000000-0000-0000-0000-000000000002',
    'a5100000-0000-0000-0000-000000000002',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 75) + time '09:00') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 75) + time '10:00') at time zone 'Europe/Budapest',
    'individual', 'private-note-warning-marker',
    'a5100000-0000-0000-0000-000000000101', 'Warning isolation test'
  )::text, true);
end;
$booking$;

-- The canonical booking/audit were already written. Only e-mail resolution fails.
update public.profiles set email = ''
where id = 'a5100000-0000-0000-0000-000000000002';
set constraints booking_email_from_audit immediate;

select case when
  (select count(*) from public.bookings where id = current_setting('test.warning_booking_id')::uuid) = 1
  and (select count(*) from public.audit_logs
       where correlation_id = 'a5100000-0000-0000-0000-000000000101'
         and action = 'booking.created' and entity_type = 'booking') = 1
  and (select count(*) from public.booking_email_outbox
       where correlation_id = 'a5100000-0000-0000-0000-000000000101') = 0
  then 'BOOKING_EMAIL_BRIDGE_DATA_OK' else 'BOOKING_EMAIL_BRIDGE_DATA_FAIL' end;
rollback;
SQL
then
  echo "Hiba: a bridge figyelmeztetés teszt SQL-műveletei nem sikerültek." >&2
  exit 1
fi

if [[ "$(tr -d '\r\n' <"$test_dir/stdout")" != "BOOKING_EMAIL_BRIDGE_DATA_OK" ]]; then
  echo "Hiba: az e-mail bridge hibája után a booking/audit/outbox állapot nem megfelelő." >&2
  exit 1
fi

if ! grep -Eq 'WARNING: +booking_email_bridge_failed sqlstate=P0001[[:space:]]*$' "$test_dir/stderr"; then
  echo "Hiba: a biztonságos SQLSTATE warning nem jelent meg a psql kimenetén." >&2
  exit 1
fi
if [[ "$(grep -c 'booking_email_bridge_failed' "$test_dir/stderr")" != "1" ]]; then
  echo "Hiba: egy logikai bridge-hibához nem pontosan egy warning tartozik." >&2
  exit 1
fi
if grep -Eq 'warning-owner@example[.]invalid|private-note-warning-marker' "$test_dir/stderr"; then
  echo "Hiba: érzékeny adat került a warning kimenetébe." >&2
  exit 1
fi

echo "Booking e-mail bridge warning teszt sikeres: SQLSTATE-only warning, booking/audit megmaradt."
