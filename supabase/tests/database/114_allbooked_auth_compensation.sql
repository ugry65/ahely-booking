begin;

select plan(15);

select has_function(
  'public',
  'admin_cleanup_failed_allbooked_auth_profile',
  array['uuid','uuid','text'],
  'A rollback cleanup RPC létezik'
);
select ok(
  not has_function_privilege('anon','public.admin_cleanup_failed_allbooked_auth_profile(uuid,uuid,text)','EXECUTE'),
  'Az anon nem hívhatja a cleanup RPC-t'
);
select ok(
  not has_function_privilege('authenticated','public.admin_cleanup_failed_allbooked_auth_profile(uuid,uuid,text)','EXECUTE'),
  'Az authenticated nem hívhatja a cleanup RPC-t'
);
select ok(
  has_function_privilege('service_role','public.admin_cleanup_failed_allbooked_auth_profile(uuid,uuid,text)','EXECUTE'),
  'A service_role hívhatja a cleanup RPC-t'
);

insert into auth.users(id,email,raw_user_meta_data) values
  ('00000000-0000-0000-0000-000000000271','migration-cleanup-admin@example.invalid','{"first_name":"Cleanup","last_name":"Admin"}'),
  ('00000000-0000-0000-0000-000000000272','fresh-cleanup@example.invalid','{"first_name":"Fresh","last_name":"Cleanup"}'),
  ('00000000-0000-0000-0000-000000000273','protected-existing@example.invalid','{"first_name":"Protected","last_name":"Existing"}'),
  ('00000000-0000-0000-0000-000000000274','wrong-email@example.invalid','{"first_name":"Wrong","last_name":"Email"}');

update public.profiles
set role='admin'
where id='00000000-0000-0000-0000-000000000271';

insert into public.access_group_members(group_id,user_id)
values (
  (select id from public.access_groups order by name limit 1),
  '00000000-0000-0000-0000-000000000273'
);

set local role service_role;
select lives_ok(
  $$select public.admin_cleanup_failed_allbooked_auth_profile(
    '00000000-0000-0000-0000-000000000271',
    '00000000-0000-0000-0000-000000000272',
    'fresh-cleanup@example.invalid'
  )$$,
  'Frissen létrehozott, üzleti adat nélküli profile eltávolítható'
);
reset role;

select is(
  (select count(*) from public.profiles where id='00000000-0000-0000-0000-000000000272'),
  0::bigint,
  'Sikeres cleanup után nem marad profile'
);
select is(
  (select count(*) from auth.users where id='00000000-0000-0000-0000-000000000272'),
  1::bigint,
  'A DB cleanup önmagában nem törli az Auth usert; azt csak a route kompenzáció következő lépése teheti'
);

set local role service_role;
select throws_ok(
  $$select public.admin_cleanup_failed_allbooked_auth_profile(
    '00000000-0000-0000-0000-000000000271',
    '00000000-0000-0000-0000-000000000273',
    'protected-existing@example.invalid'
  )$$,
  'P0001',
  'A frissen létrehozott profilhoz üzleti adat kapcsolódik; automatikus takarítás tiltva.',
  'Üzleti adattal rendelkező profile cleanupja fail-closed'
);
reset role;

select is(
  (select count(*) from public.profiles where id='00000000-0000-0000-0000-000000000273'),
  1::bigint,
  'Elutasított cleanup után a profile sértetlen'
);
select is(
  (select count(*) from auth.users where id='00000000-0000-0000-0000-000000000273'),
  1::bigint,
  'Elutasított cleanup után az Auth user sértetlen'
);

set local role service_role;
select throws_ok(
  $$select public.admin_cleanup_failed_allbooked_auth_profile(
    '00000000-0000-0000-0000-000000000271',
    '00000000-0000-0000-0000-000000000274',
    'different@example.invalid'
  )$$,
  'P0001',
  'Az Auth-user azonossága nem bizonyítható.',
  'Hibás e-maillel a cleanup elutasított'
);
select throws_ok(
  $$select public.admin_cleanup_failed_allbooked_auth_profile(
    '00000000-0000-0000-0000-000000000271',
    '00000000-0000-0000-0000-000000000299',
    'wrong-email@example.invalid'
  )$$,
  'P0001',
  'Az Auth-user azonossága nem bizonyítható.',
  'Hibás Auth ID-val a cleanup elutasított'
);
select throws_ok(
  $$select public.admin_cleanup_failed_allbooked_auth_profile(
    '00000000-0000-0000-0000-000000000274',
    '00000000-0000-0000-0000-000000000274',
    'wrong-email@example.invalid'
  )$$,
  '42501',
  'A migrációs takarítást csak aktív admin futtathatja.',
  'Nem admin actor nem futtathat cleanupot'
);
reset role;

select is(
  (select count(*) from public.profiles where id='00000000-0000-0000-0000-000000000274'),
  1::bigint,
  'Az identity-ellenőrzési hibák után a profile sértetlen'
);
select is(
  (select count(*) from auth.users where id='00000000-0000-0000-0000-000000000274'),
  1::bigint,
  'Az identity-ellenőrzési hibák után az Auth user sértetlen'
);

select * from finish();
rollback;
