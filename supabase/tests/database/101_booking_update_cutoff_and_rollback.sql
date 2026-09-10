begin;

select plan(15);

-- A security/EXECUTE/RLS határt a meglévő DB tesztek külön fedik. Ebben a
-- szemantikai regressziós tesztben a session privilegizált marad, miközben az
-- RPC-k és a trigger actorát továbbra is a request.jwt.claim.sub határozza meg.
select has_function(
  'public',
  'guard_booking_update_cutoff',
  array[]::text[],
  'A DB-szintű foglalásmódosítási cutoff guard létezik'
);

insert into auth.users (id, email, raw_user_meta_data) values
  ('b0000000-0000-0000-0000-000000000001', 'cutoff-admin@example.invalid', '{"first_name":"Cutoff","last_name":"Admin"}'),
  ('b0000000-0000-0000-0000-000000000002', 'cutoff-user@example.invalid', '{"first_name":"Cutoff","last_name":"User"}');

update public.profiles
set role = 'admin'
where id = 'b0000000-0000-0000-0000-000000000001';

update public.profiles
set can_repeat_bookings = true
where id = 'b0000000-0000-0000-0000-000000000002';

insert into public.user_room_permissions(user_id, room_id, can_book, can_repeat) values
  ('b0000000-0000-0000-0000-000000000002', '11000000-0000-0000-0000-000000000002', true, true)
on conflict (user_id, room_id) do update set can_book = true, can_repeat = true;

-- Egyedi foglalás: mesterségesen nagy cutoff mellett a +10 napos booking is
-- a tiltott ablakba kerül. Így a teszt napszaktól független és determinisztikus.
insert into public.bookings (
  id, room_id, user_id, created_by, start_at, end_at, idempotency_key, updated_at, note
) values (
  'b1000000-0000-0000-0000-000000000001',
  '11000000-0000-0000-0000-000000000002',
  'b0000000-0000-0000-0000-000000000002',
  'b0000000-0000-0000-0000-000000000002',
  (((clock_timestamp() at time zone 'Europe/Budapest')::date + 10) + time '09:00') at time zone 'Europe/Budapest',
  (((clock_timestamp() at time zone 'Europe/Budapest')::date + 10) + time '10:00') at time zone 'Europe/Budapest',
  'b2000000-0000-0000-0000-000000000001',
  date_trunc('second', clock_timestamp()),
  'cutoff eredeti'
);

update public.app_settings
set value = '10000'::jsonb
where key = 'cancellation_cutoff_hours';

select set_config('request.jwt.claim.sub', 'b0000000-0000-0000-0000-000000000002', true);
select throws_ok(
  format(
    $sql$select public.update_booking(
      'b1000000-0000-0000-0000-000000000001',
      %L::timestamptz,
      '11000000-0000-0000-0000-000000000002',
      %L::timestamptz,
      %L::timestamptz,
      'individual',
      'cutoff megkerülési kísérlet',
      'b3000000-0000-0000-0000-000000000001'
    )$sql$,
    (select updated_at from public.bookings where id = 'b1000000-0000-0000-0000-000000000001'),
    (select start_at + interval '10 days' from public.bookings where id = 'b1000000-0000-0000-0000-000000000001'),
    (select end_at + interval '10 days' from public.bookings where id = 'b1000000-0000-0000-0000-000000000001')
  ),
  'P0001',
  'A foglalás 10000 órán belül már nem módosítható.',
  'Normál user az eredeti booking cutoffján belül nem tolhatja későbbre a foglalást'
);

select ok(
  (
    select note = 'cutoff eredeti'
      and start_at = ((((clock_timestamp() at time zone 'Europe/Budapest')::date + 10) + time '09:00') at time zone 'Europe/Budapest')
      and end_at = ((((clock_timestamp() at time zone 'Europe/Budapest')::date + 10) + time '10:00') at time zone 'Europe/Budapest')
    from public.bookings
    where id = 'b1000000-0000-0000-0000-000000000001'
  ),
  'Elutasított egyedi módosítás után az eredeti booking változatlan'
);

select is(
  (select count(*) from public.booking_operation_requests
   where actor_user_id = 'b0000000-0000-0000-0000-000000000002'
     and idempotency_key = 'b3000000-0000-0000-0000-000000000001'),
  0::bigint,
  'Elutasított egyedi módosítás nem hagy félkész operation rekordot'
);

select set_config('request.jwt.claim.sub', 'b0000000-0000-0000-0000-000000000001', true);
select lives_ok(
  format(
    $sql$select public.update_booking(
      'b1000000-0000-0000-0000-000000000001',
      %L::timestamptz,
      '11000000-0000-0000-0000-000000000002',
      %L::timestamptz,
      %L::timestamptz,
      'individual',
      'admin cutoff bypass',
      'b3000000-0000-0000-0000-000000000002'
    )$sql$,
    (select updated_at from public.bookings where id = 'b1000000-0000-0000-0000-000000000001'),
    (select start_at + interval '1 hour' from public.bookings where id = 'b1000000-0000-0000-0000-000000000001'),
    (select end_at + interval '1 hour' from public.bookings where id = 'b1000000-0000-0000-0000-000000000001')
  ),
  'Admin a cutoffon belüli bookingot továbbra is módosíthatja'
);

select is(
  (select note from public.bookings where id = 'b1000000-0000-0000-0000-000000000001'),
  'admin cutoff bypass',
  'Admin cutoff bypass módosítása eltárolódott'
);

-- Scope cutoff: a teljes sorozatmódosításnak változatlanul kell maradnia.
select set_config('request.jwt.claim.sub', 'b0000000-0000-0000-0000-000000000002', true);
select lives_ok(
  format(
    $sql$select public.create_booking_series(
      '11000000-0000-0000-0000-000000000002',
      'b0000000-0000-0000-0000-000000000002',
      %L::timestamptz,
      %L::timestamptz,
      'daily', null, 3, '{}'::date[], 'abort_all', 'individual', 'scope cutoff eredeti',
      'b4000000-0000-0000-0000-000000000001'
    )$sql$,
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 20) + time '09:00') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 20) + time '10:00') at time zone 'Europe/Budapest'
  ),
  'Cutoff regressziós tesztsorozat létrejön'
);

select throws_ok(
  format(
    $sql$select public.update_booking_scope(
      %L::uuid, 'series', %L::timestamptz,
      '11000000-0000-0000-0000-000000000002',
      %L::timestamptz, %L::timestamptz,
      'individual', 'scope cutoff módosítás',
      'b5000000-0000-0000-0000-000000000001'
    )$sql$,
    (select id from public.bookings
      where series_id = (select id from public.booking_series where idempotency_key = 'b4000000-0000-0000-0000-000000000001')
      order by start_at limit 1),
    (select updated_at from public.bookings
      where series_id = (select id from public.booking_series where idempotency_key = 'b4000000-0000-0000-0000-000000000001')
      order by start_at limit 1),
    (select start_at + interval '1 hour' from public.bookings
      where series_id = (select id from public.booking_series where idempotency_key = 'b4000000-0000-0000-0000-000000000001')
      order by start_at limit 1),
    (select end_at + interval '1 hour' from public.bookings
      where series_id = (select id from public.booking_series where idempotency_key = 'b4000000-0000-0000-0000-000000000001')
      order by start_at limit 1)
  ),
  'P0001',
  'A foglalás 10000 órán belül már nem módosítható.',
  'Cutoffon belüli normál user teljes scope-update művelete elutasított'
);

select is(
  (select count(*) from public.bookings
   where series_id = (select id from public.booking_series where idempotency_key = 'b4000000-0000-0000-0000-000000000001')
     and note = 'scope cutoff eredeti'
     and (start_at at time zone 'Europe/Budapest')::time = time '09:00'),
  3::bigint,
  'Cutoff hiba után a scope mindhárom bookingja változatlan'
);

select is(
  (select count(*) from public.booking_scope_operations
   where actor_user_id = 'b0000000-0000-0000-0000-000000000002'
     and idempotency_key = 'b5000000-0000-0000-0000-000000000001'),
  0::bigint,
  'Cutoff miatt elutasított scope-update nem hagy félkész operation rekordot'
);

-- Ütközéses rollback: normál 24 órás cutoff mellett a távoli sorozat módosítható
-- lenne, de a második target 10:00-11:00 ütközése az egész műveletet visszagörgeti.
update public.app_settings
set value = '24'::jsonb
where key = 'cancellation_cutoff_hours';

select set_config('request.jwt.claim.sub', 'b0000000-0000-0000-0000-000000000002', true);
select lives_ok(
  format(
    $sql$select public.create_booking_series(
      '11000000-0000-0000-0000-000000000002',
      'b0000000-0000-0000-0000-000000000002',
      %L::timestamptz,
      %L::timestamptz,
      'daily', null, 3, '{}'::date[], 'abort_all', 'individual', 'rollback eredeti',
      'b4000000-0000-0000-0000-000000000002'
    )$sql$,
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 40) + time '09:00') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 40) + time '10:00') at time zone 'Europe/Budapest'
  ),
  'Ütközéses rollback tesztsorozat létrejön'
);

insert into public.bookings (
  id, room_id, user_id, created_by, start_at, end_at, idempotency_key, note
) values (
  'b1000000-0000-0000-0000-000000000099',
  '11000000-0000-0000-0000-000000000002',
  'b0000000-0000-0000-0000-000000000002',
  'b0000000-0000-0000-0000-000000000002',
  (((clock_timestamp() at time zone 'Europe/Budapest')::date + 41) + time '10:00') at time zone 'Europe/Budapest',
  (((clock_timestamp() at time zone 'Europe/Budapest')::date + 41) + time '11:00') at time zone 'Europe/Budapest',
  'b2000000-0000-0000-0000-000000000099',
  'ütköző kontroll'
);

select set_config('request.jwt.claim.sub', 'b0000000-0000-0000-0000-000000000002', true);
select throws_ok(
  format(
    $sql$select public.update_booking_scope(
      %L::uuid, 'series', %L::timestamptz,
      '11000000-0000-0000-0000-000000000002',
      %L::timestamptz, %L::timestamptz,
      'individual', 'rollback módosított',
      'b5000000-0000-0000-0000-000000000002'
    )$sql$,
    (select id from public.bookings
      where series_id = (select id from public.booking_series where idempotency_key = 'b4000000-0000-0000-0000-000000000002')
      order by start_at limit 1),
    (select updated_at from public.bookings
      where series_id = (select id from public.booking_series where idempotency_key = 'b4000000-0000-0000-0000-000000000002')
      order by start_at limit 1),
    (select start_at + interval '1 hour' from public.bookings
      where series_id = (select id from public.booking_series where idempotency_key = 'b4000000-0000-0000-0000-000000000002')
      order by start_at limit 1),
    (select end_at + interval '1 hour' from public.bookings
      where series_id = (select id from public.booking_series where idempotency_key = 'b4000000-0000-0000-0000-000000000002')
      order by start_at limit 1)
  ),
  'P0001',
  'A módosított sorozat egyik időpontja ütközik egy meglévő foglalással.',
  'Egy későbbi target ütközése elutasítja a teljes scope-update műveletet'
);

select is(
  (select count(*) from public.bookings
   where series_id = (select id from public.booking_series where idempotency_key = 'b4000000-0000-0000-0000-000000000002')
     and note = 'rollback eredeti'
     and (start_at at time zone 'Europe/Budapest')::time = time '09:00'),
  3::bigint,
  'Ütközés után a korábban már érinthető targetek is teljesen visszagördültek'
);

select is(
  (select count(*) from public.booking_scope_operations
   where actor_user_id = 'b0000000-0000-0000-0000-000000000002'
     and idempotency_key = 'b5000000-0000-0000-0000-000000000002'),
  0::bigint,
  'Ütközéses rollback nem hagy félkész scope operation rekordot'
);

select is(
  (select count(*) from public.audit_logs
   where correlation_id = 'b5000000-0000-0000-0000-000000000002'),
  0::bigint,
  'Ütközéses rollback nem hagy részleges booking auditot'
);

select * from finish();
rollback;
