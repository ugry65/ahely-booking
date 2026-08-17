begin;

select plan(17);

select has_function(
  'public',
  'effective_room_permissions',
  array['uuid'],
  'A közös effektív helyiségjog-segédfüggvény létezik'
);
select ok(
  (
    select prosecdef
      and provolatile = 's'
      and coalesce(proconfig @> array['search_path=""'], false)
    from pg_proc
    where oid = 'public.effective_room_permissions(uuid)'::regprocedure
  ),
  'A helper STABLE, SECURITY DEFINER és üres search_path beállítású'
);
select ok(
  not has_function_privilege('authenticated', 'public.effective_room_permissions(uuid)', 'EXECUTE'),
  'A belső helper közvetlenül nem hívható az API-ból'
);
select ok(
  exists (
    select 1
    from pg_indexes
    where schemaname = 'public'
      and tablename = 'access_group_members'
      and indexname = 'access_group_members_user_id_idx'
  ),
  'A csoporttagság user felőli feloldását célzott index támogatja'
);

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-000000000101', 'effective-access@example.invalid',
   '{"first_name":"Effektív","last_name":"Jog"}');

insert into public.user_room_permissions (user_id, room_id, can_book, can_repeat) values
  ('00000000-0000-0000-0000-000000000101', '11000000-0000-0000-0000-000000000001', true, false),
  ('00000000-0000-0000-0000-000000000101', '11000000-0000-0000-0000-000000000002', false, false),
  ('00000000-0000-0000-0000-000000000101', '11000000-0000-0000-0000-000000000003', false, false);

insert into public.access_groups (id, name, is_active) values
  ('26000000-0000-0000-0000-000000000101', 'Aktív effektív jog teszt', true),
  ('26000000-0000-0000-0000-000000000102', 'Inaktív effektív jog teszt', false);
insert into public.access_group_members (group_id, user_id) values
  ('26000000-0000-0000-0000-000000000101', '00000000-0000-0000-0000-000000000101'),
  ('26000000-0000-0000-0000-000000000102', '00000000-0000-0000-0000-000000000101');
insert into public.access_group_rooms (group_id, room_id, can_book, can_repeat) values
  ('26000000-0000-0000-0000-000000000101', '11000000-0000-0000-0000-000000000001', true, true),
  ('26000000-0000-0000-0000-000000000101', '11000000-0000-0000-0000-000000000003', true, false),
  ('26000000-0000-0000-0000-000000000102', '11000000-0000-0000-0000-000000000004', true, true);

select is(
  (select count(*) from public.effective_room_permissions('00000000-0000-0000-0000-000000000101')
   where room_id = '11000000-0000-0000-0000-000000000001'),
  1::bigint,
  'A közvetlen és csoportos jogosultság egyetlen effektív sorba aggregálódik'
);
select is(
  (select can_book from public.effective_room_permissions('00000000-0000-0000-0000-000000000101')
   where room_id = '11000000-0000-0000-0000-000000000001'),
  true,
  'Bármely engedélyező forrás effektív foglalási jogot ad'
);
select is(
  (select can_repeat from public.effective_room_permissions('00000000-0000-0000-0000-000000000101')
   where room_id = '11000000-0000-0000-0000-000000000001'),
  true,
  'A csoportból örökölt ismétlési jog egyesül a közvetlen joggal'
);
select is(
  (select can_book from public.effective_room_permissions('00000000-0000-0000-0000-000000000101')
   where room_id = '11000000-0000-0000-0000-000000000002'),
  false,
  'Az explicit közvetlen tiltás önmagában nem válik engedéllyé'
);
select is(
  (select can_repeat from public.effective_room_permissions('00000000-0000-0000-0000-000000000101')
   where room_id = '11000000-0000-0000-0000-000000000002'),
  false,
  'Az explicit ismétlési tiltás megmarad'
);
select is(
  (select can_book from public.effective_room_permissions('00000000-0000-0000-0000-000000000101')
   where room_id = '11000000-0000-0000-0000-000000000003'),
  true,
  'A csoportos engedély felülírja a közvetlen can_book=false forrást'
);
select is(
  (select count(*) from public.effective_room_permissions('00000000-0000-0000-0000-000000000101')
   where room_id = '11000000-0000-0000-0000-000000000004'),
  0::bigint,
  'Inaktív csoport nem jelenik meg az effektív jogosultságban'
);
select is(
  (select count(*) from public.effective_room_permissions('00000000-0000-0000-0000-000000000101')),
  3::bigint,
  'A helper csak a közvetlen vagy aktív csoportból származó helyiségeket adja vissza'
);

select ok(
  position('effective_room_permissions' in pg_get_functiondef(
    'public.assert_booking_request(uuid,uuid,uuid,timestamptz,timestamptz,public.booking_use_type)'::regprocedure
  )) > 0,
  'A write-validátor a közös helpert használja'
);
select ok(
  position('user_room_permissions' in pg_get_functiondef(
    'public.assert_booking_request(uuid,uuid,uuid,timestamptz,timestamptz,public.booking_use_type)'::regprocedure
  )) = 0
  and position('access_group_rooms' in pg_get_functiondef(
    'public.assert_booking_request(uuid,uuid,uuid,timestamptz,timestamptz,public.booking_use_type)'::regprocedure
  )) = 0,
  'A write-validátorban nem maradt külön jogosultsági lekérdezés'
);
select ok(
  position('effective_room_permissions' in pg_get_functiondef(
    'public.list_calendar_bookings(timestamptz,timestamptz)'::regprocedure
  )) > 0,
  'A calendar read-model a közös helpert használja'
);
select ok(
  position('user_room_permissions' in pg_get_functiondef(
    'public.list_calendar_bookings(timestamptz,timestamptz)'::regprocedure
  )) = 0
  and position('access_group_rooms' in pg_get_functiondef(
    'public.list_calendar_bookings(timestamptz,timestamptz)'::regprocedure
  )) = 0,
  'A calendar read-modelben nem maradt külön jogosultsági lekérdezés'
);
create function pg_temp.explain_effective_group_access(p_user_id uuid)
returns json
language plpgsql
as $$
declare
  v_plan json;
begin
  execute $query$
    explain (format json)
    select group_permission.room_id,
           group_permission.can_book,
           group_permission.can_repeat
    from public.access_group_members membership
    join public.access_groups access_group
      on access_group.id = membership.group_id
     and access_group.is_active
    join public.access_group_rooms group_permission
      on group_permission.group_id = membership.group_id
    where membership.user_id = $1
  $query$ into v_plan using p_user_id;
  return v_plan;
end;
$$;
set local enable_seqscan = off;
select ok(
  position(
    'access_group_members_user_id_idx'
    in pg_temp.explain_effective_group_access(
      '00000000-0000-0000-0000-000000000101'
    )::text
  ) > 0,
  'A csoportos jogosultsági lekérdezési terv képes a célzott user_id indexet használni'
);

select * from finish();
rollback;
