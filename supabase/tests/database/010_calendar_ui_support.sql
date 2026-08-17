begin;
select plan(8);

select has_function('public', 'list_bookable_rooms', array[]::text[], 'A foglalhatóhelyiség read-model létezik');
select ok((select prosecdef and coalesce(proconfig @> array['search_path=""'], false)
  from pg_proc where oid = 'public.list_bookable_rooms()'::regprocedure),
  'A read-model SECURITY DEFINER és üres search_path beállítású');
select ok(has_function_privilege('authenticated', 'public.list_bookable_rooms()', 'EXECUTE')
  and not has_function_privilege('anon', 'public.list_bookable_rooms()', 'EXECUTE'),
  'Csak authenticated szerepkör hívhatja a read-modelt');

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-000000000131', 'calendar-admin@example.invalid', '{"first_name":"Naptár","last_name":"Admin"}'),
  ('00000000-0000-0000-0000-000000000132', 'calendar-direct@example.invalid', '{"first_name":"Közvetlen","last_name":"User"}'),
  ('00000000-0000-0000-0000-000000000133', 'calendar-group@example.invalid', '{"first_name":"Csoportos","last_name":"User"}'),
  ('00000000-0000-0000-0000-000000000134', 'calendar-inactive@example.invalid', '{"first_name":"Inaktív","last_name":"User"}');
update public.profiles set role = 'admin' where id = '00000000-0000-0000-0000-000000000131';
update public.profiles set is_active = false where id = '00000000-0000-0000-0000-000000000134';
insert into public.rooms (id, name, is_active, display_order) values
  ('11000000-0000-0000-0000-000000000131', 'Inaktív naptárteszt-szoba', false, 131);
insert into public.user_room_permissions (user_id, room_id, can_book, can_repeat) values
  ('00000000-0000-0000-0000-000000000132', '11000000-0000-0000-0000-000000000002', true, false),
  ('00000000-0000-0000-0000-000000000132', '11000000-0000-0000-0000-000000000003', false, false),
  ('00000000-0000-0000-0000-000000000134', '11000000-0000-0000-0000-000000000002', true, false);
insert into public.access_groups (id, name, is_active) values
  ('27000000-0000-0000-0000-000000000131', 'Naptár aktív csoport', true),
  ('27000000-0000-0000-0000-000000000132', 'Naptár inaktív csoport', false);
insert into public.access_group_members (group_id, user_id) values
  ('27000000-0000-0000-0000-000000000131', '00000000-0000-0000-0000-000000000133'),
  ('27000000-0000-0000-0000-000000000132', '00000000-0000-0000-0000-000000000133');
insert into public.access_group_rooms (group_id, room_id, can_book, can_repeat) values
  ('27000000-0000-0000-0000-000000000131', '11000000-0000-0000-0000-000000000004', true, false),
  ('27000000-0000-0000-0000-000000000132', '11000000-0000-0000-0000-000000000005', true, false);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000132', true);
select is((select array_agg(room_id order by display_order) from public.list_bookable_rooms()),
  array['11000000-0000-0000-0000-000000000002'::uuid], 'Közvetlen can_book=true pontosan a megengedett szobát adja');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000133', true);
select is((select array_agg(room_id order by display_order) from public.list_bookable_rooms()),
  array['11000000-0000-0000-0000-000000000004'::uuid], 'Aktív csoport joga látszik, inaktív csoport joga nem');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000131', true);
select is((select count(*) from public.list_bookable_rooms()),
  (select count(*) from public.rooms where is_active), 'Admin minden aktív helyiséget lát');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000134', true);
select throws_ok($$select * from public.list_bookable_rooms()$$, '42501', 'A felhasználói fiók nem aktív.',
  'Inaktív user közvetlen joggal sem használhatja a read-modelt');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000131', true);
select is((select count(*) from public.list_bookable_rooms() where room_id = '11000000-0000-0000-0000-000000000131'),
  0::bigint, 'Inaktív helyiség admin számára sem kerül a listába');
reset role;
select * from finish();
rollback;
