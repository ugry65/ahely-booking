begin;

select plan(8);
select has_function('public','update_own_profile_data',array['text','text','text','text','text','text','text','text','uuid'],'A saját profil módosító RPC létezik');
select ok(
  not has_function_privilege('anon','public.update_own_profile_data(text,text,text,text,text,text,text,text,uuid)','EXECUTE'),
  'Anon nem hívhatja a saját profil módosító RPC-t'
);
select ok(
  has_function_privilege('authenticated','public.update_own_profile_data(text,text,text,text,text,text,text,text,uuid)','EXECUTE'),
  'Bejelentkezett user hívhatja a saját profil módosító RPC-t'
);

insert into auth.users(id,email,raw_user_meta_data) values
 ('00000000-0000-0000-0000-000000000131','self-profile@example.invalid','{"first_name":"Edit","last_name":"Owner"}');
update public.profiles set onboarding_completed_at=now(), phone='eredeti' where id='00000000-0000-0000-0000-000000000131';

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000131',true);
select lives_ok($$select public.update_own_profile_data('+3612345678','private','Owner Edit','1111','Budapest','Fő utca','1','', '25000000-0000-0000-0000-000000000131')$$,'A user módosíthatja a saját kapcsolattartási és számlázási adatait');
reset role;

select is((select phone from public.profiles where id='00000000-0000-0000-0000-000000000131'),'+3612345678','A telefonszám frissült');
select is((select last_name||'|'||first_name||'|'||email from public.profiles where id='00000000-0000-0000-0000-000000000131'),'Owner|Edit|self-profile@example.invalid','A saját módosítás nem változtathat nevet vagy e-mail címet');
select is((select count(*) from public.audit_logs where correlation_id='25000000-0000-0000-0000-000000000131'),1::bigint,'A saját adatmódosítás auditált');

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000131',true);
select throws_ok($$select public.update_own_profile_data('+3612345678','business','Owner Edit','1111','Budapest','Fő utca','1','', '25000000-0000-0000-0000-000000000132')$$,'P0001','Vállalkozói számlázás esetén az adószám megadása kötelező.','Vállalkozói számlázás adószám nélkül elutasított');
reset role;

select * from finish();
rollback;
