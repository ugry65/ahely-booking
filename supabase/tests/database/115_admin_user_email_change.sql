begin;
select plan(11);

select has_function('public','admin_prepare_user_email_change',array['uuid','text','text','uuid'],'E-mail módosítás előellenőrző RPC létezik');
select has_function('public','admin_finalize_user_email_change',array['uuid','text','text','text','uuid'],'E-mail módosítás véglegesítő RPC létezik');

insert into auth.users(id,email,raw_user_meta_data) values
 ('00000000-0000-0000-0000-000000000191','email-admin@example.invalid','{"first_name":"Email","last_name":"Admin"}'),
 ('00000000-0000-0000-0000-000000000192','old-user@example.invalid','{"first_name":"Email","last_name":"User"}'),
 ('00000000-0000-0000-0000-000000000193','taken@example.invalid','{"first_name":"Taken","last_name":"User"}');
update public.profiles set role='admin' where id='00000000-0000-0000-0000-000000000191';

set local role service_role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000191',true);
select is(
 (public.admin_prepare_user_email_change('00000000-0000-0000-0000-000000000192','NEW-user@example.invalid','Címváltás','19100000-0000-0000-0000-000000000001')->>'new_email'),
 'new-user@example.invalid','Az új e-mail normalizálódik'
);
select throws_ok(
 $$select public.admin_prepare_user_email_change('00000000-0000-0000-0000-000000000192','taken@example.invalid','Címváltás',gen_random_uuid())$$,
 'P0001','Ez az e-mail-cím már használatban van.','Duplikált profil/Auth e-mail elutasítva'
);
select throws_ok(
 $$select public.admin_prepare_user_email_change('00000000-0000-0000-0000-000000000192','bad-email','Címváltás',gen_random_uuid())$$,
 '22023','Érvénytelen e-mail-cím.','Hibás e-mail elutasítva'
);
select throws_ok(
 $$select public.admin_prepare_user_email_change('00000000-0000-0000-0000-000000000192','new-user@example.invalid','',gen_random_uuid())$$,
 '22023','Az indok kötelező.','Indok kötelező'
);

reset role;
update auth.users set email='new-user@example.invalid' where id='00000000-0000-0000-0000-000000000192';
set local role service_role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000191',true);
select lives_ok(
 $$select public.admin_finalize_user_email_change('00000000-0000-0000-0000-000000000192','old-user@example.invalid','new-user@example.invalid','Címváltás','19100000-0000-0000-0000-000000000001')$$,
 'Az Auth módosítás után a profil véglegesíthető'
);
reset role;
select is((select email from public.profiles where id='00000000-0000-0000-0000-000000000192'),'new-user@example.invalid','A profil e-mail frissült');
select is((select id::text from public.profiles where email='new-user@example.invalid'),'00000000-0000-0000-0000-000000000192','A user ID változatlan');
select is((select count(*) from public.audit_logs where correlation_id='19100000-0000-0000-0000-000000000001' and action='profile.email_changed'),1::bigint,'Az e-mail-váltás auditált');

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000193',true);
select throws_ok(
 $$select public.admin_prepare_user_email_change('00000000-0000-0000-0000-000000000192','other@example.invalid','Próba',gen_random_uuid())$$,
 '42501','permission denied for function admin_prepare_user_email_change','Normál authenticated user közvetlenül nem hívhatja az RPC-t'
);
reset role;

select * from finish();
rollback;
