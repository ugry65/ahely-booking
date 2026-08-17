begin;

select plan(33);

select has_function(
  'public',
  'create_booking',
  array['uuid', 'uuid', 'timestamp with time zone', 'timestamp with time zone', 'booking_use_type', 'text', 'uuid'],
  'A tranzakciós egyedi foglalási RPC létezik'
);

select ok(
  (
    select prosecdef
    from pg_proc
    where oid = 'public.create_booking(uuid,uuid,timestamptz,timestamptz,public.booking_use_type,text,uuid)'::regprocedure
  ),
  'A foglalási RPC SECURITY DEFINER függvény'
);

select ok(
  exists (
    select 1
    from pg_proc procedure
    cross join unnest(procedure.proconfig) as config(setting)
    where procedure.oid = 'public.create_booking(uuid,uuid,timestamptz,timestamptz,public.booking_use_type,text,uuid)'::regprocedure
      and config.setting = 'search_path=""'
  ),
  'A foglalási RPC üres, rögzített search_path beállítást használ'
);

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-000000000021', 'booking-admin@example.invalid', '{"first_name":"Booking","last_name":"Admin"}'),
  ('00000000-0000-0000-0000-000000000022', 'booking-user@example.invalid', '{"first_name":"Booking","last_name":"User"}'),
  ('00000000-0000-0000-0000-000000000023', 'booking-other@example.invalid', '{"first_name":"Booking","last_name":"Other"}');

update public.profiles set role = 'admin'
where id = '00000000-0000-0000-0000-000000000021';

insert into public.user_room_permissions (user_id, room_id, can_book) values
  ('00000000-0000-0000-0000-000000000022', '11000000-0000-0000-0000-000000000002', true),
  ('00000000-0000-0000-0000-000000000022', '11000000-0000-0000-0000-000000000001', true);

insert into public.access_groups (id, name) values
  ('13000000-0000-0000-0000-000000000031', 'RPC tesztcsoport');
insert into public.access_group_members (group_id, user_id) values
  ('13000000-0000-0000-0000-000000000031', '00000000-0000-0000-0000-000000000022');
insert into public.access_group_rooms (group_id, room_id, can_book) values
  ('13000000-0000-0000-0000-000000000031', '11000000-0000-0000-0000-000000000003', true);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000022', true);

select lives_ok(
  format(
    $sql$select public.create_booking(
      '11000000-0000-0000-0000-000000000002',
      '00000000-0000-0000-0000-000000000022',
      %L::timestamptz, %L::timestamptz, 'individual', 'Első foglalás',
      '14000000-0000-0000-0000-000000000001'
    )$sql$,
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 2) + time '09:00') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 2) + time '10:00') at time zone 'Europe/Budapest'
  ),
  'Normál user közvetlen jogosultsággal foglalhat'
);

reset role;
select is(
  (select count(*) from public.bookings where idempotency_key = '14000000-0000-0000-0000-000000000001'),
  1::bigint,
  'A foglalás pontosan egyszer létrejött'
);
select is(
  (select count(*) from public.audit_logs where correlation_id = '14000000-0000-0000-0000-000000000001'),
  1::bigint,
  'A foglalással egy tranzakcióban auditrekord jött létre'
);
select is(
  (
    select count(*)
    from public.outbox_events
    where aggregate_id = (
      select id::text from public.bookings
      where idempotency_key = '14000000-0000-0000-0000-000000000001'
    )
  ),
  1::bigint,
  'A foglalással egy tranzakcióban e-mail outbox esemény jött létre'
);
select set_config(
  'test.booking_id',
  (select id::text from public.bookings where idempotency_key = '14000000-0000-0000-0000-000000000001'),
  true
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000022', true);
select is(
  public.create_booking(
    '11000000-0000-0000-0000-000000000002',
    '00000000-0000-0000-0000-000000000022',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 2) + time '09:00') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 2) + time '10:00') at time zone 'Europe/Budapest',
    'individual', 'Első foglalás',
    '14000000-0000-0000-0000-000000000001'
  ),
  current_setting('test.booking_id')::uuid,
  'Azonos idempotenciakulcs ugyanazt a foglalást adja vissza'
);
reset role;

select is(
  (select count(*) from public.audit_logs where correlation_id = '14000000-0000-0000-0000-000000000001'),
  1::bigint,
  'Idempotens ismétlés nem duplikálja a mellékhatásokat'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000022', true);
select throws_ok(
  format(
    $sql$select public.create_booking(
      '11000000-0000-0000-0000-000000000002',
      '00000000-0000-0000-0000-000000000022',
      %L::timestamptz, %L::timestamptz, 'individual', 'Más adat',
      '14000000-0000-0000-0000-000000000001'
    )$sql$,
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 2) + time '10:00') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 2) + time '11:00') at time zone 'Europe/Budapest'
  ),
  'P0001',
  'Ezt a kérésazonosítót már más foglalási adatokkal használták.',
  'Az idempotenciakulcs más adatokkal nem használható újra'
);

select throws_ok(
  format(
    $sql$select public.create_booking(
      '11000000-0000-0000-0000-000000000002',
      '00000000-0000-0000-0000-000000000022',
      %L::timestamptz, %L::timestamptz, 'individual', null,
      '14000000-0000-0000-0000-000000000019'
    )$sql$,
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 2) + time '09:30') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 2) + time '10:30') at time zone 'Europe/Budapest'
  ),
  'P0001',
  'A helyiség a kiválasztott időpontban már foglalt.',
  'A GiST-ütközés pontos, magyar üzleti hibaüzenetet ad'
);

select lives_ok(
  format(
    $sql$select public.create_booking(
      '11000000-0000-0000-0000-000000000003',
      '00000000-0000-0000-0000-000000000022',
      %L::timestamptz, %L::timestamptz, 'individual', null,
      '14000000-0000-0000-0000-000000000002'
    )$sql$,
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 2) + time '10:00') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 2) + time '11:00') at time zone 'Europe/Budapest'
  ),
  'Aktív csoportból örökölt helyiségjoggal is lehet foglalni'
);

select throws_ok(
  format(
    $sql$select public.create_booking(
      '11000000-0000-0000-0000-000000000004',
      '00000000-0000-0000-0000-000000000022',
      %L::timestamptz, %L::timestamptz, 'individual', null,
      '14000000-0000-0000-0000-000000000011'
    )$sql$,
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 2) + time '11:00') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 2) + time '12:00') at time zone 'Europe/Budapest'
  ),
  'P0001',
  'Nincs foglalási jogosultságod ehhez a helyiséghez.',
  'Jogosulatlan helyiségfoglalás elutasított'
);

select throws_ok(
  format(
    $sql$select public.create_booking(
      '11000000-0000-0000-0000-000000000002',
      '00000000-0000-0000-0000-000000000023',
      %L::timestamptz, %L::timestamptz, 'individual', null,
      '14000000-0000-0000-0000-000000000012'
    )$sql$,
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 2) + time '12:00') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 2) + time '13:00') at time zone 'Europe/Budapest'
  ),
  'P0001',
  'Más felhasználó nevében csak admin foglalhat.',
  'Normál user más nevében nem foglalhat'
);

select throws_ok(
  format(
    $sql$select public.create_booking(
      '11000000-0000-0000-0000-000000000002',
      '00000000-0000-0000-0000-000000000022',
      %L::timestamptz, %L::timestamptz, 'individual', null,
      '14000000-0000-0000-0000-000000000013'
    )$sql$,
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 2) + time '08:15') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 2) + time '09:15') at time zone 'Europe/Budapest'
  ),
  'P0001',
  'A kezdésnek, befejezésnek és időtartamnak 30 perces rácshoz kell igazodnia.',
  'A hibás időrács magyar hibával elutasított'
);

select throws_ok(
  format(
    $sql$select public.create_booking(
      '11000000-0000-0000-0000-000000000002',
      '00000000-0000-0000-0000-000000000022',
      %L::timestamptz, %L::timestamptz, 'individual', null,
      '14000000-0000-0000-0000-000000000014'
    )$sql$,
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 2) + time '08:00') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 2) + time '08:30') at time zone 'Europe/Budapest'
  ),
  'P0001',
  'A foglalás legalább 60 perces legyen.',
  'A minimum időnél rövidebb foglalás elutasított'
);

select throws_ok(
  format(
    $sql$select public.create_booking(
      '11000000-0000-0000-0000-000000000002',
      '00000000-0000-0000-0000-000000000022',
      %L::timestamptz, %L::timestamptz, 'individual', null,
      '14000000-0000-0000-0000-000000000015'
    )$sql$,
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 91) + time '09:00') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 91) + time '10:00') at time zone 'Europe/Budapest'
  ),
  'P0001',
  'Legfeljebb 90 napra előre foglalhatsz.',
  'A default 90 napos előrefoglalási limit érvényes'
);

select throws_ok(
  format(
    $sql$select public.create_booking(
      '11000000-0000-0000-0000-000000000001',
      '00000000-0000-0000-0000-000000000022',
      %L::timestamptz, %L::timestamptz, 'individual', null,
      '14000000-0000-0000-0000-000000000016'
    )$sql$,
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 11) + time '09:00') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 11) + time '10:00') at time zone 'Europe/Budapest'
  ),
  'P0001',
  'A Tréningterem legfeljebb 10 napra előre foglalható.',
  'A Tréningterem 10 napos normál user limitje érvényes'
);

select throws_ok(
  format(
    $sql$select public.create_booking(
      '11000000-0000-0000-0000-000000000002',
      '00000000-0000-0000-0000-000000000022',
      %L::timestamptz, %L::timestamptz, 'group', null,
      '14000000-0000-0000-0000-000000000017'
    )$sql$,
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 4) + time '10:00') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 4) + time '11:00') at time zone 'Europe/Budapest'
  ),
  'P0001',
  'Csoportos használattípus csak a Tréningteremnél választható.',
  'Normál helyiséghez csoportos használattípus nem adható'
);

select lives_ok(
  format(
    $sql$select public.create_booking(
      '11000000-0000-0000-0000-000000000001',
      '00000000-0000-0000-0000-000000000022',
      %L::timestamptz, %L::timestamptz, 'group', null,
      '14000000-0000-0000-0000-000000000005'
    )$sql$,
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 5) + time '13:00') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 5) + time '14:00') at time zone 'Europe/Budapest'
  ),
  'Tréningterem egyéni vagy csoportos használattípussal foglalható'
);

reset role;
update public.profiles
set advance_booking_days_override = 120
where id = '00000000-0000-0000-0000-000000000022';

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000022', true);
select lives_ok(
  format(
    $sql$select public.create_booking(
      '11000000-0000-0000-0000-000000000002',
      '00000000-0000-0000-0000-000000000022',
      %L::timestamptz, %L::timestamptz, 'individual', null,
      '14000000-0000-0000-0000-000000000004'
    )$sql$,
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 100) + time '12:00') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 100) + time '13:00') at time zone 'Europe/Budapest'
  ),
  'Az egyedi előrefoglalási override felülírja a default limitet'
);
reset role;

update public.profiles set is_active = false
where id = '00000000-0000-0000-0000-000000000022';
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000022', true);
select throws_ok(
  format(
    $sql$select public.create_booking(
      '11000000-0000-0000-0000-000000000002',
      '00000000-0000-0000-0000-000000000022',
      %L::timestamptz, %L::timestamptz, 'individual', null,
      '14000000-0000-0000-0000-000000000021'
    )$sql$,
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 6) + time '08:00') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 6) + time '09:00') at time zone 'Europe/Budapest'
  ),
  'P0001',
  'A felhasználói fiók nem aktív.',
  'Inaktív actor nem foglalhat'
);
reset role;
update public.profiles set is_active = true
where id = '00000000-0000-0000-0000-000000000022';

update public.profiles set is_active = false
where id = '00000000-0000-0000-0000-000000000023';
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000021', true);
select throws_ok(
  format(
    $sql$select public.create_booking(
      '11000000-0000-0000-0000-000000000004',
      '00000000-0000-0000-0000-000000000023',
      %L::timestamptz, %L::timestamptz, 'individual', null,
      '14000000-0000-0000-0000-000000000022'
    )$sql$,
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 6) + time '09:00') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 6) + time '10:00') at time zone 'Europe/Budapest'
  ),
  'P0001',
  'A foglalás célfelhasználója nem aktív.',
  'Admin sem foglalhat inaktív cél-user nevében'
);
reset role;
update public.profiles set is_active = true
where id = '00000000-0000-0000-0000-000000000023';

update public.rooms set is_active = false
where id = '11000000-0000-0000-0000-000000000006';
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000022', true);
select throws_ok(
  format(
    $sql$select public.create_booking(
      '11000000-0000-0000-0000-000000000006',
      '00000000-0000-0000-0000-000000000022',
      %L::timestamptz, %L::timestamptz, 'individual', null,
      '14000000-0000-0000-0000-000000000023'
    )$sql$,
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 6) + time '10:00') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 6) + time '11:00') at time zone 'Europe/Budapest'
  ),
  'P0001',
  'A kiválasztott helyiség nem foglalható.',
  'Inaktív helyiség nem foglalható'
);
reset role;
update public.rooms set is_active = true
where id = '11000000-0000-0000-0000-000000000006';

insert into public.user_room_permissions (user_id, room_id, can_book) values
  ('00000000-0000-0000-0000-000000000022', '11000000-0000-0000-0000-000000000007', false);
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000022', true);
select throws_ok(
  format(
    $sql$select public.create_booking(
      '11000000-0000-0000-0000-000000000007',
      '00000000-0000-0000-0000-000000000022',
      %L::timestamptz, %L::timestamptz, 'individual', null,
      '14000000-0000-0000-0000-000000000024'
    )$sql$,
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 6) + time '11:00') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 6) + time '12:00') at time zone 'Europe/Budapest'
  ),
  'P0001',
  'Nincs foglalási jogosultságod ehhez a helyiséghez.',
  'A közvetlen can_book=false nem ad foglalási jogot'
);
reset role;

insert into public.access_groups (id, name, is_active) values
  ('13000000-0000-0000-0000-000000000032', 'RPC tiltott szobacsoport', true),
  ('13000000-0000-0000-0000-000000000033', 'RPC inaktív csoport', false);
insert into public.access_group_members (group_id, user_id) values
  ('13000000-0000-0000-0000-000000000032', '00000000-0000-0000-0000-000000000022'),
  ('13000000-0000-0000-0000-000000000033', '00000000-0000-0000-0000-000000000022');
insert into public.access_group_rooms (group_id, room_id, can_book) values
  ('13000000-0000-0000-0000-000000000032', '11000000-0000-0000-0000-000000000008', false),
  ('13000000-0000-0000-0000-000000000033', '11000000-0000-0000-0000-000000000009', true);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000022', true);
select throws_ok(
  format(
    $sql$select public.create_booking(
      '11000000-0000-0000-0000-000000000008',
      '00000000-0000-0000-0000-000000000022',
      %L::timestamptz, %L::timestamptz, 'individual', null,
      '14000000-0000-0000-0000-000000000025'
    )$sql$,
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 6) + time '12:00') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 6) + time '13:00') at time zone 'Europe/Budapest'
  ),
  'P0001',
  'Nincs foglalási jogosultságod ehhez a helyiséghez.',
  'A csoportos can_book=false nem ad foglalási jogot'
);

select throws_ok(
  format(
    $sql$select public.create_booking(
      '11000000-0000-0000-0000-000000000009',
      '00000000-0000-0000-0000-000000000022',
      %L::timestamptz, %L::timestamptz, 'individual', null,
      '14000000-0000-0000-0000-000000000026'
    )$sql$,
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 6) + time '13:00') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 6) + time '14:00') at time zone 'Europe/Budapest'
  ),
  'P0001',
  'Nincs foglalási jogosultságod ehhez a helyiséghez.',
  'Az inaktív csoport can_book=true mellett sem ad foglalási jogot'
);
reset role;

update public.app_settings set value = '15'::jsonb where key = 'slot_minutes';
update public.app_settings set value = '45'::jsonb where key = 'minimum_booking_minutes';
select lives_ok(
  format(
    $sql$insert into public.bookings (
      room_id, user_id, created_by, start_at, end_at, idempotency_key
    ) values (
      '11000000-0000-0000-0000-000000000010',
      '00000000-0000-0000-0000-000000000022',
      '00000000-0000-0000-0000-000000000021',
      %L::timestamptz, %L::timestamptz,
      '14000000-0000-0000-0000-000000000027'
    )$sql$,
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 30) + time '08:15') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 30) + time '09:00') at time zone 'Europe/Budapest'
  ),
  'A DB-kényszer a központilag módosított 15/45 perces szabályt érvényesíti'
);
update public.app_settings set value = '30'::jsonb where key = 'slot_minutes';
update public.app_settings set value = '60'::jsonb where key = 'minimum_booking_minutes';

insert into public.calendar_exceptions (service_date, is_closed, reason, created_by) values (
  (clock_timestamp() at time zone 'Europe/Budapest')::date + 3,
  true,
  'RPC teszt zárva tartás',
  '00000000-0000-0000-0000-000000000021'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000022', true);
select throws_ok(
  format(
    $sql$select public.create_booking(
      '11000000-0000-0000-0000-000000000002',
      '00000000-0000-0000-0000-000000000022',
      %L::timestamptz, %L::timestamptz, 'individual', null,
      '14000000-0000-0000-0000-000000000018'
    )$sql$,
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 3) + time '14:00') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 3) + time '15:00') at time zone 'Europe/Budapest'
  ),
  'P0001',
  'A kiválasztott napon az A-Hely zárva tart.',
  'A kivételdátum szerinti zárva tartás felülírja a heti nyitvatartást'
);
reset role;

select is(
  (select count(*) from public.audit_logs where correlation_id = '14000000-0000-0000-0000-000000000018'),
  0::bigint,
  'Sikertelen foglalás után nincs félkész auditrekord'
);
select is(
  (select count(*) from public.outbox_events where payload ->> 'booking_id' is null),
  0::bigint,
  'Az RPC minden outbox eseménye teljes booking payloadot tartalmaz'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000021', true);
select lives_ok(
  format(
    $sql$select public.create_booking(
      '11000000-0000-0000-0000-000000000004',
      '00000000-0000-0000-0000-000000000023',
      %L::timestamptz, %L::timestamptz, 'individual', 'Admin foglalás',
      '14000000-0000-0000-0000-000000000003'
    )$sql$,
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 200) + time '11:00') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 200) + time '12:00') at time zone 'Europe/Budapest'
  ),
  'Admin más aktív user nevében, helyiségjog és előrefoglalási limit nélkül foglalhat'
);
reset role;

select is(
  (
    select count(*)
    from public.bookings booking
    join public.audit_logs audit on audit.entity_id = booking.id::text and audit.action = 'booking.created'
    join public.outbox_events outbox on outbox.aggregate_id = booking.id::text and outbox.event_type = 'booking.created'
    where booking.idempotency_key in (
      '14000000-0000-0000-0000-000000000001',
      '14000000-0000-0000-0000-000000000002',
      '14000000-0000-0000-0000-000000000003',
      '14000000-0000-0000-0000-000000000004',
      '14000000-0000-0000-0000-000000000005'
    )
  ),
  5::bigint,
  'Minden sikeres foglalásnak pontosan egy audit- és outboxrekordja van'
);

select * from finish();
rollback;
