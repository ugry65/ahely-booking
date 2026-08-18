begin;
select plan(9);

select has_function('public', 'admin_monthly_booking_hours', array['date'], 'A havi óraszám read-model létezik');
select ok((select prosecdef and coalesce(proconfig @> array['search_path=""'], false)
  from pg_proc where oid = 'public.admin_monthly_booking_hours(date)'::regprocedure),
  'A havi óraszám read-model SECURITY DEFINER és üres search_path beállítású');
select ok(has_function_privilege('authenticated', 'public.admin_monthly_booking_hours(date)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.admin_monthly_booking_hours(date)', 'EXECUTE'),
  'A havi óraszám read-modelt csak authenticated hívhatja');

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-000000000171', 'hours-admin@example.invalid', '{"first_name":"Óra","last_name":"Admin"}'),
  ('00000000-0000-0000-0000-000000000172', 'hours-user@example.invalid', '{"first_name":"Teszt","last_name":"Bérlő"}'),
  ('00000000-0000-0000-0000-000000000173', 'hours-inactive@example.invalid', '{"first_name":"Inaktív","last_name":"Admin"}');
update public.profiles set role = 'admin' where id in ('00000000-0000-0000-0000-000000000171', '00000000-0000-0000-0000-000000000173');
update public.profiles set is_active = false where id = '00000000-0000-0000-0000-000000000173';

insert into public.bookings (id, room_id, user_id, created_by, start_at, end_at, status, idempotency_key) values
  ('22000000-0000-0000-0000-000000000171', '11000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000172', '00000000-0000-0000-0000-000000000172', '2027-02-02 09:00+01', '2027-02-02 10:00+01', 'active', '23000000-0000-0000-0000-000000000171'),
  ('22000000-0000-0000-0000-000000000172', '11000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000172', '00000000-0000-0000-0000-000000000172', '2027-02-03 10:00+01', '2027-02-03 11:30+01', 'active', '23000000-0000-0000-0000-000000000172'),
  ('22000000-0000-0000-0000-000000000173', '11000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000172', '00000000-0000-0000-0000-000000000172', '2027-02-04 12:00+01', '2027-02-04 13:00+01', 'cancelled', '23000000-0000-0000-0000-000000000173'),
  ('22000000-0000-0000-0000-000000000174', '11000000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000172', '00000000-0000-0000-0000-000000000172', '2027-01-31 21:00+01', '2027-01-31 22:00+01', 'active', '23000000-0000-0000-0000-000000000174');

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000172', true);
select throws_ok($$select * from public.admin_monthly_booking_hours('2027-02-01')$$, '42501',
  'Ehhez a művelethez aktív adminisztrátori jogosultság szükséges.', 'Normál user nem olvashat havi óraszámot');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000173', true);
select throws_ok($$select * from public.admin_monthly_booking_hours('2027-02-01')$$, '42501',
  'Ehhez a művelethez aktív adminisztrátori jogosultság szükséges.', 'Inaktív admin nem olvashat havi óraszámot');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000171', true);
select is((select count(*) from public.admin_monthly_booking_hours('2027-02-15')), 1::bigint,
  'A hónap bármely napja ugyanazt az egy useres összesítést adja');
select is((select booking_count from public.admin_monthly_booking_hours('2027-02-01')), 2::bigint,
  'A lemondott és az előző havi foglalás nem számít bele');
select is((select total_minutes from public.admin_monthly_booking_hours('2027-02-01')), 150::bigint,
  'A 60 és 90 perces aktív foglalás pontosan 150 perc');
select is((select total_hours from public.admin_monthly_booking_hours('2027-02-01')), 2.50::numeric,
  'A félórás törtrész pontosan jelenik meg');

reset role;
select * from finish();
rollback;
