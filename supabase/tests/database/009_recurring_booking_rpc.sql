begin;

select plan(48);

select has_function(
  'public', 'create_booking_series',
  array[
    'uuid','uuid','timestamp with time zone','timestamp with time zone',
    'recurrence_frequency','date','integer','date[]','conflict_policy',
    'booking_use_type','text','uuid'
  ],
  'Az ismétlődő foglalási RPC létezik'
);
select ok(
  (select prosecdef and coalesce(proconfig @> array['search_path=""'], false)
   from pg_proc
   where oid = 'public.create_booking_series(uuid,uuid,timestamptz,timestamptz,public.recurrence_frequency,date,integer,date[],public.conflict_policy,public.booking_use_type,text,uuid)'::regprocedure),
  'Az RPC SECURITY DEFINER és üres search_path beállítású'
);
select ok(
  not has_function_privilege('authenticated', 'public.recurring_occurrence_date(date,public.recurrence_frequency,integer)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.booking_series_result(uuid)', 'EXECUTE'),
  'A belső sorozatsegédek közvetlenül nem hívhatók'
);

select is(public.recurring_occurrence_date('2026-01-31', 'daily', 2), date '2026-02-02', 'Napi ismétlődés');
select is(public.recurring_occurrence_date('2026-01-31', 'weekly', 2), date '2026-02-14', 'Heti ismétlődés');
select is(public.recurring_occurrence_date('2026-01-31', 'biweekly', 2), date '2026-02-28', 'Kétheti ismétlődés');
select is(public.recurring_occurrence_date('2026-01-31', 'monthly', 1), date '2026-02-28', 'Havi ismétlődés rövid hónapban hónapvégre igazodik');
select is(public.recurring_occurrence_date('2026-01-31', 'monthly', 2), date '2026-03-31', 'Havi ismétlődés visszatér az eredeti naptári napra');
select is(public.recurring_occurrence_date('2028-01-31', 'monthly', 1), date '2028-02-29', 'Havi ismétlődés szökőévben február 29-re igazodik');

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-000000000111', 'series-admin@example.invalid', '{"first_name":"Sorozat","last_name":"Admin"}'),
  ('00000000-0000-0000-0000-000000000112', 'series-user@example.invalid', '{"first_name":"Sorozat","last_name":"User"}'),
  ('00000000-0000-0000-0000-000000000113', 'series-no-repeat@example.invalid', '{"first_name":"Egyszeri","last_name":"User"}'),
  ('00000000-0000-0000-0000-000000000114', 'series-group@example.invalid', '{"first_name":"Csoportos","last_name":"User"}'),
  ('00000000-0000-0000-0000-000000000115', 'series-inactive-group@example.invalid', '{"first_name":"Inaktív","last_name":"Csoport"}');
update public.profiles set role = 'admin'
where id = '00000000-0000-0000-0000-000000000111';
update public.profiles set can_repeat_bookings = true
where id = '00000000-0000-0000-0000-000000000112';

insert into public.user_room_permissions (user_id, room_id, can_book, can_repeat) values
  ('00000000-0000-0000-0000-000000000112', '11000000-0000-0000-0000-000000000001', true, true),
  ('00000000-0000-0000-0000-000000000112', '11000000-0000-0000-0000-000000000002', true, true),
  ('00000000-0000-0000-0000-000000000112', '11000000-0000-0000-0000-000000000003', true, true),
  ('00000000-0000-0000-0000-000000000112', '11000000-0000-0000-0000-000000000004', true, true),
  ('00000000-0000-0000-0000-000000000112', '11000000-0000-0000-0000-000000000010', true, true),
  ('00000000-0000-0000-0000-000000000112', '11000000-0000-0000-0000-000000000011', true, true),
  ('00000000-0000-0000-0000-000000000113', '11000000-0000-0000-0000-000000000007', true, false);

insert into public.access_groups (id, name, is_active) values
  ('27000000-0000-0000-0000-000000000111', 'Aktív ismétlési csoport', true),
  ('27000000-0000-0000-0000-000000000112', 'Inaktív ismétlési csoport', false);
insert into public.access_group_members (group_id, user_id) values
  ('27000000-0000-0000-0000-000000000111', '00000000-0000-0000-0000-000000000114'),
  ('27000000-0000-0000-0000-000000000112', '00000000-0000-0000-0000-000000000115');
insert into public.access_group_rooms (group_id, room_id, can_book, can_repeat) values
  ('27000000-0000-0000-0000-000000000111', '11000000-0000-0000-0000-000000000008', true, true),
  ('27000000-0000-0000-0000-000000000112', '11000000-0000-0000-0000-000000000009', true, true);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000112', true);
select lives_ok(
  format(
    $sql$select public.create_booking_series(
      '11000000-0000-0000-0000-000000000010',
      '00000000-0000-0000-0000-000000000112',
      %L::timestamptz, %L::timestamptz, 'daily', null, 2, '{}',
      'abort_all', 'individual', 'Múltbeli sorozat',
      '28000000-0000-0000-0000-000000000128'
    )$sql$,
    (((clock_timestamp() at time zone 'Europe/Budapest')::date - 4) + time '15:00') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date - 4) + time '16:00') at time zone 'Europe/Budapest'
  ),
  'Normál user teljesen múltbeli sorozatot is létrehozhat'
);
reset role;
select is(
  (select count(*) from public.bookings
   where series_id = (select id from public.booking_series where idempotency_key = '28000000-0000-0000-0000-000000000128')),
  2::bigint,
  'A múltbeli sorozat mindkét alkalma létrejött'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000112', true);

select lives_ok(
  format(
    $sql$select public.create_booking_series(
      '11000000-0000-0000-0000-000000000002',
      '00000000-0000-0000-0000-000000000112',
      %L::timestamptz, %L::timestamptz, 'daily', null, 3,
      array[%L::date], 'abort_all', 'individual', 'Napi sorozat',
      '28000000-0000-0000-0000-000000000111'
    )$sql$,
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 3) + time '09:00') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 3) + time '10:00') at time zone 'Europe/Budapest',
    (clock_timestamp() at time zone 'Europe/Budapest')::date + 4
  ),
  'Napi sorozat kivételdátummal létrehozható'
);
reset role;
select is((select count(*) from public.bookings where series_id = (
  select id from public.booking_series where idempotency_key = '28000000-0000-0000-0000-000000000111'
)), 2::bigint, 'A három napi alkalomból a két nem kivétel bookingként létrejön');
select is((select count(*) from public.booking_series_occurrences where series_id = (
  select id from public.booking_series where idempotency_key = '28000000-0000-0000-0000-000000000111'
)), 3::bigint, 'Minden generált napi alkalom eredménye dokumentált');
select is((select count(*) from public.booking_series_occurrences where series_id = (
  select id from public.booking_series where idempotency_key = '28000000-0000-0000-0000-000000000111'
) and status = 'excluded'), 1::bigint, 'A kivételdátum kizárt eredményként megmarad');
select is((select count(*) from public.audit_logs where correlation_id = '28000000-0000-0000-0000-000000000111'), 3::bigint, 'Két booking- és egy sorozataudit atomian létrejön');
select is((select count(*) from public.outbox_events where payload ->> 'series_id' = (
  select id::text from public.booking_series where idempotency_key = '28000000-0000-0000-0000-000000000111'
)), 2::bigint, 'Minden létrejött alkalomhoz outbox-esemény készül');

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000112', true);
select lives_ok(
  format(
    $sql$select public.create_booking_series(
      '11000000-0000-0000-0000-000000000002',
      '00000000-0000-0000-0000-000000000112',
      %L::timestamptz, %L::timestamptz, 'daily', null, 3,
      array[%L::date], 'abort_all', 'individual', 'Napi sorozat',
      '28000000-0000-0000-0000-000000000111'
    )$sql$,
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 3) + time '09:00') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 3) + time '10:00') at time zone 'Europe/Budapest',
    (clock_timestamp() at time zone 'Europe/Budapest')::date + 4
  ),
  'Azonos sorozatkérés idempotensen megismételhető'
);
reset role;
select is((select count(*) from public.booking_series where idempotency_key = '28000000-0000-0000-0000-000000000111'), 1::bigint, 'Az idempotens retry nem duplikál sorozatot');

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000112', true);
select throws_ok(
  format(
    $sql$select public.create_booking_series(
      '11000000-0000-0000-0000-000000000002',
      '00000000-0000-0000-0000-000000000112',
      %L::timestamptz, %L::timestamptz, 'daily', null, 3,
      array[%L::date], 'abort_all', 'individual', 'Eltérő payload',
      '28000000-0000-0000-0000-000000000111'
    )$sql$,
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 3) + time '09:00') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 3) + time '10:00') at time zone 'Europe/Budapest',
    (clock_timestamp() at time zone 'Europe/Budapest')::date + 4
  ),
  'P0001', 'Ezt a kérésazonosítót már más sorozatadatokkal használták.',
  'Azonos idempotenciakulcs eltérő payloaddal elutasított'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000112', true);
select lives_ok(
  format(
    $sql$select public.create_booking_series(
      '11000000-0000-0000-0000-000000000003',
      '00000000-0000-0000-0000-000000000112',
      %L::timestamptz, %L::timestamptz, 'weekly', null, 2, '{}',
      'abort_all', 'individual', null, '28000000-0000-0000-0000-000000000112'
    )$sql$,
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 3) + time '11:00') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 3) + time '12:00') at time zone 'Europe/Budapest'
  ),
  'Heti sorozat létrehozható'
);
select lives_ok(
  format(
    $sql$select public.create_booking_series(
      '11000000-0000-0000-0000-000000000004',
      '00000000-0000-0000-0000-000000000112',
      %L::timestamptz, %L::timestamptz, 'biweekly', null, 2, '{}',
      'abort_all', 'individual', null, '28000000-0000-0000-0000-000000000113'
    )$sql$,
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 3) + time '13:00') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 3) + time '14:00') at time zone 'Europe/Budapest'
  ),
  'Kétheti sorozat létrehozható'
);
reset role;
select is((select max(service_date) - min(service_date) from public.booking_series_occurrences
  where series_id = (select id from public.booking_series where idempotency_key = '28000000-0000-0000-0000-000000000112')), 7, 'A heti alkalmak között 7 nap van');
select is((select max(service_date) - min(service_date) from public.booking_series_occurrences
  where series_id = (select id from public.booking_series where idempotency_key = '28000000-0000-0000-0000-000000000113')), 14, 'A kétheti alkalmak között 14 nap van');

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000111', true);
select lives_ok(
  $$select public.create_booking_series(
    '11000000-0000-0000-0000-000000000005',
    '00000000-0000-0000-0000-000000000112',
    '2026-08-31 09:00+02', '2026-08-31 10:00+02', 'monthly', null, 3, '{}',
    'abort_all', 'individual', null, '28000000-0000-0000-0000-000000000114'
  )$$,
  'Admin hónapvégi havi sorozatot hozhat létre'
);
reset role;
select is(
  (select array_agg(service_date order by occurrence_index)
   from public.booking_series_occurrences
   where series_id = (select id from public.booking_series where idempotency_key = '28000000-0000-0000-0000-000000000114')),
  array[date '2026-08-31', date '2026-09-30', date '2026-10-31'],
  'A havi RPC is helyesen kezeli a hónapvégi napokat'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000113', true);
select throws_ok(
  format(
    $sql$select public.create_booking_series(
      '11000000-0000-0000-0000-000000000007',
      '00000000-0000-0000-0000-000000000113',
      %L::timestamptz, %L::timestamptz, 'weekly', null, 2, '{}',
      'abort_all', 'individual', null, gen_random_uuid()
    )$sql$,
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 3) + time '15:00') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 3) + time '16:00') at time zone 'Europe/Budapest'
  ),
  'P0001', 'Nincs ismétlődő foglalási jogosultságod ehhez a helyiséghez.',
  'can_repeat=false mellett normál user nem hozhat létre sorozatot'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000114', true);
select throws_ok(
  format(
    $sql$select public.create_booking_series(
      '11000000-0000-0000-0000-000000000008',
      '00000000-0000-0000-0000-000000000114',
      %L::timestamptz, %L::timestamptz, 'weekly', null, 2, '{}',
      'abort_all', 'individual', null, '28000000-0000-0000-0000-000000000115'
    )$sql$,
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 3) + time '17:00') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 3) + time '18:00') at time zone 'Europe/Budapest'
  ),
  'P0001', 'Nincs ismétlődő foglalási jogosultságod ehhez a helyiséghez.',
  'Aktív csoport sem ad ismétlődési jogot'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000115', true);
select throws_ok(
  format(
    $sql$select public.create_booking_series(
      '11000000-0000-0000-0000-000000000009',
      '00000000-0000-0000-0000-000000000115',
      %L::timestamptz, %L::timestamptz, 'weekly', null, 2, '{}',
      'abort_all', 'individual', null, gen_random_uuid()
    )$sql$,
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 3) + time '17:00') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 3) + time '18:00') at time zone 'Europe/Budapest'
  ),
  'P0001', 'Nincs ismétlődő foglalási jogosultságod ehhez a helyiséghez.',
  'Inaktív csoport nem ad ismétlési jogot'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000112', true);
select throws_ok(
  format(
    $sql$select public.create_booking_series(
      '11000000-0000-0000-0000-000000000001',
      '00000000-0000-0000-0000-000000000112',
      %L::timestamptz, %L::timestamptz, 'daily', null, 2, '{}',
      'abort_all', 'individual', null, gen_random_uuid()
    )$sql$,
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 3) + time '19:00') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 3) + time '20:00') at time zone 'Europe/Budapest'
  ),
  'P0001', 'Nincs ismétlődő foglalási jogosultságod ehhez a helyiséghez.',
  'Normál user nem hozhat létre Tréningterem-sorozatot'
);

select throws_ok(
  format(
    $sql$select public.create_booking_series(
      '11000000-0000-0000-0000-000000000002',
      '00000000-0000-0000-0000-000000000112',
      %L::timestamptz, %L::timestamptz, 'daily', %L::date, 2, '{}',
      'abort_all', 'individual', null, gen_random_uuid()
    )$sql$,
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 3) + time '09:00') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 3) + time '10:00') at time zone 'Europe/Budapest',
    (clock_timestamp() at time zone 'Europe/Budapest')::date + 10
  ),
  'P0001', 'Végdátum vagy ismétlésszám közül pontosan az egyik kötelező.',
  'Végdátum és ismétlésszám egyszerre nem adható meg'
);
select throws_ok(
  format(
    $sql$select public.create_booking_series(
      '11000000-0000-0000-0000-000000000002',
      '00000000-0000-0000-0000-000000000112',
      %L::timestamptz, %L::timestamptz, 'daily', null, null, '{}',
      'abort_all', 'individual', null, gen_random_uuid()
    )$sql$,
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 3) + time '09:00') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 3) + time '10:00') at time zone 'Europe/Budapest'
  ),
  'P0001', 'Végdátum vagy ismétlésszám közül pontosan az egyik kötelező.',
  'Végdátum és ismétlésszám közül legalább az egyik kötelező'
);
select throws_ok(
  format(
    $sql$select public.create_booking_series(
      '11000000-0000-0000-0000-000000000002',
      '00000000-0000-0000-0000-000000000112',
      %L::timestamptz, %L::timestamptz, 'daily', null, 401, '{}',
      'abort_all', 'individual', null, gen_random_uuid()
    )$sql$,
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 3) + time '09:00') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 3) + time '10:00') at time zone 'Europe/Budapest'
  ),
  'P0001', 'Az ismétlésszám 1 és 400 közötti lehet.',
  'A 401 alkalmas sorozat elutasított'
);
select throws_ok(
  format(
    $sql$select public.create_booking_series(
      '11000000-0000-0000-0000-000000000002',
      '00000000-0000-0000-0000-000000000112',
      %L::timestamptz, %L::timestamptz, 'weekly', %L::date, null, '{}',
      'abort_all', 'individual', null, gen_random_uuid()
    )$sql$,
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 3) + time '09:00') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 3) + time '10:00') at time zone 'Europe/Budapest',
    (clock_timestamp() at time zone 'Europe/Budapest')::date + 370
  ),
  'P0001', 'A sorozat végdátuma legfeljebb 366 nappal lehet az első alkalom után.',
  'A 367 napos végdátum elutasított'
);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000111', true);
select lives_ok(
  format(
    $sql$select public.create_booking_series(
      '11000000-0000-0000-0000-000000000004',
      '00000000-0000-0000-0000-000000000112',
      %L::timestamptz, %L::timestamptz, 'weekly', %L::date, null, '{}',
      'abort_all', 'individual', null, '28000000-0000-0000-0000-000000000126'
    )$sql$,
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 3) + time '15:00') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 3) + time '16:00') at time zone 'Europe/Budapest',
    (clock_timestamp() at time zone 'Europe/Budapest')::date + 369
  ),
  'A pontosan 366 napos sorozat megengedett'
);
reset role;

insert into public.bookings (
  room_id, user_id, created_by, start_at, end_at, idempotency_key
) values
  (
    '11000000-0000-0000-0000-000000000011',
    '00000000-0000-0000-0000-000000000112',
    '00000000-0000-0000-0000-000000000112',
    ((((clock_timestamp() at time zone 'Europe/Budapest')::date + 20) + time '09:00') at time zone 'Europe/Budapest'),
    ((((clock_timestamp() at time zone 'Europe/Budapest')::date + 20) + time '10:00') at time zone 'Europe/Budapest'),
    '28000000-0000-0000-0000-000000000120'
  ),
  (
    '11000000-0000-0000-0000-000000000010',
    '00000000-0000-0000-0000-000000000112',
    '00000000-0000-0000-0000-000000000112',
    ((((clock_timestamp() at time zone 'Europe/Budapest')::date + 20) + time '11:00') at time zone 'Europe/Budapest'),
    ((((clock_timestamp() at time zone 'Europe/Budapest')::date + 20) + time '12:00') at time zone 'Europe/Budapest'),
    '28000000-0000-0000-0000-000000000121'
  );

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000112', true);
select throws_ok(
  format(
    $sql$select public.create_booking_series(
      '11000000-0000-0000-0000-000000000011',
      '00000000-0000-0000-0000-000000000112',
      %L::timestamptz, %L::timestamptz, 'daily', null, 2, '{}',
      'abort_all', 'individual', null, '28000000-0000-0000-0000-000000000122'
    )$sql$,
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 20) + time '09:00') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 20) + time '10:00') at time zone 'Europe/Budapest'
  ),
  'P0001', null,
  'abort_all ütközésnél visszagörgeti a teljes sorozatot'
);
reset role;
select is(
  (select count(*) from public.booking_series where idempotency_key = '28000000-0000-0000-0000-000000000122'),
  0::bigint,
  'abort_all után sorozatrekord sem marad'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000112', true);
select lives_ok(
  format(
    $sql$select public.create_booking_series(
      '11000000-0000-0000-0000-000000000010',
      '00000000-0000-0000-0000-000000000112',
      %L::timestamptz, %L::timestamptz, 'daily', null, 2, '{}',
      'create_available', 'individual', null, '28000000-0000-0000-0000-000000000123'
    )$sql$,
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 20) + time '11:00') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 20) + time '12:00') at time zone 'Europe/Budapest'
  ),
  'create_available létrehozza a szabad alkalmat'
);
reset role;
select is(
  (select count(*) from public.booking_series_occurrences
   where series_id = (select id from public.booking_series where idempotency_key = '28000000-0000-0000-0000-000000000123')
     and status = 'created'),
  1::bigint,
  'create_available pontosan egy szabad alkalmat hoz létre'
);
select is(
  (select count(*) from public.booking_series_occurrences
   where series_id = (select id from public.booking_series where idempotency_key = '28000000-0000-0000-0000-000000000123')
     and status = 'unavailable'
     and reason = 'A helyiség a kiválasztott időpontban már foglalt.'),
  1::bigint,
  'create_available az ütköző alkalmat pontos okkal dokumentálja'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000111', true);
select lives_ok(
  $$select public.create_booking_series(
    '11000000-0000-0000-0000-000000000006',
    '00000000-0000-0000-0000-000000000112',
    '2026-10-18 09:00+02', '2026-10-18 10:00+02', 'weekly', null, 3, '{}',
    'abort_all', 'individual', null, '28000000-0000-0000-0000-000000000124'
  )$$,
  'A DST-váltást átmetsző heti sorozat létrehozható'
);
reset role;
select is(
  (select array_agg((start_at at time zone 'Europe/Budapest')::time order by occurrence_index)
   from public.booking_series_occurrences
   where series_id = (select id from public.booking_series where idempotency_key = '28000000-0000-0000-0000-000000000124')),
  array[time '09:00', time '09:00', time '09:00'],
  'DST-váltás után is azonos budapesti falióra marad'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000111', true);
select lives_ok(
  $$select public.create_booking_series(
    '11000000-0000-0000-0000-000000000007',
    '00000000-0000-0000-0000-000000000112',
    '2027-03-21 09:00+01', '2027-03-21 10:00+01', 'weekly', null, 3, '{}',
    'abort_all', 'individual', null, '28000000-0000-0000-0000-000000000127'
  )$$,
  'A tavaszi DST-váltást átmetsző heti sorozat létrehozható'
);
reset role;
select is(
  (select array_agg((start_at at time zone 'Europe/Budapest')::time order by occurrence_index)
   from public.booking_series_occurrences
   where series_id = (select id from public.booking_series where idempotency_key = '28000000-0000-0000-0000-000000000127')),
  array[time '09:00', time '09:00', time '09:00'],
  'A tavaszi DST-váltás után is azonos budapesti falióra marad'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000111', true);
select lives_ok(
  format(
    $sql$select public.create_booking_series(
      '11000000-0000-0000-0000-000000000001',
      '00000000-0000-0000-0000-000000000112',
      %L::timestamptz, %L::timestamptz, 'daily', null, 2, '{}',
      'abort_all', 'individual', null, '28000000-0000-0000-0000-000000000125'
    )$sql$,
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 3) + time '19:00') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 3) + time '20:00') at time zone 'Europe/Budapest'
  ),
  'Admin létrehozhat ismétlődő Tréningterem-foglalást'
);
reset role;
select is(
  (select count(*) from public.bookings
   where series_id = (select id from public.booking_series where idempotency_key = '28000000-0000-0000-0000-000000000125')),
  2::bigint,
  'Az admin Tréningterem-sorozatának minden alkalma létrejön'
);

select throws_ok(
  $$delete from public.booking_series where idempotency_key = '28000000-0000-0000-0000-000000000111'$$,
  '42501', null,
  'A sorozat fizikailag nem törölhető'
);
select throws_ok(
  $$update public.booking_series_occurrences set reason = 'tiltott'
    where series_id = (select id from public.booking_series where idempotency_key = '28000000-0000-0000-0000-000000000111')
      and status = 'excluded'$$,
  '42501', 'Ez az archivált rekord nem módosítható és nem törölhető.',
  'Az alkalomeredmény append-only'
);

select * from finish();
rollback;
