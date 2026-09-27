begin;

select plan(2);

insert into auth.users(id,email,raw_user_meta_data) values
 ('00000000-0000-0000-0000-000000000194','pricing-guard-admin@example.invalid','{"first_name":"Pricing","last_name":"Guard"}');
update public.profiles set role='admin' where id='00000000-0000-0000-0000-000000000194';

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000194',true);

select throws_ok(
  $$select public.admin_set_central_pricing(timezone('Europe/Budapest',now())::date,2500,1900,1700,'Retroaktív tiltás teszt',gen_random_uuid())$$,
  '22023','Az új központi díjszabás legkorábban holnaptól lehet érvényes.','A központi díjszabás nem állítható visszamenőlegesen vagy mára'
);

select throws_ok(
  $$select public.admin_set_training_room_rate(5000,timezone('Europe/Budapest',now())::date,'Retroaktív tiltás teszt',gen_random_uuid())$$,
  '22023','Az új Tréningterem-díj legkorábban holnaptól lehet érvényes.','A Tréningterem globális díja nem állítható visszamenőlegesen vagy mára'
);

select * from finish();
rollback;
