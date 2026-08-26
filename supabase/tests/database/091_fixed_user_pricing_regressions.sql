begin;

select plan(11);

insert into auth.users (id, email, raw_user_meta_data) values
  ('91000000-0000-0000-0000-000000000001', 'pricing-reg-admin@example.invalid', '{"first_name":"Pricing","last_name":"Admin"}'),
  ('91000000-0000-0000-0000-000000000002', 'pricing-reg-user@example.invalid', '{"first_name":"Pricing","last_name":"User"}');
update public.profiles set role = 'admin' where id = '91000000-0000-0000-0000-000000000001';

select ok(
  not has_function_privilege(
    'authenticated',
    'public.admin_set_user_pricing_policy(uuid,public.user_pricing_scheme,date,uuid)',
    'EXECUTE'
  ),
  'A belső pricing policy helper közvetlenül nem hívható authenticated szerepkörből'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '91000000-0000-0000-0000-000000000001', true);
select lives_ok(
  $$select public.admin_set_user_pricing_configuration('91000000-0000-0000-0000-000000000002','fixed',2400,date '2027-01-01',gen_random_uuid())$$,
  'Fix díj beállítható'
);
select lives_ok(
  $$select public.admin_set_user_pricing_configuration('91000000-0000-0000-0000-000000000002','progressive',null,date '2027-02-01',gen_random_uuid())$$,
  'Fix után Progresszív mód beállítható'
);
reset role;

select is(
  (select valid_to from public.user_price_overrides where user_id='91000000-0000-0000-0000-000000000002' and valid_from=date '2027-01-01'),
  date '2027-01-31',
  'Fixed → Progresszív lezárja a Fix időszakot'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '91000000-0000-0000-0000-000000000001', true);
select lives_ok(
  $$select public.admin_set_user_pricing_configuration('91000000-0000-0000-0000-000000000002','fixed',2600,date '2027-03-01',gen_random_uuid())$$,
  'Új Fix időszak beállítható'
);
select lives_ok(
  $$select public.admin_set_user_pricing_configuration('91000000-0000-0000-0000-000000000002','tiered',null,date '2027-04-01',gen_random_uuid())$$,
  'Fix után Sávos mód beállítható'
);
reset role;

select is(
  (select valid_to from public.user_price_overrides where user_id='91000000-0000-0000-0000-000000000002' and valid_from=date '2027-03-01'),
  date '2027-03-31',
  'Fixed → Sávos lezárja a Fix időszakot'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '91000000-0000-0000-0000-000000000001', true);
select throws_ok(
  $$select public.admin_set_user_pricing_configuration('91000000-0000-0000-0000-000000000002','fixed',2000,date '2026-07-01',gen_random_uuid())$$,
  '22023',
  'Korábbi lezárt hónap díjazása nem módosítható.',
  'Múltbeli hónapra Fix díj nem állítható'
);

select lives_ok(
  $$select public.admin_set_user_pricing_configuration('91000000-0000-0000-0000-000000000002','fixed',3000,date '2027-05-01',gen_random_uuid())$$,
  'Májusra Fix díj beállítható a kombinált pricing teszthez'
);
reset role;

insert into public.bookings (id,room_id,user_id,created_by,start_at,end_at,use_type,status,idempotency_key) values
  ('91000000-0000-0000-0000-000000000101','11000000-0000-0000-0000-000000000001','91000000-0000-0000-0000-000000000002','91000000-0000-0000-0000-000000000001','2027-05-10 08:00 Europe/Budapest','2027-05-10 09:00 Europe/Budapest','group','active',gen_random_uuid()),
  ('91000000-0000-0000-0000-000000000102','11000000-0000-0000-0000-000000000002','91000000-0000-0000-0000-000000000002','91000000-0000-0000-0000-000000000001','2027-05-10 10:00 Europe/Budapest','2027-05-10 11:00 Europe/Budapest','individual','active',gen_random_uuid());

select is(
  (select normal_due_huf from public.calculate_monthly_pricing('91000000-0000-0000-0000-000000000002',date '2027-05-01')),
  3000::bigint,
  'Fix user óradíj a normál órára érvényes'
);
select is(
  (select special_due_huf from public.calculate_monthly_pricing('91000000-0000-0000-0000-000000000002',date '2027-05-01')),
  5000::bigint,
  'Tréningterem csoportos díja Fix usernél is külön 5 000 Ft marad'
);

select * from finish();
rollback;
