begin;

select plan(10);

select has_function('public','admin_set_profile_role',array['uuid','app_role','uuid'],'A szerepkör-admin RPC létezik');

insert into auth.users(id,email,raw_user_meta_data) values
 ('00000000-0000-0000-0000-000000000171','role-admin-a@example.invalid','{"first_name":"Role","last_name":"AdminA"}'),
 ('00000000-0000-0000-0000-000000000172','role-admin-b@example.invalid','{"first_name":"Role","last_name":"AdminB"}'),
 ('00000000-0000-0000-0000-000000000173','role-user@example.invalid','{"first_name":"Role","last_name":"User"}');
update public.profiles set role='admin' where id in ('00000000-0000-0000-0000-000000000171','00000000-0000-0000-0000-000000000172');

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000171',true);
select lives_ok(
 $$select public.admin_set_profile_role('00000000-0000-0000-0000-000000000173','admin','17100000-0000-0000-0000-000000000001')$$,
 'Admin normál usert adminná emelhet'
);
reset role;
select is((select role::text from public.profiles where id='00000000-0000-0000-0000-000000000173'),'admin','A szerepkör módosult');
select is((select count(*) from public.audit_logs where correlation_id='17100000-0000-0000-0000-000000000001'),1::bigint,'A szerepkörváltás auditált');

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000171',true);
select lives_ok(
 $$select public.admin_set_profile_role('00000000-0000-0000-0000-000000000173','user','17100000-0000-0000-0000-000000000002')$$,
 'Több aktív admin mellett admin visszaminősíthető userré'
);
reset role;

update public.profiles set role='user' where id='00000000-0000-0000-0000-000000000172';

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000171',true);
select throws_ok(
 $$select public.admin_set_profile_role('00000000-0000-0000-0000-000000000171','user','17100000-0000-0000-0000-000000000003')$$,
 'P0001','Az utolsó aktív adminisztrátor nem fokozható le.','Az utolsó aktív admin nem fokozható le'
);
select throws_ok(
 $$select public.admin_update_profile(
 '00000000-0000-0000-0000-000000000171','Role','AdminA',null,'private',null,null,null,null,null,null,false,
 '17100000-0000-0000-0000-000000000004')$$,
 'P0001','Az utolsó aktív adminisztrátor nem deaktiválható.','Az utolsó aktív admin nem deaktiválható'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000172',true);
select throws_ok(
 $$select public.admin_set_profile_role('00000000-0000-0000-0000-000000000173','admin',gen_random_uuid())$$,
 '42501','Ehhez a művelethez aktív adminisztrátori jogosultság szükséges.','Normál user nem módosíthat szerepkört'
);
reset role;

select is((select role::text from public.profiles where id='00000000-0000-0000-0000-000000000171'),'admin','A tiltott műveletek után az utolsó admin szerepköre megmarad');
select is((select is_active from public.profiles where id='00000000-0000-0000-0000-000000000171'),true,'A tiltott deaktiválás után az utolsó admin aktív marad');

select * from finish();
rollback;
