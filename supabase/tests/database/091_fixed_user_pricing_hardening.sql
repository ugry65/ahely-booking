begin;

select plan(9);

insert into auth.users (id, email, raw_user_meta_data) values
  ('91000000-0000-0000-0000-000000000001', 'fixed-hardening-admin@example.com', '{"first_name":"Fix","last_name":"Admin"}'::jsonb),
  ('91000000-0000-0000-0000-000000000002', 'fixed-hardening-user@example.com', '{"first_name":"Fix","last_name":"User"}'::jsonb);

update public.profiles set role = 'admin' where id = '91000000-0000-0000-0000-000000000001';
select set_config('request.jwt.claim.sub', '91000000-0000-0000-0000-000000000001', true);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.admin_set_user_pricing_policy(uuid,public.user_pricing_scheme,date,uuid)',
    'EXECUTE'
  ),
  'A legacy pricing-policy RPC authenticated szerepkörből közvetlenül nem hívható'
);

select lives_ok(
  $$select public.admin_set_user_pricing_configuration(
    '91000000-0000-0000-0000-000000000002', 'fixed', 2200, date '2027-01-01', gen_random_uuid()
  )$$,
  'Tiered/default állapotból Fix óradíj beállítható'
);

insert into public.bookings (
  room_id,user_id,created_by,start_at,end_at,use_type,status,idempotency_key
) values (
  '11000000-0000-0000-0000-000000000001',
  '91000000-0000-0000-0000-000000000002',
  '91000000-0000-0000-0000-000000000001',
  '2027-01-12 10:00 Europe/Budapest',
  '2027-01-12 11:00 Europe/Budapest',
  'group','active',gen_random_uuid()
);

select is(
  (select special_due_huf from public.calculate_monthly_pricing(
    '91000000-0000-0000-0000-000000000002', date '2027-01-01'
  )),
  5000::bigint,
  'Fix user óradíj mellett a Tréningterem csoportos foglalás a speciális 5000 Ft-os díjat használja'
);

select lives_ok(
  $$select public.admin_set_user_pricing_configuration(
    '91000000-0000-0000-0000-000000000002', 'progressive', null, date '2027-02-01', gen_random_uuid()
  )$$,
  'Fix módról Progresszív módra lehet váltani'
);

select is(
  (select valid_to from public.user_price_overrides
    where user_id = '91000000-0000-0000-0000-000000000002'
      and valid_from = date '2027-01-01'),
  date '2027-01-31',
  'Fixed → Progressive váltás lezárja a Fix intervallumot'
);

select lives_ok(
  $$select public.admin_set_user_pricing_configuration(
    '91000000-0000-0000-0000-000000000002', 'fixed', 2500, date '2027-03-01', gen_random_uuid()
  )$$,
  'Progresszív módról új Fix óradíjra lehet váltani'
);

select lives_ok(
  $$select public.admin_set_user_pricing_configuration(
    '91000000-0000-0000-0000-000000000002', 'tiered', null, date '2027-04-01', gen_random_uuid()
  )$$,
  'Fix módról Sávos módra lehet váltani'
);

select is(
  (select valid_to from public.user_price_overrides
    where user_id = '91000000-0000-0000-0000-000000000002'
      and valid_from = date '2027-03-01'),
  date '2027-03-31',
  'Fixed → Tiered váltás lezárja a Fix intervallumot'
);

select throws_ok(
  format(
    $$select public.admin_set_user_pricing_configuration(
      '91000000-0000-0000-0000-000000000002', 'fixed', 2000, date '%s', gen_random_uuid()
    )$$,
    (date_trunc('month', current_date) - interval '1 month')::date
  ),
  '22023',
  'Korábbi lezárt hónap díjazása nem módosítható.',
  'Múltbeli hónapra Fix óradíj nem állítható be'
);

select * from finish();
rollback;
