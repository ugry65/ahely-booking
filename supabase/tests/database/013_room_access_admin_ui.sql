begin;
select plan(10);

select has_function('public', 'admin_room_access_overview', array[]::text[], 'Az admin hozzáférési read-model létezik');
select ok((select prosecdef and coalesce(proconfig @> array['search_path=""'], false)
  from pg_proc where oid = 'public.admin_room_access_overview()'::regprocedure),
  'Az admin read-model SECURITY DEFINER és üres search_path beállítású');
select ok(has_function_privilege('authenticated', 'public.admin_room_access_overview()', 'EXECUTE')
  and not has_function_privilege('anon', 'public.admin_room_access_overview()', 'EXECUTE'),
  'A read-modelt csak authenticated szerepkör hívhatja');

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-000000000161', 'access-ui-admin@example.invalid', '{"first_name":"Aktív","last_name":"Admin"}'),
  ('00000000-0000-0000-0000-000000000162', 'access-ui-user@example.invalid', '{"first_name":"Normál","last_name":"User"}'),
  ('00000000-0000-0000-0000-000000000163', 'access-ui-inactive@example.invalid', '{"first_name":"Inaktív","last_name":"Admin"}');
update public.profiles set role = 'admin' where id in (
  '00000000-0000-0000-0000-000000000161', '00000000-0000-0000-0000-000000000163'
);
update public.profiles set is_active = false where id = '00000000-0000-0000-0000-000000000163';
update public.rooms set is_active = false where id = '11000000-0000-0000-0000-000000000011';
insert into public.user_room_permissions (user_id, room_id, can_book, can_repeat) values
  ('00000000-0000-0000-0000-000000000162', '11000000-0000-0000-0000-000000000002', true, true);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000162', true);
select throws_ok($$select public.admin_room_access_overview()$$, '42501',
  'Ehhez a művelethez aktív adminisztrátori jogosultság szükséges.',
  'Normál user nem olvashat admin hozzáférési adatokat');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000163', true);
select throws_ok($$select public.admin_room_access_overview()$$, '42501',
  'Ehhez a művelethez aktív adminisztrátori jogosultság szükséges.',
  'Inaktív admin nem olvashat admin hozzáférési adatokat');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000161', true);

select is((select jsonb_array_length(public.admin_room_access_overview()->'rooms')), 11,
  'Aktív admin az inaktív helyiséget is látja');
select ok((public.admin_room_access_overview()->'rooms') @> '[{"id":"11000000-0000-0000-0000-000000000011","is_active":false}]'::jsonb,
  'Az inaktív helyiség állapota megmarad a read-modelben');
select ok((public.admin_room_access_overview()->'user_room_permissions') @>
  '[{"user_id":"00000000-0000-0000-0000-000000000162","room_id":"11000000-0000-0000-0000-000000000002","can_book":true,"can_repeat":true}]'::jsonb,
  'A közvetlen userjog megjelenik a read-modelben');
select is((select array_agg(key order by key) from jsonb_object_keys(public.admin_room_access_overview()) key),
  array['group_members','group_room_permissions','groups','rooms','user_room_permissions','users']::text[],
  'A read-model csak a dokumentált adatköröket adja vissza');
select ok(not exists (
    select 1 from jsonb_array_elements(public.admin_room_access_overview()->'users') item
    cross join lateral jsonb_object_keys(item) key
    where key not in ('id', 'name', 'email', 'is_active')
  ), 'A user objektumok nem tartalmaznak nem dokumentált vagy érzékeny mezőt');

reset role;
select * from finish();
rollback;
