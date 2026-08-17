begin;

select plan(27);

select has_function('public', 'list_calendar_bookings', array['timestamp with time zone','timestamp with time zone'], 'A biztonságos naptár-read RPC létezik');
select has_function('public', 'admin_set_other_booker_names_visible', array['uuid','boolean','uuid'], 'A névláthatóság admin RPC létezik');
select ok(
  (select prosecdef and coalesce(proconfig @> array['search_path=""'], false)
   from pg_proc where oid = 'public.list_calendar_bookings(timestamptz,timestamptz)'::regprocedure),
  'A naptár-read RPC SECURITY DEFINER és üres search_path beállítású'
);
select ok(
  (select prosecdef and coalesce(proconfig @> array['search_path=""'], false)
   from pg_proc where oid = 'public.admin_set_other_booker_names_visible(uuid,boolean,uuid)'::regprocedure),
  'Az admin RPC SECURITY DEFINER és üres search_path beállítású'
);
select is(
  (
    select array_agg(argument_name order by ordinal_position)
    from pg_proc procedure
    cross join unnest(procedure.proargnames)
      with ordinality arguments(argument_name, ordinal_position)
    where procedure.oid = 'public.list_calendar_bookings(timestamptz,timestamptz)'::regprocedure
      and ordinal_position > procedure.pronargs
  ),
  array['booking_id','room_id','room_name','start_at','end_at','use_type','is_own','booker_display_name']::text[],
  'A read model kimenete nem tartalmaz user UUID-t, e-mailt vagy foglalási megjegyzést'
);

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-000000000091', 'visibility-admin@example.invalid', '{"first_name":"Látó","last_name":"Admin"}'),
  ('00000000-0000-0000-0000-000000000092', 'visibility-viewer@example.invalid', '{"first_name":"Naptár","last_name":"Néző"}'),
  ('00000000-0000-0000-0000-000000000093', 'visibility-booker@example.invalid', '{"first_name":"Béla","last_name":"Foglaló"}'),
  ('00000000-0000-0000-0000-000000000094', 'visibility-inactive@example.invalid', '{"first_name":"Inaktív","last_name":"Néző"}');
update public.profiles set role = 'admin' where id = '00000000-0000-0000-0000-000000000091';
update public.profiles set is_active = false where id = '00000000-0000-0000-0000-000000000094';

insert into public.user_room_permissions (user_id, room_id, can_book) values
  ('00000000-0000-0000-0000-000000000092', '11000000-0000-0000-0000-000000000009', true),
  ('00000000-0000-0000-0000-000000000092', '11000000-0000-0000-0000-000000000011', true),
  ('00000000-0000-0000-0000-000000000094', '11000000-0000-0000-0000-000000000009', true);

insert into public.access_groups (id, name) values
  ('25000000-0000-0000-0000-000000000091', 'Naptár csoportos jog teszt');
insert into public.access_group_members (group_id, user_id) values
  ('25000000-0000-0000-0000-000000000091', '00000000-0000-0000-0000-000000000092');
insert into public.access_group_rooms (group_id, room_id, can_book) values
  ('25000000-0000-0000-0000-000000000091', '11000000-0000-0000-0000-000000000010', true);
update public.rooms set is_active = false where id = '11000000-0000-0000-0000-000000000011';

insert into public.bookings (id, room_id, user_id, created_by, start_at, end_at, idempotency_key) values
  ('24000000-0000-0000-0000-000000000091', '11000000-0000-0000-0000-000000000009',
   '00000000-0000-0000-0000-000000000093', '00000000-0000-0000-0000-000000000093',
   '2026-09-10 09:00:00+02', '2026-09-10 10:00:00+02', '24000000-0000-0000-0000-000000000001'),
  ('24000000-0000-0000-0000-000000000092', '11000000-0000-0000-0000-000000000009',
   '00000000-0000-0000-0000-000000000092', '00000000-0000-0000-0000-000000000092',
   '2026-09-10 10:00:00+02', '2026-09-10 11:00:00+02', '24000000-0000-0000-0000-000000000002'),
  ('24000000-0000-0000-0000-000000000093', '11000000-0000-0000-0000-000000000010',
   '00000000-0000-0000-0000-000000000093', '00000000-0000-0000-0000-000000000093',
   '2026-09-10 11:00:00+02', '2026-09-10 12:00:00+02', '24000000-0000-0000-0000-000000000003'),
  ('24000000-0000-0000-0000-000000000094', '11000000-0000-0000-0000-000000000011',
   '00000000-0000-0000-0000-000000000093', '00000000-0000-0000-0000-000000000093',
   '2026-09-10 12:00:00+02', '2026-09-10 13:00:00+02', '24000000-0000-0000-0000-000000000004'),
  ('24000000-0000-0000-0000-000000000095', '11000000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-000000000093', '00000000-0000-0000-0000-000000000093',
   '2026-09-10 13:00:00+02', '2026-09-10 14:00:00+02', '24000000-0000-0000-0000-000000000005');

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000092', true);
select is(
  (select count(*) from public.list_calendar_bookings('2026-09-10 00:00+02','2026-09-11 00:00+02')),
  3::bigint, 'A user csak az engedélyezett aktív helyiségek foglalásait látja'
);
select is(
  (select booker_display_name from public.list_calendar_bookings('2026-09-10 00:00+02','2026-09-11 00:00+02') where booking_id = '24000000-0000-0000-0000-000000000091'),
  'Foglaló Béla', 'Alapértelmezetten más foglaló neve látható'
);
select is(
  (select booker_display_name from public.list_calendar_bookings('2026-09-10 00:00+02','2026-09-11 00:00+02') where booking_id = '24000000-0000-0000-0000-000000000092'),
  'Néző Naptár', 'A saját foglalás felismerhető'
);
select is(
  (select count(*) from public.list_calendar_bookings('2026-09-10 00:00+02','2026-09-11 00:00+02') where room_id = '11000000-0000-0000-0000-000000000010'),
  1::bigint, 'Aktív csoportból örökölt helyiségjog láthatóvá teszi a foglaltságot'
);
select is(
  (select count(*) from public.list_calendar_bookings('2026-09-10 00:00+02','2026-09-11 00:00+02') where room_id = '11000000-0000-0000-0000-000000000011'),
  0::bigint, 'Engedélyezett, de inaktív helyiség foglalása nem látható'
);
select throws_ok(
  $$select * from public.bookings$$, '42501', null,
  'Normál user közvetlenül nem olvashatja a bookings táblát'
);

select throws_ok(
  $$select public.admin_set_other_booker_names_visible(
    '00000000-0000-0000-0000-000000000092', false, gen_random_uuid())$$,
  '42501', 'Ehhez a művelethez aktív adminisztrátori jogosultság szükséges.',
  'Normál user nem módosíthatja a névláthatóságot'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000091', true);
select lives_ok(
  $$select public.admin_set_other_booker_names_visible(
    '00000000-0000-0000-0000-000000000092', false,
    '24000000-0000-0000-0000-000000000011')$$,
  'Admin letilthatja a névláthatóságot'
);
reset role;
select is((select other_booker_names_visible from public.profiles where id = '00000000-0000-0000-0000-000000000092'), false, 'A kapcsoló mentve van');
select is((select count(*) from public.audit_logs where correlation_id = '24000000-0000-0000-0000-000000000011'), 1::bigint, 'A módosítás auditált');
select is(
  (select before_data ->> 'other_booker_names_visible' from public.audit_logs where correlation_id = '24000000-0000-0000-0000-000000000011'),
  'true', 'Az audit a korábbi értéket tartalmazza'
);
select is(
  (select after_data ->> 'other_booker_names_visible' from public.audit_logs where correlation_id = '24000000-0000-0000-0000-000000000011'),
  'false', 'Az audit az új értéket tartalmazza'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000091', true);
select lives_ok(
  $$select public.admin_set_other_booker_names_visible(
    '00000000-0000-0000-0000-000000000092', false,
    '24000000-0000-0000-0000-000000000012')$$,
  'Azonos beállítás idempotensen újraküldhető'
);
reset role;
select is((select count(*) from public.audit_logs where entity_id = '00000000-0000-0000-0000-000000000092' and action = 'profile.booking_name_visibility.updated'), 1::bigint, 'Idempotens ismétlés nem duplikál auditot');

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000092', true);
select is(
  (select booker_display_name from public.list_calendar_bookings('2026-09-10 00:00+02','2026-09-11 00:00+02') where booking_id = '24000000-0000-0000-0000-000000000091'),
  null, 'Letiltás után más foglaló neve maszkolt'
);
select is(
  (select booker_display_name from public.list_calendar_bookings('2026-09-10 00:00+02','2026-09-11 00:00+02') where booking_id = '24000000-0000-0000-0000-000000000092'),
  'Néző Naptár', 'Letiltás után a saját foglalás továbbra is felismerhető'
);
select is(
  (select count(*) from public.list_calendar_bookings('2026-09-10 00:00+02','2026-09-11 00:00+02') where room_id = '11000000-0000-0000-0000-000000000001'),
  0::bigint, 'Tiltott helyiség foglalása nem szivárog'
);
select throws_ok(
  $$select * from public.list_calendar_bookings('2026-01-01','2026-04-01')$$,
  '22023', 'Legfeljebb 62 napos időszak kérdezhető le.',
  'A read RPC korlátozza a lekérdezési időszakot'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000094', true);
select throws_ok(
  $$select * from public.list_calendar_bookings('2026-09-10 00:00+02','2026-09-11 00:00+02')$$,
  '42501', 'A felhasználói fiók nem aktív.',
  'Inaktív user nem használhatja a read RPC-t'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000091', true);
select is(
  (select count(*) from public.list_calendar_bookings('2026-09-10 00:00+02','2026-09-11 00:00+02')),
  4::bigint, 'Admin minden aktív helyiség foglalását látja'
);
select is(
  (select count(*) from public.list_calendar_bookings('2026-09-10 00:00+02','2026-09-11 00:00+02') where booker_display_name is not null),
  4::bigint, 'Admin minden foglaló nevét látja'
);
select throws_ok(
  $$select * from public.list_calendar_bookings('2026-09-11','2026-09-10')$$,
  '22023', 'Érvényes lekérdezési időszak szükséges.',
  'Fordított időszak elutasított'
);

reset role;
select * from finish();
rollback;
