begin;

select plan(24);

select has_function(
  'public', 'cancel_booking', array['uuid', 'text', 'uuid'],
  'A lemondási RPC létezik'
);
select has_table('public', 'booking_operation_requests', 'Az idempotencia-ledger létezik');
select has_column(
  'public', 'booking_cancellations', 'settlement_excluded',
  'A lemondás elszámolási kizárása explicit mező'
);
select has_trigger(
  'public', 'booking_cancellations', 'booking_cancellations_immutable',
  'A lemondási snapshot módosítása és törlése tiltott'
);
select has_trigger(
  'public', 'booking_operation_requests', 'booking_operation_requests_no_physical_delete',
  'Az idempotencia-ledger fizikailag nem törölhető'
);
select has_trigger(
  'public', 'bookings', 'bookings_validate_time_rules',
  'A dinamikus foglalási időszabály DB-triggerként létezik'
);
select has_trigger(
  'public', 'bookings', 'bookings_lock_room_writes',
  'Az azonos helyiség párhuzamos írásai determinisztikusan sorba állnak'
);
select ok(
  (
    select prosecdef from pg_proc
    where oid = 'public.validate_booking_time_rules()'::regprocedure
  ),
  'A dinamikus időszabály-trigger SECURITY DEFINER jogosultsággal olvassa a beállításokat'
);
select ok(
  (
    select prosecdef from pg_proc
    where oid = 'public.cancel_booking(uuid,text,uuid)'::regprocedure
  ),
  'A lemondási RPC SECURITY DEFINER függvény'
);
select ok(
  exists (
    select 1
    from pg_proc procedure
    cross join unnest(procedure.proconfig) as config(setting)
    where procedure.oid = 'public.cancel_booking(uuid,text,uuid)'::regprocedure
      and config.setting = 'search_path=""'
  ),
  'A lemondási RPC üres, rögzített search_path beállítást használ'
);

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-000000000051', 'cancel-admin@example.invalid', '{"first_name":"Cancel","last_name":"Admin"}'),
  ('00000000-0000-0000-0000-000000000052', 'cancel-user@example.invalid', '{"first_name":"Cancel","last_name":"User"}'),
  ('00000000-0000-0000-0000-000000000053', 'cancel-other@example.invalid', '{"first_name":"Cancel","last_name":"Other"}');

update public.profiles set role = 'admin'
where id = '00000000-0000-0000-0000-000000000051';

insert into public.user_room_permissions (user_id, room_id, can_book) values
  ('00000000-0000-0000-0000-000000000052', '11000000-0000-0000-0000-000000000002', true);

create temporary table cancellation_test_times as
select (
  case
    when (clock_timestamp() at time zone 'Europe/Budapest')::time < time '12:00'
      then (clock_timestamp() at time zone 'Europe/Budapest')::date + time '20:00'
    else (clock_timestamp() at time zone 'Europe/Budapest')::date + 1 + time '08:00'
  end at time zone 'Europe/Budapest'
) as near_start;

insert into public.bookings (
  id, room_id, user_id, created_by, start_at, end_at, idempotency_key
) values
  (
    '20000000-0000-0000-0000-000000000051',
    '11000000-0000-0000-0000-000000000002',
    '00000000-0000-0000-0000-000000000052',
    '00000000-0000-0000-0000-000000000052',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 2) + time '09:00') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 2) + time '10:00') at time zone 'Europe/Budapest',
    '16000000-0000-0000-0000-000000000051'
  ),
  (
    '20000000-0000-0000-0000-000000000052',
    '11000000-0000-0000-0000-000000000003',
    '00000000-0000-0000-0000-000000000053',
    '00000000-0000-0000-0000-000000000053',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 2) + time '11:00') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 2) + time '12:00') at time zone 'Europe/Budapest',
    '16000000-0000-0000-0000-000000000052'
  );

insert into public.bookings (
  id, room_id, user_id, created_by, start_at, end_at, idempotency_key
)
select
  '20000000-0000-0000-0000-000000000053',
  '11000000-0000-0000-0000-000000000004',
  '00000000-0000-0000-0000-000000000052',
  '00000000-0000-0000-0000-000000000052',
  near_start,
  near_start + interval '1 hour',
  '16000000-0000-0000-0000-000000000053'
from cancellation_test_times;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000052', true);
select lives_ok(
  $$select public.cancel_booking(
    '20000000-0000-0000-0000-000000000051',
    'Időben lemondva',
    '17000000-0000-0000-0000-000000000051'
  )$$,
  'Normál user legalább 24 órával korábban lemondhatja a saját foglalását'
);
reset role;

select is(
  (select status::text from public.bookings where id = '20000000-0000-0000-0000-000000000051'),
  'cancelled',
  'A booking történeti sora cancelled állapotban megmarad'
);
select ok(
  (
    select settlement_excluded
      and original_snapshot ->> 'status' = 'active'
      and original_snapshot ->> 'room_id' = '11000000-0000-0000-0000-000000000002'
    from public.booking_cancellations
    where booking_id = '20000000-0000-0000-0000-000000000051'
  ),
  'Az eredeti snapshot megmarad és a lemondás teljesen kizárt az elszámolásból'
);
select is(
  (
    select count(*)
    from public.audit_logs audit
    join public.outbox_events outbox
      on outbox.aggregate_id = audit.entity_id
      and outbox.event_type = 'booking.cancelled'
    where audit.action = 'booking.cancelled'
      and audit.correlation_id = '17000000-0000-0000-0000-000000000051'
  ),
  1::bigint,
  'A lemondással pontosan egy audit- és outboxrekord jött létre'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000052', true);
select is(
  public.cancel_booking(
    '20000000-0000-0000-0000-000000000051',
    'Időben lemondva',
    '17000000-0000-0000-0000-000000000051'
  ),
  '20000000-0000-0000-0000-000000000051'::uuid,
  'Azonos lemondási kérés idempotensen ugyanazt az eredményt adja'
);
reset role;

select is(
  (
    select count(*) from public.booking_cancellations
    where booking_id = '20000000-0000-0000-0000-000000000051'
  ),
  1::bigint,
  'Idempotens ismétlés nem duplikálja a lemondást'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000052', true);
select throws_ok(
  $$select public.cancel_booking(
    '20000000-0000-0000-0000-000000000051',
    'Eltérő indok',
    '17000000-0000-0000-0000-000000000051'
  )$$,
  'P0001',
  'Ezt a kérésazonosítót már más műveleti adatokkal használták.',
  'Azonos idempotenciakulcs eltérő payloadhoz nem használható'
);

select lives_ok(
  format(
    $sql$select public.create_booking(
      '11000000-0000-0000-0000-000000000002',
      '00000000-0000-0000-0000-000000000052',
      %L::timestamptz, %L::timestamptz, 'individual', null,
      '16000000-0000-0000-0000-000000000054'
    )$sql$,
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 2) + time '09:00') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 2) + time '10:00') at time zone 'Europe/Budapest'
  ),
  'Lemondás után a felszabadult idősáv újra foglalható'
);

select throws_ok(
  $$select public.cancel_booking(
    '20000000-0000-0000-0000-000000000052',
    null,
    '17000000-0000-0000-0000-000000000052'
  )$$,
  'P0001',
  'Csak a saját foglalásodat mondhatod le.',
  'Normál user más foglalását nem mondhatja le'
);

select throws_ok(
  $$select public.cancel_booking(
    '20000000-0000-0000-0000-000000000053',
    null,
    '17000000-0000-0000-0000-000000000053'
  )$$,
  'P0001',
  'A foglalás 24 órán belül már nem mondható le.',
  'Normál user a határidőn belül már nem mondhat le'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000051', true);
select lives_ok(
  $$select public.cancel_booking(
    '20000000-0000-0000-0000-000000000053',
    'Admin lemondás határidőn belül',
    '17000000-0000-0000-0000-000000000054'
  )$$,
  'Admin a 24 órás határidőn belül is lemondhat'
);
reset role;

select ok(
  (
    select cancellation.settlement_excluded
      and booking.status = 'cancelled'
    from public.booking_cancellations cancellation
    join public.bookings booking on booking.id = cancellation.booking_id
    where cancellation.booking_id = '20000000-0000-0000-0000-000000000053'
  ),
  'Az admin által lemondott foglalás is 0 Ft-os és elszámolásból kizárt'
);

select throws_ok(
  $$update public.booking_cancellations
    set reason = 'Tiltott módosítás'
    where booking_id = '20000000-0000-0000-0000-000000000051'$$,
  '42501',
  'audit_logs is append-only',
  'A lemondási snapshot utólag nem módosítható'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000052', true);
select throws_ok(
  $$select public.cancel_booking(
    '20000000-0000-0000-0000-000000009999',
    null,
    '17000000-0000-0000-0000-000000000055'
  )$$,
  'P0001',
  'A foglalás nem található.',
  'Nem létező foglalás magyar, érthető hibát ad'
);
reset role;

select * from finish();
rollback;
