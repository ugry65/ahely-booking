#!/usr/bin/env bash
set -euo pipefail

if ! command -v psql >/dev/null 2>&1; then
  echo "Hiba: a psql kliens nincs telepítve." >&2
  exit 127
fi

readonly database_url="${AHELY_TEST_DB_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
readonly actor_id="a4100000-0000-0000-0000-000000000001"
readonly user_id="a4100000-0000-0000-0000-000000000002"
readonly booking_id="a4100000-0000-0000-0000-000000000010"
readonly outbox_id="a4100000-0000-0000-0000-000000000020"

test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

psql "$database_url" -X -v ON_ERROR_STOP=1 <<SQL
-- Earlier committed booking concurrency tests now legitimately leave pending
-- notification work behind. Drain it through the public worker state machine so
-- this test's two workers compete only for the dedicated fixture below.
do \$drain\$
declare
  claimed record;
  claimed_any boolean;
begin
  loop
    claimed_any := false;
    for claimed in
      select * from public.claim_booking_email_outbox(100, 30)
    loop
      claimed_any := true;
      perform public.complete_booking_email_outbox(
        claimed.id,
        claimed.lease_token,
        'captured'
      );
    end loop;
    exit when not claimed_any;
  end loop;
end;
\$drain\$;

insert into auth.users (id, email, raw_user_meta_data) values
  ('$actor_id', 'email-claim-actor@example.invalid', '{"first_name":"Claim","last_name":"Actor"}'),
  ('$user_id', 'email-claim-user@example.invalid', '{"first_name":"Claim","last_name":"User"}');

insert into public.bookings (
  id, room_id, user_id, created_by, start_at, end_at, use_type, status, idempotency_key
) values (
  '$booking_id',
  '11000000-0000-0000-0000-000000000011',
  '$user_id',
  '$actor_id',
  '2031-01-10 09:00 Europe/Budapest',
  '2031-01-10 10:00 Europe/Budapest',
  'individual',
  'active',
  'a4100000-0000-0000-0000-000000000011'
);

insert into public.booking_email_outbox (
  id, correlation_id, deduplication_key, event_type, scope, booking_id,
  recipient_user_id, recipient_email, actor_user_id, performed_by_admin,
  payload_version, payload
) values (
  '$outbox_id',
  'a4100000-0000-0000-0000-000000000021',
  'a4100000-0000-0000-0000-000000000021:booking.created:$user_id',
  'booking.created',
  'single',
  '$booking_id',
  '$user_id',
  'email-claim-user@example.invalid',
  '$actor_id',
  false,
  1,
  '{"room_name":"Forrás tér"}'::jsonb
);
SQL

run_claim() {
  local output_file="$1"
  psql "$database_url" -X -At -v ON_ERROR_STOP=1 >"$output_file" 2>&1 <<SQL
begin;
set local role service_role;
select id from public.claim_booking_email_outbox(1, 300);
select pg_sleep(2);
commit;
SQL
}

set +e
run_claim "$test_dir/first.log" &
first_pid=$!
run_claim "$test_dir/second.log" &
second_pid=$!
wait "$first_pid"
first_status=$?
wait "$second_pid"
second_status=$?
set -e

if [[ "$first_status" -ne 0 || "$second_status" -ne 0 ]]; then
  echo "Hiba: mindkét konkurens claim tranzakciónak hiba nélkül kell lefutnia." >&2
  sed -n '1,120p' "$test_dir/first.log" >&2
  sed -n '1,120p' "$test_dir/second.log" >&2
  exit 1
fi

claimed_count="$({ grep -Fh "$outbox_id" "$test_dir/first.log" "$test_dir/second.log" || true; } | wc -l | tr -d ' ')"

if [[ "$claimed_count" != "1" ]]; then
  echo "Hiba: két konkurens worker összesen pontosan egyszer kaphatja meg ugyanazt az outbox rekordot." >&2
  sed -n '1,120p' "$test_dir/first.log" >&2
  sed -n '1,120p' "$test_dir/second.log" >&2
  exit 1
fi

claim_state="$(
  psql "$database_url" -X -At -v ON_ERROR_STOP=1 -c "
    select status || ':' || attempts::text || ':' || (lease_token is not null)::text
    from public.booking_email_outbox
    where id = '$outbox_id';
  "
)"

if [[ "$claim_state" != "sending:0:true" ]]; then
  echo "Hiba: a konkurens claim után a lease-állapot nem konzisztens: $claim_state" >&2
  exit 1
fi

echo "Booking e-mail outbox konkurenciateszt sikeres: két worker közül pontosan egy claimelte a rekordot."
