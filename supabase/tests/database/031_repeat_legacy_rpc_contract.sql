begin;

select plan(8);

select ok(
  to_regprocedure('public.promote_user_repeat_permission_from_legacy()') is null,
  'A nem támogatott direkt repeat promotion triggerfüggvény nincs jelen'
);

select is(
  (select count(*)::bigint
   from pg_trigger trigger
   join pg_class relation on relation.oid = trigger.tgrelid
   join pg_namespace namespace on namespace.oid = relation.relnamespace
   where namespace.nspname='public'
     and relation.relname='user_room_permissions'
     and trigger.tgname='promote_user_repeat_permission_from_legacy'
     and not trigger.tgisinternal),
  0::bigint,
  'A user_room_permissions táblán nincs direkt repeat promotion trigger'
);

insert into auth.users(id,email,raw_user_meta_data) values
 ('00000000-0000-0000-0000-000000000231','legacy-repeat-user@example.invalid','{"first_name":"Legacy","last_name":"Repeat"}'),
 ('00000000-0000-0000-0000-000000000232','legacy-repeat-admin@example.invalid','{"first_name":"Legacy","last_name":"Admin"}');
update public.profiles set role='admin' where id='00000000-0000-0000-0000-000000000232';

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000232',true);
select lives_ok(
  $$select public.admin_set_user_room_permission(
    '00000000-0000-0000-0000-000000000231',
    '11000000-0000-0000-0000-000000000002',
    true, true, '23100000-0000-0000-0000-000000000001')$$,
  'A támogatott legacy admin RPC TRUE jelzése működik'
);
reset role;

select is(
  (select can_repeat_bookings from public.profiles where id='00000000-0000-0000-0000-000000000231'),
  true,
  'A legacy RPC TRUE a kanonikus user-szintű repeat jogot bekapcsolja'
);

select is(
  (select count(*)::bigint from public.audit_logs where correlation_id='23100000-0000-0000-0000-000000000001'),
  2::bigint,
  'A legacy TRUE hívás külön auditálja a profil-promóciót és a room-permission változást'
);

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000232',true);
select lives_ok(
  $$select public.admin_set_user_room_permission(
    '00000000-0000-0000-0000-000000000231',
    '11000000-0000-0000-0000-000000000002',
    true, false, '23100000-0000-0000-0000-000000000002')$$,
  'A legacy room flag később FALSE-ra állítható'
);
reset role;

select is(
  (select can_repeat_bookings from public.profiles where id='00000000-0000-0000-0000-000000000231'),
  true,
  'A legacy FALSE nem kapcsolja ki a kanonikus user-szintű repeat jogot'
);

select is(
  (select count(*)::bigint from public.audit_logs where correlation_id='23100000-0000-0000-0000-000000000002'),
  1::bigint,
  'A legacy FALSE csak a room-permission változást auditálja'
);

select * from finish();
rollback;
