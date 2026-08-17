begin;

select plan(19);

select has_function(
  'public',
  'update_booking',
  array[
    'uuid', 'timestamp with time zone', 'uuid', 'timestamp with time zone',
    'timestamp with time zone', 'booking_use_type', 'text', 'uuid'
  ],
  'A foglalásmódosítási RPC létezik'
);
select ok(
  (
    select prosecdef from pg_proc
    where oid = 'public.update_booking(uuid,timestamptz,uuid,timestamptz,timestamptz,public.booking_use_type,text,uuid)'::regprocedure
  ),
  'A módosítási RPC SECURITY DEFINER függvény'
);
select ok(
  exists (
    select 1
    from pg_proc procedure
    cross join unnest(procedure.proconfig) as config(setting)
    where procedure.oid = 'public.update_booking(uuid,timestamptz,uuid,timestamptz,timestamptz,public.booking_use_type,text,uuid)'::regprocedure
      and config.setting = 'search_path=""'
  ),
  'A módosítási RPC üres, rögzített search_path beállítást használ'
);

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-000000000061', 'update-admin@example.invalid', '{"first_name":"Update","last_name":"Admin"}'),
  ('00000000-0000-0000-0000-000000000062', 'update-user@example.invalid', '{"first_name":"Update","last_name":"User"}'),
  ('00000000-0000-0000-0000-000000000063', 'update-other@example.invalid', '{"first_name":"Update","last_name":"Other"}');

update public.profiles set role = 'admin'
where id = '00000000-0000-0000-0000-000000000061';

insert into public.user_room_permissions (user_id, room_id, can_book) values
  ('00000000-0000-0000-0000-000000000062', '11000000-0000-0000-0000-000000000002', true),
  ('00000000-0000-0000-0000-000000000062', '11000000-0000-0000-0000-000000000003', true);

insert into public.bookings (
  id, room_id, user_id, created_by, start_at, end_at, idempotency_key, updated_at
) values
  (
    '20000000-0000-0000-0000-000000000061',
    '11000000-0000-0000-0000-000000000002',
    '00000000-0000-0000-0000-000000000062',
    '00000000-0000-0000-0000-000000000062',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 4) + time '09:00') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 4) + time '10:00') at time zone 'Europe/Budapest',
    '18000000-0000-0000-0000-000000000061',
    date_trunc('second', clock_timestamp())
  ),
  (
    '20000000-0000-0000-0000-000000000062',
    '11000000-0000-0000-0000-000000000003',
    '00000000-0000-0000-0000-000000000063',
    '00000000-0000-0000-0000-000000000063',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 4) + time '11:00') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 4) + time '12:00') at time zone 'Europe/Budapest',
    '18000000-0000-0000-0000-000000000062',
    date_trunc('second', clock_timestamp())
  ),
  (
    '20000000-0000-0000-0000-000000000063',
    '11000000-0000-0000-0000-000000000003',
    '00000000-0000-0000-0000-000000000063',
    '00000000-0000-0000-0000-000000000063',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 5) + time '10:00') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 5) + time '11:00') at time zone 'Europe/Budapest',
    '18000000-0000-0000-0000-000000000063',
    date_trunc('second', clock_timestamp())
  ),
  (
    '20000000-0000-0000-0000-000000000064',
    '11000000-0000-0000-0000-000000000002',
    '00000000-0000-0000-0000-000000000062',
    '00000000-0000-0000-0000-000000000062',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 6) + time '12:00') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 6) + time '13:00') at time zone 'Europe/Budapest',
    '18000000-0000-0000-0000-000000000064',
    date_trunc('second', clock_timestamp())
  );

update public.bookings set status = 'cancelled'
where id = '20000000-0000-0000-0000-000000000064';

select set_config(
  'test.update_initial',
  (select updated_at::text from public.bookings where id = '20000000-0000-0000-0000-000000000061'),
  true
);
select set_config(
  'test.update_other',
  (select updated_at::text from public.bookings where id = '20000000-0000-0000-0000-000000000062'),
  true
);
select set_config(
  'test.update_cancelled',
  (select updated_at::text from public.bookings where id = '20000000-0000-0000-0000-000000000064'),
  true
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000062', true);
select lives_ok(
  format(
    $sql$select public.update_booking(
      '20000000-0000-0000-0000-000000000061',
      %L::timestamptz,
      '11000000-0000-0000-0000-000000000002',
      %L::timestamptz, %L::timestamptz,
      'individual', 'Módosított megjegyzés',
      '19000000-0000-0000-0000-000000000061'
    )$sql$,
    current_setting('test.update_initial'),
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 4) + time '10:00') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 4) + time '11:00') at time zone 'Europe/Budapest'
  ),
  'Normál user szabályosan módosíthatja a saját egyedi foglalását'
);
reset role;

select ok(
  (
    select note = 'Módosított megjegyzés'
      and start_at = ((((clock_timestamp() at time zone 'Europe/Budapest')::date + 4) + time '10:00') at time zone 'Europe/Budapest')
      and end_at = ((((clock_timestamp() at time zone 'Europe/Budapest')::date + 4) + time '11:00') at time zone 'Europe/Budapest')
    from public.bookings
    where id = '20000000-0000-0000-0000-000000000061'
  ),
  'A módosított időpont és megjegyzés eltárolódott'
);
select is(
  (
    select count(*)
    from public.audit_logs audit
    join public.outbox_events outbox
      on outbox.aggregate_id = audit.entity_id and outbox.event_type = 'booking.updated'
    where audit.correlation_id = '19000000-0000-0000-0000-000000000061'
      and audit.action = 'booking.updated'
  ),
  1::bigint,
  'A módosítással pontosan egy audit- és outboxrekord jött létre'
);
select set_config(
  'test.update_current',
  (select updated_at::text from public.bookings where id = '20000000-0000-0000-0000-000000000061'),
  true
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000062', true);
select is(
  public.update_booking(
    '20000000-0000-0000-0000-000000000061',
    current_setting('test.update_initial')::timestamptz,
    '11000000-0000-0000-0000-000000000002',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 4) + time '10:00') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 4) + time '11:00') at time zone 'Europe/Budapest',
    'individual', 'Módosított megjegyzés',
    '19000000-0000-0000-0000-000000000061'
  ),
  '20000000-0000-0000-0000-000000000061'::uuid,
  'Azonos módosítási kérés idempotensen ugyanazt az eredményt adja'
);
reset role;

select is(
  (
    select count(*) from public.booking_operation_requests
    where actor_user_id = '00000000-0000-0000-0000-000000000062'
      and idempotency_key = '19000000-0000-0000-0000-000000000061'
  ),
  1::bigint,
  'Idempotens ismétlés nem duplikálja a műveleti ledgert'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000062', true);
select throws_ok(
  format(
    $sql$select public.update_booking(
      '20000000-0000-0000-0000-000000000061', %L::timestamptz,
      '11000000-0000-0000-0000-000000000002',
      %L::timestamptz, %L::timestamptz, 'individual', 'Eltérő payload',
      '19000000-0000-0000-0000-000000000061'
    )$sql$,
    current_setting('test.update_initial'),
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 4) + time '10:00') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 4) + time '11:00') at time zone 'Europe/Budapest'
  ),
  'P0001', 'Ezt a kérésazonosítót már más műveleti adatokkal használták.',
  'Azonos idempotenciakulcs eltérő módosításhoz nem használható'
);

select throws_ok(
  format(
    $sql$select public.update_booking(
      '20000000-0000-0000-0000-000000000061', %L::timestamptz,
      '11000000-0000-0000-0000-000000000002',
      %L::timestamptz, %L::timestamptz, 'individual', null,
      '19000000-0000-0000-0000-000000000062'
    )$sql$,
    current_setting('test.update_initial'),
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 4) + time '12:00') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 4) + time '13:00') at time zone 'Europe/Budapest'
  ),
  'P0001', 'A foglalás időközben módosult. Frissítsd az oldalt, majd próbáld újra.',
  'Elavult verzióval a módosítás elutasított'
);

select throws_ok(
  format(
    $sql$select public.update_booking(
      '20000000-0000-0000-0000-000000000062', %L::timestamptz,
      '11000000-0000-0000-0000-000000000003',
      %L::timestamptz, %L::timestamptz, 'individual', null,
      '19000000-0000-0000-0000-000000000063'
    )$sql$,
    current_setting('test.update_other'),
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 4) + time '13:00') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 4) + time '14:00') at time zone 'Europe/Budapest'
  ),
  'P0001', 'Csak a saját foglalásodat módosíthatod.',
  'Normál user más foglalását nem módosíthatja'
);

select throws_ok(
  format(
    $sql$select public.update_booking(
      '20000000-0000-0000-0000-000000000061', %L::timestamptz,
      '11000000-0000-0000-0000-000000000004',
      %L::timestamptz, %L::timestamptz, 'individual', null,
      '19000000-0000-0000-0000-000000000064'
    )$sql$,
    current_setting('test.update_current'),
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 4) + time '14:00') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 4) + time '15:00') at time zone 'Europe/Budapest'
  ),
  'P0001', 'Nincs foglalási jogosultságod ehhez a helyiséghez.',
  'Módosításkor a helyiségjog újraellenőrzött'
);

select throws_ok(
  format(
    $sql$select public.update_booking(
      '20000000-0000-0000-0000-000000000061', %L::timestamptz,
      '11000000-0000-0000-0000-000000000002',
      %L::timestamptz, %L::timestamptz, 'individual', null,
      '19000000-0000-0000-0000-000000000065'
    )$sql$,
    current_setting('test.update_current'),
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 4) + time '14:15') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 4) + time '15:15') at time zone 'Europe/Budapest'
  ),
  'P0001', 'A kezdésnek, befejezésnek és időtartamnak 30 perces rácshoz kell igazodnia.',
  'Módosításkor az időrács újraellenőrzött'
);

select throws_ok(
  format(
    $sql$select public.update_booking(
      '20000000-0000-0000-0000-000000000061', %L::timestamptz,
      '11000000-0000-0000-0000-000000000003',
      %L::timestamptz, %L::timestamptz, 'individual', null,
      '19000000-0000-0000-0000-000000000066'
    )$sql$,
    current_setting('test.update_current'),
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 5) + time '10:30') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 5) + time '11:30') at time zone 'Europe/Budapest'
  ),
  'P0001', 'A helyiség a kiválasztott időpontban már foglalt.',
  'Módosításkor a DB-szintű átfedésvédelem magyar hibát ad'
);

select throws_ok(
  format(
    $sql$select public.update_booking(
      '20000000-0000-0000-0000-000000000064', %L::timestamptz,
      '11000000-0000-0000-0000-000000000002',
      %L::timestamptz, %L::timestamptz, 'individual', null,
      '19000000-0000-0000-0000-000000000067'
    )$sql$,
    current_setting('test.update_cancelled'),
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 6) + time '14:00') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 6) + time '15:00') at time zone 'Europe/Budapest'
  ),
  'P0001', 'Csak aktív foglalás módosítható.',
  'Lemondott foglalás nem módosítható'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000061', true);
select lives_ok(
  format(
    $sql$select public.update_booking(
      '20000000-0000-0000-0000-000000000062', %L::timestamptz,
      '11000000-0000-0000-0000-000000000004',
      %L::timestamptz, %L::timestamptz, 'individual', 'Admin módosítás',
      '19000000-0000-0000-0000-000000000068'
    )$sql$,
    current_setting('test.update_other'),
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 150) + time '15:00') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 150) + time '16:00') at time zone 'Europe/Budapest'
  ),
  'Admin más user foglalását helyiségjog és előrefoglalási limit nélkül módosíthatja'
);
reset role;

select ok(
  (
    select room_id = '11000000-0000-0000-0000-000000000004'
      and note = 'Admin módosítás'
    from public.bookings
    where id = '20000000-0000-0000-0000-000000000062'
  ),
  'Az adminmódosítás eltárolódott'
);

select is(
  (
    select count(*) from public.booking_operation_requests
    where operation = 'update'
  ),
  2::bigint,
  'Csak a két sikeres módosítás hagyott idempotencia-ledger rekordot'
);

select ok(
  (
    select note = 'Módosított megjegyzés'
      and start_at = ((((clock_timestamp() at time zone 'Europe/Budapest')::date + 4) + time '10:00') at time zone 'Europe/Budapest')
    from public.bookings
    where id = '20000000-0000-0000-0000-000000000061'
  ),
  'A sikertelen módosítások nem hagytak részleges állapotot'
);

select * from finish();
rollback;
