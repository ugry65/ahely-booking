begin;
select plan(10);

select has_function('public', 'list_repeatable_rooms', array[]::text[], 'Az ismételhető helyiségek read-model létezik');
select has_function('public', 'get_my_booking_series_result', array['uuid'], 'A saját sorozateredmény read-model létezik');
select ok((select prosecdef and coalesce(proconfig @> array['search_path=""'], false) from pg_proc where oid = 'public.list_repeatable_rooms()'::regprocedure), 'A helyiséglista SECURITY DEFINER és üres search_path beállítású');
select ok((select prosecdef and coalesce(proconfig @> array['search_path=""'], false) from pg_proc where oid = 'public.get_my_booking_series_result(uuid)'::regprocedure), 'A sorozateredmény SECURITY DEFINER és üres search_path beállítású');
select ok(has_function_privilege('authenticated', 'public.list_repeatable_rooms()', 'EXECUTE') and not has_function_privilege('anon', 'public.list_repeatable_rooms()', 'EXECUTE'), 'A helyiséglistát csak authenticated hívhatja');

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-000000000151', 'repeat-ui-user@example.invalid', '{"first_name":"Ismétlő","last_name":"User"}'),
  ('00000000-0000-0000-0000-000000000152', 'repeat-ui-inactive@example.invalid', '{"first_name":"Inaktív","last_name":"User"}');
update public.profiles set is_active = false where id = '00000000-0000-0000-0000-000000000152';
insert into public.user_room_permissions (user_id, room_id, can_book, can_repeat) values
  ('00000000-0000-0000-0000-000000000151', '11000000-0000-0000-0000-000000000002', true, true),
  ('00000000-0000-0000-0000-000000000151', '11000000-0000-0000-0000-000000000003', true, false),
  ('00000000-0000-0000-0000-000000000151', '11000000-0000-0000-0000-000000000001', true, true);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000151', true);
select is((select array_agg(room_id order by display_order) from public.list_repeatable_rooms()),
  array['11000000-0000-0000-0000-000000000002'::uuid],
  'Normál usernek csak can_repeat helyiség látszik, a Tréningterem nem');
select throws_ok($$select public.get_my_booking_series_result('33000000-0000-0000-0000-000000000151')$$,
  '42501', 'A foglalási sorozat nem található.', 'Más vagy nem létező sorozat eredménye nem olvasható');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000152', true);
select throws_ok($$select * from public.list_repeatable_rooms()$$, '42501', 'A felhasználói fiók nem aktív.', 'Inaktív user nem kérhet helyiséglistát');
select throws_ok($$select public.get_my_booking_series_result('33000000-0000-0000-0000-000000000151')$$, '42501', 'A felhasználói fiók nem aktív.', 'Inaktív user nem kérhet sorozateredményt');
select ok(not has_function_privilege('anon', 'public.get_my_booking_series_result(uuid)', 'EXECUTE'), 'Anon nem olvashat sorozateredményt');
reset role;
select * from finish();
rollback;
