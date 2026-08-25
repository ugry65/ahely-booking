begin;

select plan(9);

insert into auth.users (id, email, raw_user_meta_data) values
  ('88000000-0000-0000-0000-000000000001', 'atomic-rate-admin@example.invalid', '{"first_name":"Atomic","last_name":"Admin"}'),
  ('88000000-0000-0000-0000-000000000002', 'atomic-rate-user@example.invalid', '{"first_name":"Atomic","last_name":"User"}');
update public.profiles set role = 'admin' where id = '88000000-0000-0000-0000-000000000001';
update public.profiles set can_repeat_bookings = true where id = '88000000-0000-0000-0000-000000000002';
insert into public.user_room_permissions (user_id, room_id, can_book, can_repeat)
values ('88000000-0000-0000-0000-000000000002', '11000000-0000-0000-0000-000000000001', true, true)
on conflict (user_id, room_id) do update set can_book = true, can_repeat = true;

set local role authenticated;
select set_config('request.jwt.claim.sub', '88000000-0000-0000-0000-000000000002', true);
select throws_ok(
  format(
    $sql$select public.admin_create_booking_with_group_rate(
      '11000000-0000-0000-0000-000000000001', '88000000-0000-0000-0000-000000000002',
      %L::timestamptz, %L::timestamptz, 'group', null,
      '88000000-0000-0000-0000-000000000101', 'Nem admin', 7500
    )$sql$,
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 3) + time '08:00') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 3) + time '09:00') at time zone 'Europe/Budapest'
  ),
  '42501', 'Ehhez a művelethez aktív adminisztrátori jogosultság szükséges.',
  'Normál user nem hívhatja az atomi admin foglalási RPC-t'
);

select set_config('request.jwt.claim.sub', '88000000-0000-0000-0000-000000000001', true);
select lives_ok(
  format(
    $sql$select public.admin_create_booking_with_group_rate(
      '11000000-0000-0000-0000-000000000001', '88000000-0000-0000-0000-000000000002',
      %L::timestamptz, %L::timestamptz, 'group', 'Atomi egyedi díj',
      '88000000-0000-0000-0000-000000000102', 'Atomi csoport', 7500
    )$sql$,
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 3) + time '09:00') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 3) + time '10:00') at time zone 'Europe/Budapest'
  ),
  'Admin egy tranzakcióban hozhat létre 7 500 Ft-os csoportos foglalást'
);
reset role;

select is(
  (select group_hourly_rate_huf from public.bookings where idempotency_key = '88000000-0000-0000-0000-000000000102'),
  7500::bigint,
  'Az atomi foglaláson azonnal a kért 7 500 Ft-os díj marad'
);
select is(
  (select count(*) from public.audit_logs where action = 'booking.group_rate_changed' and entity_id = (select id::text from public.bookings where idempotency_key = '88000000-0000-0000-0000-000000000102')),
  1::bigint,
  'Az atomi egyedi díj auditált'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '88000000-0000-0000-0000-000000000001', true);
select throws_ok(
  format(
    $sql$select public.admin_create_booking_with_group_rate(
      '11000000-0000-0000-0000-000000000001', '88000000-0000-0000-0000-000000000002',
      %L::timestamptz, %L::timestamptz, 'individual', null,
      '88000000-0000-0000-0000-000000000103', 'Rollback teszt', 7500
    )$sql$,
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 3) + time '10:00') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 3) + time '11:00') at time zone 'Europe/Budapest'
  ),
  'P0001', 'Egyedi csoportos óradíj csak a Tréningterem csoportos foglalásán állítható.',
  'Ha a díjrögzítés hibás, az atomi foglalási RPC hibával leáll'
);
reset role;
select is(
  (select count(*) from public.bookings where idempotency_key = '88000000-0000-0000-0000-000000000103'),
  0::bigint,
  'Díjrögzítési hiba után nem marad félkész egyedi foglalás'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '88000000-0000-0000-0000-000000000001', true);
select lives_ok(
  format(
    $sql$select public.admin_create_booking_series_with_group_rate(
      '11000000-0000-0000-0000-000000000001', '88000000-0000-0000-0000-000000000002',
      %L::timestamptz, %L::timestamptz, 'daily', null, 2, '{}', 'abort_all', 'group',
      'Atomi sorozat', '88000000-0000-0000-0000-000000000104', 'Atomi sorozat cím', 8000
    )$sql$,
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 5) + time '09:00') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 5) + time '10:00') at time zone 'Europe/Budapest'
  ),
  'Admin egy tranzakcióban hozhat létre 8 000 Ft-os csoportos sorozatot'
);
reset role;
select is(
  (select count(*) from public.bookings b join public.booking_series s on s.id = b.series_id where s.idempotency_key = '88000000-0000-0000-0000-000000000104' and b.group_hourly_rate_huf = 8000),
  2::bigint,
  'Az atomi sorozat minden létrejött foglalása 8 000 Ft-os díjat kap'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '88000000-0000-0000-0000-000000000001', true);
select throws_ok(
  format(
    $sql$select public.admin_create_booking_series_with_group_rate(
      '11000000-0000-0000-0000-000000000001', '88000000-0000-0000-0000-000000000002',
      %L::timestamptz, %L::timestamptz, 'daily', null, 2, '{}', 'abort_all', 'individual',
      'Rollback sorozat', '88000000-0000-0000-0000-000000000105', 'Rollback sorozat cím', 8000
    )$sql$,
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 7) + time '09:00') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 7) + time '10:00') at time zone 'Europe/Budapest'
  ),
  'P0001', 'Egyedi csoportos óradíj csak teljes egészében Tréningterem csoportos sorozatra állítható.',
  'Ha a sorozat díjrögzítése hibás, az atomi sorozat RPC hibával leáll'
);
reset role;
select is(
  (select count(*) from public.booking_series where idempotency_key = '88000000-0000-0000-0000-000000000105'),
  0::bigint,
  'Díjrögzítési hiba után nem marad félkész foglalási sorozat'
);

select * from finish();
rollback;
