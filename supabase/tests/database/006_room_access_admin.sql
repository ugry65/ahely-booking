begin;

select plan(29);

select has_function('public', 'admin_upsert_room', array['uuid','text','integer','boolean','boolean','uuid'], 'A helyiség admin RPC létezik');
select has_function('public', 'admin_set_user_room_permission', array['uuid','uuid','boolean','boolean','uuid'], 'A közvetlen jogosultság RPC létezik');
select has_function('public', 'admin_upsert_access_group', array['uuid','text','boolean','uuid'], 'A csoport admin RPC létezik');
select has_function('public', 'admin_set_group_member', array['uuid','uuid','boolean','uuid'], 'A csoporttagság RPC létezik');
select has_function('public', 'admin_set_group_room_permission', array['uuid','uuid','boolean','boolean','uuid'], 'A csoportjog RPC létezik');

select ok(
  not has_function_privilege('authenticated', 'public.require_active_admin()', 'EXECUTE'),
  'A belső adminellenőrző közvetlenül nem hívható'
);
select ok(
  (
    select bool_and(prosecdef and coalesce(proconfig @> array['search_path=""'], false))
    from pg_proc
    where oid in (
      'public.admin_upsert_room(uuid,text,integer,boolean,boolean,uuid)'::regprocedure,
      'public.admin_set_user_room_permission(uuid,uuid,boolean,boolean,uuid)'::regprocedure,
      'public.admin_upsert_access_group(uuid,text,boolean,uuid)'::regprocedure,
      'public.admin_set_group_member(uuid,uuid,boolean,uuid)'::regprocedure,
      'public.admin_set_group_room_permission(uuid,uuid,boolean,boolean,uuid)'::regprocedure
    )
  ),
  'Minden admin RPC SECURITY DEFINER és üres search_path beállítású'
);

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-000000000061', 'access-admin@example.invalid', '{"first_name":"Access","last_name":"Admin"}'),
  ('00000000-0000-0000-0000-000000000062', 'access-user@example.invalid', '{"first_name":"Access","last_name":"User"}'),
  ('00000000-0000-0000-0000-000000000063', 'access-inactive@example.invalid', '{"first_name":"Inactive","last_name":"Admin"}');
update public.profiles set role = 'admin' where id in (
  '00000000-0000-0000-0000-000000000061', '00000000-0000-0000-0000-000000000063'
);
update public.profiles set is_active = false where id = '00000000-0000-0000-0000-000000000063';

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000062', true);
select throws_ok(
  $$select public.admin_upsert_room(null, 'Tiltott terem', 90, false, true, gen_random_uuid())$$,
  '42501', 'Ehhez a művelethez aktív adminisztrátori jogosultság szükséges.',
  'Normál user nem használhat admin RPC-t'
);
select throws_ok(
  $$insert into public.user_room_permissions (user_id, room_id) values
    ('00000000-0000-0000-0000-000000000062', '11000000-0000-0000-0000-000000000001')$$,
  '42501', null, 'A közvetlen Data API írás tiltott'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000063', true);
select throws_ok(
  $$select public.admin_upsert_access_group(null, 'Tiltott csoport', true, gen_random_uuid())$$,
  '42501', 'Ehhez a művelethez aktív adminisztrátori jogosultság szükséges.',
  'Inaktív admin nem használhat admin RPC-t'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000061', true);
select lives_ok(
  $$select public.admin_upsert_room('16000000-0000-0000-0000-000000000001', 'Új tesztterem', 50, false, true,
    '16000000-0000-0000-0000-000000000011')$$,
  'Admin létrehozhat helyiséget'
);
select is((select name from public.rooms where id = '16000000-0000-0000-0000-000000000001'), 'Új tesztterem', 'A helyiség létrejött');
select lives_ok(
  $$select public.admin_upsert_room('16000000-0000-0000-0000-000000000001', 'Átnevezett tesztterem', 51, false, false,
    '16000000-0000-0000-0000-000000000012')$$,
  'Admin módosíthat és deaktiválhat helyiséget'
);
select is((select is_active from public.rooms where id = '16000000-0000-0000-0000-000000000001'), false, 'A helyiség fizikailag megmarad, de inaktív');
select is((select count(*) from public.audit_logs where entity_id = '16000000-0000-0000-0000-000000000001'), 2::bigint, 'A létrehozás és módosítás auditált');
select lives_ok(
  $$select public.admin_upsert_room('16000000-0000-0000-0000-000000000001', 'Átnevezett tesztterem', 51, false, false,
    '16000000-0000-0000-0000-000000000019')$$,
  'Azonos helyiségadat idempotensen újraküldhető'
);
select is((select count(*) from public.audit_logs where entity_id = '16000000-0000-0000-0000-000000000001'), 2::bigint, 'Az idempotens ismétlés nem duplikálja az auditot');

select throws_ok(
  $$select public.admin_set_user_room_permission(
    '00000000-0000-0000-0000-000000000062', '11000000-0000-0000-0000-000000000001', false, true, gen_random_uuid())$$,
  '22023', 'Ismétlődő foglalási jog csak foglalási jog mellett adható.',
  'Ismétlési jog foglalási jog nélkül nem adható'
);
select lives_ok(
  $$select public.admin_set_user_room_permission(
    '00000000-0000-0000-0000-000000000062', '11000000-0000-0000-0000-000000000001', true, true,
    '16000000-0000-0000-0000-000000000013')$$,
  'Admin közvetlen foglalási és ismétlési jogot adhat'
);
select is((select can_repeat from public.user_room_permissions where user_id = '00000000-0000-0000-0000-000000000062' and room_id = '11000000-0000-0000-0000-000000000001'), true, 'A közvetlen jog mentve van');

select lives_ok(
  $$select public.admin_upsert_access_group('16000000-0000-0000-0000-000000000002', 'Teszt hozzáférési csoport', true,
    '16000000-0000-0000-0000-000000000014')$$,
  'Admin csoportot hozhat létre'
);
select lives_ok(
  $$select public.admin_set_group_member(
    '16000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000062', true,
    '16000000-0000-0000-0000-000000000015')$$,
  'Admin usert adhat a csoporthoz'
);
select lives_ok(
  $$select public.admin_set_group_room_permission(
    '16000000-0000-0000-0000-000000000002', '11000000-0000-0000-0000-000000000002', true, true,
    '16000000-0000-0000-0000-000000000016')$$,
  'Admin csoportos helyiségjogot adhat'
);
select is((select count(*) from public.audit_logs where correlation_id in (
  '16000000-0000-0000-0000-000000000014', '16000000-0000-0000-0000-000000000015', '16000000-0000-0000-0000-000000000016'
)), 3::bigint, 'A csoport minden változása auditált');

select lives_ok(
  $$select public.admin_upsert_access_group('16000000-0000-0000-0000-000000000002', 'Teszt hozzáférési csoport', false,
    '16000000-0000-0000-0000-000000000017')$$,
  'Admin deaktiválhatja a csoportot'
);
reset role;
select is(
  (select count(*) from public.access_group_members member
   join public.access_groups access_group on access_group.id = member.group_id and access_group.is_active
   join public.access_group_rooms permission on permission.group_id = member.group_id and permission.can_book
   where member.user_id = '00000000-0000-0000-0000-000000000062'
     and permission.room_id = '11000000-0000-0000-0000-000000000002'),
  0::bigint, 'Inaktív csoport nem ad effektív foglalási jogot'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000061', true);
select lives_ok(
  $$select public.admin_set_group_member(
    '16000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000062', false,
    '16000000-0000-0000-0000-000000000018')$$,
  'Admin eltávolíthatja a csoporttagságot'
);
reset role;
select is((select count(*) from public.access_group_members where group_id = '16000000-0000-0000-0000-000000000002'), 0::bigint, 'A tagság eltávolítása megtörtént');
select is((select count(*) from public.audit_logs where correlation_id = '16000000-0000-0000-0000-000000000018'), 1::bigint, 'A tagság eltávolítása auditált');

select * from finish();
rollback;
