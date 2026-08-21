begin;

select plan(16);

select has_function('public', 'list_calendar_bookings', array['timestamp with time zone','timestamp with time zone'], 'A biztonságos naptár-read RPC létezik');
select has_function('public', 'admin_set_booking_name_visibility', array['boolean','uuid'], 'A globális névláthatóság admin RPC létezik');
select ok(
  (select prosecdef and coalesce(proconfig @> array['search_path=""'], false)
   from pg_proc where oid = 'public.list_calendar_bookings(timestamptz,timestamptz)'::regprocedure),
  'A naptár-read RPC SECURITY DEFINER és üres search_path beállítású'
);
select is(
  (select value from public.app_settings where key = 'show_other_booker_names'),
  'true'::jsonb,
  'A más foglalók neve alapértelmezetten globálisan látható'
);

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-000000000091', 'visibility-admin@example.invalid', '{"first_name":"Látó","last_name":"Admin"}'),
  ('00000000-0000-0000-0000-000000000092', 'visibility-viewer@example.invalid', '{"first_name":"Naptár","last_name":"Néző"}'),
  ('00000000-0000-0000-0000-000000000093', 'visibility-booker@example.invalid', '{"first_name":"Béla","last_name":"Foglaló"}'),
  ('00000000-0000-0000-0000-000000000094', 'visibility-inactive@example.invalid', '{"first_name":"Inaktív","last_name":"Néző"}');
update public.profiles set role = 'admin' where id = '00000000-0000-0000-0000-000000000091';
update public.profiles set is_active = false where id = '00000000-0000-0000-0000-000000000094';

insert into public.user_room_permissions (user_id, room_id, can_book) values
  ('00000000-0000-0000-0000-000000000092', '11000000-0000-0000-0000-000000000009', true);

insert into public.bookings (id, room_id, user_id, created_by, start_at, end_at, idempotency_key) values
  ('24000000-0000-0000-0000-000000000091', '11000000-0000-0000-0000-000000000009',
   '00000000-0000-0000-0000-000000000093', '00000000-0000-0000-0000-000000000093',
   '2026-09-10 09:00:00+02', '2026-09-10 10:00:00+02', '24000000-0000-0000-0000-000000000001'),
  ('24000000-0000-0000-0000-000000000092', '11000000-0000-0000-0000-000000000009',
   '00000000-0000-0000-0000-000000000092', '00000000-0000-0000-0000-000000000092',
   '2026-09-10 10:00:00+02', '2026-09-10 11:00:00+02', '24000000-0000-0000-0000-000000000002');

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000092', true);
select is(
  (select count(*) from public.list_calendar_bookings('2026-09-10 00:00+02','2026-09-11 00:00+02')),
  2::bigint, 'A user az engedélyezett helyiség foglalásait látja'
);
select is(
  (select booker_display_name from public.list_calendar_bookings('2026-09-10 00:00+02','2026-09-11 00:00+02') where booking_id = '24000000-0000-0000-0000-000000000091'),
  'Foglaló Béla', 'Bekapcsolt globális beállításnál más foglaló neve látható'
);
select is(
  (select booker_display_name from public.list_calendar_bookings('2026-09-10 00:00+02','2026-09-11 00:00+02') where booking_id = '24000000-0000-0000-0000-000000000092'),
  'Néző Naptár', 'A saját foglalás felismerhető'
);
select throws_ok(
  $$select public.admin_set_booking_name_visibility(false, gen_random_uuid())$$,
  '42501', 'Ehhez a művelethez aktív adminisztrátori jogosultság szükséges.',
  'Normál user nem módosíthatja a globális névláthatóságot'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000091', true);
select lives_ok(
  $$select public.admin_set_booking_name_visibility(false, '24000000-0000-0000-0000-000000000011')$$,
  'Admin kikapcsolhatja a globális névláthatóságot'
);
reset role;
select is((select value from public.app_settings where key = 'show_other_booker_names'), 'false'::jsonb, 'A globális kapcsoló mentve van');
select is((select count(*) from public.audit_logs where correlation_id = '24000000-0000-0000-0000-000000000011'), 1::bigint, 'A globális módosítás auditált');

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000092', true);
select is(
  (select booker_display_name from public.list_calendar_bookings('2026-09-10 00:00+02','2026-09-11 00:00+02') where booking_id = '24000000-0000-0000-0000-000000000091'),
  null, 'Kikapcsolt globális beállításnál más foglaló neve maszkolt'
);
select is(
  (select booker_display_name from public.list_calendar_bookings('2026-09-10 00:00+02','2026-09-11 00:00+02') where booking_id = '24000000-0000-0000-0000-000000000092'),
  'Néző Naptár', 'Kikapcsolás után a saját foglalás továbbra is felismerhető'
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
  2::bigint, 'Admin a globális maszkolástól függetlenül látja a foglalásokat'
);
select is(
  (select count(*) from public.list_calendar_bookings('2026-09-10 00:00+02','2026-09-11 00:00+02') where booker_display_name is not null),
  2::bigint, 'Admin kikapcsolt globális beállításnál is látja a foglalók nevét'
);

reset role;
select * from finish();
rollback;
