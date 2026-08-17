begin;
select plan(8);

select has_function('public', 'list_my_bookings', array[]::text[], 'A saját foglalások read-model létezik');
select ok((select prosecdef and coalesce(proconfig @> array['search_path=""'], false)
  from pg_proc where oid = 'public.list_my_bookings()'::regprocedure),
  'A read-model SECURITY DEFINER és üres search_path beállítású');
select ok(has_function_privilege('authenticated', 'public.list_my_bookings()', 'EXECUTE')
  and not has_function_privilege('anon', 'public.list_my_bookings()', 'EXECUTE'),
  'Csak authenticated szerepkör hívhatja a read-modelt');

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-000000000141', 'my-bookings-owner@example.invalid', '{"first_name":"Saját","last_name":"Foglaló"}'),
  ('00000000-0000-0000-0000-000000000142', 'my-bookings-other@example.invalid', '{"first_name":"Másik","last_name":"Foglaló"}'),
  ('00000000-0000-0000-0000-000000000143', 'my-bookings-inactive@example.invalid', '{"first_name":"Inaktív","last_name":"Foglaló"}');
update public.profiles set is_active = false where id = '00000000-0000-0000-0000-000000000143';

insert into public.bookings (id, room_id, user_id, created_by, start_at, end_at, use_type, status, note, idempotency_key) values
  ('31000000-0000-0000-0000-000000000141', '11000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000141', '00000000-0000-0000-0000-000000000141', current_date + interval '2 days 09 hours', current_date + interval '2 days 10 hours', 'individual', 'active', 'Saját aktív', '32000000-0000-0000-0000-000000000141'),
  ('31000000-0000-0000-0000-000000000142', '11000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000142', '00000000-0000-0000-0000-000000000142', current_date + interval '3 days 09 hours', current_date + interval '3 days 10 hours', 'individual', 'active', 'Más foglalása', '32000000-0000-0000-0000-000000000142'),
  ('31000000-0000-0000-0000-000000000143', '11000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000141', '00000000-0000-0000-0000-000000000141', current_date + interval '4 days 09 hours', current_date + interval '4 days 10 hours', 'individual', 'cancelled', 'Lemondott', '32000000-0000-0000-0000-000000000143'),
  ('31000000-0000-0000-0000-000000000144', '11000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000141', '00000000-0000-0000-0000-000000000141', current_date - interval '1 day' + interval '09 hours', current_date - interval '1 day' + interval '10 hours', 'individual', 'active', 'Lezárult', '32000000-0000-0000-0000-000000000144');

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000141', true);
select is((select count(*) from public.list_my_bookings()), 1::bigint,
  'Csak a saját, aktív, még le nem zárult foglalás látszik');
select is((select note from public.list_my_bookings()), 'Saját aktív',
  'A saját foglalás szerkesztéséhez szükséges megjegyzés visszatér');
select ok((select updated_at is not null from public.list_my_bookings()),
  'Az optimista módosításhoz szükséges updated_at visszatér');
select is((select room_name from public.list_my_bookings()), 'Boróka',
  'A helyiség megjelenítési neve visszatér');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000143', true);
select throws_ok($$select * from public.list_my_bookings()$$, '42501', 'A felhasználói fiók nem aktív.',
  'Inaktív user nem használhatja a read-modelt');
reset role;
select * from finish();
rollback;
