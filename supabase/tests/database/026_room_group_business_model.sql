begin;

select plan(10);

select is(
  (select count(*)::bigint from public.access_groups where is_active and name in ('A-Hely','Másik Hely','Tréningterem','Forrás tér')),
  4::bigint,
  'A négy kanonikus helyiségcsoport aktív'
);

select is(
  (select count(*)::bigint from public.access_group_rooms mapping join public.access_groups g on g.id=mapping.group_id where g.name='A-Hely' and mapping.can_book),
  3::bigint,
  'Az A-Hely csoport pontosan három foglalható helyiséget ad'
);
select is(
  (select count(*)::bigint from public.access_group_rooms mapping join public.access_groups g on g.id=mapping.group_id where g.name='Másik Hely' and mapping.can_book),
  6::bigint,
  'A Másik Hely csoport pontosan hat foglalható helyiséget ad'
);
select is(
  (select count(*)::bigint from public.access_group_rooms mapping join public.access_groups g on g.id=mapping.group_id where g.name='Tréningterem' and mapping.can_book),
  1::bigint,
  'A Tréningterem csoport csak a Tréningtermet adja'
);
select is(
  (select count(*)::bigint from public.access_group_rooms mapping join public.access_groups g on g.id=mapping.group_id where g.name='Forrás tér' and mapping.can_book),
  1::bigint,
  'A Forrás tér csoport csak a Forrás teret adja'
);
select is(
  (select count(*)::bigint from public.access_group_rooms mapping join public.access_groups g on g.id=mapping.group_id where g.name in ('A-Hely','Másik Hely','Tréningterem','Forrás tér') and mapping.can_repeat),
  0::bigint,
  'Egyetlen kanonikus helyiségcsoport sem ad repeat jogot'
);

insert into auth.users(id,email,raw_user_meta_data) values
 ('00000000-0000-0000-0000-000000000161','room-group-user@example.invalid','{"first_name":"Group","last_name":"User"}'),
 ('00000000-0000-0000-0000-000000000162','room-group-admin@example.invalid','{"first_name":"Group","last_name":"Admin"}');
update public.profiles set role='admin' where id='00000000-0000-0000-0000-000000000162';

insert into public.access_group_members(group_id,user_id)
select id,'00000000-0000-0000-0000-000000000161'::uuid from public.access_groups where name='A-Hely';

select is(
  (select count(*)::bigint from public.effective_room_permissions('00000000-0000-0000-0000-000000000161') where can_book),
  3::bigint,
  'A user az A-Hely csoportból mindhárom szobára foglalási jogot kap'
);
select is(
  (select count(*)::bigint from public.effective_room_permissions('00000000-0000-0000-0000-000000000161') where can_repeat),
  0::bigint,
  'A csoporttagság önmagában nem ad ismétlődési jogot'
);

insert into public.user_room_permissions(user_id,room_id,can_book,can_repeat)
select '00000000-0000-0000-0000-000000000161'::uuid,id,true,true from public.rooms where name='Gyerek szoba';
select is(
  (select can_repeat from public.effective_room_permissions('00000000-0000-0000-0000-000000000161') permission join public.rooms room on room.id=permission.room_id where room.name='Gyerek szoba'),
  true,
  'A közvetlen user-szintű repeat jog a csoporttagság mellett is megmarad'
);

select set_config('ahely_test.group_id',(select id::text from public.access_groups where name='A-Hely'),true);
select set_config('ahely_test.room_id',(select id::text from public.rooms where name='Gyerek szoba'),true);
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000162',true);
select throws_ok(
  format(
    $sql$select public.admin_set_group_room_permission(%L::uuid,%L::uuid,true,true,'27000000-0000-0000-0000-000000000161'::uuid)$sql$,
    current_setting('ahely_test.group_id'),
    current_setting('ahely_test.room_id')
  ),
  '22023',
  'Helyiségcsoport nem adhat ismétlődő foglalási jogosultságot.',
  'Az admin RPC backend-oldalon is tiltja a csoportos repeat jogot'
);
reset role;

select * from finish();
rollback;
