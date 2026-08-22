begin;

select plan(13);

insert into auth.users(id,email,raw_user_meta_data) values
 ('00000000-0000-0000-0000-000000000181','repeat-user@example.invalid','{"first_name":"Repeat","last_name":"User"}'),
 ('00000000-0000-0000-0000-000000000182','repeat-admin@example.invalid','{"first_name":"Repeat","last_name":"Admin"}');
update public.profiles set role='admin' where id='00000000-0000-0000-0000-000000000182';

insert into public.access_group_members(group_id,user_id)
select id,'00000000-0000-0000-0000-000000000181'::uuid
from public.access_groups where name in ('A-Hely','Másik Hely','Tréningterem');

select is(
  (select can_repeat_bookings from public.profiles where id='00000000-0000-0000-0000-000000000181'),
  false,
  'Új user ismétlődő foglalási joga alapból kikapcsolt'
);

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000181',true);
select is(
  (select count(*)::bigint from public.list_repeatable_rooms()),
  0::bigint,
  'Repeat jog nélkül egyetlen foglalható szobában sem ismételhet'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000182',true);
select lives_ok(
  $$select public.admin_set_profile_repeat_permission('00000000-0000-0000-0000-000000000181',true,'18100000-0000-0000-0000-000000000001')$$,
  'Admin engedélyezheti a user-szintű repeat jogot'
);
reset role;

select is(
  (select can_repeat_bookings from public.profiles where id='00000000-0000-0000-0000-000000000181'),
  true,
  'A profil user-szintű repeat joga bekapcsolt'
);
select is(
  (select count(*)::bigint from public.audit_logs where correlation_id='18100000-0000-0000-0000-000000000001'),
  1::bigint,
  'A user-szintű repeat jog változása auditált'
);

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000181',true);
select is(
  (select count(*)::bigint from public.list_repeatable_rooms()),
  9::bigint,
  'Repeat joggal az A-Hely és Másik Hely minden foglalható normál szobája ismételhető'
);
select is(
  (select count(*)::bigint from public.list_repeatable_rooms() where is_training_room),
  0::bigint,
  'Normál user Tréningteremben user-szintű repeat joggal sem ismételhet'
);
reset role;

-- Independent-review L1: prove explicitly that a can_book right coming only
-- from a direct exception receives the same user-level repeat permission.
insert into public.user_room_permissions(user_id,room_id,can_book,can_repeat)
select '00000000-0000-0000-0000-000000000181'::uuid,id,true,false
from public.rooms where name='Forrás tér';
select is(
  (select can_repeat
   from public.effective_room_permissions('00000000-0000-0000-0000-000000000181') permission
   join public.rooms room on room.id=permission.room_id
   where room.name='Forrás tér'),
  true,
  'A kizárólag közvetlen can_book kivételjog ugyanúgy megkapja a user-szintű repeat jogot'
);

select is(
  (select count(*)::bigint from public.effective_room_permissions('00000000-0000-0000-0000-000000000181') where can_book and can_repeat),
  10::bigint,
  'Az effektív repeat jog minden foglalható normál szobára és a közvetlen kivételre kiterjed'
);
select is(
  (select can_repeat from public.effective_room_permissions('00000000-0000-0000-0000-000000000181') permission join public.rooms room on room.id=permission.room_id where room.name='Tréningterem'),
  false,
  'Az effektív jogosultsági modell Tréningteremnél is tiltja a repeat jogot'
);

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000181',true);
select throws_ok(
  $$select public.admin_set_profile_repeat_permission('00000000-0000-0000-0000-000000000181',false,gen_random_uuid())$$,
  '42501',
  'Ehhez a művelethez aktív adminisztrátori jogosultság szükséges.',
  'Normál user közvetlen RPC hívással sem módosíthat repeat jogot'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000182',true);
select lives_ok(
  $$select public.admin_set_profile_repeat_permission('00000000-0000-0000-0000-000000000181',false,'18100000-0000-0000-0000-000000000002')$$,
  'Admin kikapcsolhatja a user-szintű repeat jogot'
);
reset role;

select is(
  (select count(*)::bigint from public.effective_room_permissions('00000000-0000-0000-0000-000000000181') where can_repeat),
  0::bigint,
  'Kikapcsolás után egyik helyiségben sem marad effektív repeat jog'
);

select * from finish();
rollback;
